"""Read-only Ducker BLE handshake probe. Never transfers text or executes USB keys."""
import argparse
import asyncio

from bleak import BleakClient, BleakScanner

SERVICE = "8fe5b3d5-2e7f-4a98-2a48-7acc60fe0000"
RX = "19ed82ae-ed21-4c9d-4145-228e62fe0000"
TX = "19ed82ae-ed21-4c9d-4145-228e61fe0000"
FLOW = "19ed82ae-ed21-4c9d-4145-228e63fe0000"
RPC_STATUS = "19ed82ae-ed21-4c9d-4145-228e64fe0000"


async def probe(name: str) -> None:
    print("Scanning for the explicitly selected Flipper...", flush=True)
    device = await BleakScanner.find_device_by_filter(
        lambda item, advertisement: name.casefold() in
        (advertisement.local_name or item.name or "").casefold(), timeout=12,
    )
    if device is None:
        raise RuntimeError("Selected Flipper not found; keep Ducker open and other clients disconnected.")
    print("Selected Flipper discovered; connecting...", flush=True)
    ready = asyncio.Event()
    buffer = bytearray()

    def notification(_characteristic, data):
        buffer.extend(data)
        if len(buffer) > 1024:
            raise RuntimeError("Oversized handshake response")
        while b"\n" in buffer:
            line, _, remaining = buffer.partition(b"\n")
            buffer[:] = remaining
            text = line.decode("ascii").strip()
            if text.startswith(("READY:", "LAYOUT:", "ERR:")):
                print("Response:", text, flush=True)
            if text == "READY:1:65536":
                ready.set()

    async with BleakClient(device, timeout=25) as client:
        print("BLE connected; services discovered.", flush=True)
        service = client.services.get_service(SERVICE)
        if service is None:
            raise RuntimeError("Serial service missing")
        for characteristic in service.characteristics:
            if characteristic.uuid in (RX, TX):
                print("Characteristic:", characteristic.uuid, characteristic.properties, flush=True)
        for title, uuid, order in [("RPC status", RPC_STATUS, "little"), ("RX buffer capacity", FLOW, "big")]:
            value = await asyncio.wait_for(client.read_gatt_char(uuid), 8)
            if len(value) != 4:
                raise RuntimeError(f"Unexpected {title} response length")
            if uuid == RPC_STATUS:
                print("RPC active flag:", value[0], flush=True)
            else:
                print(title + ":", int.from_bytes(value, order), flush=True)
        await asyncio.wait_for(client.start_notify(TX, notification), 15)
        print("Status subscription enabled; sending TTF? only...", flush=True)
        await asyncio.wait_for(client.write_gatt_char(RX, b"TTF?\n", response=True), 15)
        print("Handshake write acknowledged; waiting for READY...", flush=True)
        await asyncio.wait_for(ready.wait(), 8)
        print("TTF1 handshake verified. No typing payload or execution command was sent.", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True, help="Unique advertised device name or name fragment")
    args = parser.parse_args()
    try:
        asyncio.run(asyncio.wait_for(probe(args.name), 70))
    except (Exception, KeyboardInterrupt) as error:
        raise SystemExit(f"Handshake probe failed: {type(error).__name__}: {error}")
