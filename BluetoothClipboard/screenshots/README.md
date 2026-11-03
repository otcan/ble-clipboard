# Screenshot Provenance

BLE Clipboard takes over USB as a keyboard/mouse, disconnecting qFlipper.
These images use the Flipper catalog AGENTS.md exception for USB-HID apps.
They are not photographs or evidence of a physical hardware test.

The host-only adapter compiles the actual clipboard_screen.c with the official
firmware 1.5.1 u8g2 renderer, haxrcorp4089 font and button icons. It renders the
same Info and Downloads states at 128x64, then uses nearest-neighbor 4x scaling
and exactly the catalog qFlipper palette: orange (254,138,44) and black (0,0,0).
No text, border or annotation is added to the resulting 512x256 PNGs.

Reproduce with Python 3, Pillow, a C compiler and the official 1.5.1 firmware
source checkout:

    python3 scripts/render_catalog_screens.py /path/to/flipperzero-firmware

This tool does not open a device, start the app, access pairing keys or read any
user library. The adapter is not compiled into the shipped Flipper application.
