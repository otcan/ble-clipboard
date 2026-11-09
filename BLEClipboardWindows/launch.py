"""PyInstaller entry point, including a packaging smoke test for Windows CI."""

import json
import sys
import traceback
from pathlib import Path


def main():
    if "--offline-ui-test" in sys.argv:
        from ble_clipboard.ui_checks import run

        scales = (
            (float(sys.argv[sys.argv.index("--ui-scale") + 1]),)
            if "--ui-scale" in sys.argv
            else (1, 1.5, 2)
        )
        run(Path(sys.argv[sys.argv.index("--offline-ui-test") + 1]), scales=scales)
        return 0
    if "--self-test" in sys.argv:
        import tkinter as tk

        from ble_clipboard.macros import (
            compile_macro,
            decode_library,
            encode_library,
            new_macro,
            step,
        )
        from ble_clipboard.protocol import Timing, compile_text
        from ble_clipboard.release import version
        from bleak.backends.winrt.client import BleakClientWinRT
        from bleak.backends.winrt.scanner import BleakScannerWinRT

        assert BleakClientWinRT and BleakScannerWinRT
        assert (
            compile_text("Hello", 0, Timing(80, 30))[:11]
            == b"BCM4\x02\x00\x07\x50\x00\x1e\x00"
        )
        macro = new_macro()
        macro["steps"] = [step("text", "Packaged test")]
        assert decode_library(encode_library([macro])) == [macro]
        assert compile_macro(macro).program.startswith(b"BCM4") and version()
        root = tk.Tk()
        root.withdraw()
        root.update()
        root.destroy()
        return 0
    from ble_clipboard.app import main as run

    run()
    return 0


if __name__ == "__main__":
    code = 0
    try:
        code = main()
    except Exception:
        code = 1
        details = traceback.format_exc()
        if sys.stderr is not None:
            sys.stderr.write(details)
        if "--report" in sys.argv:
            Path(sys.argv[sys.argv.index("--report") + 1]).write_text(
                json.dumps({"ok": False, "error": details})
            )
    else:
        if "--report" in sys.argv:
            Path(sys.argv[sys.argv.index("--report") + 1]).write_text(
                json.dumps({"ok": True})
            )
    raise SystemExit(code)
