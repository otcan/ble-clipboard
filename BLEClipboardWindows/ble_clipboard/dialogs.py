"""Local editing, explicit run review, keyboard preferences and companion info."""

import queue
import threading
import tkinter as tk
import webbrowser
from copy import deepcopy
from datetime import datetime, timezone
from tkinter import ttk

from .app import TITLES, button
from .macros import chord, movement, new_macro, options, step, validate
from .macros import text as validate_text
from .protocol import (
    LAYOUT_IDS,
    LAYOUTS,
    TARGET_IDS,
    TARGETS,
    KeyboardSettings,
    Timing,
    saved_descriptor,
)
from .release import REPOSITORY, check, links, version
from .review import RunReview


class StepDialog(tk.Toplevel):
    def __init__(self, app, sequence, index):
        super().__init__(app.root)
        self.title(TITLES[sequence[index]["kind"]])
        self.maxsize(6000, 4000)
        self.geometry(f"{int(560 * app.scale)}x{int(490 * app.scale)}")
        self.minsize(int(500 * app.scale), int(440 * app.scale))
        self.transient(app.root)
        self.grab_set()
        original = sequence[index]
        fields = {}
        body = ttk.Frame(self, padding=16)
        body.pack(fill="both", expand=True)
        kind = original["kind"]
        text = None
        if kind in ("text", "template", "chord"):
            text = app.text_widget(body)
            text.insert("1.0", original["value"])

        def field(key, title, low, high, default):
            row = ttk.Frame(body)
            row.pack(fill="x", pady=4)
            ttk.Label(row, text=title).pack(side="left")
            value = tk.StringVar(
                value=str(
                    original.get(key) if original.get(key) is not None else default
                )
            )
            fields[key] = value
            ttk.Spinbox(row, textvariable=value, from_=low, to=high, width=10).pack(
                side="right"
            )

        if kind == "delay":
            field("milliseconds", "Delay (ms)", 1, 30000, 250)
        if kind == "moveMouse":
            for key, title, default in (
                ("mouseXMinimum", "X minimum", 1),
                ("mouseXMaximum", "X maximum", original.get("mouseXMinimum", 1)),
                ("mouseYMinimum", "Y minimum", 0),
                ("mouseYMaximum", "Y maximum", original.get("mouseYMinimum", 0)),
            ):
                field(key, title, -127, 127, default)
        if kind == "repeatFor":
            for key, title, low, high, default in (
                ("mouseDurationSeconds", "Duration (seconds)", 1, 86400, 28800),
                ("mouseIntervalSeconds", "Interval minimum (seconds)", 1, 3600, 60),
                (
                    "mouseIntervalMaximumSeconds",
                    "Interval maximum (seconds)",
                    1,
                    3600,
                    original.get("mouseIntervalSeconds", 60),
                ),
            ):
                field(key, title, low, high, default)
        error = tk.StringVar()
        ttk.Label(body, textvariable=error, foreground="#ad3429", wraplength=490).pack(
            fill="x", pady=8
        )

        def save():
            try:
                result = deepcopy(original)
                if text:
                    result["value"] = text.get("1.0", "end-1c")
                for key, var in fields.items():
                    result[key] = int(var.get())
                if kind == "moveMouse":
                    result["varyingMouse"] = True
                    movement(result)
                elif kind == "repeatFor":
                    result["varyingInterval"] = True
                    options(result)
                elif kind == "delay":
                    if not 1 <= result["milliseconds"] <= 30000:
                        raise ValueError("Delay must be 1-30000 ms.")
                elif kind == "chord":
                    chord(result["value"], TARGETS.index(app.target.get()))
                else:
                    validate_text(result["value"], LAYOUTS.index(app.layout.get()))
                sequence[index] = result
                app.edited()
                app.refresh_steps()
                self.destroy()
            except ValueError as failure:
                error.set(str(failure))

        row = ttk.Frame(body)
        row.pack(fill="x", side="bottom")
        button(row, "Apply", save)
        button(row, "Cancel", self.destroy)


def parameters_dialog(app):
    window = tk.Toplevel(app.root)
    window.title("Parameters")
    window.maxsize(6000, 4000)
    window.geometry(f"{int(520 * app.scale)}x{int(400 * app.scale)}")
    window.transient(app.root)
    window.grab_set()
    rows = ttk.Treeview(window, columns=("label",), height=7)
    rows.heading("#0", text="Identifier")
    rows.heading("label", text="Label")
    rows.pack(fill="both", expand=True, padx=12, pady=12)
    parameters = deepcopy(app.current["parameters"])

    def refresh():
        rows.delete(*rows.get_children())
        for i, p in enumerate(parameters):
            rows.insert("", "end", iid=str(i), text=p["id"], values=(p["label"],))

    refresh()
    fields = ttk.Frame(window)
    fields.pack(fill="x", padx=12)
    pid, label = tk.StringVar(), tk.StringVar()
    ttk.Entry(fields, textvariable=pid, width=17).pack(side="left")
    ttk.Entry(fields, textvariable=label).pack(side="left", fill="x", expand=True)
    error = tk.StringVar()
    ttk.Label(window, textvariable=error, foreground="#ad3429", wraplength=460).pack(
        fill="x", padx=12
    )

    def valid(candidate):
        probe = new_macro("Parameters")
        probe["steps"] = [step("text", "x")]
        probe["parameters"] = candidate
        try:
            validate(probe)
            error.set("")
            return True
        except ValueError as failure:
            error.set(str(failure))
            return False

    def add():
        candidate = parameters + [{"id": pid.get(), "label": label.get()}]
        if not valid(candidate):
            return
        parameters[:] = candidate
        pid.set("")
        label.set("")
        refresh()

    def remove():
        if rows.selection():
            parameters.pop(int(rows.selection()[0]))
            refresh()

    row = ttk.Frame(window, padding=12)
    row.pack(fill="x")
    button(row, "Add", add)

    def selected(_=None):
        if rows.selection():
            current = parameters[int(rows.selection()[0])]
            pid.set(current["id"])
            label.set(current["label"])

    rows.bind("<<TreeviewSelect>>", selected)

    def update():
        if not rows.selection():
            return
        candidate = deepcopy(parameters)
        candidate[int(rows.selection()[0])] = {"id": pid.get(), "label": label.get()}
        if valid(candidate):
            parameters[:] = candidate
            refresh()

    button(row, "Update", update)
    button(row, "Remove", remove)

    def apply():
        if not valid(parameters):
            return
        app.current["parameters"] = parameters
        app.edited()
        window.destroy()

    button(row, "Apply", apply)
    return window


def keyboard_dialog(app):
    window = tk.Toplevel(app.root)
    window.title("Flipper keyboard")
    window.transient(app.root)
    frame = ttk.Frame(window, padding=16)
    frame.pack(fill="both", expand=True)
    settings = app.keyboard or KeyboardSettings()
    target, layout, saved = (
        tk.StringVar(value=TARGETS[settings.target]),
        tk.StringVar(value=LAYOUTS[settings.layout]),
        tk.BooleanVar(value=settings.use_saved),
    )
    app.target_controls(frame, target, layout)
    ttk.Checkbutton(
        frame, text="Use this keyboard for local saved-job runs", variable=saved
    ).pack(anchor="w", pady=8)
    ttk.Label(
        frame,
        text="Flipper wins on reconnect. Existing desktop macros keep their own layout.",
        wraplength=460,
    ).pack(fill="x")
    row = ttk.Frame(frame)
    row.pack(fill="x", pady=12)

    def apply():
        if app.offline or app.state != "ready" or app.keyboard is None:
            app.validation.set("Connect and refresh the Flipper keyboard while idle.")
            return
        candidate = KeyboardSettings(
            LAYOUTS.index(layout.get()),
            TARGETS.index(target.get()),
            saved.get(),
            settings.revision,
        )
        app.worker.submit(app.worker.transport.set_keyboard(candidate))
        window.destroy()

    button(row, "Save on Flipper", apply)
    if not app.offline:

        def refresh():
            future = app.worker.submit(app.worker.transport.get_keyboard())

            def result():
                nonlocal settings
                if not window.winfo_exists():
                    return
                if not future.done():
                    window.after(100, result)
                    return
                if future.cancelled() or future.exception():
                    return
                settings = future.result()
                target.set(TARGETS[settings.target])
                layout.set(LAYOUTS[settings.layout])
                saved.set(settings.use_saved)

            window.after(100, result)

        button(row, "Refresh", refresh)


def info_dialog(app):
    window = tk.Toplevel(app.root)
    window.title("Info & Companions")
    window.maxsize(6000, 4000)
    window.geometry(f"{int(540 * app.scale)}x{int(480 * app.scale)}")
    window.transient(app.root)
    frame = ttk.Frame(window, padding=20)
    frame.pack(fill="both", expand=True)
    ttk.Label(frame, text=f"BLE Clipboard {version()}", style="Heading.TLabel").pack(
        anchor="w"
    )
    ttk.Label(
        frame, text="Windows x64 - unsigned beta\nProtocol 4", padding=(0, 10)
    ).pack(anchor="w")
    actual = app.device_info
    ttk.Label(
        frame,
        text=f"Flipper: {actual['version']} / API {actual['api']}"
        if actual
        else "Flipper version: unavailable",
    ).pack(anchor="w")
    state = tk.StringVar(value="Matching release not checked")
    ttk.Label(frame, textvariable=state, wraplength=480).pack(fill="x", pady=8)
    download_buttons = []
    for name, url in links(version()).items():
        b = ttk.Button(
            frame,
            text=name,
            command=lambda url=url: webbrowser.open(url),
            state="disabled",
        )
        b.pack(anchor="w", pady=2)
        download_buttons.append(b)
    result_queue = queue.Queue()

    def update_result():
        if not window.winfo_exists():
            return
        try:
            result = result_queue.get_nowait()
        except queue.Empty:
            window.after(100, update_result)
            return
        state.set(
            "Matching downloads available"
            if result is True
            else "Not published or incomplete"
            if result is False
            else "Release check unavailable"
        )
        if result is True:
            for b in download_buttons:
                b.configure(state="normal")

    def fetch():
        try:
            result_queue.put(check(version()))
        except Exception:
            result_queue.put(None)

    def refresh():
        state.set("Checking exact-version downloads...")
        if app.offline:
            result_queue.put(False)
        else:
            threading.Thread(target=fetch, daemon=True).start()
        window.after(100, update_result)

    ttk.Button(frame, text="Check downloads", command=refresh).pack(anchor="w", pady=8)
    ttk.Button(
        frame,
        text="Setup guide",
        command=lambda: webbrowser.open(f"{REPOSITORY}/blob/v{version()}/README.md"),
    ).pack(anchor="w")


class ReviewDialog(tk.Toplevel):
    def __init__(self, app, macro, save):
        super().__init__(app.root)
        self.app, self.macro = app, deepcopy(macro)
        self.model = RunReview()
        self.title("Review expanded output")
        self.maxsize(6000, 4000)
        self.geometry(f"{int(760 * app.scale)}x{int(660 * app.scale)}")
        self.minsize(int(660 * app.scale), int(600 * app.scale))
        self.transient(app.root)
        self.grab_set()
        self.date = datetime.now(timezone.utc)
        self.destination = tk.StringVar(value="save" if save else "run")
        self.standalone = tk.BooleanVar(
            value=any(s["kind"] in ("mouseJiggle", "repeatFor") for s in macro["steps"])
        )
        self.confirmed = tk.BooleanVar(value=False)
        self.stored_name = tk.StringVar(value=macro["name"])
        outer = ttk.Frame(self, padding=16)
        outer.pack(fill="both", expand=True)
        footer = ttk.Frame(outer)
        footer.pack(side="bottom", fill="x")
        viewport = ttk.Frame(outer)
        viewport.pack(fill="both", expand=True)
        canvas = tk.Canvas(viewport, highlightthickness=0)
        scroll = ttk.Scrollbar(viewport, command=canvas.yview)
        canvas.configure(yscrollcommand=scroll.set)
        scroll.pack(side="right", fill="y")
        canvas.pack(side="left", fill="both", expand=True)
        body = ttk.Frame(canvas)
        item = canvas.create_window(0, 0, window=body, anchor="nw")
        body.bind(
            "<Configure>", lambda _: canvas.configure(scrollregion=canvas.bbox("all"))
        )
        canvas.bind(
            "<Configure>", lambda event: canvas.itemconfigure(item, width=event.width)
        )
        ttk.Label(
            body,
            text=f"{macro['name']} / {TARGETS[TARGET_IDS.index(macro['target'])]} / {LAYOUTS[LAYOUT_IDS.index(macro['layout'])]}",
            style="Heading.TLabel",
            wraplength=700,
        ).pack(fill="x")
        self.parameters = {}
        self.clipboard = tk.StringVar(value="")
        for p in macro["parameters"]:
            row = ttk.Frame(body)
            row.pack(fill="x", pady=3)
            ttk.Label(
                row, text=p["label"], width=20, wraplength=int(180 * app.scale)
            ).pack(side="left")
            var = tk.StringVar()
            self.parameters[p["id"]] = var
            ttk.Entry(row, textvariable=var).pack(side="left", fill="x", expand=True)
            var.trace_add("write", self.prepare)
        all_steps = macro["steps"] + [
            c for s in macro["steps"] for c in (s.get("children") or [])
        ]
        if any("{{clipboard}}" in s["value"] for s in all_steps):
            row = ttk.Frame(body)
            row.pack(fill="x", pady=5)
            ttk.Label(row, text="Clipboard snapshot").pack(side="left")
            ttk.Entry(row, textvariable=self.clipboard).pack(
                side="left", fill="x", expand=True, padx=5
            )

            def load():
                try:
                    self.clipboard.set(app.root.clipboard_get())
                except tk.TclError:
                    self.error.set("Clipboard contains no text.")

            button(row, "Load Clipboard", load)
            self.clipboard.trace_add("write", self.prepare)
        self.preview = app.text_widget(body, height=10)
        row = ttk.Frame(body)
        row.pack(fill="x", pady=8)
        for title, value in (("Run now", "run"), ("Save on Flipper SD", "save")):
            ttk.Radiobutton(
                row, text=title, variable=self.destination, value=value
            ).pack(side="left", padx=(0, 12))
        ttk.Checkbutton(
            body,
            text="Continue independently on Flipper after Bluetooth disconnects",
            variable=self.standalone,
        ).pack(anchor="w")
        row = ttk.Frame(body)
        row.pack(fill="x", pady=5)
        ttk.Label(row, text="Saved name").pack(side="left")
        ttk.Entry(row, textvariable=self.stored_name).pack(
            side="left", fill="x", expand=True, padx=8
        )
        ttk.Label(
            body,
            text="Match the USB target's keyboard layout. Shortcuts can affect other apps or the whole system. This app cannot restore focus. Stop on Flipper remains available.",
            wraplength=700,
        ).pack(fill="x", pady=8)
        self.error = tk.StringVar()
        self.error_label = ttk.Label(
            footer, textvariable=self.error, foreground="#ad3429", wraplength=700
        )
        self.error_label.pack(fill="x")
        self.confirm_toggle = ttk.Checkbutton(
            footer,
            text="I reviewed the output and confirm the USB target / SD snapshot",
            variable=self.confirmed,
            command=self.update_run,
        )
        self.confirm_toggle.pack(anchor="w", pady=8)
        row = ttk.Frame(footer)
        row.pack(fill="x")
        self.run_button = button(
            row, "Save on Flipper" if save else "Run", self.execute, state="disabled"
        )
        button(row, "Refresh review", self.prepare)
        button(row, "Cancel", self.destroy)
        for var in (self.destination, self.standalone, self.stored_name):
            var.trace_add("write", self.prepare)
        self.prepare()

    def invalidate(self):
        self.model.invalidate()
        self.confirmed.set(False)
        self.error.set(
            "Settings or connection changed. Refresh the review before confirming."
        )
        self.update_run()

    def prepare(self, *_):
        self.confirmed.set(False)
        try:
            compiled = self.model.prepare(
                self.macro,
                clipboard=self.clipboard.get(),
                parameters={k: v.get() for k, v in self.parameters.items()},
                date=self.date,
                timing=self.app.timing(),
            )
            if compiled is None:
                raise ValueError(self.model.error)
            if (
                not self.app.offline
                and self.app.state == "ready"
                and compiled.timing != Timing()
                and not self.app.worker.transport._capabilities & 128
            ):
                raise ValueError(
                    "Update Flipper for this typing speed, or select Fast."
                )
            if self.destination.get() == "save":
                saved_descriptor(self.macro["id"], self.stored_name.get())
            self.preview.configure(state="normal")
            self.preview.delete("1.0", "end")
            self.preview.insert("1.0", "\n\n".join(compiled.preview))
            self.preview.configure(state="disabled")
            self.error.set(
                f"{len(compiled.program):,} compiled bytes"
                + (" / Offline preview; output disabled" if self.app.offline else "")
            )
            self.error_label.configure(foreground="#5c6269")
        except ValueError as error:
            self.model.invalidate()
            self.error.set(str(error))
            self.error_label.configure(foreground="#ad3429")
            self.preview.configure(state="normal")
            self.preview.delete("1.0", "end")
            self.preview.configure(state="disabled")
        self.update_run()

    def update_run(self):
        self.model.confirmed = self.confirmed.get()
        self.run_button.configure(
            text="Save on Flipper" if self.destination.get() == "save" else "Run",
            state="normal"
            if self.model.compiled
            and self.confirmed.get()
            and self.app.state == "ready"
            and not self.app.offline
            else "disabled",
        )

    def execute(self):
        if (
            self.app.offline
            or self.app.state != "ready"
            or self.run_button.instate(["disabled"])
        ):
            return
        compiled = self.model.consume()
        saved = (
            (self.macro["id"], self.stored_name.get())
            if self.destination.get() == "save"
            else None
        )
        self.app.state = "sending"
        self.app.save_preferences()
        self.app.worker.submit(
            self.app.worker.transport.transfer(
                compiled, saved=saved, standalone=self.standalone.get()
            )
        )
        self.destroy()
