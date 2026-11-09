"""Acknowledged, CRC-verified protocol 4 transfers on one background asyncio loop."""

import asyncio
import secrets
import struct

from .protocol import (
    HELLO,
    LAYOUTS,
    RX_UUID,
    SERVICE_UUID,
    TARGETS,
    TX_UUID,
    Command,
    FrameDecoder,
    KeyboardSettings,
    Timing,
    compile_text,
    crc32,
    frame,
    saved_descriptor,
    text_bytes,
)

KEYBOARD_ERRORS = (
    None,
    "Keyboard changed on Flipper; review its current setting.",
    "Flipper is busy; stop the job first.",
    "Invalid keyboard setting.",
    "Keyboard map unavailable; check SD layout assets.",
    "Keyboard not saved; check Flipper SD.",
)


class ClipboardTransport:
    def __init__(self, emit, *, scanner=None, client_factory=None):
        self.emit = emit
        self._scanner, self._client_factory = scanner, client_factory
        self._client = None
        self._decoder = FrameDecoder()
        self._write_lock = asyncio.Lock()
        self._pending = self._done = None
        self._expected = None
        self.ready = self.busy = self.connecting = False
        self._cancel_requested = self._cancel_sent = self._executing = False
        self._remote_active = False
        self._job = self._total = self._cursor = 0
        self._capacity = self._chunk_size = self._capabilities = 0
        self._activity = asyncio.Event()
        self.keyboard = None
        self._keyboard_id = 0
        self._monitor = None
        self.autonomous = False

    async def scan(self):
        if self.busy or self.connecting:
            return []
        if self._scanner is None:
            await self._check_thread()
            from bleak import BleakClient, BleakScanner

            self._scanner, self._client_factory = BleakScanner, BleakClient
        found = await self._scanner.discover(timeout=15, return_adv=True)
        return [
            device
            for device, advert in found.values()
            if SERVICE_UUID in [s.lower() for s in advert.service_uuids]
        ]

    async def connect(self, device=None):
        if self.connecting or self.busy:
            return
        await self.disconnect()
        self.connecting = True
        self.emit("state", "connecting")
        self.emit(
            "status", "Searching for BLE Clipboard. Open the app on your Flipper."
        )
        try:
            if self._scanner is None:
                await self._check_thread()
                from bleak import BleakClient, BleakScanner

                self._scanner, self._client_factory = BleakScanner, BleakClient
            if device is None:
                devices = await self.scan_for_connection()
                if len(devices) != 1:
                    raise RuntimeError("Choose one Flipper from the device list.")
                device = devices[0]
            if device is None:
                raise RuntimeError(
                    "Flipper not found. Open BLE Clipboard on the Flipper, then Connect."
                )
            self.emit(
                "status",
                "Pair Paste in Windows Bluetooth settings first; approve matching codes on both devices.",
            )
            # WinRT automatic pairing supports Just Works only. Let Windows
            # Settings perform numeric comparison without downgrading security.
            client = self._client_factory(
                device, disconnected_callback=self._disconnected, pair=False, timeout=60
            )
            self._client = client
            await asyncio.wait_for(client.connect(), 75)
            await client.start_notify(TX_UUID, self._notification)
            payload = await self._request(
                Command.HELLO, HELLO, Command.READY, timeout=30
            )
            if len(payload) < 10 or len(payload) > 41:
                raise ValueError("Invalid Flipper handshake.")
            capacity, chunk, layouts, targets, capabilities = struct.unpack_from(
                "<IHBBB", payload
            )
            if not (
                6 <= capacity <= 65536
                and 1 <= chunk <= 512
                and layouts == len(LAYOUTS)
                and targets & 7 == 7
                and capabilities & 31 == 31
            ):
                raise ValueError("Install a matching protocol 4 Flipper companion.")
            name = payload[9:].decode("utf-8")
            if not name or self._client is not client or not client.is_connected:
                raise RuntimeError(
                    "Flipper disconnected during setup. Connect to try again."
                )
            self._capacity, self._chunk_size, self._capabilities = (
                capacity,
                chunk,
                capabilities,
            )
            if capabilities & 32:
                try:
                    info = await self._request(
                        Command.INFO, b"", Command.INFO_REPLY, timeout=10
                    )
                    self._info(info)
                except (ValueError, RuntimeError, asyncio.TimeoutError):
                    self.emit("info", None)
            if capabilities & 64:
                try:
                    await self.get_keyboard()
                except (ValueError, RuntimeError, asyncio.TimeoutError) as error:
                    self.emit(
                        "keyboard_error",
                        str(error) or "Keyboard sync unavailable; refresh to retry.",
                    )
            if self._client is not client or not client.is_connected:
                raise RuntimeError("Flipper disconnected during setup.")
            self.ready = True
            self.emit("device", name)
            self.emit("capabilities", capabilities)
            self.emit("state", "sending" if self._remote_active else "ready")
            self.emit(
                "status",
                "Reconnected to standalone run; Stop is available"
                if self._remote_active
                else f"Connected to {name}",
            )
            if self._remote_active:
                self._monitor = asyncio.create_task(self._watch_remote())
        except BaseException:
            await self.disconnect()
            raise
        finally:
            self.connecting = False

    async def scan_for_connection(self):
        found = await self._scanner.discover(timeout=15, return_adv=True)
        return [
            device
            for device, advert in found.values()
            if SERVICE_UUID in [s.lower() for s in advert.service_uuids]
        ]

    @staticmethod
    async def _check_thread():
        import sys

        if sys.platform == "win32":
            from bleak.backends.winrt.util import assert_mta

            await assert_mta()

    def _info(self, data):
        if len(data) != 13:
            raise ValueError("Invalid companion info.")
        schema, major, minor, patch, wire, api, api_minor, target = struct.unpack(
            "<BHHHBHHB", data
        )
        if schema != 1 or wire != 4 or not api or target != 7:
            raise ValueError("Invalid companion info.")
        self.emit(
            "info",
            {
                "version": f"{major}.{minor}.{patch}",
                "api": f"{api}.{api_minor}",
                "target": target,
            },
        )

    async def get_keyboard(self):
        if not self._capabilities & 64:
            raise ValueError("Companion has no keyboard sync.")
        self._keyboard_id = self._keyboard_id % 65535 + 1
        data = await self._request(
            Command.GET_KEYBOARD,
            struct.pack("<H", self._keyboard_id),
            Command.KEYBOARD_REPLY,
            timeout=10,
        )
        request, result, settings = KeyboardSettings.reply(data)
        if request != self._keyboard_id:
            raise ValueError("Stale keyboard reply.")
        self._apply_keyboard(settings)
        if result:
            raise ValueError(KEYBOARD_ERRORS[result])
        return settings

    def _apply_keyboard(self, settings):
        if self.keyboard is None or settings.revision >= self.keyboard.revision:
            self.keyboard = settings
            self.emit("keyboard", settings)

    async def set_keyboard(self, settings):
        if (
            not self.ready
            or self.busy
            or self._pending is not None
            or not self._capabilities & 64
            or self.keyboard is None
        ):
            raise ValueError("Keyboard is not ready to change. Refresh it while idle.")
        self._keyboard_id = self._keyboard_id % 65535 + 1
        data = await self._request(
            Command.SET_KEYBOARD,
            settings.payload(self._keyboard_id),
            Command.KEYBOARD_REPLY,
            timeout=10,
        )
        request, result, actual = KeyboardSettings.reply(data)
        if request != self._keyboard_id:
            raise ValueError("Stale keyboard reply.")
        self._apply_keyboard(actual)
        if result:
            raise ValueError(KEYBOARD_ERRORS[result])

    async def _watch_remote(self):
        try:
            while self._remote_active and self._client is not None:
                await asyncio.wait_for(self._activity.wait(), 45)
                self._activity.clear()
                if self._done.done():
                    result = self._done.result()
                    self.emit(
                        "status",
                        "Cancelled; some input may have been sent"
                        if result
                        else "USB output complete",
                    )
                    self.busy = self._executing = self._remote_active = False
                    self._job = 0
                    self.emit("state", "ready")
                    break
        except (asyncio.TimeoutError, RuntimeError, ValueError):
            await self.disconnect()
        finally:
            if (
                self._done is not None
                and self._done.done()
                and not self._done.cancelled()
            ):
                self._done.exception()
            self._done = None

    async def disconnect(self):
        client, self._client = self._client, None
        was_busy = self.busy
        continues = self.busy and self.autonomous
        if self._monitor is not None and self._monitor is not asyncio.current_task():
            self._monitor.cancel()
        self._monitor = None
        self.keyboard = None
        self.ready = self.busy = False
        self._remote_active = False
        for future in (self._pending, self._done):
            if future is not None and not future.done():
                future.cancel()
        self._decoder = FrameDecoder()
        self.emit("state", "disconnected")
        self.emit(
            "status",
            "Disconnected; standalone run may continue. Use Stop on Flipper."
            if continues
            else "Disconnected. Text may be incomplete; check the target before resending."
            if was_busy
            else "Disconnected",
        )
        if client is not None:
            try:
                await asyncio.wait_for(client.disconnect(), 10)
            except (Exception, asyncio.CancelledError):
                pass

    def _disconnected(self, client):
        if self._client is not client:
            return
        self._client = None
        message = (
            "Flipper disconnected; standalone run may continue. Use Stop on Flipper."
            if self.busy and self.autonomous
            else "Flipper disconnected. Output may be incomplete; check the target before resending."
            if self.busy
            else "Flipper disconnected. Connect to try again."
        )
        self.ready = self.busy = False
        self.keyboard = None
        self._remote_active = False
        self._fail_waiter(RuntimeError(message))
        self.emit("state", "disconnected")
        self.emit("status", message)

    async def _write(self, data):
        async with self._write_lock:
            client = self._client
            if client is None or not client.is_connected:
                raise RuntimeError("Flipper is disconnected.")
            chunk_size = min(128, max(1, client.mtu_size - 3))
            for offset in range(0, len(data), chunk_size):
                if self._client is not client:
                    raise RuntimeError(
                        "Flipper disconnected. Check the target before resending."
                    )
                await asyncio.wait_for(
                    client.write_gatt_char(
                        RX_UUID, data[offset : offset + chunk_size], response=True
                    ),
                    15,
                )

    async def _request(self, command, payload, expected, timeout=15):
        if self._pending is not None:
            raise RuntimeError("Another protocol request is pending.")
        pending = self._pending = asyncio.get_running_loop().create_future()
        self._expected = expected
        try:
            await self._write(frame(command, payload))
            return await asyncio.wait_for(asyncio.shield(pending), timeout)
        finally:
            if not pending.done():
                pending.cancel()
            elif not pending.cancelled():
                pending.exception()
            self._pending = self._expected = None

    async def send(self, text, layout, timing, target=0):
        from .macros import CompiledMacro

        compiled = CompiledMacro(
            compile_text(text, layout, timing), (), layout, target, timing
        )
        result = await self.transfer(compiled)
        self.emit(
            "result",
            (
                "cancelled" if result else "USB keystrokes sent",
                len(text_bytes(text, layout)),
            ),
        )

    async def transfer(self, compiled, *, saved=None, standalone=False):
        if not self.ready or self.busy:
            raise RuntimeError(
                "Connect to a Flipper and wait for the current transfer to finish."
            )
        target, layout, timing, program = (
            compiled.target,
            compiled.layout,
            compiled.timing,
            compiled.program,
        )
        if (
            type(target) is not int
            or not 0 <= target < len(TARGETS)
            or type(layout) is not int
            or not 0 <= layout < len(LAYOUTS)
        ):
            raise ValueError("Choose a supported USB target OS.")
        if len(program) < 6 or not program.startswith(b"BCM4"):
            raise ValueError("Invalid compiled program.")
        if self._pending is not None:
            raise RuntimeError("Keyboard or metadata request is pending.")
        saved_payload = b""
        if saved is not None:
            sid, name = saved
            saved_payload = saved_descriptor(sid, name)
        if len(program) > self._capacity:
            raise ValueError("Text exceeds this Flipper's capacity.")
        if timing != Timing() and not self._capabilities & 128:
            raise ValueError(
                "Update the Flipper companion for slower or variable typing, or choose Fast."
            )
        self.busy = True
        self.autonomous = bool(standalone and saved is None)
        self._cancel_requested = self._cancel_sent = self._executing = False
        self._job = secrets.randbelow(0xFFFFFFFF) + 1
        self._total, self._cursor = len(program), 0
        job = struct.pack("<I", self._job)
        self._done = asyncio.get_running_loop().create_future()
        self.emit("state", "sending")
        self.emit("progress", 0)
        self.emit("status", "Uploading and verifying text. USB output has not started.")
        try:
            header = struct.pack(
                "<IBBIIB",
                self._job,
                layout,
                target,
                len(program),
                crc32(program),
                2 if saved else int(standalone),
            )
            await self._request(Command.BEGIN, header, Command.BEGUN)
            if not await self._cancel_if_requested():
                for offset in range(0, len(program), self._chunk_size):
                    chunk = program[offset : offset + self._chunk_size]
                    response = await self._request(
                        Command.CHUNK,
                        job + struct.pack("<I", offset) + chunk,
                        Command.CHUNKED,
                    )
                    if len(response) != 8 or struct.unpack_from("<I", response, 4)[
                        0
                    ] != offset + len(chunk):
                        raise ValueError(
                            "Unexpected upload acknowledgement. No automatic retry."
                        )
                    self.emit("progress", (offset + len(chunk)) / len(program) * 0.2)
                    if await self._cancel_if_requested():
                        break
                if not self._cancel_sent:
                    await self._request(Command.COMMIT, job, Command.VERIFIED)
                    if not await self._cancel_if_requested():
                        self._activity.clear()
                        if saved is not None:
                            await self._request(
                                Command.SAVE, job + saved_payload, Command.SAVED
                            )
                            self._done.set_result(2)
                        else:
                            self._executing = True
                            await self._write(frame(Command.EXECUTE, job))
            while not self._done.done():
                await asyncio.wait_for(self._activity.wait(), 45)
                self._activity.clear()
            result = await self._done
            self.emit(
                "status",
                "Saved on Flipper SD; not started"
                if result == 2
                else "Cancelled. Output may be incomplete."
                if result
                else "USB output complete; check target",
            )
            return result
        except asyncio.TimeoutError:
            await self.disconnect()
            raise RuntimeError(
                "Flipper status timed out. Check the target before resending."
            ) from None
        except (Exception, asyncio.CancelledError):
            await self.disconnect()
            raise
        finally:
            if self._done is not None:
                if not self._done.done():
                    self._done.cancel()
                elif not self._done.cancelled():
                    self._done.exception()
            self._done = None
            self.busy = self._executing = False
            self._job = 0
            if self.ready:
                self.emit("state", "ready")

    async def cancel(self):
        if not self.busy:
            return
        self._cancel_requested = True
        self.emit("status", "Cancelling USB output...")
        # During upload wait for the current application ACK before a CANCEL.
        if self._executing:
            await self._cancel_if_requested()

    async def _cancel_if_requested(self):
        if not self._cancel_requested:
            return False
        if not self._cancel_sent:
            self._cancel_sent = True
            await self._write(frame(Command.CANCEL, struct.pack("<I", self._job)))
        return True

    def _fail_waiter(self, error):
        for future in (self._pending, self._done):
            if future is not None and not future.done():
                future.set_exception(error)
                self._activity.set()
                return

    def _notification(self, _characteristic, data):
        try:
            for command, payload in self._decoder.append(data):
                if command == Command.READY:
                    if (
                        self._expected == command
                        and self._pending is not None
                        and not self._pending.done()
                    ):
                        self._pending.set_result(payload)
                    continue
                if command == Command.ACTIVE:
                    if len(payload) != 17:
                        raise ValueError("Invalid active job status.")
                    job, total, elapsed, remaining, flags = struct.unpack(
                        "<IIIIB", payload
                    )
                    if (
                        not job
                        or not 6 <= total <= 65536
                        or flags != 1
                        or remaining > 86400000
                    ):
                        raise ValueError("Invalid active job status.")
                    if not self.connecting or self.busy:
                        continue
                    self._remote_active = self.busy = self._executing = (
                        self.autonomous
                    ) = True
                    self._job, self._total, self._cursor = job, total, 0
                    self._done = asyncio.get_running_loop().create_future()
                    self.emit("timer", (elapsed // 1000, (remaining + 999) // 1000))
                    self._activity.set()
                    continue
                if command in (Command.INFO_REPLY, Command.KEYBOARD_REPLY):
                    if command == Command.KEYBOARD_REPLY:
                        try:
                            request, result, settings = KeyboardSettings.reply(payload)
                        except ValueError:
                            continue
                        if request == 0 and result == 0:
                            self._apply_keyboard(settings)
                        if request != self._keyboard_id:
                            continue
                    if (
                        self._expected == command
                        and self._pending is not None
                        and not self._pending.done()
                    ):
                        self._pending.set_result(payload)
                    continue
                if len(payload) < 4:
                    raise ValueError("Truncated Flipper response.")
                job = struct.unpack_from("<I", payload)[0]
                if command == Command.ERROR:
                    if job not in (0, self._job):
                        continue
                    if len(payload) < 5:
                        raise ValueError("Invalid error response.")
                    self._fail_waiter(
                        RuntimeError(
                            payload[5:].decode("utf-8", errors="replace")
                            or "Flipper rejected the request."
                        )
                    )
                    continue
                if not self.busy or job != self._job:
                    continue  # Stale job IDs cannot acknowledge or complete this transfer.
                if (
                    command
                    in (
                        Command.BEGUN,
                        Command.VERIFIED,
                        Command.STARTED,
                        Command.WAIT_USB,
                        Command.SAVED,
                    )
                    and len(payload) != 4
                ):
                    raise ValueError("Invalid job acknowledgement.")
                if (
                    command == self._expected
                    and self._pending is not None
                    and not self._pending.done()
                ):
                    self._pending.set_result(payload)
                elif command == Command.STARTED:
                    self.emit("accepted", None)
                    self.emit("status", "USB output in progress...")
                    self._activity.set()
                elif command == Command.WAIT_USB:
                    self.emit(
                        "status",
                        "Connect the Flipper USB cable to your target within 30 seconds.",
                    )
                    self._activity.set()
                elif command == Command.PROGRESS:
                    if len(payload) != 20:
                        raise ValueError("Invalid progress response.")
                    _, cursor, total, elapsed, remaining = struct.unpack(
                        "<IIIII", payload
                    )
                    if (
                        total != self._total
                        or not self._cursor <= cursor <= total
                        or remaining > 86400000
                    ):
                        raise ValueError("Invalid USB progress position.")
                    self._cursor = cursor
                    self.emit("progress", 0.2 + 0.8 * cursor / total)
                    self.emit("timer", (elapsed // 1000, (remaining + 999) // 1000))
                    self._activity.set()
                elif command == Command.DONE:
                    if len(payload) != 5 or payload[4] > 1:
                        raise ValueError("Invalid completion response.")
                    if self._done is not None and not self._done.done():
                        self._done.set_result(payload[4])
                    self._activity.set()
        except (ValueError, UnicodeError) as error:
            self._fail_waiter(error)
