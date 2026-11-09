"""Protocol 4 quick-paste compiler, compatible with the Mac and Flipper engines."""

import struct
import unicodedata
import zlib
from dataclasses import dataclass
from enum import IntEnum

SERVICE_UUID = "a6f1d9c0-7b21-4c9a-8e52-3d7710aa0301"
TX_UUID = "a6f1d9c0-7b21-4c9a-8e52-3d7710aa0302"
RX_UUID = "a6f1d9c0-7b21-4c9a-8e52-3d7710aa0303"
MAX_PROGRAM_BYTES = 65536
MAX_TEXT_BYTES = MAX_PROGRAM_BYTES - 11
HELLO = b"BLECLIP/4"
LAYOUTS = (
    "English (US)",
    "Turkish Q (experimental)",
    "Bosnian",
    "Czech",
    "Danish",
    "German (Swiss)",
    "German",
    "Dvorak",
    "English (UK)",
    "Spanish",
    "Spanish (Latin America)",
    "French (Belgium)",
    "French (Canada)",
    "French (Swiss)",
    "French (Mac)",
    "French",
    "Croatian",
    "Hungarian",
    "Italian (Mac)",
    "Italian",
    "Japanese",
    "Norwegian",
    "Dutch",
    "Portuguese (Brazil)",
    "Portuguese",
    "Slovenian",
    "Slovak",
    "Swedish",
)
TARGETS = ("macOS", "Windows", "Linux")
TARGET_IDS = ("macOS", "windows", "linux")
LAYOUT_IDS = (
    "QWERTY US",
    "tr-TR.kl",
    "ba-BA.kl",
    "cz_CS.kl",
    "da-DA.kl",
    "de-CH.kl",
    "de-DE.kl",
    "dvorak.kl",
    "en-UK.kl",
    "es-ES.kl",
    "es-LA.kl",
    "fr-BE.kl",
    "fr-CA.kl",
    "fr-CH.kl",
    "fr-FR-mac.kl",
    "fr-FR.kl",
    "hr-HR.kl",
    "hu-HU.kl",
    "it-IT-mac.kl",
    "it-IT.kl",
    "ja-JP.kl",
    "nb-NO.kl",
    "nl-NL.kl",
    "pt-BR.kl",
    "pt-PT.kl",
    "si-SI.kl",
    "sk-SK.kl",
    "sv-SE.kl",
)
TURKISH = frozenset("ÇçĞğİıÖöŞşÜü")


class Command(IntEnum):
    HELLO = 1
    BEGIN = 2
    CHUNK = 3
    COMMIT = 4
    EXECUTE = 5
    CANCEL = 6
    SAVE = 7
    INFO = 8
    GET_KEYBOARD = 9
    SET_KEYBOARD = 10
    READY = 0x81
    BEGUN = 0x82
    CHUNKED = 0x83
    VERIFIED = 0x84
    STARTED = 0x85
    WAIT_USB = 0x86
    PROGRESS = 0x87
    DONE = 0x88
    SAVED = 0x89
    ACTIVE = 0x8A
    INFO_REPLY = 0x8B
    KEYBOARD_REPLY = 0x8C
    ERROR = 0xFF


@dataclass(frozen=True)
class Timing:
    pause_ms: int = 0
    variation_ms: int = 0

    def validate(self):
        if (
            type(self.pause_ms) is not int
            or type(self.variation_ms) is not int
            or not 0 <= self.pause_ms <= 1000
            or not 0 <= self.variation_ms <= self.pause_ms
            or self.pause_ms + self.variation_ms > 1000
        ):
            raise ValueError(
                "Pause must be 0–1000 ms; variation must keep the pause within that range."
            )


PRESETS = {"Fast": Timing(), "Slow": Timing(80), "Variable": Timing(80, 30)}


def text_bytes(text, layout=0):
    if type(layout) is not int or not 0 <= layout < len(LAYOUTS):
        raise ValueError("Choose a supported target keyboard layout.")
    normalized = (
        unicodedata.normalize("NFC", text).replace("\r\n", "\n").replace("\r", "\n")
    )
    if any(
        not (
            32 <= ord(char) <= 126 or char in "\t\n" or layout == 1 and char in TURKISH
        )
        for char in normalized
    ):
        raise ValueError(
            "Text supports ASCII, tabs and line breaks; Turkish letters require Turkish Q."
        )
    data = normalized.encode("utf-8")
    if not 1 <= len(data) <= MAX_TEXT_BYTES:
        raise ValueError(f"Enter between 1 and {MAX_TEXT_BYTES:,} UTF-8 bytes.")
    return data


def compile_text(text, layout, timing=Timing()):
    timing.validate()
    data = text_bytes(text, layout)
    records = b"\x01" + struct.pack("<I", len(data)) + data
    count = 1
    if timing != Timing():
        records = struct.pack("<BHH", 7, timing.pause_ms, timing.variation_ms) + records
        count += 1
    result = b"BCM4" + struct.pack("<H", count) + records
    if len(result) > MAX_PROGRAM_BYTES:
        raise ValueError(
            "Text plus typing options exceeds the 65,536-byte program limit."
        )
    return result


def crc32(program):
    return zlib.crc32(program) & 0xFFFFFFFF


def frame(command, payload=b""):
    if len(payload) > 520:
        raise ValueError("Frame is too large.")
    return struct.pack("<BBH", 4, command, len(payload)) + payload


@dataclass(frozen=True)
class KeyboardSettings:
    layout: int = 0
    target: int = 0
    use_saved: bool = False
    revision: int = 0

    def payload(self, request):
        if (
            type(request) is not int
            or not 1 <= request <= 65535
            or type(self.layout) is not int
            or not 0 <= self.layout < 28
            or type(self.target) is not int
            or not 0 <= self.target < 3
            or type(self.use_saved) is not bool
            or type(self.revision) is not int
            or not 0 <= self.revision <= 0xFFFFFFFF
        ):
            raise ValueError("Invalid keyboard settings.")
        return struct.pack(
            "<HBBBBI",
            request,
            1,
            self.layout,
            self.target,
            int(self.use_saved),
            self.revision,
        )

    @classmethod
    def reply(cls, payload):
        if len(payload) != 11:
            raise ValueError("Invalid keyboard settings reply.")
        schema, request, result, layout, target, saved, revision = struct.unpack(
            "<BHBBBBI", payload
        )
        if (
            schema != 1
            or result > 5
            or layout >= 28
            or target >= 3
            or saved > 1
            or revision == 0
            and (layout or target or saved)
        ):
            raise ValueError("Invalid keyboard settings reply.")
        return request, result, cls(layout, target, bool(saved), revision)


class FrameDecoder:
    def __init__(self):
        self._buffer = bytearray()

    def append(self, data):
        self._buffer.extend(data)
        result = []
        while len(self._buffer) >= 4:
            version, command, length = struct.unpack_from("<BBH", self._buffer)
            if (
                version != 4
                or length > 124
                or command not in Command._value2member_map_
                or command < 0x81
            ):
                self._buffer.clear()
                raise ValueError(
                    "Invalid response from Flipper. Install the matching companion and reconnect."
                )
            if len(self._buffer) < length + 4:
                break
            result.append((Command(command), bytes(self._buffer[4 : 4 + length])))
            del self._buffer[: 4 + length]
        return result
