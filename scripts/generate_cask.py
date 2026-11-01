#!/usr/bin/env python3
"""Generate a Homebrew cask from a real release artifact and its SHA-256."""

import argparse
import hashlib
from pathlib import Path
import re
from string import Template


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("archive", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        parser.error("version must be x.y.z")
    with args.archive.open("rb") as archive:
        digest = hashlib.file_digest(archive, "sha256").hexdigest()
    template = Path(__file__).resolve().parents[1] / "packaging/homebrew/ble-clipboard.rb.in"
    result = Template(template.read_text()).substitute(version=args.version, sha256=digest)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(result)
    print(f"Generated {args.output} ({digest})")


if __name__ == "__main__":
    main()
