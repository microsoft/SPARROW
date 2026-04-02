#!/usr/bin/env python3
"""
xbee_master_collect.py (round-robin fairness + rotating logs)

DigiMesh "master" node:

Receives:
  * RD (ready):  "RD" + session_id(4) + file_size(4) + name_len(1) + name(...)
  * RB (chunk):  "RB"(2) + session_id(4) + total_chunks(2) + chunk_index(2) + flags(1)
                if first: file_size(4) + name_len(1) + name(name_len)
                payload(...)

Sends (unicast back to the device):
  * GO: "GO" + session_id(4)             (permission to start sending that session)
  * OK: "OK" + session_id(4) + crc32(4)  (transfer complete + integrity)

Upgrades:
- Sessions keyed by (src64, session_id) so devices can't collide
- ONE device permitted at a time (reliable scaling)
- Round-robin fairness across devices (no noisy device can dominate)
- Per-device backlog cap (configurable)
- Rotating log file + console output

Round-robin behavior:
- Each device has its own queue of pending sessions.
- Master grants GO to devices in a rotating order (one session per turn).
"""

import os
import time
import struct
import argparse
import binascii
import serial
import logging
from logging.handlers import RotatingFileHandler
from collections import deque

START_DELIM = 0x7E


# -------------------- Logging --------------------

def setup_logger(log_path: str, max_bytes: int, backup_count: int, console: bool, level: str) -> logging.Logger:
    logger = logging.getLogger("xbee_master")
    logger.setLevel(getattr(logging, level.upper(), logging.INFO))
    logger.propagate = False

    fmt = logging.Formatter("%(asctime)s %(levelname)s %(message)s")

    # Avoid duplicate handlers if reloaded
    if not logger.handlers:
        os.makedirs(os.path.dirname(log_path), exist_ok=True)

        fh = RotatingFileHandler(log_path, maxBytes=max_bytes, backupCount=backup_count)
        fh.setFormatter(fmt)
        fh.setLevel(logger.level)
        logger.addHandler(fh)

        if console:
            ch = logging.StreamHandler()
            ch.setFormatter(fmt)
            ch.setLevel(logger.level)
            logger.addHandler(ch)

    return logger


# -------------------- XBee framing --------------------

def read_exact(ser: serial.Serial, n: int) -> bytes | None:
    buf = bytearray()
    while len(buf) < n:
        chunk = ser.read(n - len(buf))
        if not chunk:
            return None
        buf.extend(chunk)
    return bytes(buf)


def read_api_frame(ser: serial.Serial) -> bytes | None:
    """Read one full valid XBee API frame and return its frame_data."""
    while True:
        b = ser.read(1)
        if not b:
            return None
        if b[0] != START_DELIM:
            continue
        ln = read_exact(ser, 2)
        if not ln:
            continue
        length = struct.unpack(">H", ln)[0]
        data = read_exact(ser, length)
        if not data:
            continue
        cks = read_exact(ser, 1)
        if not cks:
            continue
        if ((sum(data) + cks[0]) & 0xFF) != 0xFF:
            continue
        return data


def xbee_checksum(frame_data: bytes) -> int:
    return (0xFF - (sum(frame_data) & 0xFF)) & 0xFF


def build_api_frame(frame_data: bytes) -> bytes:
    length = len(frame_data)
    return bytes([START_DELIM]) + struct.pack(">H", length) + frame_data + bytes([xbee_checksum(frame_data)])


def build_tx_request_0x10(frame_id: int, dest64_int: int, rf_data: bytes) -> bytes:
    """
    0x10 Transmit Request (DigiMesh / XBee API)
    """
    frame_type = 0x10
    dest16 = 0xFFFE
    broadcast_radius = 0x00
    options = 0x00
    frame = struct.pack(">BBQHBB", frame_type, frame_id, dest64_int, dest16, broadcast_radius, options) + rf_data
    return build_api_frame(frame)


def src64_bytes_to_int(src64_b: bytes) -> int:
    return int.from_bytes(src64_b, "big", signed=False)


def fmt64(x: int) -> str:
    return f"{x:016X}"


# -------------------- Main --------------------

def main():
    ap = argparse.ArgumentParser(description="DigiMesh master: round-robin scheduling + rotating logs.")
    ap.add_argument("--port", required=True, help="Serial port (Windows COMx, Linux /dev/ttyUSB0)")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--out", default="received_images", help="Output directory")
    ap.add_argument("--session-timeout", type=float, default=30.0, help="Seconds before abandoning a stalled session")
    ap.add_argument("--ready-ttl", type=float, default=300.0, help="Seconds before dropping a stale RD/session")
    ap.add_argument("--max-devices", type=int, default=500, help="Safety cap for number of tracked devices")
    ap.add_argument("--per-device-cap", type=int, default=2, help="Max pending sessions kept per device")
    ap.add_argument("--coalesce-latest", action="store_true",
                    help="If set, keep ONLY the latest RD per device (drops older pending for that device)")

    # Logging options
    ap.add_argument("--log", default="logs/xbee_master.log", help="Log file path (rotating)")
    ap.add_argument("--log-bytes", type=int, default=5_000_000, help="Rotate after N bytes (default 5MB)")
    ap.add_argument("--log-backups", type=int, default=5, help="How many rotated logs to keep")
    ap.add_argument("--no-console", action="store_true", help="Disable console logging")
    ap.add_argument("--log-level", default="INFO", help="DEBUG, INFO, WARNING, ERROR")

    args = ap.parse_args()

    logger = setup_logger(
        log_path=args.log,
        max_bytes=args.log_bytes,
        backup_count=args.log_backups,
        console=(not args.no_console),
        level=args.log_level,
    )

    os.makedirs(args.out, exist_ok=True)

    ser = serial.Serial(args.port, args.baud, timeout=0.2)

    # Round-robin scheduling structures
    # dev_queues[src64] = deque of items: {"sid":int,"t_ready":float,"meta":{...}}
    dev_queues: dict[int, deque] = {}
    # rr = deque of src64 that currently have pending items
    rr = deque()
    # membership set to avoid duplicates in rr
    rr_set = set()

    # Active transfer: dict or None
    active = None

    # Reassembly store: (src64_int, session_id) -> state
    sessions: dict[tuple[int, int], dict] = {}

    frame_id = 1

    def next_frame_id(cur: int) -> int:
        return (cur % 255) + 1

    def send_to(src64_int: int, rf: bytes):
        nonlocal frame_id
        tx = build_tx_request_0x10(frame_id, src64_int, rf)
        ser.write(tx)
        ser.flush()
        frame_id = next_frame_id(frame_id)

    def _ensure_device(src64_int: int):
        if src64_int not in dev_queues:
            if len(dev_queues) >= args.max_devices:
                # Hard safety: refuse to track infinite devices
                return False
            dev_queues[src64_int] = deque()
        return True

    def enqueue_ready(src64_int: int, sid: int, meta: dict):
        """Add a pending session for a device with fairness + caps."""
        if not _ensure_device(src64_int):
            logger.warning("RD drop: max-devices reached; dev=%s sid=%08x", fmt64(src64_int), sid)
            return

        q = dev_queues[src64_int]
        t_now = time.time()

        # Drop duplicates (same sid already queued)
        for it in q:
            if it["sid"] == sid:
                # refresh timestamp/meta
                it["t_ready"] = t_now
                it["meta"] = meta
                break
        else:
            if args.coalesce_latest:
                q.clear()
            # Enforce per-device cap: keep newest items, drop oldest
            if args.per_device_cap > 0:
                while len(q) >= args.per_device_cap:
                    dropped = q.popleft()
                    logger.info("RD cap-drop: dev=%s drop sid=%08x (cap=%d)", fmt64(src64_int), dropped["sid"], args.per_device_cap)
            q.append({"sid": sid, "t_ready": t_now, "meta": meta})

        # Put device into rr if it has items and isn't already there
        if q and (src64_int not in rr_set):
            rr.append(src64_int)
            rr_set.add(src64_int)

        logger.info(
            "RD <- dev=%s sid=%08x name='%s' size=%s dev_q=%d rr=%d",
            fmt64(src64_int),
            sid,
            meta.get("name", ""),
            meta.get("size", None),
            len(q),
            len(rr),
        )

    def pop_next_rr():
        """Round-robin select next (dev,sid,meta). Also drops stale items."""
        t_now = time.time()

        while rr:
            src64_int = rr.popleft()
            rr_set.discard(src64_int)

            q = dev_queues.get(src64_int)
            if not q:
                continue

            # Drop stale items at head until a valid one exists
            while q and (t_now - q[0]["t_ready"]) > args.ready_ttl:
                stale = q.popleft()
                logger.info("RD stale-drop: dev=%s sid=%08x age=%.1fs", fmt64(src64_int), stale["sid"], (t_now - stale["t_ready"]))

            if not q:
                continue

            item = q.popleft()
            sid = item["sid"]
            meta = item["meta"]

            # If still has pending after taking one, re-add device to end of rr
            if q:
                rr.append(src64_int)
                rr_set.add(src64_int)

            return src64_int, sid, meta

        return None

    def requeue_active_as_ready():
        """If active timed out, requeue the same (dev,sid,meta) to try later."""
        nonlocal active
        if not active:
            return
        enqueue_ready(active["src64"], active["sid"], active.get("meta", {}))
        active = None

    logger.info("MASTER start port=%s baud=%d out=%s", args.port, args.baud, os.path.abspath(args.out))
    logger.info("Fairness: per-device-cap=%d coalesce-latest=%s ready-ttl=%.1fs",
                args.per_device_cap, args.coalesce_latest, args.ready_ttl)

    try:
        while True:
            # If nothing active, permit next device in RR order
            if active is None:
                nxt = pop_next_rr()
                if nxt:
                    src64_int, sid, meta = nxt
                    active = {"src64": src64_int, "sid": sid, "t_go": time.time(), "t_last": time.time(), "meta": meta}
                    send_to(src64_int, b"GO" + struct.pack(">I", sid))
                    logger.info("GO -> dev=%s sid=%08x name='%s' size=%s rr=%d dev_q=%d",
                                fmt64(src64_int), sid, meta.get("name", ""), meta.get("size", None),
                                len(rr), len(dev_queues.get(src64_int, ())))
                # else: idle until frames arrive

            # Cleanup stalled reassembly sessions (memory protection)
            t_now = time.time()
            for key, st in list(sessions.items()):
                if (t_now - st.get("t_last", st["t0"])) > args.session_timeout:
                    d, sid = key
                    logger.warning("DROP stalled session dev=%s sid=%08x", fmt64(d), sid)
                    sessions.pop(key, None)

            # If active but no progress, time out and move on (requeue)
            if active is not None and (t_now - active["t_last"]) > args.session_timeout:
                logger.warning("TIMEOUT active dev=%s sid=%08x (requeue)", fmt64(active["src64"]), active["sid"])
                requeue_active_as_ready()

            frame = read_api_frame(ser)
            if not frame:
                continue

            # Expect 0x90 Receive Packet
            if frame[0] != 0x90 or len(frame) < 12:
                continue

            src64_int = src64_bytes_to_int(frame[1:9])
            rf = frame[12:]
            if len(rf) < 2:
                continue

            # --- RD: ready announcement ---
            if rf.startswith(b"RD"):
                # RD + sid(4) + size(4) + name_len(1) + name
                if len(rf) < (2 + 4 + 4 + 1):
                    continue
                sid = struct.unpack(">I", rf[2:6])[0]
                size = struct.unpack(">I", rf[6:10])[0]
                name_len = rf[10]
                if len(rf) < 11 + name_len:
                    continue
                name = rf[11:11 + name_len].decode("utf-8", errors="replace")
                meta = {"name": name, "size": size}
                enqueue_ready(src64_int, sid, meta)
                continue

            # --- RB: image chunk ---
            if not rf.startswith(b"RB"):
                continue

            # Strict gating: only accept from active device/session
            if active is None:
                continue
            if src64_int != active["src64"]:
                continue

            if len(rf) < (2 + 4 + 2 + 2 + 1):
                continue

            sid = struct.unpack(">I", rf[2:6])[0]
            if sid != active["sid"]:
                continue

            total_chunks = struct.unpack(">H", rf[6:8])[0]
            chunk_index = struct.unpack(">H", rf[8:10])[0]
            flags = rf[10]
            is_first = (flags & 0x01) != 0

            pos = 11
            key = (src64_int, sid)

            if key not in sessions:
                sessions[key] = {
                    "total": total_chunks,
                    "chunks": {},
                    "name": None,
                    "size": None,
                    "t0": time.time(),
                    "t_last": time.time(),
                }
                logger.info("RX start dev=%s sid=%08x total_chunks=%d", fmt64(src64_int), sid, total_chunks)

            st = sessions[key]
            st["t_last"] = time.time()
            active["t_last"] = time.time()
            st["total"] = total_chunks

            if is_first:
                if len(rf) < pos + 4 + 1:
                    continue
                size = struct.unpack(">I", rf[pos:pos + 4])[0]
                pos += 4
                name_len = rf[pos]
                pos += 1
                if len(rf) < pos + name_len:
                    continue
                name = rf[pos:pos + name_len].decode("utf-8", errors="replace")
                pos += name_len
                st["name"] = name
                st["size"] = size
                logger.info("RX meta dev=%s sid=%08x name='%s' size=%d", fmt64(src64_int), sid, name, size)

            payload = rf[pos:]
            st["chunks"][chunk_index] = payload

            got = len(st["chunks"])
            if got % 50 == 0 or got == total_chunks:
                logger.info("RX prog dev=%s sid=%08x chunks=%d/%d", fmt64(src64_int), sid, got, total_chunks)

            if got == total_chunks and st["name"] and st["size"] is not None:
                # Reassemble
                data = bytearray()
                for i in range(total_chunks):
                    part = st["chunks"].get(i)
                    if part is None:
                        data = None
                        break
                    data.extend(part)

                if data is None:
                    logger.warning("RX reassemble missing chunk dev=%s sid=%08x (unexpected)", fmt64(src64_int), sid)
                    continue

                data = data[:st["size"]]
                crc32 = binascii.crc32(data) & 0xFFFFFFFF

                out_name = f"{fmt64(src64_int)}_{sid:08x}_{os.path.basename(st['name'])}"
                out_path = os.path.join(args.out, out_name)
                with open(out_path, "wb") as f:
                    f.write(data)

                dt = time.time() - st["t0"]
                kbps = (len(data) * 8) / (dt * 1000) if dt > 0 else 0.0
                logger.info(
                    "SAVED path=%s dev=%s sid=%08x bytes=%d time=%.1fs rate=%.1fkbps crc32=%08x",
                    out_path, fmt64(src64_int), sid, len(data), dt, kbps, crc32
                )

                # Tell sender we're done (OK + crc32)
                send_to(src64_int, b"OK" + struct.pack(">I", sid) + struct.pack(">I", crc32))
                logger.info("OK -> dev=%s sid=%08x crc32=%08x", fmt64(src64_int), sid, crc32)

                # Cleanup session and clear active to schedule next device
                sessions.pop(key, None)
                active = None

    except KeyboardInterrupt:
        logger.info("MASTER exiting (KeyboardInterrupt).")
    finally:
        try:
            ser.close()
        except Exception:
            pass


if __name__ == "__main__":
    main()