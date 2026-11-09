"""One authoritative payload allowlist/checksum file for a matching release set."""

import argparse
import hashlib
import re
from pathlib import Path


def payloads(version):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Invalid release version.")
    return [
        f"BLE-Clipboard-{version}-universal.zip",
        f"BLE-Clipboard-{version}-windows-x64-setup.exe",
        f"BLE-Clipboard-{version}-windows-x64-portable.zip",
        "ble_clipboard.fap",
        "ble-clipboard-flipper-source.tar.gz",
        "ble-clipboard-source.tar.gz",
        "FLIPPER-SOURCE-SHA256SUMS.txt",
        "WINDOWS-THIRD-PARTY.txt",
        "README.md",
        "NOTICE",
        "LICENSE",
    ]


def digest(file):
    with open(file, "rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def hashes(directory, version):
    directory = Path(directory)
    result = {}
    for name in payloads(version):
        file = directory / name
        if file.is_symlink() or not file.is_file() or file.stat().st_size == 0:
            raise ValueError(f"Missing/unsafe release payload: {name}")
        result[name] = digest(file)
    return result


def checksums(directory, version, *, verify=False):
    directory = Path(directory)
    expected = "".join(
        f"{sha}  {name}\n" for name, sha in hashes(directory, version).items()
    )
    file = directory / "SHA256SUMS.txt"
    if verify:
        if file.read_text(encoding="ascii") != expected:
            raise ValueError(
                "Release checksum set differs; do not replace public assets."
            )
    else:
        temporary = directory / ".SHA256SUMS.tmp"
        temporary.write_text(expected, encoding="ascii")
        temporary.replace(file)


def verify_windows(directory, version, revision):
    directory = Path(directory)
    if (directory / "SOURCE-COMMIT.txt").read_text(
        encoding="utf-8-sig"
    ).strip() != revision:
        raise ValueError(
            "Windows artifacts are not from this reviewed source revision."
        )
    folder = directory / f"v{version}"
    expected_names = {
        f"BLE-Clipboard-{version}-windows-x64-setup.exe",
        f"BLE-Clipboard-{version}-windows-x64-portable.zip",
    }
    lines = (folder / "SHA256SUMS-windows.txt").read_text(encoding="ascii").splitlines()
    values = {}
    for line in lines:
        sha, separator, name = line.partition("  ")
        if (
            not separator
            or not re.fullmatch(r"[0-9a-f]{64}", sha)
            or name in values
            or name not in expected_names
        ):
            raise ValueError("Invalid Windows build checksum receipt.")
        values[name] = sha
    if values.keys() != expected_names or any(
        digest(folder / name) != sha for name, sha in values.items()
    ):
        raise ValueError("Windows build payloads differ from their CI receipt.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("version")
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--windows-revision")
    args = parser.parse_args()
    if args.windows_revision:
        verify_windows(args.directory, args.version, args.windows_revision)
    else:
        checksums(args.directory, args.version, verify=args.verify)
