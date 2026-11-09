"""Local Developer ID submission/finalization with a durable no-resubmit guard."""

import json
import os
import plistlib
import subprocess
import sys
from pathlib import Path

from release_assets import checksums, digest, hashes

ROOT = Path(__file__).resolve().parents[1]


def run(*args, quiet=False):
    result = subprocess.run(
        args, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    if result.returncode:
        raise RuntimeError(
            f"{args[0]} failed ({result.returncode}): {result.stderr.strip()}"
        )
    if not quiet and result.stderr.strip():
        print(result.stderr.strip())
    return result.stdout


def write_json(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def verify_app(app, version, team, build):
    run("codesign", "--verify", "--deep", "--strict", str(app))
    details = subprocess.run(
        ["codesign", "-d", "--verbose=4", str(app)],
        text=True,
        capture_output=True,
        check=True,
    ).stderr
    if (
        f"TeamIdentifier={team}" not in details.splitlines()
        or "Authority=Developer ID Application:" not in details
    ):
        raise ValueError("Candidate is not signed by the expected Developer ID team.")
    with open(app / "Contents/Info.plist", "rb") as file:
        info = plistlib.load(file)
    if (
        info.get("CFBundleShortVersionString") != version
        or str(info.get("CFBundleVersion")) != build
    ):
        raise ValueError("Candidate version/build differs from frozen source.")
    run(
        "lipo",
        str(app / "Contents/MacOS/BLEClipboardMac"),
        "-verify_arch",
        "arm64",
        "x86_64",
    )


def main(version):
    if (ROOT / "VERSION").read_text().strip() != version:
        raise ValueError("Version must match this checkout.")
    profile = os.environ.get("NOTARY_PROFILE", "ble-clipboard-notary")
    team = os.environ.get("DEVELOPER_TEAM_ID", "4NFKSZN69G")
    logs = ROOT / "dist/notary-logs" / f"v{version}"
    out = ROOT / "dist" / f"v{version}"
    candidate_file = logs / "candidate.json"
    submission_file = logs / "submission.json"
    marker = logs / "SUBMISSION-STARTED"
    frozen_app = logs / "signed/BLE Clipboard.app"
    archive_name = f"BLE-Clipboard-{version}-universal.zip"
    submitted = logs / archive_name
    revision = run("git", "rev-parse", "HEAD", quiet=True).strip()
    if not candidate_file.exists():
        if marker.exists() or submission_file.exists():
            raise ValueError(
                "Submission state exists without candidate metadata. Recover manually; never resubmit blindly."
            )
        if run("git", "status", "--porcelain", quiet=True).strip():
            raise ValueError("Freeze a clean reviewed source commit before notarizing.")
        # Apple secrets remain in Keychain; never inspect values or move them to CI.
        run(
            "xcrun",
            "notarytool",
            "history",
            "--keychain-profile",
            profile,
            "--output-format",
            "json",
            quiet=True,
        )
        if not os.environ.get("CODE_SIGN_IDENTITY", "").startswith(
            "Developer ID Application:"
        ):
            raise ValueError(
                "Set CODE_SIGN_IDENTITY to the existing Developer ID Application identity."
            )
        run("zsh", str(ROOT / "scripts/package_release.sh"), version)
        with open(ROOT / "BLEClipboardMac/Resources/Info.plist", "rb") as file:
            build = str(plistlib.load(file)["CFBundleVersion"])
        logs.mkdir(parents=True, exist_ok=True)
        run(
            "ditto",
            str(ROOT / "BLEClipboardMac/dist/BLE Clipboard.app"),
            str(frozen_app),
        )
        verify_app(frozen_app, version, team, build)
        run("ditto", str(out / archive_name), str(submitted))
        write_json(
            candidate_file,
            {
                "version": version,
                "build": build,
                "team": team,
                "revision": revision,
                "submittedSHA256": digest(submitted),
                "payloads": hashes(out, version),
            },
        )
    candidate = json.loads(candidate_file.read_text())
    if candidate["revision"] != revision or candidate["version"] != version:
        raise ValueError(
            "Checkout differs from frozen notarization source; restore that reviewed worktree, do not rebuild."
        )
    if digest(submitted) != candidate["submittedSHA256"]:
        raise ValueError("Preserved submission archive hash mismatch.")
    for name, expected in candidate["payloads"].items():
        if name != archive_name and digest(out / name) != expected:
            raise ValueError(f"Frozen release payload changed: {name}")
    verify_app(frozen_app, version, team, candidate["build"])
    if (logs / "finalized.json").exists():
        final = json.loads((logs / "finalized.json").read_text())
        if hashes(out, version) != final["payloads"]:
            raise ValueError(
                "Finalized payload set changed. Do not regenerate or clobber public assets."
            )
        checksums(out, version, verify=True)
        run("xcrun", "stapler", "validate", str(frozen_app))
        print(f"Already finalized and verified: {out}")
        return 0
    if not submission_file.exists():
        if marker.exists():
            raise ValueError(
                "Submission attempt already started but its receipt is missing. Recover its ID from Apple history; no automatic resubmission."
            )
        if digest(out / archive_name) != candidate["submittedSHA256"]:
            raise ValueError("Pre-staple candidate archive changed.")
        marker.touch(exist_ok=False)
        result = subprocess.run(
            [
                "xcrun",
                "notarytool",
                "submit",
                str(submitted),
                "--keychain-profile",
                profile,
                "--output-format",
                "json",
            ],
            cwd=ROOT,
            text=True,
            capture_output=True,
        )
        # Persist every response, including a nonzero tool result, before deciding to continue.
        (logs / "submission-response.txt").write_text(
            result.stdout + "\n" + result.stderr
        )
        try:
            receipt = json.loads(result.stdout)
        except ValueError:
            raise RuntimeError(
                "Submission response unavailable. Recover the existing submission; do not resubmit."
            ) from None
        if not receipt.get("id"):
            raise RuntimeError(
                "Submission returned no ID. Inspect the local response before recovery; do not resubmit."
            )
        write_json(submission_file, receipt)
    receipt = json.loads(submission_file.read_text())
    submission_id = receipt["id"]
    info = json.loads(
        run(
            "xcrun",
            "notarytool",
            "info",
            submission_id,
            "--keychain-profile",
            profile,
            "--output-format",
            "json",
            quiet=True,
        )
    )
    write_json(logs / "info.json", info)
    status = info.get("status")
    if status == "In Progress":
        print(
            f"Notarization In Progress: {submission_id}. Retry this command to poll; no rebuild/resubmit."
        )
        return 3
    if status != "Accepted":
        run(
            "xcrun",
            "notarytool",
            "log",
            submission_id,
            "--keychain-profile",
            profile,
            str(logs / "rejection.json"),
        )
        raise RuntimeError(
            f"Notarization {status}. See {logs / 'rejection.json'}; publication blocked."
        )
    validation = subprocess.run(
        ["xcrun", "stapler", "validate", str(frozen_app)], capture_output=True
    )
    if validation.returncode:
        run("xcrun", "stapler", "staple", str(frozen_app))
    run("xcrun", "stapler", "validate", str(frozen_app))
    verify_app(frozen_app, version, team, candidate["build"])
    assessment = subprocess.run(
        ["spctl", "--assess", "--type", "execute", "--verbose=2", str(frozen_app)],
        text=True,
        capture_output=True,
    )
    if (
        assessment.returncode
        or "source=Notarized Developer ID" not in assessment.stderr
    ):
        raise ValueError("Gatekeeper did not assess as Notarized Developer ID.")
    temporary = out / (archive_name + ".tmp")
    prepared_file = logs / "prepared.json"
    if prepared_file.exists():
        prepared = json.loads(prepared_file.read_text())
        if digest(out / archive_name) != prepared["payloads"][archive_name]:
            if (
                not temporary.is_file()
                or digest(temporary) != prepared["payloads"][archive_name]
            ):
                raise ValueError(
                    "Interrupted finalization archive changed; inspect before recovery."
                )
            temporary.replace(out / archive_name)
    else:
        run(
            "ditto",
            "-c",
            "-k",
            "--sequesterRsrc",
            "--keepParent",
            str(frozen_app),
            str(temporary),
        )
        prepared = {
            "submission": submission_id,
            "revision": revision,
            "payloads": hashes(out, version),
            "gatekeeper": assessment.stderr.strip(),
        }
        prepared["payloads"][archive_name] = digest(temporary)
        write_json(prepared_file, prepared)
        temporary.replace(out / archive_name)
    checksums(out, version)
    if hashes(out, version) != prepared["payloads"]:
        raise ValueError("Finalized payload hash mismatch.")
    write_json(logs / "finalized.json", prepared)
    print(f"Verified notarized release set: {out}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1]))
    except (ValueError, OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
