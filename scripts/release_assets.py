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


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("version")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    checksums(args.directory, args.version, verify=args.verify)
