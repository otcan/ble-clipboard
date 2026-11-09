"""Windows CI only: synthetic libraries, BLE disabled, no clipboard or HID access."""

import ctypes
import json
import sys
import tempfile
import time
import tkinter as tk
from ctypes import wintypes
from pathlib import Path
from tkinter import font

from PIL import ImageGrab, ImageStat

from .app import ClipboardApp
from .macros import new_macro, step


def capture(window, path):
    user = ctypes.windll.user32
    user.GetAncestor.restype = wintypes.HWND
    user.GetAncestor.argtypes = (wintypes.HWND, wintypes.UINT)
    user.GetWindowRect.argtypes = (wintypes.HWND, ctypes.POINTER(wintypes.RECT))
    user.SetWindowPos.argtypes = (
        wintypes.HWND,
        wintypes.HWND,
        ctypes.c_int,
        ctypes.c_int,
        ctypes.c_int,
        ctypes.c_int,
        wintypes.UINT,
    )
    hwnd = user.GetAncestor(window.winfo_id(), 2)
    rect = wintypes.RECT()
    user.GetWindowRect(hwnd, ctypes.byref(rect))
    width, height = rect.right - rect.left, rect.bottom - rect.top
    work = wintypes.RECT()
    if not user.SystemParametersInfoW(0x0030, 0, ctypes.byref(work), 0):
        raise RuntimeError("CI work area unavailable.")
    viewport_w, viewport_h = work.right - work.left, work.bottom - work.top

    def positions(size, viewport):
        result = [0]
        while result[-1] + viewport < size:
            result.append(min(result[-1] + viewport - 96, size - viewport))
        return result

    xs, ys = positions(width, viewport_w), positions(height, viewport_h)
    colored = False
    receipts = []
    try:
        for row, y in enumerate(ys):
            for column, x in enumerate(xs):
                # Move only this isolated synthetic test window; no input or hotkeys.
                if not user.SetWindowPos(
                    hwnd,
                    None,
                    work.left - x,
                    work.top - y,
                    0,
                    0,
                    0x0001 | 0x0010 | 0x0040,
                ):
                    raise RuntimeError("Test window positioning failed.")
                window.update()
                time.sleep(0.1)
                window.update()
                image = (
                    ImageGrab.grab(window=hwnd)
                    if len(xs) == len(ys) == 1
                    else ImageGrab.grab(
                        bbox=(
                            work.left,
                            work.top,
                            work.left + min(viewport_w, width - x),
                            work.top + min(viewport_h, height - y),
                        ),
                        all_screens=True,
                    )
                )
                colored |= max(ImageStat.Stat(image).stddev) > 5
                target = (
                    path
                    if len(xs) == len(ys) == 1
                    else path.with_name(f"{path.stem}-tile-{row}-{column}.png")
                )
                image.save(target)
                receipts.append(
                    {
                        "file": target.name,
                        "window_offset": [x, y],
                        "pixels": list(image.size),
                    }
                )
        if not colored:
            raise RuntimeError("Blank UI viewport screenshots.")
        path.with_suffix(".capture.json").write_text(
            json.dumps(
                {
                    "window": [width, height],
                    "viewport": [viewport_w, viewport_h],
                    "tiles": receipts,
                    "unedited_native_screen_capture": True,
                },
                indent=2,
            )
        )
    finally:
        user.SetWindowPos(
            hwnd, None, rect.left, rect.top, 0, 0, 0x0001 | 0x0010 | 0x0040
        )
        window.update()


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


def run(directory, *, scales=(1, 1.5, 2)):
    if sys.platform != "win32":
        raise RuntimeError("Genuine Windows UI checks must run on Windows.")
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    results = []
    for scale in scales:
        with tempfile.TemporaryDirectory() as data:
            root = tk.Tk()
            root.tk.call("tk", "scaling", 96 / 72 * scale)
            for name in font.names(root):
                named = font.nametofont(name, root=root)
                named.configure(size=named.cget("size"))
            root.maxsize(6000, 4000)
            app = ClipboardApp(root, data_dir=data, offline=True)
            try:
                assert app.worker is None
                root.geometry(f"{int(960 * scale)}x{int(640 * scale)}+0+0")
                root.minsize(int(960 * scale), int(640 * scale))
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
                app.search.set("no-such-synthetic-macro")
                root.update()
                assert not app.visible
                app.search.set("")
                root.update()
                visible_controls_fit(root)
                assert app.stop_button.winfo_ismapped(), "Stop must remain visible"
                capture(root, directory / f"editor-{int(scale * 100)}.png")
                app.replace_text("Offline Quick Paste preview")
                app.tabs.select(0)
                root.update()
                visible_controls_fit(root)
                assert app.quick_run_button.winfo_ismapped()
                capture(root, directory / f"quick-paste-{int(scale * 100)}.png")
                app.tabs.select(1)
                root.update()
                app.open_review()
                root.update()
                review = app.review
                review.geometry(f"{int(760 * scale)}x{int(660 * scale)}+0+0")
                root.update()
                assert review.model.compiled and review.run_button.instate(["disabled"])
                review.confirm_toggle.invoke()
                assert review.model.confirmed
                app.mode.set("Variable")
                assert not review.model.confirmed and review.model.compiled is None
                review.prepare()
                assert review.model.compiled.program[6] == 7
                visible_controls_fit(review)
                assert review.run_button.winfo_ismapped(), (
                    "Run confirmation must remain visible"
                )
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
                root.geometry(f"{int(960 * scale)}x{int(640 * scale)}+0+0")
                root.update()
                visible_controls_fit(root)
                assert app.stop_button.winfo_ismapped(), (
                    "Stop must remain visible at minimum size"
                )
                capture(root, directory / f"minimum-{int(scale * 100)}.png")
                from .dialogs import StepDialog, parameters_dialog

                for kind in ("text", "delay", "moveMouse", "repeatFor"):
                    item = step(kind, "Offline edit" if kind == "text" else "")
                    if kind == "repeatFor":
                        item["children"] = [step("moveMouse")]
                    app.current["steps"] = [item]
                    app.refresh_steps()
                    dialog = StepDialog(app, app.current["steps"], 0)
                    root.update()
                    visible_controls_fit(dialog)
                    capture(dialog, directory / f"step-{kind}-{int(scale * 100)}.png")
                    dialog.destroy()
                parameter_window = parameters_dialog(app)
                root.update()
                visible_controls_fit(parameter_window)
                capture(
                    parameter_window, directory / f"parameters-{int(scale * 100)}.png"
                )
                parameter_window.destroy()
                crowded = new_macro("Many parameters", target=1)
                crowded["parameters"] = [
                    {"id": f"field{i}", "label": f"Parameter {i}"} for i in range(32)
                ]
                crowded["steps"] = [step("template", "Value: {{field0}}")]
                app.mode.set("Fast")
                app.load_macro(crowded)
                app.open_review()
                root.update()
                visible_controls_fit(app.review)
                assert app.review.run_button.winfo_ismapped()
                capture(
                    app.review, directory / f"many-parameters-{int(scale * 100)}.png"
                )
                app.review.destroy()
                app.review = None
                results.append(
                    {
                        "scale": scale,
                        "editing": True,
                        "review_invalidation": True,
                        "errors": True,
                        "minimum": True,
                        "step_dialogs": True,
                        "parameters": True,
                        "ble_disabled": True,
                    }
                )
            finally:
                app.dirty = False
                app.state = "disconnected"
                app.close()
    for result in results:
        (directory / f"results-{int(result['scale'] * 100)}.json").write_text(
            json.dumps(result, indent=2)
        )
