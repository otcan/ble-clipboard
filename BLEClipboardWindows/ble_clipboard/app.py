"""Windows macro workspace. Tk owns UI; one MTA asyncio worker owns BLE."""

import asyncio
import concurrent.futures
import json
import os
import queue
import sys
import threading
import tkinter as tk
from copy import deepcopy
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from .macros import (
    KINDS,
    MacroLibrary,
    atomic_write,
    encode_library,
    mouse_preset,
    new_macro,
    step,
    validate,
)
from .protocol import LAYOUT_IDS, LAYOUTS, PRESETS, TARGET_IDS, TARGETS, Timing
from .release import version
from .transport import ClipboardTransport

TITLES = dict(
    zip(
        KINDS,
        (
            "Literal text",
            "Template",
            "Key combination",
            "Delay",
            "Move Mouse",
            "Repeat",
        ),
    )
)


class AsyncWorker:
    def __init__(self, events):
        self.events = events
        self.loop = asyncio.new_event_loop()
        self.transport = ClipboardTransport(
            lambda kind, value: events.put((kind, value))
        )
        self.thread = threading.Thread(
            target=self._run, name="Bluetooth-MTA", daemon=True
        )
        self.thread.start()

    def _run(self):
        asyncio.set_event_loop(self.loop)
        if sys.platform == "win32":
            from bleak.backends.winrt.util import uninitialize_sta

            uninitialize_sta()
        self.loop.run_forever()
        self.loop.close()

    def submit(self, coroutine):
        future = asyncio.run_coroutine_threadsafe(coroutine, self.loop)

        def finished(result):
            try:
                result.result()
            except (asyncio.CancelledError, concurrent.futures.CancelledError):
                pass
            except Exception as error:
                self.events.put(("error", str(error) or type(error).__name__))

        future.add_done_callback(finished)
        return future

    def close(self):
        async def shutdown():
            await self.transport.disconnect()
            tasks = [t for t in asyncio.all_tasks() if t is not asyncio.current_task()]
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)

        future = self.submit(shutdown())
        future.add_done_callback(
            lambda _: self.loop.call_soon_threadsafe(self.loop.stop)
        )


def button(parent, text, command, **kwargs):
    widget = ttk.Button(parent, text=text, command=command, **kwargs)
    widget.pack(side="left", padx=(0, 6))
    return widget


class ClipboardApp:
    def __init__(self, root, *, data_dir=None, offline=False):
        self.root, self.offline = root, offline
        self.events = queue.Queue()
        self.worker = None if offline else AsyncWorker(self.events)
        self.state, self.devices, self.selected_id = "disconnected", [], None
        self.keyboard, self.device_info, self.review = None, None, None
        self.loading, self.dirty = False, False
        self.data_dir = (
            Path(data_dir)
            if data_dir
            else Path(os.environ.get("APPDATA", str(Path.home()))) / "BLE Clipboard"
        )
        self.library = MacroLibrary(self.data_dir / "macros.json")
        try:
            prefs = json.loads((self.data_dir / "preferences.json").read_text())
        except (OSError, ValueError):
            prefs = {}
        if not isinstance(prefs, dict):
            prefs = {}
        self.root.title(
            f"BLE Clipboard {version()} - Windows beta"
            + (" - Offline preview" if offline else "")
        )
        self.root.geometry("1120x800")
        self.root.minsize(960, 720)
        self.root.protocol("WM_DELETE_WINDOW", self.close)
        style = ttk.Style(root)
        if "vista" in style.theme_names():
            style.theme_use("vista")
        style.configure("Heading.TLabel", font=("Segoe UI", 14, "bold"))
        icon = (
            Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parents[1]))
            / "resources"
            / "AppIcon.ico"
        )
        if sys.platform == "win32" and icon.exists():
            root.iconbitmap(str(icon))

        def choice(key, values, default):
            return prefs.get(key) if prefs.get(key) in values else default

        self.quick_layout = tk.StringVar(value=choice("layout", LAYOUTS, LAYOUTS[0]))
        self.quick_target = tk.StringVar(value=choice("target", TARGETS, TARGETS[1]))
        self.mode = tk.StringVar(value=choice("mode", (*PRESETS, "Custom"), "Fast"))
        self.pause = tk.StringVar(value=str(prefs.get("pause", 80)))
        self.variation = tk.StringVar(value=str(prefs.get("variation", 30)))
        self.status = tk.StringVar(
            value="Offline preview; Bluetooth disabled."
            if offline
            else "Pair Paste in Windows Bluetooth settings; approve matching codes on both devices."
        )
        self.timer = tk.StringVar(value="00:00 elapsed / -- remaining")
        self.validation = tk.StringVar(value=self.library.error or "")
        self.search, self.name, self.layout, self.target = (
            tk.StringVar() for _ in range(4)
        )
        self.device = tk.StringVar()
        self._build()
        self.search.trace_add("write", lambda *_: self.refresh_library())
        for var in (self.name, self.layout, self.target):
            var.trace_add("write", self.edited)
        for var in (
            self.quick_layout,
            self.quick_target,
            self.mode,
            self.pause,
            self.variation,
        ):
            var.trace_add("write", self.preferences_changed)
        self.refresh_library()
        self._pump_id = root.after(80, self._pump)

    def _build(self):
        menu = tk.Menu(self.root)
        library = tk.Menu(menu, tearoff=False)
        for title, callback in (
            ("Import macros...", self.import_library),
            ("Export library...", self.export_library),
            ("Export selected...", lambda: self.export_library(True)),
            ("Recover backup...", self.recover),
        ):
            library.add_command(label=title, command=callback)
        menu.add_cascade(label="Library", menu=library)
        menu.add_command(label="Info & Companions", command=self.info)
        self.root.configure(menu=menu)
        header = ttk.Frame(self.root, padding=12)
        header.pack(fill="x")
        ttk.Label(header, text="BLE Clipboard", style="Heading.TLabel").pack(
            side="left", padx=(0, 18)
        )
        self.device_picker = ttk.Combobox(
            header, textvariable=self.device, state="readonly", width=23
        )
        self.device_picker.pack(side="left", padx=6)
        self.scan_button = button(header, "Refresh", self.scan)
        self.connect_button = button(header, "Connect", self.connect)
        if sys.platform == "win32":
            button(
                header,
                "Bluetooth settings",
                lambda: os.startfile("ms-settings:bluetooth"),
            )
        button(header, "Keyboard", self.keyboard_dialog)
        panes = ttk.Panedwindow(self.root, orient="horizontal")
        panes.pack(fill="both", expand=True, padx=12)
        sidebar = ttk.Frame(panes, width=220)
        panes.add(sidebar, weight=0)
        ttk.Entry(sidebar, textvariable=self.search, width=24).pack(
            fill="x", pady=(0, 8)
        )
        self.macros = tk.Listbox(
            sidebar,
            exportselection=False,
            width=25,
            activestyle="dotbox",
            font=("Segoe UI", 10),
        )
        self.macros.pack(fill="both", expand=True)
        self.macros.bind("<<ListboxSelect>>", self.select_macro)
        commands = ttk.Frame(sidebar)
        commands.pack(fill="x", pady=8)
        button(commands, "+", self.create_macro, width=3)
        button(commands, "Duplicate", self.duplicate)
        button(commands, "Delete", self.delete)
        button(
            sidebar, "Mouse Jiggle preset", lambda: self.create_macro(mouse_preset())
        )
        self.tabs = ttk.Notebook(panes)
        panes.add(self.tabs, weight=1)
        quick, editor = (
            ttk.Frame(self.tabs, padding=12),
            ttk.Frame(self.tabs, padding=12),
        )
        self.tabs.add(quick, text="Quick Paste")
        self.tabs.add(editor, text="Macro editor")
        row = ttk.Frame(quick)
        row.pack(fill="x", pady=(0, 8))
        button(row, "Load Clipboard", self.load_clipboard)
        button(row, "Open Text File", self.open_file)
        button(row, "Clear", lambda: self.replace_text(""))
        self.quick_text = self.text_widget(quick, height=12)
        self.quick_text.bind("<<Modified>>", self.quick_changed)
        self.target_controls(quick, self.quick_target, self.quick_layout)
        row = ttk.Frame(quick)
        row.pack(fill="x", pady=10)
        button(row, "Review & Run", lambda: self.open_review(False))
        button(row, "Send to Flipper", lambda: self.open_review(False, True))
        ttk.Label(editor, text="Name").pack(anchor="w")
        ttk.Entry(editor, textvariable=self.name).pack(fill="x", pady=(3, 6))
        self.target_controls(editor, self.target, self.layout)
        self.steps = ttk.Treeview(
            editor,
            columns=("action", "value"),
            show="tree headings",
            selectmode="browse",
            height=9,
        )
        self.steps.heading("#0", text="#")
        self.steps.column("#0", width=45, stretch=False)
        self.steps.heading("action", text="Action")
        self.steps.column("action", width=115, stretch=False)
        self.steps.heading("value", text="Value / options")
        self.steps.column("value", width=250)
        self.steps.pack(fill="both", expand=True, pady=(8, 6))
        self.steps.bind("<Double-1>", lambda _: self.edit_step())
        row = ttk.Frame(editor)
        row.pack(fill="x")
        self.kind = tk.StringVar(value=KINDS[0])
        ttk.Combobox(
            row, textvariable=self.kind, values=KINDS, state="readonly", width=12
        ).pack(side="left", padx=(0, 6))
        for title, callback in (
            ("Add", self.add_step),
            ("Edit", self.edit_step),
            ("Up", lambda: self.move_step(-1)),
            ("Down", lambda: self.move_step(1)),
            ("Remove", self.remove_step),
        ):
            button(row, title, callback)
        row = ttk.Frame(editor)
        row.pack(fill="x", pady=10)
        button(row, "Parameters", self.parameters_dialog)
        button(row, "Save macro", self.save_macro)
        button(row, "Review & Run", lambda: self.open_review(True))
        button(row, "Send to Flipper", lambda: self.open_review(True, True))
        pacing = ttk.Frame(self.root, padding=(12, 10))
        pacing.pack(fill="x")
        ttk.Label(pacing, text="Typing").pack(side="left", padx=(0, 6))
        ttk.Combobox(
            pacing,
            textvariable=self.mode,
            values=(*PRESETS, "Custom"),
            state="readonly",
            width=12,
        ).pack(side="left")
        for title, var in (
            ("Extra pause (ms)", self.pause),
            ("Variation +/- (ms)", self.variation),
        ):
            ttk.Label(pacing, text=title).pack(side="left", padx=(12, 5))
            ttk.Spinbox(pacing, textvariable=var, from_=0, to=1000, width=6).pack(
                side="left"
            )
        footer = ttk.Frame(self.root, padding=(12, 0, 12, 12))
        footer.pack(fill="x")
        ttk.Label(
            footer, textvariable=self.validation, foreground="#ad3429", wraplength=900
        ).pack(fill="x")
        ttk.Label(footer, textvariable=self.status, wraplength=900).pack(
            fill="x", pady=4
        )
        self.progress = ttk.Progressbar(footer, maximum=1)
        self.progress.pack(fill="x")
        row = ttk.Frame(footer)
        row.pack(fill="x", pady=(6, 0))
        ttk.Label(row, textvariable=self.timer).pack(side="left")
        self.stop_button = ttk.Button(
            row, text="Stop", command=self.stop, state="disabled"
        )
        self.stop_button.pack(side="right")
        if self.offline:
            self.connect_button.configure(state="disabled")
            self.scan_button.configure(state="disabled")

    @staticmethod
    def text_widget(parent, height=8):
        row = ttk.Frame(parent)
        row.pack(fill="both", expand=True)
        text = tk.Text(
            row,
            wrap="word",
            undo=True,
            font=("Consolas", 11),
            height=height,
            width=40,
            padx=8,
            pady=8,
        )
        scroll = ttk.Scrollbar(row, command=text.yview)
        text.configure(yscrollcommand=scroll.set)
        scroll.pack(side="right", fill="y")
        text.pack(side="left", fill="both", expand=True)
        return text

    @staticmethod
    def target_controls(parent, target, layout):
        row = ttk.Frame(parent)
        row.pack(fill="x", pady=6)
        ttk.Label(row, text="USB target OS").pack(side="left", padx=(0, 5))
        ttk.Combobox(
            row, textvariable=target, values=TARGETS, state="readonly", width=9
        ).pack(side="left")
        ttk.Label(row, text="Keyboard").pack(side="left", padx=(12, 5))
        ttk.Combobox(
            row, textvariable=layout, values=LAYOUTS, state="readonly", width=24
        ).pack(side="left")

    def invalidate(self):
        if self.review and self.review.winfo_exists():
            self.review.invalidate()

    def edited(self, *_):
        if not self.loading:
            self.dirty = True
            self.invalidate()

    def quick_changed(self, _=None):
        if self.quick_text.edit_modified():
            self.quick_text.edit_modified(False)
            self.invalidate()

    def preferences_changed(self, *_):
        self.invalidate()
        self.save_preferences()

    def timing(self):
        if self.mode.get() in PRESETS:
            return PRESETS[self.mode.get()]
        try:
            result = Timing(int(self.pause.get()), int(self.variation.get()))
        except ValueError:
            raise ValueError("Enter whole milliseconds.") from None
        result.validate()
        return result

    def save_preferences(self):
        prefs = {
            "layout": self.quick_layout.get(),
            "target": self.quick_target.get(),
            "mode": self.mode.get(),
            "pause": self.pause.get(),
            "variation": self.variation.get(),
        }
        try:
            atomic_write(self.data_dir / "preferences.json", json.dumps(prefs).encode())
        except OSError as error:
            self.validation.set(f"Preferences not saved: {error}")

    def refresh_library(self, selected=None):
        selected = selected or self.selected_id
        self.visible = [
            m
            for m in self.library.macros
            if self.search.get().casefold() in m["name"].casefold()
        ]
        self.macros.delete(0, "end")
        for i, m in enumerate(self.visible):
            self.macros.insert("end", m["name"])
            if m["id"] == selected:
                self.macros.selection_set(i)

    def discard(self):
        return not self.dirty or messagebox.askyesno(
            "Unsaved macro", "Discard changes to this macro?", parent=self.root
        )

    def select_macro(self, _=None):
        selected = self.macros.curselection()
        if not selected:
            return
        candidate = self.visible[selected[0]]
        if candidate["id"] == self.selected_id:
            return
        if not self.discard():
            self.refresh_library()
            return
        self.load_macro(candidate)
        self.tabs.select(1)

    def load_macro(self, macro):
        self.invalidate()
        self.loading = True
        self.current = deepcopy(macro)
        self.selected_id = macro["id"]
        self.name.set(macro["name"])
        self.layout.set(LAYOUTS[LAYOUT_IDS.index(macro["layout"])])
        self.target.set(TARGETS[TARGET_IDS.index(macro["target"])])
        self.loading = False
        self.dirty = False
        self.refresh_steps()
        self.refresh_library()

    def draft(self):
        if not self.selected_id:
            raise ValueError("Choose or create a macro.")
        result = deepcopy(self.current)
        result.update(
            name=self.name.get(),
            layout=LAYOUT_IDS[LAYOUTS.index(self.layout.get())],
            target=TARGET_IDS[TARGETS.index(self.target.get())],
        )
        return result

    def guard(self, callback):
        try:
            return callback()
        except (ValueError, OSError, UnicodeError) as error:
            self.validation.set(str(error))
            return None

    def create_macro(self, macro=None):
        if not self.discard():
            return
        macro = macro or new_macro(
            layout=LAYOUTS.index(self.quick_layout.get()),
            target=TARGETS.index(self.quick_target.get()),
        )
        self.load_macro(macro)
        self.dirty = True
        self.tabs.select(1)

    def save_macro(self):
        def save():
            macro = self.draft()
            self.library.save(macro)
            self.load_macro(macro)
            self.validation.set("")
            return True

        return self.guard(save)

    def duplicate(self):
        def duplicate():
            macro = self.draft()
            validate(macro)
            mid = self.library.duplicate(macro)
            self.load_macro(next(m for m in self.library.macros if m["id"] == mid))

        self.guard(duplicate)

    def delete(self):
        if self.selected_id and messagebox.askyesno(
            "Delete macro", f"Delete {self.name.get()}?", parent=self.root
        ):

            def delete():
                self.library.remove(self.selected_id)
                self.selected_id = None
                self.steps.delete(*self.steps.get_children())
                self.name.set("")
                self.dirty = False
                self.invalidate()
                self.refresh_library()

            self.guard(delete)

    def refresh_steps(self):
        self.steps.delete(*self.steps.get_children())
        self.step_paths = {}

        def insert(sequence, parent="", prefix=()):
            for i, s in enumerate(sequence):
                path = prefix + (i,)
                iid = ":".join(map(str, path))
                self.step_paths[iid] = path
                value = (
                    s["value"]
                    if s["kind"] in ("text", "template", "chord")
                    else str(s["milliseconds"]) + " ms"
                    if s["kind"] == "delay"
                    else " / ".join(
                        f"{k}={v}" for k, v in s.items() if k.startswith("mouse")
                    )
                )
                self.steps.insert(
                    parent,
                    "end",
                    iid=iid,
                    text=str(i + 1),
                    values=(TITLES.get(s["kind"], s["kind"]), value.replace("\n", " ")),
                    open=True,
                )
                if s["kind"] == "repeatFor":
                    insert(s.get("children", []), iid, path)

        if self.selected_id:
            insert(self.current["steps"])

    def location(self):
        selection = self.steps.selection()
        if not selection:
            raise ValueError("Choose a step.")
        path = self.step_paths[selection[0]]
        sequence = (
            self.current["steps"]
            if len(path) == 1
            else self.current["steps"][path[0]]["children"]
        )
        return sequence, path[-1]

    def add_step(self):
        if not self.selected_id:
            return
        selected = self.steps.selection()
        sequence = self.current["steps"]
        if selected:
            source, index = self.location()
            if source[index]["kind"] == "repeatFor":
                sequence = source[index].setdefault("children", [])
            elif source is not sequence:
                sequence = source
        if self.kind.get() == "repeatFor" and sequence is not self.current["steps"]:
            self.validation.set("Nested Repeat is not supported.")
            return
        item = step(self.kind.get(), "PRIMARY+A" if self.kind.get() == "chord" else "")
        if item["kind"] == "repeatFor":
            item["children"] = [step("moveMouse")]
        sequence.append(item)
        self.edited()
        self.refresh_steps()

    def move_step(self, delta):
        def move():
            sequence, index = self.location()
            dest = index + delta
            if not 0 <= dest < len(sequence):
                return
            selection = self.steps.selection()[0].split(":")
            selection[-1] = str(dest)
            sequence[index], sequence[dest] = sequence[dest], sequence[index]
            self.edited()
            self.refresh_steps()
            self.steps.selection_set(":".join(selection))

        self.guard(move)

    def remove_step(self):
        def remove():
            sequence, index = self.location()
            sequence.pop(index)
            self.edited()
            self.refresh_steps()

        self.guard(remove)

    def edit_step(self):
        from .dialogs import StepDialog

        def edit():
            sequence, index = self.location()
            StepDialog(self, sequence, index)

        self.guard(edit)

    def parameters_dialog(self):
        from .dialogs import parameters_dialog

        if self.selected_id:
            parameters_dialog(self)

    def replace_text(self, text):
        self.quick_text.delete("1.0", "end")
        self.quick_text.insert("1.0", text)
        self.invalidate()

    def load_clipboard(self):
        def load():
            text = self.root.clipboard_get()
            if len(text.encode()) > 65536:
                raise ValueError("Clipboard exceeds 65,536 bytes.")
            self.replace_text(text)

        try:
            self.guard(load)
        except tk.TclError:
            self.validation.set("Clipboard contains no text.")

    def open_file(self):
        name = filedialog.askopenfilename(
            parent=self.root, filetypes=[("Text", "*.txt")]
        )
        if not name:
            return

        def load():
            with open(name, "rb") as file:
                data = file.read(65540)
            text = data.decode("utf-8-sig")
            if len(text.encode()) > 65536:
                raise ValueError("Text file exceeds 65,536 bytes.")
            self.replace_text(text)

        self.guard(load)

    def import_library(self):
        if not self.discard():
            return
        name = filedialog.askopenfilename(
            parent=self.root, filetypes=[("Macro library", "*.json")]
        )
        if name:

            def load():
                mid = self.library.import_data(MacroLibrary.read(name))
                self.refresh_library(mid)
                if mid:
                    self.load_macro(
                        next(m for m in self.library.macros if m["id"] == mid)
                    )

            self.guard(load)

    def export_library(self, selected=False):
        def export():
            data = encode_library([self.draft()] if selected else self.library.macros)
            name = filedialog.asksaveasfilename(
                parent=self.root,
                defaultextension=".json",
                filetypes=[("Macro library", "*.json")],
            )
            if name:
                atomic_write(name, data)

        self.guard(export)

    def recover(self):
        if messagebox.askyesno(
            "Recover backup",
            "Replace the current library with its last valid backup?",
            parent=self.root,
        ):

            def restore():
                self.library.recover()
                self.selected_id = None
                self.dirty = False
                self.invalidate()
                self.refresh_library()
                self.validation.set("")

            self.guard(restore)

    def open_review(self, macro=True, save=False):
        from .dialogs import ReviewDialog

        def review():
            if self.review and self.review.winfo_exists():
                self.review.destroy()
            if macro:
                definition = self.draft()
            else:
                definition = new_macro(
                    "Clipboard Snapshot" if save else "Quick Paste",
                    LAYOUTS.index(self.quick_layout.get()),
                    TARGETS.index(self.quick_target.get()),
                )
                definition["steps"] = [
                    step("text", self.quick_text.get("1.0", "end-1c"))
                ]
            validate(definition)
            self.review = ReviewDialog(self, definition, save)

        self.guard(review)

    def scan(self):
        if self.offline or self.state != "disconnected":
            return
        self.scan_button.configure(state="disabled")
        self.status.set("Searching for Flippers...")

        async def scan():
            try:
                self.events.put(("devices", await self.worker.transport.scan()))
            finally:
                self.events.put(("scan_done", None))

        self.worker.submit(scan())

    def connect(self):
        if self.offline:
            return
        if self.state in ("ready", "sending"):
            self.worker.submit(self.worker.transport.disconnect())
            return
        index = self.device_picker.current()
        if index < 0:
            self.status.set("Refresh and choose a Flipper first.")
            return
        self.state = "connecting"
        self.connect_button.configure(state="disabled")
        self.worker.submit(self.worker.transport.connect(self.devices[index]))

    def stop(self):
        if not self.offline:
            self.worker.submit(self.worker.transport.cancel())

    def keyboard_dialog(self):
        from .dialogs import keyboard_dialog

        keyboard_dialog(self)

    def info(self):
        from .dialogs import info_dialog

        info_dialog(self)

    def _pump(self):
        while True:
            try:
                kind, value = self.events.get_nowait()
            except queue.Empty:
                break
            if kind == "state":
                self.state = value
                self.invalidate()
                self.connect_button.configure(
                    text="Disconnect" if value in ("ready", "sending") else "Connect",
                    state="disabled"
                    if self.offline or value == "connecting"
                    else "normal",
                )
                self.scan_button.configure(
                    state="normal"
                    if not self.offline and value == "disconnected"
                    else "disabled"
                )
                self.stop_button.configure(
                    state="normal" if value == "sending" else "disabled"
                )
                if value == "disconnected":
                    self.keyboard = self.device_info = None
            elif kind in ("status", "error", "keyboard_error"):
                self.status.set(value)
            elif kind == "progress":
                self.progress["value"] = value
            elif kind == "timer":
                self.timer.set(
                    f"{value[0] // 60:02}:{value[0] % 60:02} elapsed / {value[1] // 60:02}:{value[1] % 60:02} remaining"
                )
            elif kind == "devices":
                self.devices = value
                self.device_picker.configure(
                    values=[f"{d.name or 'Flipper'} ({d.address})" for d in value]
                )
                if len(value) == 1:
                    self.device_picker.current(0)
                self.status.set(f"{len(value)} Flipper(s) found")
            elif kind == "scan_done":
                self.scan_button.configure(
                    state="normal"
                    if self.state == "disconnected" and not self.offline
                    else "disabled"
                )
            elif kind == "keyboard":
                if self.keyboard != value:
                    self.invalidate()
                self.keyboard = value
                self.quick_layout.set(LAYOUTS[value.layout])
                self.quick_target.set(TARGETS[value.target])
            elif kind == "info":
                self.device_info = value
        self._pump_id = self.root.after(80, self._pump)

    def close(self):
        if not self.discard():
            return
        if self.state == "sending" and not messagebox.askyesno(
            "Disconnect",
            "Close companion? Standalone jobs continue on Flipper; other jobs stop. Check the target before retrying.",
            parent=self.root,
        ):
            return
        self.save_preferences()
        if self.worker:
            self.worker.close()
        self.root.after_cancel(self._pump_id)
        self.root.destroy()


def main():
    root = tk.Tk()
    ClipboardApp(root)
    root.mainloop()
