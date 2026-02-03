import asyncio
import json

from bleak import BleakClient, BleakScanner

QUERY_UUID = "00002a57-0000-1000-8000-00805f9b34fb"
MUTATION_UUID = "00002a58-0000-1000-8000-00805f9b34fb"
SUBSCRIPTION_UUID = "00002a59-0000-1000-8000-00805f9b34fb"


async def notification_handler(sender, data):
    print(f"Notification: {data.decode('utf-8')}")


async def test_gatt_server():
    # Find your device
    devices = await BleakScanner.discover()
    print("Available devices:")
    for d in devices:
        print(d.name)
    target = None
    for d in devices:
        if "reality2" in d.name or "r2" in d.name:
            print(d.name)
            target = d
            break

    if not target:
        print("Device not found")
        return

    async with BleakClient(target.address) as client:
        print(f"Connected to {target.name}")

        # Test 1: Read query characteristic (get all Sentants)
        query_data = await client.read_gatt_char(QUERY_UUID)
        print(f"Sentants: {query_data.decode('utf-8')}")

        # Test 2: Subscribe to notifications
        await client.start_notify(SUBSCRIPTION_UUID, notification_handler)

        # Test 3: Write mutation
        mutation = {
            "id": "test_sentant",
            "event": "test_event",
            "parameters": {"test": "data"},
        }
        await client.write_gatt_char(
            MUTATION_UUID, json.dumps(mutation).encode("utf-8")
        )

        # Wait for notifications
        await asyncio.sleep(5)
        await client.stop_notify(SUBSCRIPTION_UUID)


asyncio.run(test_gatt_server())
