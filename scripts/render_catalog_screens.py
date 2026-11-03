#!/usr/bin/env python3
"""Render the real screen C code for the catalog's USB-HID screenshot exception."""
import argparse
from pathlib import Path
import platform
import subprocess
import tempfile

from PIL import Image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("firmware", type=Path, help="Official firmware 1.5.1 source checkout")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    firmware = args.firmware.resolve()
    u8g2 = firmware / "lib/u8g2"
    destination = root / "dist/catalog-preview"
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as temp:
        build = Path(temp)
        icons = []
        for name, asset in (("left", "ButtonLeft_4x7"), ("center", "ButtonCenter_7x7"), ("right", "ButtonRight_4x7")):
            image = Image.open(firmware / f"assets/icons/Common/{asset}.png").convert("RGB")
            assert image.size == ((7, 7) if name == "center" else (4, 7))
            rows = [sum((1 << x) for x in range(image.width) if image.getpixel((x, y)) == (0, 0, 0)) for y in range(7)]
            icons.append(f"static const uint8_t button_{name}[] = {{{','.join(map(str, rows))}}};")
        (build / "button_icons.h").write_text("\n".join(icons) + "\n", encoding="ascii")
        units = ("u8g2_font", "u8g2_fonts", "u8g2_buffer", "u8g2_setup", "u8g2_hvline", "u8g2_ll_hvline", "u8g2_line", "u8g2_box", "u8g2_bitmap", "u8g2_intersection", "u8x8_8x8")
        command = ["cc", "-std=c11", "-O2", "-ffunction-sections", "-fdata-sections",
                   "-I" + str(root / "scripts/catalog_screen"), "-I" + str(root / "BluetoothClipboard"),
                   "-I" + str(u8g2), "-I" + str(build), str(root / "scripts/catalog_screen/render.c"),
                   str(root / "BluetoothClipboard/clipboard_screen.c")]
        command += [str(u8g2 / f"{unit}.c") for unit in units]
        command += ["-Wl,-dead_strip" if platform.system() == "Darwin" else "-Wl,--gc-sections", "-o", str(build / "render")]
        subprocess.run(command, check=True)
        for name in ("info", "downloads"):
            frame = subprocess.check_output([str(build / "render"), name])
            assert len(frame) == 1024
            image = Image.new("RGB", (128, 64))
            image.putdata([(0, 0, 0) if frame[(y // 8) * 128 + x] & (1 << (y % 8)) else (254, 138, 44)
                           for y in range(64) for x in range(128)])
            image = image.resize((512, 256), Image.Resampling.NEAREST)
            assert set(image.getdata()) == {(0, 0, 0), (254, 138, 44)}
            image.save(destination / f"{name}.png")
            print(f"Rendered actual clipboard_screen_draw / firmware 1.5.1 font: {name}.png")


if __name__ == "__main__":
    main()
