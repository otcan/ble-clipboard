"""Verify a frozen matching set; optionally replace a draft and publish it once."""

import argparse
import json
import struct
import subprocess
import tarfile
import tempfile
import zipfile
from pathlib import Path

from notarize_candidate import ROOT, verify_app
from release_assets import checksums, digest, hashes, payloads

REPO = "otcan/ble-clipboard"


def run(*args):
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed: {result.stderr.strip()}")
    return result.stdout


def public_metadata(version):
    return json.loads(
        run(
            "curl",
            "-q",
            "--fail",
            "--silent",
            "--show-error",
            "--proto",
            "=https",
            f"https://api.github.com/repos/{REPO}/releases/tags/v{version}",
        )
    )


def verify_downloads(directory, version, expected, candidate):
    checksums(directory, version, verify=True)
    if hashes(directory, version) != expected:
        raise ValueError(
            "Downloaded release differs from frozen artifacts. Public assets must not be overwritten."
        )
    with zipfile.ZipFile(
        directory / f"BLE-Clipboard-{version}-windows-x64-portable.zip"
    ) as archive:
        names = [
            name
            for name in archive.namelist()
            if name == "BLEClipboard/BLEClipboard.exe"
        ]
        if len(names) != 1:
            raise ValueError("Portable package has no unique executable.")
        with archive.open(names[0]) as executable:
            if executable.read(2) != b"MZ":
                raise ValueError("Invalid portable PE executable.")
            executable.seek(0x3C)
            offset = struct.unpack("<I", executable.read(4))[0]
            if offset > 65536:
                raise ValueError("Invalid portable PE header offset.")
            executable.seek(offset)
            if executable.read(6) != b"PE\0\0\x64\x86":
                raise ValueError("Portable executable is not x64.")
    with tarfile.open(directory / "ble-clipboard-source.tar.gz", "r:gz") as archive:
        names = archive.getnames()
        if "BLEClipboardWindows/ble_clipboard/macros.py" not in names:
            raise ValueError("Corresponding Windows source missing.")
        if any(
            any(
                part.startswith(".venv") or part in ("dist", ".build", "__pycache__")
                for part in Path(name).parts
            )
            for name in names
        ):
            raise ValueError("Unallowlisted build/runtime files in source archive.")
        if archive.extractfile("VERSION").read().decode().strip() != version:
            raise ValueError("Corresponding source version mismatch.")
    with tempfile.TemporaryDirectory(prefix="ble-clipboard-verify-") as staging:
        run(
            "ditto",
            "-x",
            "-k",
            str(directory / f"BLE-Clipboard-{version}-universal.zip"),
            staging,
        )
        app = Path(staging) / "BLE Clipboard.app"
        verify_app(app, version, candidate["team"], candidate["build"])
        run("xcrun", "stapler", "validate", str(app))
        assessment = subprocess.run(
            ["spctl", "--assess", "--type", "execute", "--verbose=2", str(app)],
            text=True,
            capture_output=True,
        )
        if (
            assessment.returncode
            or "source=Notarized Developer ID" not in assessment.stderr
        ):
            raise ValueError(
                "Downloaded Mac app failed Notarized Developer ID assessment."
            )


def main(version, publish):
    directory = ROOT / "dist" / f"v{version}"
    logs = ROOT / "dist/notary-logs" / f"v{version}"
    candidate = json.loads((logs / "candidate.json").read_text())
    frozen = json.loads((logs / "finalized.json").read_text())
    checksums(directory, version, verify=True)
    if hashes(directory, version) != frozen["payloads"]:
        raise ValueError("Local frozen artifact set changed.")
    tag = f"v{version}"
    commit = run("gh", "api", f"repos/{REPO}/commits/{tag}", "--jq", ".sha").strip()
    if commit != candidate["revision"] or commit != frozen["revision"]:
        raise ValueError("Tag differs from reviewed source revision.")
    release = json.loads(
        run(
            "gh",
            "release",
            "view",
            tag,
            "--repo",
            REPO,
            "--json",
            "isDraft,tagName,url,assets",
        )
    )
    names = payloads(version) + ["SHA256SUMS.txt"]
    if release["tagName"] != tag or {a["name"] for a in release["assets"]} != set(
        names
    ):
        raise ValueError(
            "Unexpected release asset set; inspect the draft before replacement."
        )
    if release["isDraft"]:
        if not publish:
            raise ValueError(
                "Draft has not been finalized. Use --publish only with publication authorization."
            )
        runs = json.loads(
            run(
                "gh",
                "run",
                "list",
                "--repo",
                REPO,
                "--workflow",
                "release.yml",
                "--commit",
                commit,
                "--json",
                "status,conclusion",
                "--limit",
                "1",
            )
        )
        if not runs or runs[0] != {"status": "completed", "conclusion": "success"}:
            raise ValueError(
                "Tag workflow must finish successfully before asset replacement."
            )
        verify_downloads(directory, version, frozen["payloads"], candidate)
        run(
            "gh",
            "release",
            "upload",
            tag,
            "--repo",
            REPO,
            "--clobber",
            *(str(directory / name) for name in names),
        )
        with tempfile.TemporaryDirectory(prefix="ble-clipboard-draft-") as staging:
            args = ["gh", "release", "download", tag, "--repo", REPO, "--dir", staging]
            for name in names:
                args += ["--pattern", name]
            run(*args)
            verify_downloads(Path(staging), version, frozen["payloads"], candidate)
        run("gh", "release", "edit", tag, "--repo", REPO, "--draft=false")
    metadata = public_metadata(version)
    if (
        metadata.get("draft") is not False
        or metadata.get("tag_name") != tag
        or metadata.get("html_url") != f"https://github.com/{REPO}/releases/tag/{tag}"
    ):
        raise ValueError("Public exact-tag API mismatch.")
    if len(metadata["assets"]) != len(names) or {
        a["name"] for a in metadata["assets"]
    } != set(names):
        raise ValueError("Public asset set is incomplete or duplicated.")
    with tempfile.TemporaryDirectory(prefix="ble-clipboard-public-") as staging:
        for asset in metadata["assets"]:
            expected_url = (
                f"https://github.com/{REPO}/releases/download/{tag}/{asset['name']}"
            )
            if (
                asset["browser_download_url"] != expected_url
                or asset["state"] != "uploaded"
                or asset["size"] <= 0
            ):
                raise ValueError("Public exact-tag download mismatch.")
            run(
                "curl",
                "-q",
                "--fail",
                "--silent",
                "--show-error",
                "--location",
                "--proto",
                "=https",
                "--output",
                str(Path(staging) / asset["name"]),
                expected_url,
            )
        verify_downloads(Path(staging), version, frozen["payloads"], candidate)
        if digest(Path(staging) / "SHA256SUMS.txt") != digest(
            directory / "SHA256SUMS.txt"
        ):
            raise ValueError("Public checksum file changed.")
    (logs / "public-verified.json").write_text(
        json.dumps(
            {
                "revision": commit,
                "release": metadata["html_url"],
                "payloads": frozen["payloads"],
                "anonymous": True,
                "mac_signature_ticket_gatekeeper": True,
                "windows_x64": True,
            },
            indent=2,
        )
        + "\n"
    )
    print(f"Verified all twelve anonymous public downloads: {metadata['html_url']}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("version")
    parser.add_argument("--publish", action="store_true")
    args = parser.parse_args()
    main(args.version, args.publish)
