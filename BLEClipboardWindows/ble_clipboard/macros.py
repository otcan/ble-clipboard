"""Portable macro library and BCM4 compiler; no clipboard, BLE or input access."""

import json
import math
import os
import re
import struct
import tempfile
import time
import uuid
from copy import deepcopy
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import regex

from .protocol import LAYOUT_IDS, MAX_PROGRAM_BYTES, TARGET_IDS, Timing

MAX_LIBRARY_BYTES = 2_000_000
KINDS = ("text", "template", "chord", "delay", "moveMouse", "repeatFor")
TOKEN = re.compile(r"\{\{([A-Za-z][A-Za-z0-9_]{0,31})\}\}")
SPECIAL = dict(
    zip(
        (
            "ENTER",
            "TAB",
            "ESC",
            "BACKSPACE",
            "DEL",
            "UP",
            "DOWN",
            "LEFT",
            "RIGHT",
            "HOME",
            "END",
            "PGUP",
            "PGDN",
            "SPACE",
        ),
        range(0x100, 0x10E),
    )
)
SPECIAL.update({f"F{i}": 0x10F + i for i in range(1, 13)})


def identifier(value):
    try:
        return str(uuid.UUID(value)).upper()
    except (ValueError, TypeError, AttributeError):
        raise ValueError("Invalid macro or step identifier.") from None


def integer(value, low, high):
    if type(value) is not int or not low <= value <= high:
        raise ValueError(f"Expected a whole number between {low} and {high}.")
    return value


def label(value):
    if (
        not isinstance(value, str)
        or not value.strip()
        or len(regex.findall(r"\X", value)) > 80
    ):
        raise ValueError("Names and parameter labels need 1-80 characters.")


def step(kind="text", value="", **options):
    return {
        "id": str(uuid.uuid4()).upper(),
        "kind": kind,
        "value": value,
        "milliseconds": 250,
        **options,
    }


def new_macro(name="New Macro", layout=0, target=0):
    return {
        "id": str(uuid.uuid4()).upper(),
        "name": name,
        "layout": LAYOUT_IDS[layout],
        "target": TARGET_IDS[target],
        "steps": [step()],
        "parameters": [],
        "updatedAt": time.time() - 978307200,
    }


def mouse_preset():
    macro = new_macro("Mouse Jiggle")
    macro["steps"] = [
        step(
            "repeatFor",
            mouseDurationSeconds=28800,
            mouseIntervalSeconds=45,
            mouseIntervalMaximumSeconds=95,
            varyingInterval=True,
            children=[
                step(
                    "moveMouse",
                    varyingMouse=True,
                    mouseXMinimum=-2,
                    mouseXMaximum=2,
                    mouseYMinimum=-2,
                    mouseYMaximum=2,
                )
            ],
        )
    ]
    return macro


def starters():
    result = []
    for name, steps, parameters in (
        ("Type Clipboard", [step("template", "{{clipboard}}")], []),
        ("Saved Snippet", [step("text", "Hello from BLE Clipboard.")], []),
        ("Timestamp", [step("template", "{{timestamp}}")], []),
        (
            "Replace Field",
            [step("chord", "PRIMARY+A"), step("template", "{{clipboard}}")],
            [],
        ),
        (
            "Fill Two Fields",
            [
                step("template", "{{first}}"),
                step("chord", "TAB"),
                step("template", "{{second}}"),
            ],
            [
                {"id": "first", "label": "First field"},
                {"id": "second", "label": "Second field"},
            ],
        ),
    ):
        macro = new_macro(name)
        macro.update(steps=steps, parameters=parameters)
        result.append(macro)
    return result


def tokens(template):
    rest = TOKEN.sub("", template)
    if "{{" in rest or "}}" in rest:
        raise ValueError("Malformed template parameter.")
    return TOKEN.findall(template)


def chord(value, target):
    keys = value.upper().split("+")
    if not 1 <= len(keys) <= 5 or not keys[-1]:
        raise ValueError("Invalid key combination.")
    modifiers = [
        ("WIN" if target == 0 else "CTRL") if key == "PRIMARY" else key
        for key in keys[:-1]
    ]
    bits = {"CTRL": 1, "SHIFT": 2, "ALT": 4, "WIN": 8}
    key = keys[-1]
    if (
        len(set(modifiers)) != len(modifiers)
        or any(m not in bits for m in modifiers)
        or key not in SPECIAL
        and not re.fullmatch(r"[A-Z0-9]", key)
    ):
        raise ValueError(f"Unsupported key combination: {value}")
    return struct.pack(
        "<BBH",
        2,
        sum(bits[m] for m in modifiers),
        SPECIAL.get(key, ord(key.lower()[0])),
    )


def text(value, layout):
    if not isinstance(value, str):
        raise ValueError("Step text must be a string.")
    if not value:
        return b""
    # The compiler can accept a full-size definition; encoded size is checked separately.
    import unicodedata

    from .protocol import TURKISH

    value = (
        unicodedata.normalize("NFC", value).replace("\r\n", "\n").replace("\r", "\n")
    )
    if len(value.encode()) > MAX_PROGRAM_BYTES or any(
        not (32 <= ord(c) <= 126 or c in "\t\n" or layout == 1 and c in TURKISH)
        for c in value
    ):
        raise ValueError(
            "Text supports ASCII, tabs and line breaks; Turkish letters require Turkish Q."
        )
    return value.encode()


def options(s):
    duration = integer(
        s.get("mouseDurationSeconds")
        if s.get("mouseDurationSeconds") is not None
        else 28800,
        1,
        86400,
    )
    low = integer(
        s.get("mouseIntervalSeconds")
        if s.get("mouseIntervalSeconds") is not None
        else 60,
        1,
        3600,
    )
    high = (
        integer(
            s.get("mouseIntervalMaximumSeconds")
            if s.get("mouseIntervalMaximumSeconds") is not None
            else low,
            low,
            3600,
        )
        if s.get("varyingInterval", False)
        else low
    )
    return duration, low, high


def movement(s):
    get = lambda name, default: s[name] if s.get(name) is not None else default
    xmin, ymin = (
        integer(get("mouseXMinimum", 1), -127, 127),
        integer(get("mouseYMinimum", 0), -127, 127),
    )
    xmax = (
        integer(get("mouseXMaximum", xmin), xmin, 127)
        if s.get("varyingMouse", False)
        else xmin
    )
    ymax = (
        integer(get("mouseYMaximum", ymin), ymin, 127)
        if s.get("varyingMouse", False)
        else ymin
    )
    if not any((xmin, xmax, ymin, ymax)):
        raise ValueError("Move Mouse needs a nonzero movement.")
    return xmin, xmax, ymin, ymax


def validate(macro):
    if not isinstance(macro, dict):
        raise ValueError("Invalid macro definition.")
    identifier(macro.get("id"))
    label(macro.get("name"))
    try:
        layout, target = (
            LAYOUT_IDS.index(macro["layout"]),
            TARGET_IDS.index(macro["target"]),
        )
    except (ValueError, KeyError):
        raise ValueError("Unsupported target or keyboard layout.") from None
    date = macro.get("updatedAt")
    if type(date) not in (int, float) or not math.isfinite(date):
        raise ValueError("Invalid macro date.")
    parameters = macro.get("parameters")
    if not isinstance(parameters, list) or len(parameters) > 32:
        raise ValueError("A macro permits at most 32 parameters.")
    known = {"clipboard", "timestamp"}
    for parameter in parameters:
        if not isinstance(parameter, dict):
            raise ValueError("Invalid parameter.")
        name = parameter.get("id")
        if (
            not isinstance(name, str)
            or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{0,31}", name)
            or name in known
        ):
            raise ValueError("Invalid or duplicate parameter name.")
        label(parameter.get("label"))
        known.add(name)
    ids, budget = set(), {"nodes": 0, "bytes": 0, "delay": 0, "timed": 0}

    def sequence(steps, nested=False):
        if not isinstance(steps, list) or not 1 <= len(steps) <= 128:
            raise ValueError("Each sequence needs 1-128 steps.")
        output = False
        for s in steps:
            if not isinstance(s, dict):
                raise ValueError("Invalid step.")
            sid = identifier(s.get("id"))
            if sid in ids:
                raise ValueError("Duplicate step identifiers.")
            ids.add(sid)
            budget["nodes"] += 1
            kind, value = s.get("kind"), s.get("value")
            if not isinstance(value, str):
                raise ValueError("Step value must be text.")
            integer(s.get("milliseconds"), -(2**63), 2**63 - 1)
            for field in ("varyingInterval", "varyingMouse"):
                if field in s and s[field] is not None and type(s[field]) is not bool:
                    raise ValueError("Invalid range toggle.")
            for field in (
                "mouseDurationSeconds",
                "mouseIntervalSeconds",
                "mouseIntervalMaximumSeconds",
                "mouseXMinimum",
                "mouseXMaximum",
                "mouseYMinimum",
                "mouseYMaximum",
            ):
                if field in s and s[field] is not None:
                    integer(s[field], -(2**63), 2**63 - 1)
            budget["bytes"] += len(value.encode())
            if budget["nodes"] > 512 or budget["bytes"] > 65536:
                raise ValueError("Macro definition is too large.")
            children = s.get("children")
            if children is not None and not isinstance(children, list):
                raise ValueError("Invalid step children.")
            if kind != "repeatFor" and children:
                raise ValueError("Only Repeat can contain children.")
            if kind in ("text", "template"):
                text(value, layout)
                if kind == "template" and any(t not in known for t in tokens(value)):
                    raise ValueError("Unknown template parameter.")
                output |= bool(value)
            elif kind == "chord":
                chord(value, target)
                output = True
            elif kind == "delay":
                budget["delay"] += integer(s["milliseconds"], 1, 30000)
            elif kind == "moveMouse":
                movement(s)
                output = True
            elif kind in ("repeatFor", "mouseJiggle"):
                if nested:
                    raise ValueError("Nested timed blocks are not supported.")
                duration, _, _ = options(s)
                budget["timed"] += duration
                if kind == "repeatFor" and not sequence(children, True):
                    raise ValueError("Repeat needs an output action.")
                output = True
            else:
                raise ValueError("Unsupported macro step.")
        return output

    if (
        not sequence(macro.get("steps"))
        or budget["delay"] > 120000
        or budget["timed"] > 86400
    ):
        raise ValueError(
            "Macro needs output, at most 120 seconds of delays and 24 hours of timed actions."
        )
    return layout, target


def migrate(macro):
    macro = deepcopy(macro)
    for s in macro["steps"]:
        if s["kind"] == "mouseJiggle":
            s["kind"] = "repeatFor"
            s["children"] = [
                step("moveMouse"),
                step("delay", milliseconds=50),
                step("moveMouse", mouseXMinimum=-1),
            ]
    return macro


@dataclass(frozen=True)
class CompiledMacro:
    program: bytes
    preview: tuple
    layout: int
    target: int
    timing: Timing


def compile_macro(
    macro, *, clipboard="", parameters=None, date=None, timing=Timing(), limit=65536
):
    layout, target = validate(macro)
    timing.validate()
    parameters = parameters or {}
    date = date or datetime.now(timezone.utc)
    stamp = (
        date.astimezone(timezone.utc)
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z")
    )
    preview, nodes = [], [0]

    def sequence(steps, nested=False, indent=""):
        records, count, has_output = bytearray(), 0, False
        for s in steps:
            kind, value = s["kind"], s["value"]
            if kind in ("text", "template"):
                if kind == "template":
                    expanded_bytes = len(value.encode())

                    def replace(match):
                        nonlocal expanded_bytes
                        name = match[1]
                        replacement = (
                            clipboard
                            if name == "clipboard"
                            else stamp
                            if name == "timestamp"
                            else parameters.get(name)
                        )
                        if not isinstance(replacement, str):
                            raise ValueError(f"Enter a value for {name}.")
                        text(replacement, layout)
                        expanded_bytes += len(replacement.encode()) - len(
                            match[0].encode()
                        )
                        if expanded_bytes > min(limit, MAX_PROGRAM_BYTES):
                            raise ValueError("Expanded template is too large.")
                        return replacement

                    value = TOKEN.sub(replace, value)
                data = text(value, layout)
                if data:
                    records.extend(struct.pack("<BI", 1, len(data)) + data)
                    count += 1
                    has_output = True
                preview.append(f"{indent}Text: {data.decode()}")
            elif kind == "chord":
                records.extend(chord(value, target))
                count += 1
                has_output = True
                preview.append(f"{indent}Key: {value}")
            elif kind == "delay":
                records.extend(struct.pack("<BI", 3, s["milliseconds"]))
                count += 1
                preview.append(f"{indent}Delay: {s['milliseconds']} ms")
            elif kind == "moveMouse":
                has_output = True
                xy = movement(s)
                records.extend(struct.pack("<Bbbbb", 5, *xy))
                count += 1
                preview.append(
                    f"{indent}Move Mouse: X {xy[0]}...{xy[1]}, Y {xy[2]}...{xy[3]}"
                )
            elif kind == "mouseJiggle":
                has_output = True
                duration, low, _ = options(s)
                records.extend(struct.pack("<BII", 4, duration * 1000, low * 1000))
                count += 1
                preview.append(f"{indent}Mouse Jiggle: {duration} s; every {low} s")
            else:
                has_output = True
                duration, low, high = options(s)
                preview.append(
                    f"{indent}Repeat: {duration} s; interval {low}...{high} s"
                )
                body, body_count = sequence(s["children"], True, indent + "  ")
                records.extend(
                    struct.pack(
                        "<BIIIHI",
                        6,
                        duration * 1000,
                        low * 1000,
                        high * 1000,
                        body_count,
                        len(body),
                    )
                    + body
                )
                count += 1
            if len(records) > min(65536, limit):
                raise ValueError("Expanded macro exceeds device capacity.")
        nodes[0] += count
        if not has_output or not 1 <= count <= 128 or nodes[0] > 512:
            raise ValueError("Too many operations or empty output.")
        return bytes(records), count

    records, count = sequence(macro["steps"])
    if timing != Timing():
        records = struct.pack("<BHH", 7, timing.pause_ms, timing.variation_ms) + records
        count += 1
        nodes[0] += 1
        preview.insert(0, f"Typing: {timing.pause_ms} +/- {timing.variation_ms} ms")
    program = b"BCM4" + struct.pack("<H", count) + records
    if count > 128 or nodes[0] > 512 or len(program) > min(65536, limit):
        raise ValueError("Expanded macro exceeds device capacity or operation limits.")
    return CompiledMacro(program, tuple(preview), layout, target, timing)


def decode_library(data):
    if len(data) > MAX_LIBRARY_BYTES:
        raise ValueError("Library file is too large.")
    try:
        document = json.loads(data)
        integer(document["schemaVersion"], 1, 3)
        macros = document["macros"]
        if not isinstance(macros, list) or len(macros) > 1000:
            raise ValueError("Too many macros.")
        ids = [identifier(m["id"]) for m in macros]
        if len(ids) != len(set(ids)):
            raise ValueError("Duplicate macro identifiers.")
        for m in macros:
            validate(m)
        result = [migrate(m) for m in macros]
        for m in result:
            validate(m)
        return result
    except (
        KeyError,
        TypeError,
        UnicodeError,
        json.JSONDecodeError,
        RecursionError,
    ) as error:
        raise ValueError("Invalid macro library.") from error


def encode_library(macros):
    schema = (
        3
        if any(
            s["kind"] in ("moveMouse", "repeatFor") for m in macros for s in m["steps"]
        )
        else 1
    )
    data = json.dumps(
        {"schemaVersion": schema, "macros": macros},
        ensure_ascii=True,
        indent=2,
        sort_keys=True,
        allow_nan=False,
    ).encode()
    decode_library(data)
    return data


def atomic_write(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    name = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as file:
            name = file.name
            file.write(data)
            file.flush()
            os.fsync(file.fileno())
        os.replace(name, path)
    finally:
        if name and os.path.exists(name):
            os.unlink(name)


class MacroLibrary:
    def __init__(self, path):
        self.path = Path(path)
        self.error = None
        self.macros = []
        try:
            self.macros = (
                decode_library(self.read(self.path))
                if self.path.exists()
                else starters()
            )
        except (OSError, ValueError) as error:
            self.error = (
                f"Library could not be opened; existing file unchanged. {error}"
            )

    @staticmethod
    def read(path):
        if not Path(path).is_file():
            raise ValueError("Choose a regular JSON file.")
        with open(path, "rb") as file:
            data = file.read(MAX_LIBRARY_BYTES + 1)
        if len(data) > MAX_LIBRARY_BYTES:
            raise ValueError("Library file is too large.")
        return data

    def persist(self, macros):
        if self.error:
            raise ValueError("Recover the library backup before saving.")
        data = encode_library(macros)
        if self.path.exists():
            previous = self.read(self.path)
            decode_library(previous)
            atomic_write(str(self.path) + ".backup", previous)
        atomic_write(self.path, data)
        self.macros = deepcopy(macros)

    def save(self, macro):
        macro = deepcopy(macro)
        validate(macro)
        macro["updatedAt"] = time.time() - 978307200
        self.persist(
            [macro if m["id"] == macro["id"] else m for m in self.macros]
            if any(m["id"] == macro["id"] for m in self.macros)
            else self.macros + [macro]
        )

    def remove(self, mid):
        self.persist([m for m in self.macros if m["id"] != mid])

    def duplicate(self, macro):
        copy = deepcopy(macro)
        copy["id"] = str(uuid.uuid4()).upper()
        copy["name"] = "".join(regex.findall(r"\X", copy["name"])[:70]) + " Copy"
        self.save(copy)
        return copy["id"]

    def import_data(self, data):
        copies = decode_library(data)
        for m in copies:
            m["id"] = str(uuid.uuid4()).upper()
        self.persist(self.macros + copies)
        return copies[0]["id"] if copies else None

    def recover(self):
        data = self.read(str(self.path) + ".backup")
        macros = decode_library(data)
        atomic_write(self.path, data)
        self.macros = macros
        self.error = None
