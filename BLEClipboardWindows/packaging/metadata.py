"""Generate package metadata from VERSION and collect installed runtime licenses."""

import platform
import struct
import sys
from importlib import metadata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "BLEClipboardWindows"))
from ble_clipboard.release import version


def machine(path):
    with open(path, "rb") as file:
        if file.read(2) != b"MZ":
            raise ValueError("Not a PE executable.")
        file.seek(0x3C)
        offset = struct.unpack("<I", file.read(4))[0]
        file.seek(offset)
        if file.read(4) != b"PE\0\0":
            raise ValueError("Invalid PE header.")
        return struct.unpack("<H", file.read(2))[0]


def generate():
    if (
        sys.platform != "win32"
        or platform.machine().lower() not in ("amd64", "x86_64")
        or machine(sys.executable) != 0x8664
    ):
        raise ValueError(
            "Build Windows x64 packages with native x64 Python on Windows."
        )
    value = version()
    numeric = tuple(map(int, value.split("."))) + (0,)
    out = ROOT / "BLEClipboardWindows/build"
    out.mkdir(parents=True, exist_ok=True)
    info = f"""VSVersionInfo(ffi=FixedFileInfo(filevers={numeric!r}, prodvers={numeric!r}, mask=0x3f, flags=0, OS=0x40004, fileType=1, subtype=0, date=(0,0)), kids=[StringFileInfo([StringTable('040904B0', [StringStruct('FileDescription','BLE Clipboard Windows beta'),StringStruct('FileVersion','{value}'),StringStruct('ProductName','BLE Clipboard'),StringStruct('ProductVersion','{value}')])]),VarFileInfo([VarStruct('Translation',[1033,1200])])])"""
    (out / "version-info.txt").write_text(info, encoding="utf-8")
    notices = [
        "BLE Clipboard Windows runtime licenses\n",
        (ROOT / "LICENSE").read_text(),
        (ROOT / "NOTICE").read_text(),
    ]
    # Build tooling is not shipped. Runtime distributions must carry their actual license text.
    names = [
        d.metadata["Name"]
        for d in metadata.distributions()
        if d.metadata["Name"].lower()
        not in (
            "pip",
            "setuptools",
            "pyinstaller",
            "pyinstaller-hooks-contrib",
            "altgraph",
            "pefile",
            "pywin32-ctypes",
            "pillow",
            "packaging",
        )
    ]
    for name in sorted(names):
        dist = metadata.distribution(name)
        files = [
            f
            for f in dist.files or []
            if any(part.lower().startswith(("license", "copying")) for part in f.parts)
        ]
        if not files:
            raise ValueError(f"Runtime license missing: {name}")
        notices.append(f"\n--- {name} {dist.version} ---\n")
        for file in files:
            notices.append(
                dist.locate_file(file).read_text(encoding="utf-8", errors="replace")
            )
    python_license = Path(sys.base_prefix) / "LICENSE.txt"
    notices += ["\n--- Python ---\n", python_license.read_text()]
    for runtime in ("tcl8.6", "tk8.6"):
        license_file = Path(sys.base_prefix) / "tcl" / runtime / "license.terms"
        if not license_file.exists():
            raise ValueError(f"Tcl/Tk license missing: {license_file}")
        notices += [f"\n--- {runtime} ---\n", license_file.read_text()]
    (out / "THIRD-PARTY.txt").write_text("\n".join(notices), encoding="utf-8")


if __name__ == "__main__":
    if len(sys.argv) == 2:
        if machine(sys.argv[1]) != 0x8664:
            raise SystemExit("Executable is not x64.")
    else:
        generate()
