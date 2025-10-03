# file: lapmonitor_handoff_decoder.py
import asyncio, json, binascii, datetime as dt, time, os
from typing import Optional
from bleak import BleakScanner, BleakClient

def u16_be(b, i): return (b[i] << 8) | b[i+1]
def u16_le(b, i): return (b[i+1] << 8) | b[i]

def parse_frame(buf: bytes):
    # Expect 13 bytes: '#','l', 5x u16, 0xA5
    if len(buf) != 13 or buf[0] != 0x23 or buf[1] != 0x6C or buf[-1] != 0xA5:
        return None
    msgType   = u16_be(buf, 2)              # usually 0x014C
    lapNumber = u16_be(buf, 4)              # big-endian
    deviceId  = u16_be(buf, 6)              # big-endian (79, 33, 22, …)
    auxBE     = u16_be(buf, 8)              # TBD (sector/flags/quality?)
    cumulativeSeconds = u16_le(buf,10)      # was our guess; keep for reference
    return {
        "msgType": msgType,
        "lapNumber": lapNumber,
        "deviceId": deviceId,
        "aux": auxBE,
        "cumulativeSeconds": cumulativeSeconds
    }

# Per-device state
last_seen_ns = {}             # monotonic clock, for lap deltas
lap_times_by_device = {}      # deviceId -> [lap_ms, ...]
lap_counts_by_device = {}     # deviceId -> count of completed laps
best_lap_by_device = {}       # deviceId -> best (min) lap time in ms

# Rider name mapping
#Examples below
RIDER_NAMES = {
    22: "Luke",
    33: "Anakin", 
    79: "Ventress"
}

def format_ms(ms: Optional[int]) -> str:
    if ms is None:
        return "—"
    s, msec = divmod(ms, 1000)
    mins, sec = divmod(s, 60)
    return f"{mins}:{sec:02d}.{msec:03d}"

def _format_secs_from_ms(ms: Optional[int]) -> str:
    """Return 'X.YYYs' trimmed (e.g., 21.111s, 22.22s)."""
    if ms is None:
        return "—"
    s = ms / 1000.0
    txt = f"{s:.3f}".rstrip('0').rstrip('.')
    return f"{txt}s"

def write_summary_file():
    """Rewrite /tmp/laptimes.txt with a line per known device."""
    path = "/tmp/laptimes.txt"
    tmp_path = path + ".tmp"
    # Gather all device IDs we know about
    device_ids = set(lap_counts_by_device.keys()) | set(best_lap_by_device.keys())
    lines = []
    for dev in sorted(device_ids):
        laps = lap_counts_by_device.get(dev, 0)
        best_ms = best_lap_by_device.get(dev)
        best_str = _format_secs_from_ms(best_ms)
        # Use rider name if known, otherwise use "Device X"
        display_name = RIDER_NAMES.get(dev, f"Device {dev}")
        lines.append(f"{display_name}: {laps} laps Best: {best_str}")
    # Ensure directory exists (it will for /tmp), then atomic replace
    with open(tmp_path, "w") as f:
        f.write("\n".join(lines) + ("\n" if lines else ""))
    os.replace(tmp_path, path)

def handle_event(raw_bytes: bytes):
    wall_ts = dt.datetime.now().isoformat(timespec="milliseconds")
    parsed = parse_frame(raw_bytes)
    if not parsed:
        print(json.dumps({"timestamp": wall_ts, "type": "raw",
                          "hex": binascii.hexlify(raw_bytes).decode()}), flush=True)
        return

    dev = parsed["deviceId"]
    now_ns = time.monotonic_ns()
    lap_ms = None

    # Lap time = time since we last saw THIS device (monotonic)
    if dev in last_seen_ns:
        delta_ms = (now_ns - last_seen_ns[dev]) // 1_000_000
        # Basic sanity: ignore negative/zero or absurdly large gaps (> 20 minutes)
        if 1 <= delta_ms <= 20 * 60 * 1000:
            lap_ms = int(delta_ms)
            # Track laps list
            laps_list = lap_times_by_device.setdefault(dev, [])
            laps_list.append(lap_ms)
            # Increment lap count
            lap_counts_by_device[dev] = lap_counts_by_device.get(dev, 0) + 1
            # Update best lap
            prev_best = best_lap_by_device.get(dev)
            if prev_best is None or lap_ms < prev_best:
                best_lap_by_device[dev] = lap_ms
            # Write the full summary file after each counted lap
            write_summary_file()

    last_seen_ns[dev] = now_ns

    # Average lap per device
    avg_lap_ms = None
    if lap_times_by_device.get(dev):
        avg_lap_ms = sum(lap_times_by_device[dev]) // len(lap_times_by_device[dev])

    out = {
        "timestamp": wall_ts,
        "deviceId": dev,
        "lapNumber": parsed["lapNumber"],
        "cumulativeSeconds": parsed["cumulativeSeconds"],  # kept for reference/debug
        "lapTimeMs": lap_ms,                                # based on local monotonic delta
        "averageLapTimeMs": avg_lap_ms,
        "aux": parsed["aux"],
        "raw": binascii.hexlify(raw_bytes).decode()
    }
    # 1) JSON line
    #print(json.dumps(out, separators=(",", ":")), flush=True)
    # 2) Human-readable
    display_name = RIDER_NAMES.get(dev, f"Device {dev}")
    human_readable = (
        f"{display_name} | Lap {parsed['lapNumber']} | "
        f"Lap Time {format_ms(lap_ms)} | "
        f"CumulativeField {parsed['cumulativeSeconds']}s | "
        f"Avg Lap {format_ms(avg_lap_ms)}"
    )
    print(human_readable, flush=True)
    
    # 3) Append to laplogs.txt with timestamp
    script_dir = os.path.dirname(os.path.abspath(__file__))
    log_path = os.path.join(script_dir, "laplogs.txt")
    with open(log_path, "a") as f:
        f.write(f"{wall_ts} {human_readable}\n")

def notify_cb(_, data: bytearray):
    try:
        handle_event(data)
    except Exception as e:
        print(json.dumps({"error": str(e)}), flush=True)

async def main():
    print("Scanning for LapMonitor device (name starts with 'LapMfd')...", flush=True)
    while True:
        try:
            devices = await BleakScanner.discover()
            for dev in devices:
                if (dev.name or "").startswith("LapMfd"):
                    print(f"Found {dev.name}; attempting to connect...", flush=True)
                    async with BleakClient(dev, timeout=10.0) as client:
                        await client.connect()
                        print("Connected; hijacking lapmonitor...", flush=True)
                        #services = await client.get_services()
                        services = client.services 
                        tx_char = None
                        for service in services:
                            for char in service.characteristics:
                                if "notify" in char.properties:
                                    tx_char = char.uuid
                                    break
                            if tx_char:
                                break
                        if not tx_char:
                            print("No notify characteristic found.")
                            return
                        await client.start_notify(tx_char, notify_cb)
                        print(f"Listening on {tx_char}... (Ctrl+C to quit)", flush=True)
                        while True:
                            await asyncio.sleep(1)
            print("No LapMfd device found; retrying in 2s...", flush=True)
            await asyncio.sleep(2)
        except Exception as e:
            print(f"Error: {e}. Retrying in 3s...", flush=True)
            await asyncio.sleep(3)

if __name__ == "__main__":
    asyncio.run(main())
