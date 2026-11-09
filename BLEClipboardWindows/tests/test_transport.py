import asyncio
import struct
import unittest
from types import SimpleNamespace

from ble_clipboard.macros import CompiledMacro, compile_macro, new_macro, step
from ble_clipboard.protocol import (
    HELLO,
    RX_UUID,
    SERVICE_UUID,
    TX_UUID,
    Command,
    KeyboardSettings,
    Timing,
    compile_text,
    crc32,
    frame,
)
from ble_clipboard.transport import ClipboardTransport


class FakeClient:
    def __init__(self, _device, *, disconnected_callback, pair, timeout):
        self.on_disconnect, self.pair = disconnected_callback, pair
        self.is_connected = False
        self.mtu_size = 23
        self.buffer = bytearray()
        self.frames = []
        self.auto_complete = True
        self.delay_chunk = False
        self.chunk_received, self.executed = asyncio.Event(), asyncio.Event()
        self.reject = None
        self.fail_write = self.wrong_offset = self.had_commit = False
        self.job = 0
        self.program = bytearray()
        self.capabilities = 255
        self.keyboard = (0, 0, 0, 0)

    async def connect(self):
        self.is_connected = True

    async def disconnect(self):
        self.is_connected = False
        self.on_disconnect(self)

    async def start_notify(self, uuid, callback):
        assert uuid == TX_UUID
        self.callback = callback

    def respond(self, command, payload=b""):
        encoded = frame(command, payload)
        self.callback(None, encoded[:3])
        self.callback(None, encoded[3:])

    def job_reply(self, command, suffix=b"", job=None):
        self.respond(
            command, struct.pack("<I", self.job if job is None else job) + suffix
        )

    async def write_gatt_char(self, uuid, data, *, response):
        assert uuid == RX_UUID and response and len(data) <= self.mtu_size - 3
        if self.fail_write:
            raise RuntimeError("Write failed")
        self.buffer.extend(data)
        await asyncio.sleep(0)
        if len(self.buffer) < 4:
            return
        length = struct.unpack_from("<H", self.buffer, 2)[0]
        if len(self.buffer) < length + 4:
            return
        assert len(self.buffer) == length + 4, "Frames were interleaved"
        command, payload = self.buffer[1], bytes(self.buffer[4:])
        self.buffer.clear()
        self.frames.append((command, payload))
        if self.reject:
            self.job_reply(Command.ERROR, b"\x02" + self.reject)
        elif command == Command.HELLO:
            assert payload == HELLO
            self.respond(
                Command.READY,
                struct.pack("<IHBBB", 65536, 512, 28, 7, self.capabilities)
                + b"Test Flipper",
            )
        elif command == Command.BEGIN:
            self.job, self.layout, self.target, self.size, self.crc, flags = (
                struct.unpack("<IBBIIB", payload)
            )
            assert flags in (0, 1, 2)
            self.program.clear()
            self.had_commit = False
            self.job_reply(Command.BEGUN)
        elif command == Command.CHUNK:
            job, offset = struct.unpack_from("<II", payload)
            assert job == self.job and offset == len(self.program)
            self.program.extend(payload[8:])
            self.chunk_received.set()
            if not self.delay_chunk:
                self.ack_chunk()
        elif command == Command.COMMIT:
            assert len(self.program) == self.size and crc32(self.program) == self.crc
            self.had_commit = True
            self.job_reply(Command.VERIFIED)
        elif command == Command.EXECUTE:
            assert self.had_commit, "Output started before verification"
            self.executed.set()
            self.job_reply(Command.STARTED)
            if self.auto_complete:
                self.job_reply(Command.DONE, b"\x00")
        elif command == Command.CANCEL:
            self.job_reply(Command.DONE, b"\x01")
        elif command == Command.INFO:
            self.respond(
                Command.INFO_REPLY, struct.pack("<BHHHBHHB", 1, 0, 5, 4, 4, 88, 2, 7)
            )
        elif command in (Command.GET_KEYBOARD, Command.SET_KEYBOARD):
            request = struct.unpack_from("<H", payload)[0]
            if command == Command.SET_KEYBOARD:
                _, _, layout, target, saved, revision = struct.unpack(
                    "<HBBBBI", payload
                )
                result = int(revision != self.keyboard[3])
                if not result:
                    self.keyboard = (layout, target, saved, revision + 1)
                self.respond(
                    Command.KEYBOARD_REPLY,
                    struct.pack("<BHBBBBI", 1, request, result, *self.keyboard),
                )
            else:
                self.respond(
                    Command.KEYBOARD_REPLY,
                    struct.pack("<BHBBBBI", 1, request, 0, *self.keyboard),
                )
        elif command == Command.SAVE:
            assert self.had_commit
            self.job_reply(Command.SAVED)

    def ack_chunk(self):
        self.job_reply(
            Command.CHUNKED,
            struct.pack("<I", len(self.program) + int(self.wrong_offset)),
        )


class FakeScanner:
    @staticmethod
    async def discover(*, timeout, return_adv):
        assert timeout == 15 and return_adv
        return {
            "test": (
                SimpleNamespace(name="Paste", address="test"),
                SimpleNamespace(service_uuids=[SERVICE_UUID.upper()]),
            )
        }


class TransportTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.events, self.clients = [], []

        def factory(*args, **kwargs):
            client = FakeClient(*args, **kwargs)
            self.clients.append(client)
            return client

        self.transport = ClipboardTransport(
            lambda kind, value: self.events.append((kind, value)),
            scanner=FakeScanner,
            client_factory=factory,
        )
        await self.transport.connect()
        self.client = self.clients[-1]

    async def asyncTearDown(self):
        await self.transport.disconnect()

    async def test_maximum_upload_crc_verified_before_execute(self):
        self.assertFalse(self.client.pair)
        text = "a" * 65520
        await self.transport.send(text, 1, Timing(300, 100), target=2)
        self.assertEqual(self.client.program, compile_text(text, 1, Timing(300, 100)))
        self.assertEqual(self.client.target, 2)
        self.assertIn(("result", ("USB keystrokes sent", len(text))), self.events)
        self.assertFalse(self.transport.busy)
        self.assertTrue(self.transport.ready)

    async def test_cancel_upload_waits_for_ack_never_executes(self):
        self.client.delay_chunk = True
        send = asyncio.create_task(
            self.transport.send("Hello" * 200, 0, Timing(80, 30))
        )
        await asyncio.wait_for(self.client.chunk_received.wait(), 2)
        await self.transport.cancel()
        self.assertNotIn(Command.CANCEL, [command for command, _ in self.client.frames])
        self.client.ack_chunk()
        await asyncio.wait_for(send, 2)
        self.assertFalse(self.client.executed.is_set())
        self.assertEqual(
            sum(command == Command.CANCEL for command, _ in self.client.frames), 1
        )
        self.assertNotIn(("accepted", None), self.events)

    async def test_cancel_while_slow_typing(self):
        self.client.auto_complete = False
        send = asyncio.create_task(self.transport.send("Hello", 0, Timing(1000)))
        await asyncio.wait_for(self.client.executed.wait(), 2)
        await asyncio.gather(self.transport.cancel(), self.transport.cancel())
        await asyncio.wait_for(send, 2)
        self.assertEqual(
            sum(command == Command.CANCEL for command, _ in self.client.frames), 1
        )
        self.assertIn(("result", ("cancelled", 5)), self.events)

    async def test_disconnect_reconnect_no_replay(self):
        self.client.auto_complete = False
        send = asyncio.create_task(self.transport.send("Hello", 0, Timing()))
        await asyncio.wait_for(self.client.executed.wait(), 2)
        self.client.is_connected = False
        self.client.on_disconnect(self.client)
        with self.assertRaisesRegex(RuntimeError, "incomplete"):
            await send
        await self.transport.connect()
        self.assertEqual(
            [c for c, _ in self.clients[-1].frames],
            [Command.HELLO, Command.INFO, Command.GET_KEYBOARD],
        )

    async def test_old_firmware_rejected_before_upload(self):
        self.transport._capabilities = 127
        before = list(self.client.frames)
        with self.assertRaisesRegex(ValueError, "Update the Flipper"):
            await self.transport.send("Hello", 0, Timing(80))
        self.assertEqual(self.client.frames, before)
        forged = CompiledMacro(compile_text("Hello", 0, Timing(80)), (), 0, 0, Timing())
        with self.assertRaisesRegex(ValueError, "differs from the reviewed"):
            await self.transport.transfer(forged)
        self.assertEqual(self.client.frames, before)
        await self.transport.send("Hello", 0, Timing())

    async def test_wrong_offset_and_server_error_prevent_execute(self):
        self.client.wrong_offset = True
        with self.assertRaisesRegex(ValueError, "acknowledgement"):
            await self.transport.send("Hello", 0, Timing())
        self.assertFalse(self.client.executed.is_set())
        await self.transport.connect()
        self.client = self.clients[-1]
        self.client.reject = b"Keyboard layout unavailable"
        with self.assertRaisesRegex(RuntimeError, "layout unavailable"):
            await self.transport.send("Hello", 0, Timing())
        self.assertFalse(self.client.executed.is_set())

    async def test_stale_done_is_ignored(self):
        self.client.auto_complete = False
        send = asyncio.create_task(self.transport.send("Hello", 0, Timing()))
        await asyncio.wait_for(self.client.executed.wait(), 2)
        self.client.job_reply(Command.DONE, b"\x00", job=self.client.job ^ 1)
        await asyncio.sleep(0)
        self.assertFalse(send.done())
        self.client.job_reply(
            Command.PROGRESS,
            struct.pack(
                "<IIII", len(self.client.program), len(self.client.program), 1000, 0
            ),
        )
        self.client.job_reply(Command.DONE, b"\x00")
        await asyncio.wait_for(send, 2)

    async def test_invalid_frame_and_write_failure_disconnect(self):
        self.client.auto_complete = False
        send = asyncio.create_task(self.transport.send("A", 0, Timing()))
        await asyncio.wait_for(self.client.executed.wait(), 2)
        self.client.callback(None, bytes([2, 0x88, 0, 0]))
        with self.assertRaisesRegex(ValueError, "Invalid response"):
            await send
        self.assertFalse(self.transport.ready)
        await self.transport.connect()
        self.clients[-1].fail_write = True
        with self.assertRaisesRegex(RuntimeError, "Write failed"):
            await self.transport.send("A", 0, Timing())
        self.assertFalse(self.transport.ready)

    async def test_invalid_text_never_written(self):
        before = list(self.client.frames)
        with self.assertRaises(ValueError):
            await self.transport.send("café", 0, Timing())
        self.assertEqual(self.client.frames, before)

    async def test_save_only_never_executes_and_capacity_rejects_before_upload(self):
        macro = new_macro("Snapshot")
        macro["steps"] = [step("text", "Saved")]
        compiled = compile_macro(macro, timing=Timing(80))
        result = await self.transport.transfer(
            compiled, saved=(macro["id"], macro["name"])
        )
        self.assertEqual(result, 2)
        self.assertFalse(self.client.executed.is_set())
        self.assertEqual(
            [
                payload[-1]
                for cmd, payload in self.client.frames
                if cmd == Command.BEGIN
            ],
            [2],
        )
        before = list(self.client.frames)
        self.transport._capacity = 6
        with self.assertRaises(ValueError):
            await self.transport.transfer(compiled)
        self.assertEqual(self.client.frames, before)

    async def test_keyboard_revision_conflicts_and_stale_notifications(self):
        await self.transport.set_keyboard(KeyboardSettings(1, 2, True, 0))
        self.assertEqual(self.transport.keyboard, KeyboardSettings(1, 2, True, 1))
        with self.assertRaisesRegex(ValueError, "changed on Flipper"):
            await self.transport.set_keyboard(KeyboardSettings(6, 1, True, 0))
        self.assertEqual(self.transport.keyboard, KeyboardSettings(1, 2, True, 1))
        self.client.respond(
            Command.KEYBOARD_REPLY, struct.pack("<BHBBBBI", 1, 0, 0, 0, 0, 0, 0)
        )
        self.assertEqual(self.transport.keyboard.revision, 1)
        self.client.respond(
            Command.KEYBOARD_REPLY, struct.pack("<BHBBBBI", 1, 0, 0, 6, 1, 1, 2)
        )
        self.assertEqual(self.transport.keyboard, KeyboardSettings(6, 1, True, 2))
        before = list(self.client.frames)
        self.transport.busy = True
        with self.assertRaises(ValueError):
            await self.transport.set_keyboard(KeyboardSettings())
        self.transport.busy = False
        self.assertEqual(self.client.frames, before)

    async def test_standalone_disconnect_warns_no_replay(self):
        self.client.auto_complete = False
        macro = new_macro()
        macro["steps"] = [step("text", "A")]
        send = asyncio.create_task(
            self.transport.transfer(compile_macro(macro), standalone=True)
        )
        await asyncio.wait_for(self.client.executed.wait(), 2)
        self.client.is_connected = False
        self.client.on_disconnect(self.client)
        with self.assertRaisesRegex(RuntimeError, "standalone run may continue"):
            await send
        self.assertIn(
            (
                "status",
                "Flipper disconnected; standalone run may continue. Use Stop on Flipper.",
            ),
            self.events,
        )

    async def test_attach_standalone_without_upload_and_remote_stop(self):
        await self.transport.disconnect()
        original = self.transport._client_factory

        def factory(*args, **kwargs):
            client = original(*args, **kwargs)
            start_notify = client.start_notify

            async def notify(uuid, callback):
                await start_notify(uuid, callback)
                client.job = 99
                client.respond(
                    Command.ACTIVE, struct.pack("<IIIIB", 99, 60, 1000, 5000, 1)
                )

            client.start_notify = notify
            return client

        self.transport._client_factory = factory
        await self.transport.connect()
        client = self.clients[-1]
        self.assertTrue(self.transport.busy)
        self.assertNotIn(Command.EXECUTE, [c for c, _ in client.frames])
        await self.transport.cancel()
        await asyncio.sleep(0)
        await asyncio.sleep(0)
        self.assertIn(Command.CANCEL, [c for c, _ in client.frames])
        self.assertNotIn(Command.BEGIN, [c for c, _ in client.frames])
