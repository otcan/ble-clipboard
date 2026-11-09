"""Windows CI only: synthetic libraries, BLE disabled, no clipboard or HID access."""

import ctypes
import json
import sys
import tempfile
import tkinter as tk
from ctypes import wintypes
from pathlib import Path

from PIL import Image, ImageStat

from .app import ClipboardApp
from .macros import new_macro, step


def capture(window, path):
    user, gdi = ctypes.windll.user32, ctypes.windll.gdi32
    user.GetAncestor.restype = wintypes.HWND
    user.GetWindowDC.restype = wintypes.HDC
    gdi.CreateCompatibleDC.restype = wintypes.HDC
    gdi.CreateCompatibleBitmap.restype = wintypes.HBITMAP
    gdi.SelectObject.restype = wintypes.HGDIOBJ
    user.GetAncestor.argtypes = (wintypes.HWND, wintypes.UINT)
    user.GetWindowDC.argtypes = (wintypes.HWND,)
    user.GetWindowRect.argtypes = (wintypes.HWND, ctypes.POINTER(wintypes.RECT))
    user.ReleaseDC.argtypes = (wintypes.HWND, wintypes.HDC)
    user.PrintWindow.argtypes = (wintypes.HWND, wintypes.HDC, wintypes.UINT)
    gdi.CreateCompatibleDC.argtypes = (wintypes.HDC,)
    gdi.CreateCompatibleBitmap.argtypes = (wintypes.HDC, ctypes.c_int, ctypes.c_int)
    gdi.SelectObject.argtypes = (wintypes.HDC, wintypes.HGDIOBJ)
    gdi.GetDIBits.argtypes = (
        wintypes.HDC,
        wintypes.HBITMAP,
        wintypes.UINT,
        wintypes.UINT,
        ctypes.c_void_p,
        ctypes.c_void_p,
        wintypes.UINT,
    )
    gdi.DeleteDC.argtypes = (wintypes.HDC,)
    gdi.DeleteObject.argtypes = (wintypes.HGDIOBJ,)
    hwnd = user.GetAncestor(window.winfo_id(), 2)
    rect = wintypes.RECT()
    user.GetWindowRect(hwnd, ctypes.byref(rect))
    width, height = rect.right - rect.left, rect.bottom - rect.top
    dc = user.GetWindowDC(hwnd)
    memory = gdi.CreateCompatibleDC(dc)
    bitmap = gdi.CreateCompatibleBitmap(dc, width, height)
    previous = gdi.SelectObject(memory, bitmap)
    try:
        if not user.PrintWindow(hwnd, memory, 2):
            raise RuntimeError("Windows failed to render test window.")

        class Header(ctypes.Structure):
            _fields_ = [
                ("size", wintypes.DWORD),
                ("width", wintypes.LONG),
                ("height", wintypes.LONG),
                ("planes", wintypes.WORD),
                ("bits", wintypes.WORD),
                ("compression", wintypes.DWORD),
                ("image_size", wintypes.DWORD),
                ("x", wintypes.LONG),
                ("y", wintypes.LONG),
                ("used", wintypes.DWORD),
                ("important", wintypes.DWORD),
            ]

        header = Header(
            ctypes.sizeof(Header),
            width,
            -height,
            1,
            32,
            0,
            width * height * 4,
            0,
            0,
            0,
            0,
        )
        pixels = ctypes.create_string_buffer(width * height * 4)
        gdi.SelectObject(memory, previous)
        if not gdi.GetDIBits(
            memory, bitmap, 0, height, pixels, ctypes.byref(header), 0
        ):
            raise RuntimeError("Windows screenshot readback failed.")
        image = Image.frombytes("RGB", (width, height), pixels.raw, "raw", "BGRX")
        if max(ImageStat.Stat(image).stddev) < 5:
            raise RuntimeError("Blank UI screenshot.")
        image.save(path)
    finally:
        gdi.SelectObject(memory, previous)
        gdi.DeleteObject(bitmap)
        gdi.DeleteDC(memory)
        user.ReleaseDC(hwnd, dc)


def visible_controls_fit(window):
    def inspect(parent):
        for widget in parent.winfo_children():
            if not widget.winfo_ismapped() or isinstance(widget, tk.Toplevel):
                continue
            if widget.winfo_manager() in ("pack", "grid"):
                assert widget.winfo_x() >= -1 and widget.winfo_y() >= -1, str(widget)
                assert (
                    widget.winfo_x() + widget.winfo_width() <= parent.winfo_width() + 2
                ), str(widget)
                assert (
                    widget.winfo_y() + widget.winfo_height()
                    <= parent.winfo_height() + 2
                ), str(widget)
                if isinstance(widget, (tk.Button,)) or widget.winfo_class() in (
                    "TButton",
                    "TCheckbutton",
                    "TLabel",
                    "TRadiobutton",
                ):
                    assert widget.winfo_reqwidth() <= widget.winfo_width() + 2, str(
                        widget
                    )
                    assert widget.winfo_reqheight() <= widget.winfo_height() + 2, str(
                        widget
                    )
            inspect(widget)

    inspect(window)


def run(directory):
    if sys.platform != "win32":
        raise RuntimeError("Genuine Windows UI checks must run on Windows.")
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    results = []
    for scale in (1, 1.5, 2):
        with tempfile.TemporaryDirectory() as data:
            root = tk.Tk()
            root.tk.call("tk", "scaling", 96 / 72 * scale)
            root.maxsize(6000, 4000)
            app = ClipboardApp(root, data_dir=data, offline=True)
            try:
                assert app.worker is None
                root.geometry(f"{int(1120 * scale)}x{int(800 * scale)}+0+0")
                root.minsize(int(960 * scale), int(720 * scale))
                macro = new_macro("Offline Windows editor demo", target=1)
                macro["steps"] = [
                    step("text", "echo Hello from BLE Clipboard"),
                    step("delay", milliseconds=250),
                    step("chord", "ENTER"),
                ]
                app.load_macro(macro)
                app.tabs.select(1)
                root.update()
                app.name.set("Edited offline macro")
                assert app.dirty
                assert app.save_macro()
                assert app.library.macros[-1]["name"] == "Edited offline macro"
                app.kind.set("moveMouse")
                app.add_step()
                app.steps.selection_set("3")
                app.move_step(-1)
                assert app.current["steps"][2]["kind"] == "moveMouse"
                app.remove_step()
                assert len(app.current["steps"]) == 3
                app.search.set("clipboard")
                root.update()
                assert not app.visible
                app.search.set("")
                root.update()
                visible_controls_fit(root)
                capture(root, directory / f"editor-{int(scale * 100)}.png")
                app.open_review()
                root.update()
                review = app.review
                review.geometry(f"{int(760 * scale)}x{int(730 * scale)}+0+0")
                root.update()
                assert review.model.compiled and review.run_button.instate(["disabled"])
                review.confirm_toggle.invoke()
                assert review.model.confirmed
                app.mode.set("Variable")
                assert not review.model.confirmed and review.model.compiled is None
                review.prepare()
                assert review.model.compiled.program[6] == 7
                visible_controls_fit(review)
                capture(review, directory / f"review-{int(scale * 100)}.png")
                review.destroy()
                app.review = None
                app.pause.set("1001")
                app.mode.set("Custom")
                app.open_review()
                root.update()
                assert (
                    app.review.model.compiled is None
                    and app.review.run_button.instate(["disabled"])
                )
                capture(app.review, directory / f"error-{int(scale * 100)}.png")
                app.review.destroy()
                app.review = None
                root.geometry(f"{int(960 * scale)}x{int(720 * scale)}+0+0")
                root.update()
                visible_controls_fit(root)
                capture(root, directory / f"minimum-{int(scale * 100)}.png")
                results.append(
                    {
                        "scale": scale,
                        "editing": True,
                        "review_invalidation": True,
                        "errors": True,
                        "minimum": True,
                        "ble_disabled": True,
                    }
                )
            finally:
                app.dirty = False
                app.state = "disconnected"
                app.close()
    (directory / "results.json").write_text(json.dumps(results, indent=2))
