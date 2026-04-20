#!/usr/bin/env python3
"""
xbee_master_collect.py

Hardening:
- Serial open retry loop
- Serial read/write recovery loop
- Preserves pending RD queues across reconnects
- Clears active transfer and partial reassembly on reconnect

Startup logging:
- Reads and logs local XBee NI / SH / SL / 64-bit address at startup
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

    if not logger.handlers:
        log_dir = os.path.dirname(log_path)
        if log_dir:
            os.makedirs(log_dir, exist_ok=True)

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
    frame_type = 0x10
    dest16 = 0xFFFE
    broadcast_radius = 0x00
    options = 0x00
    frame = struct.pack(">BBQHBB", frame_type, frame_id, dest64_int, dest16, broadcast_radius, options) + rf_data
    return build_api_frame(frame)


def build_at_command_0x08(frame_id: int, at_cmd: str, parameter: bytes = b"") -> bytes:
    frame_type = 0x08
    frame = struct.pack(">BB2s", frame_type, frame_id, at_cmd.encode("ascii")) + parameter
    return build_api_frame(frame)


def src64_bytes_to_int(src64_b: bytes) -> int:
    return int.from_bytes(src64_b, "big", signed=False)


def fmt64(x: int) -> str:
    return f"{x:016X}"


def open_serial_forever(port: str, baud: int, logger: logging.Logger, timeout: float = 0.2) -> serial.Serial:
    while True:
        try:
            ser = serial.Serial(port, baud, timeout=timeout)
            logger.info("SERIAL open ok port=%s baud=%d timeout=%.1f", port, baud, timeout)
            return ser
        except (serial.SerialException, OSError) as e:
            logger.error("SERIAL open failed port=%s err=%s; retrying in 2s", port, e)
            time.sleep(2)


def xbee_local_at(ser: serial.Serial, at_cmd: str, logger: logging.Logger, timeout_s: float = 2.0) -> bytes | None:
    """
    Send a local AT command (0x08) and wait for AT Command Response (0x88).
    Returns parameter bytes on success, or None.
    """
    frame_id = 0x52
    ser.write(build_at_command_0x08(frame_id, at_cmd))
    ser.flush()

    deadline = time.time() + timeout_s
    while time.time() < deadline:
        frame = read_api_frame(ser)
        if not frame:
            continue
        if frame[0] != 0x88 or len(frame) < 5:
            continue
        if frame[1] != frame_id:
            continue
        if frame[2:4] != at_cmd.encode("ascii"):
            continue

        status = frame[4]
        if status != 0x00:
            logger.warning("AT %s failed status=0x%02X", at_cmd, status)
            return None
        return frame[5:]

    logger.warning("AT %s timed out", at_cmd)
    return None


# -------------------- Main --------------------

def main():
    ap = argparse.ArgumentParser(description="DigiMesh master with reconnecting serial.")
    ap.add_argument("--port", required=True, help="Serial port")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--out", default="received_images", help="Output directory")
    ap.add_argument("--session-timeout", type=float, default=30.0, help="Seconds before abandoning a stalled session")
    ap.add_argument("--ready-ttl", type=float, default=300.0, help="Seconds before dropping a stale RD/session")
    ap.add_argument("--max-devices", type=int, default=500, help="Safety cap for number of tracked devices")
    ap.add_argument("--per-device-cap", type=int, default=2, help="Max pending sessions kept per device")
    ap.add_argument("--coalesce-latest", action="store_true",
                    help="If set, keep ONLY the latest RD per device (drops older pending for that device)")

    ap.add_argument("--log", default="logs/xbee_master.log", help="Log file path (rotating)")
    ap.add_argument("--log-bytes", type=int, default=5_000_000, help="Rotate after N bytes")
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

    dev_queues: dict[int, deque] = {}
    rr = deque()
    rr_set = set()

    active = None
    sessions: dict[tuple[int, int], dict] = {}

    frame_id = 1
    ser = None
    master_id_logged = False

    def next_frame_id(cur: int) -> int:
        return (cur % 255) + 1

    def send_to(src64_int: int, rf: bytes):
        nonlocal frame_id, ser
        tx = build_tx_request_0x10(frame_id, src64_int, rf)
        ser.write(tx)
        ser.flush()
        frame_id = next_frame_id(frame_id)

    def reset_link_state(reason: str):
        nonlocal active, sessions, master_id_logged
        if active is not None or sessions:
            logger.warning(
                "LINK reset reason=%s clearing active=%s partial_sessions=%d",
                reason,
                "none" if active is None else f"{fmt64(active['src64'])}/{active['sid']:08x}",
                len(sessions),
            )
        active = None
        sessions.clear()
        master_id_logged = False

    def log_local_xbee_identity():
        nonlocal master_id_logged, ser
        if master_id_logged or ser is None:
            return

        try:
            ni_b = xbee_local_at(ser, "NI", logger)
            sh_b = xbee_local_at(ser, "SH", logger)
            sl_b = xbee_local_at(ser, "SL", logger)

            ni = ni_b.decode("utf-8", errors="replace") if ni_b else ""
            sh = int.from_bytes(sh_b, "big") if sh_b else None
            sl = int.from_bytes(sl_b, "big") if sl_b else None

            if sh is not None and sl is not None:
                addr64 = (sh << 32) | sl
                logger.info(
                    "MASTER identity NI='%s' addr64=%s SH=%08X SL=%08X",
                    ni, fmt64(addr64), sh, sl
                )
            else:
                logger.info("MASTER identity NI='%s' addr64=unknown", ni)

            master_id_logged = True
        except Exception:
            logger.exception("Failed to read local XBee identity")

    def _ensure_device(src64_int: int):
        if src64_int not in dev_queues:
            if len(dev_queues) >= args.max_devices:
                return False
            dev_queues[src64_int] = deque()
        return True

    def enqueue_ready(src64_int: int, sid: int, meta: dict):
        if not _ensure_device(src64_int):
            logger.warning("RD drop: max-devices reached; dev=%s sid=%08x", fmt64(src64_int), sid)
            return

        q = dev_queues[src64_int]
        t_now = time.time()

        for it in q:
            if it["sid"] == sid:
                it["t_ready"] = t_now
                it["meta"] = meta
                break
        else:
            if args.coalesce_latest:
                q.clear()

            if args.per_device_cap > 0:
                while len(q) >= args.per_device_cap:
                    dropped = q.popleft()
                    logger.info("RD cap-drop: dev=%s drop sid=%08x (cap=%d)", fmt64(src64_int), dropped["sid"], args.per_device_cap)

            q.append({"sid": sid, "t_ready": t_now, "meta": meta})

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
        t_now = time.time()

        while rr:
            src64_int = rr.popleft()
            rr_set.discard(src64_int)

            q = dev_queues.get(src64_int)
            if not q:
                continue

            while q and (t_now - q[0]["t_ready"]) > args.ready_ttl:
                stale = q.popleft()
                logger.info("RD stale-drop: dev=%s sid=%08x age=%.1fs", fmt64(src64_int), stale["sid"], (t_now - stale["t_ready"]))

            if not q:
                continue

            item = q.popleft()
            sid = item["sid"]
            meta = item["meta"]

            if q:
                rr.append(src64_int)
                rr_set.add(src64_int)

            return src64_int, sid, meta

        return None

    def requeue_active_as_ready():
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
            try:
                if ser is None or not ser.is_open:
                    ser = open_serial_forever(args.port, args.baud, logger, timeout=0.2)
                    reset_link_state("serial-open")
                    log_local_xbee_identity()

                if active is None:
                    nxt = pop_next_rr()
                    if nxt:
                        src64_int, sid, meta = nxt
                        active = {
                            "src64": src64_int,
                            "sid": sid,
                            "t_go": time.time(),
                            "t_last": time.time(),
                            "meta": meta,
                        }
                        send_to(src64_int, b"GO" + struct.pack(">I", sid))
                        logger.info(
                            "GO -> dev=%s sid=%08x name='%s' size=%s rr=%d dev_q=%d",
                            fmt64(src64_int), sid, meta.get("name", ""), meta.get("size", None),
                            len(rr), len(dev_queues.get(src64_int, ()))
                        )

                t_now = time.time()
                for key, st in list(sessions.items()):
                    if (t_now - st.get("t_last", st["t0"])) > args.session_timeout:
                        d, sid = key
                        logger.warning("DROP stalled session dev=%s sid=%08x", fmt64(d), sid)
                        sessions.pop(key, None)

                if active is not None and (t_now - active["t_last"]) > args.session_timeout:
                    logger.warning("TIMEOUT active dev=%s sid=%08x (requeue)", fmt64(active["src64"]), active["sid"])
                    requeue_active_as_ready()

                frame = read_api_frame(ser)
                if not frame:
                    continue

                logger.debug("RX raw frame type=0x%02X len=%d", frame[0], len(frame))

                if frame[0] != 0x90 or len(frame) < 12:
                    logger.debug("RX ignored frame type=0x%02X len=%d", frame[0], len(frame))
                    continue

                src64_int = src64_bytes_to_int(frame[1:9])
                rf = frame[12:]

                logger.debug(
                    "RX 0x90 from=%s rf=%r rf_hex=%s",
                    fmt64(src64_int),
                    rf,
                    rf.hex()
                )

                if len(rf) < 2:
                    continue

                if rf.startswith(b"SG?"):
                    logger.info("SG? <- dev=%s", fmt64(src64_int))
                    try:
                        send_to(src64_int, b"SG!")
                        logger.info("SG! -> dev=%s", fmt64(src64_int))
                    except Exception:
                        logger.exception("SG! send failed dev=%s", fmt64(src64_int))
                    continue

                if rf.startswith(b"RD"):
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

                if not rf.startswith(b"RB"):
                    continue

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

                if total_chunks == 0:
                    logger.warning("RX invalid total_chunks dev=%s sid=%08x total=0", fmt64(src64_int), sid)
                    continue

                if chunk_index >= total_chunks:
                    logger.warning(
                        "RX invalid chunk index dev=%s sid=%08x idx=%d total=%d",
                        fmt64(src64_int), sid, chunk_index, total_chunks
                    )
                    continue

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

                    send_to(src64_int, b"OK" + struct.pack(">I", sid) + struct.pack(">I", crc32))
                    logger.info("OK -> dev=%s sid=%08x crc32=%08x", fmt64(src64_int), sid, crc32)

                    sessions.pop(key, None)
                    active = None

            except (serial.SerialException, OSError) as e:
                logger.error("SERIAL fault err=%s; closing and reopening", e)
                try:
                    if ser is not None:
                        ser.close()
                except Exception:
                    pass
                ser = None
                reset_link_state("serial-fault")
                time.sleep(1)

            except Exception:
                logger.exception("Unhandled exception in main loop; resetting link state")
                try:
                    if ser is not None:
                        ser.close()
                except Exception:
                    pass
                ser = None
                reset_link_state("unhandled-exception")
                time.sleep(1)

    except KeyboardInterrupt:
        logger.info("MASTER exiting (KeyboardInterrupt).")
    finally:
        try:
            if ser is not None:
                ser.close()
        except Exception:
            pass


if __name__ == "__main__":
    main()
