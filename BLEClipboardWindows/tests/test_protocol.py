import struct
import unittest

from ble_clipboard.protocol import (
    MAX_TEXT_BYTES,
    Command,
    FrameDecoder,
    Timing,
    compile_text,
    crc32,
    frame,
    saved_descriptor,
)


class ProtocolTests(unittest.TestCase):
    def test_saved_descriptor_rejects_invalid_names_before_upload(self):
        sid = "10000000-0000-4000-8000-000000000001"
        self.assertEqual(saved_descriptor(sid, "a" * 79)[16], 79)
        for name in ("", "  ", "x" * 80, "Line\nBreak", "Tab\t", "Zero\u200bWidth"):
            with self.assertRaises(ValueError):
                saved_descriptor(sid, name)
        with self.assertRaises(ValueError):
            saved_descriptor("00000000-0000-0000-0000-000000000000", "Name")

    def test_wire_and_limits(self):
        self.assertEqual(
            compile_text("A\r\n\t", 1), b"BCM4\x01\x00\x01\x03\x00\x00\x00A\n\t"
        )
        self.assertEqual(
            compile_text("A", 1, Timing(300, 100)),
            b"BCM4\x02\x00\x07\x2c\x01\x64\x00\x01\x01\x00\x00\x00A",
        )
        self.assertEqual(len(compile_text("a" * MAX_TEXT_BYTES, 0)), 65536)
        self.assertEqual(
            len(compile_text("a" * (MAX_TEXT_BYTES - 5), 0, Timing(80, 30))), 65536
        )
        self.assertEqual(crc32(b"123456789"), 0xCBF43926)
        self.assertEqual(compile_text("s\u0327I\u0307", 1)[11:], "şİ".encode())

    def test_validation(self):
        for text in (
            "",
            "a" * (MAX_TEXT_BYTES + 1),
            "café",
            "\x00",
            "\x1b",
            "\x7f",
            "🎹",
            "ş",
        ):
            with self.assertRaises(ValueError):
                compile_text(text, 0)
        with self.assertRaises(ValueError):
            compile_text("a" * MAX_TEXT_BYTES, 0, Timing(80))
        for layout in (-1, 28, True, "0"):
            with self.assertRaises(ValueError):
                compile_text("A", layout)
        for timing in (
            Timing(-1),
            Timing(1001),
            Timing(10, 11),
            Timing(900, 101),
            Timing(80, -1),
            Timing("80"),
        ):
            with self.assertRaises(ValueError):
                compile_text("A", 0, timing)

    def test_frames(self):
        decoder = FrameDecoder()
        ready, done = frame(Command.READY, b"Flipper"), frame(Command.DONE, b"typed")
        self.assertEqual(decoder.append(ready[:3]), [])
        self.assertEqual(
            decoder.append(ready[3:] + done),
            [(Command.READY, b"Flipper"), (Command.DONE, b"typed")],
        )
        for header in (
            bytes([2, 0x81, 0, 0]),
            struct.pack("<BBH", 4, 0x81, 125),
            bytes([4, 0x8E, 0, 0]),
        ):
            with self.assertRaises(ValueError):
                decoder.append(header)
            self.assertEqual(decoder.append(done), [(Command.DONE, b"typed")])
