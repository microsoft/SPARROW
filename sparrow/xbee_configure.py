#!/usr/bin/env python3
import argparse
import time
import sys
import serial

DEFAULT_PROBE_BAUDS = [115200, 9600, 57600, 19200, 38400, 230400]

def read_until(ser: serial.Serial, timeout_s: float = 1.5) -> str:
    """Read whatever arrives until timeout."""
    end = time.time() + timeout_s
    buf = bytearray()
    while time.time() < end:
        chunk = ser.read(ser.in_waiting or 1)
        if chunk:
            buf.extend(chunk)
            # small wait to allow response completion
            time.sleep(0.05)
        else:
            time.sleep(0.02)
    try:
        return buf.decode(errors="replace")
    except Exception:
        return repr(buf)

def write_line(ser: serial.Serial, s: str):
    ser.write((s + "\r").encode("ascii"))
    ser.flush()

def enter_command_mode(ser: serial.Serial) -> bool:
    """
    Enter AT command mode: 1s silence, '+++', 1s silence.
    Must NOT send Enter after +++.
    """
    ser.reset_input_buffer()
    ser.reset_output_buffer()

    time.sleep(1.1)
    ser.write(b"+++")
    ser.flush()
    time.sleep(1.1)

    resp = read_until(ser, 1.5)
    return "OK" in resp

def at(ser: serial.Serial, cmd: str, expect_ok: bool = True) -> str:
    """
    Send an AT command (without the leading 'AT') and return response text.
    Example cmd: 'AP1' or 'BD7' or 'NIROBIN'
    """
    ser.reset_input_buffer()
    write_line(ser, "AT" + cmd)
    resp = read_until(ser, 1.5).strip()
    if expect_ok and ("OK" not in resp) and ("ERROR" in resp or resp == ""):
        raise RuntimeError(f"AT{cmd} failed, response: {resp!r}")
    return resp

def configure_xbee(
    port: str,
    probe_bauds,
    final_baud: int,
    api_mode: int,
    rf_rate: int,
    router_mode: int,
    network_id_hex: str | None,
    node_id: str | None,
):
    # 1) Probe to find current baud that allows +++
    ser = None
    working_baud = None
    for b in probe_bauds:
        try:
            ser = serial.Serial(port, b, timeout=0.1)
            if enter_command_mode(ser):
                working_baud = b
                break
            ser.close()
        except Exception:
            try:
                if ser:
                    ser.close()
            except Exception:
                pass
            ser = None

    if working_baud is None or ser is None:
        raise RuntimeError(
            f"Could not enter command mode on {port} using bauds {probe_bauds}. "
            "Check wiring/power, or confirm the XBee is not already in API-only mode with config pin forcing."
        )

    print(f"[OK] Entered command mode on {port} @ {working_baud} baud")

    # 2) Apply settings (queued + write)
    # API mode: AP=1 (no escapes) is typically best unless you need escaped control chars.
    print(f"Setting AP={api_mode} (API mode) ...")
    at(ser, f"AP{api_mode}")

    # Routing: CE=0 Standard router (routes packets)
    print(f"Setting CE={router_mode} (routing/messaging mode) ...")
    at(ser, f"CE{router_mode}")

    # RF data rate: BR=1 for 80kbps (all nodes must match)
    print(f"Setting BR={rf_rate} (RF data rate) ...")
    at(ser, f"BR{rf_rate}")

    # Optional Network ID (hex). Example: 1234
    if network_id_hex:
        nid = network_id_hex.lower().replace("0x", "")
        if not all(c in "0123456789abcdef" for c in nid) or len(nid) > 8:
            raise ValueError("network_id must be hex up to 32-bit, e.g. 0x1234 or 1234")
        print(f"Setting ID=0x{nid} (Network ID) ...")
        at(ser, f"ID{nid}")

    # Optional node identifier (NI) (ASCII)
    if node_id:
        # NI cannot start with space per Digi docs; keep it simple.
        safe = node_id.strip()
        if not safe:
            raise ValueError("node_id cannot be empty/whitespace")
        print(f"Setting NI={safe} (Node Identifier) ...")
        at(ser, f"NI{safe}", expect_ok=True)

    # Set UART baud (BD). Use standard numeric mapping if possible.
    # Common: 7=115200, 8=230400 (per Digi SX 868 guide).
    bd_map = {1200:0, 2400:1, 4800:2, 9600:3, 19200:4, 38400:5, 57600:6, 115200:7, 230400:8}
    if final_baud in bd_map:
        bd_val = bd_map[final_baud]
        print(f"Setting BD={bd_val} (UART baud {final_baud}) ...")
        at(ser, f"BD{bd_val}")
    else:
        # Non-standard: send as hex of baud * 256? Digi supports “non-standard BD”
        # We avoid that here; keep to standard table for reliability.
        raise ValueError(f"final_baud must be one of {sorted(bd_map.keys())}")

    # Write settings to flash and apply
    print("Writing to flash (WR) ...")
    at(ser, "WR")
    print("Applying changes (AC) ...")
    at(ser, "AC")

    # Exit command mode
    print("Exiting command mode (CN) ...")
    at(ser, "CN", expect_ok=False)

    ser.close()

    # 3) Re-open at final baud just to confirm we can still talk (enter cmd mode again)
    ser2 = serial.Serial(port, final_baud, timeout=0.1)
    ok = enter_command_mode(ser2)
    if not ok:
        print(f"[WARN] Re-opened at {final_baud} but couldn't re-enter command mode. "
              "This can happen if timing is off; API mode may still be set correctly.")
    else:
        # Read back key params
        ap = at(ser2, "AP", expect_ok=False)
        br = at(ser2, "BR", expect_ok=False)
        ce = at(ser2, "CE", expect_ok=False)
        bd = at(ser2, "BD", expect_ok=False)
        print(f"[VERIFY] AP={ap.strip()} BR={br.strip()} CE={ce.strip()} BD={bd.strip()}")
        at(ser2, "CN", expect_ok=False)
    ser2.close()

def main():
    p = argparse.ArgumentParser(description="Configure Digi XBee 868 over USB serial (AT command mode).")
    p.add_argument("--port", default="/dev/ttyUSB0", help="Serial port (default: /dev/ttyUSB0)")
    p.add_argument("--probe-baud", action="append", type=int,
                   help="Add a baud to probe list (can repeat). Default probes common bauds.")
    p.add_argument("--baud", type=int, default=115200, help="Final UART baud (115200 or 230400 recommended).")
    p.add_argument("--api", type=int, default=1, choices=[0,1,2],
                   help="AP API mode: 0=Transparent, 1=API no-escapes, 2=API escaped")
    p.add_argument("--rf", type=int, default=1, choices=[0,1],
                   help="BR RF rate: 0=10kbps, 1=80kbps (fast)")
    p.add_argument("--router", type=int, default=0, choices=[0,1,2,3,4,6],
                   help="CE routing/messaging mode (0=standard router)")
    p.add_argument("--netid", default=None, help="Network ID (hex), e.g. 1234 or 0x1234")
    p.add_argument("--node", default=None, help="Node identifier (NI), e.g. SPARROW_GATEWAY")
    args = p.parse_args()

    probe = args.probe_baud[:] if args.probe_baud else DEFAULT_PROBE_BAUDS

    configure_xbee(
        port=args.port,
        probe_bauds=probe,
        final_baud=args.baud,
        api_mode=args.api,
        rf_rate=args.rf,
        router_mode=args.router,
        network_id_hex=args.netid,
        node_id=args.node,
    )
    print("[DONE] Configuration complete.")

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"[ERROR] {e}")
        sys.exit(2)
