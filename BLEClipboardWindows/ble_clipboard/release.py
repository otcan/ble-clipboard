"""Exact-version companion links; no latest-release fallback or credentials."""

import json
import re
import sys
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

REPOSITORY = "https://github.com/otcan/ble-clipboard"


def version():
    root = (
        Path(sys._MEIPASS)
        if getattr(sys, "frozen", False)
        else Path(__file__).resolve().parents[2]
    )
    value = (root / "VERSION").read_text(encoding="ascii").strip()
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", value):
        raise ValueError("Invalid application version.")
    return value


def links(value):
    if not re.fullmatch(r"\d+\.\d+\.\d+", value):
        raise ValueError("Invalid release version.")
    base = f"{REPOSITORY}/releases/download/v{value}"
    return {
        "Windows installer": f"{base}/BLE-Clipboard-{value}-windows-x64-setup.exe",
        "Windows portable": f"{base}/BLE-Clipboard-{value}-windows-x64-portable.zip",
        "Mac companion": f"{base}/BLE-Clipboard-{value}-universal.zip",
        "Flipper app": f"{base}/ble_clipboard.fap",
        "Checksums": f"{base}/SHA256SUMS.txt",
    }


def availability(value, document):
    expected = links(value)
    if (
        not isinstance(document, dict)
        or document.get("draft") is not False
        or document.get("tag_name") != f"v{value}"
        or document.get("html_url") != f"{REPOSITORY}/releases/tag/v{value}"
    ):
        return False
    assets = document.get("assets")
    if not isinstance(assets, list) or len(assets) > 64:
        return False
    for url in expected.values():
        matches = [
            a
            for a in assets
            if isinstance(a, dict) and a.get("name") == url.rsplit("/", 1)[1]
        ]
        if (
            len(matches) != 1
            or matches[0].get("browser_download_url") != url
            or matches[0].get("state") != "uploaded"
            or type(matches[0].get("size")) is not int
            or matches[0]["size"] <= 0
        ):
            return False
    return True


def check(value):
    url = f"https://api.github.com/repos/otcan/ble-clipboard/releases/tags/v{value}"
    request = Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": f"BLE-Clipboard/{version()}",
        },
    )
    try:
        with urlopen(request, timeout=15) as response:
            if response.url != url:
                raise ValueError("Unexpected release redirect.")
            data = response.read(1_000_001)
            if len(data) > 1_000_000:
                raise ValueError("Release response too large.")
            return availability(value, json.loads(data))
    except HTTPError as error:
        if error.code == 404:
            return False
        raise
