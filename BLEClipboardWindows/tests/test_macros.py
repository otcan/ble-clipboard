import os
import struct
import tempfile
import unittest
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path

from ble_clipboard.macros import (
    MacroLibrary,
    compile_macro,
    decode_library,
    encode_library,
    new_macro,
    step,
    validate,
)
from ble_clipboard.protocol import HELLO, Command, Timing, crc32, frame
from ble_clipboard.release import availability, links, version
from ble_clipboard.review import RunReview

FIXTURE = (
    Path(__file__).resolve().parents[2] / "scripts/tests/fixtures/library-interop.json"
)


class MacroTests(unittest.TestCase):
    def test_shared_roundtrip_and_compiler_fixtures(self):
        macros = decode_library(FIXTURE.read_bytes())
        self.assertEqual(decode_library(encode_library(macros)), macros)
        self.assertEqual(macros[0]["updatedAt"], 721692800)
        self.assertEqual(
            macros[-1]["steps"][0]["id"], "20000000-0000-4000-8000-000000000010"
        )
        for i, macro in enumerate(macros):
            result = compile_macro(
                macro,
                clipboard="{{name}}",
                parameters={"name": "Sam"},
                date=datetime.fromtimestamp(1700000000, timezone.utc),
                timing=Timing(80, 30),
            )
            expected = (
                Path(str(FIXTURE).replace("library-interop.json", f"interop-{i}.hex"))
                .read_text()
                .strip()
            )
            self.assertEqual(result.program.hex(), expected)
            if os.environ.get("CLIPBOARD_FIXTURE_DIR"):
                directory = Path(os.environ["CLIPBOARD_FIXTURE_DIR"]) / "python"
                directory.mkdir(parents=True, exist_ok=True)
                data = result.program
                job = struct.pack("<I", 7)
                wire = frame(Command.HELLO, HELLO) + frame(
                    Command.BEGIN,
                    struct.pack(
                        "<IBBIIB",
                        7,
                        result.layout,
                        result.target,
                        len(data),
                        crc32(data),
                        0,
                    ),
                )
                for offset in range(0, len(data), 512):
                    wire += frame(
                        Command.CHUNK,
                        job + struct.pack("<I", offset) + data[offset : offset + 512],
                    )
                wire += frame(Command.COMMIT, job) + frame(Command.EXECUTE, job)
                (directory / f"interop-{i}.wire").write_bytes(wire)

    def test_validation_and_empty_template_output(self):
        macro = new_macro()
        macro["steps"] = [
            step("template", "{{clipboard}}"),
            step("delay", milliseconds=100),
        ]
        with self.assertRaisesRegex(ValueError, "empty output"):
            compile_macro(macro)
        macro["steps"] = [step("template", "{{oops}}")]
        with self.assertRaises(ValueError):
            validate(macro)
        for s in (
            step("delay", milliseconds=True),
            step("moveMouse", mouseXMinimum=128),
            step("chord", "CTRL+CTRL+A"),
        ):
            macro["steps"] = [s]
            with self.assertRaises(ValueError):
                validate(macro)
        macro["steps"] = [
            step(
                "repeatFor", children=[step("repeatFor", children=[step("text", "a")])]
            )
        ]
        with self.assertRaises(ValueError):
            validate(macro)
        macro["steps"] = [step("template", "{{clipboard}}" * 300)]
        with self.assertRaises(ValueError):
            compile_macro(macro, clipboard="x" * 65500)
        for invalid in (
            b"[]",
            b"null",
            b'{"schemaVersion":true,"macros":[]}',
            b'{"schemaVersion":4,"macros":[]}',
            b"x" * 2000001,
        ):
            with self.assertRaises(ValueError):
                decode_library(invalid)

    def test_corrupt_library_backup_recovery_and_import_ids(self):
        with tempfile.TemporaryDirectory() as path:
            file = Path(path) / "macros.json"
            library = MacroLibrary(file)
            macro = new_macro()
            macro["steps"] = [step("text", "One")]
            library.save(macro)
            first = file.read_bytes()
            macro["name"] = "Two"
            library.save(macro)
            self.assertEqual(Path(str(file) + ".backup").read_bytes(), first)
            file.write_bytes(b"corrupt")
            recovered = MacroLibrary(file)
            self.assertTrue(recovered.error)
            with self.assertRaises(ValueError):
                recovered.persist([])
            self.assertEqual(file.read_bytes(), b"corrupt")
            recovered.recover()
            self.assertEqual(file.read_bytes(), first)
            before = deepcopy(recovered.macros)
            recovered.import_data(first)
            self.assertEqual(len(recovered.macros), len(before) * 2)
            self.assertTrue(
                set(m["id"] for m in before).isdisjoint(
                    m["id"] for m in recovered.macros[len(before) :]
                )
            )

    def test_review_is_frozen_single_use_and_edits_clear_confirmation(self):
        macro = new_macro()
        macro["steps"] = [step("template", "{{clipboard}}")]
        review = RunReview()
        compiled = review.prepare(macro, clipboard="Original")
        with self.assertRaises(ValueError):
            review.consume()
        review.confirmed = True
        macro["steps"][0]["value"] = "Edited"
        self.assertEqual(review.consume(), compiled)
        with self.assertRaises(ValueError):
            review.consume()
        review.prepare(macro)
        review.confirmed = True
        review.invalidate()
        self.assertFalse(review.confirmed)
        self.assertIsNone(review.compiled)

    def test_exact_version_release_checks(self):
        value = version()
        assets = [
            {
                "name": url.rsplit("/", 1)[1],
                "browser_download_url": url,
                "state": "uploaded",
                "size": 1,
            }
            for url in links(value).values()
        ]
        document = {
            "tag_name": f"v{value}",
            "draft": False,
            "html_url": f"https://github.com/otcan/ble-clipboard/releases/tag/v{value}",
            "assets": assets,
        }
        self.assertTrue(availability(value, document))
        document["assets"] = assets[:-1]
        self.assertFalse(availability(value, document))
        document["assets"] = assets + [assets[0]]
        self.assertFalse(availability(value, document))
        document["assets"] = assets
        document["tag_name"] = "v0.5.3"
        self.assertFalse(availability(value, document))
