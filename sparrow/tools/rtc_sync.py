#!/usr/bin/env python3
"""
One-shot DS3231 -> system clock sync.
Runs once on container start, logs the RTC time and result, then exits.
"""

import os
import logging
import smbus2
import subprocess
from datetime import datetime

# Configuration
LOG_DIR   = "/app/logs"
LOG_FILE  = os.path.join(LOG_DIR, "rtc_sync.log")

# Prefer Jetson I2C bus 7, fall back to Raspberry Pi bus 1
PREFERRED_I2C_BUSES = (7, 1)

DS3231_ADDR = 0x68  # DS3231 I2C address

# Logger Setup
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[logging.FileHandler(LOG_FILE)],
)
logger = logging.getLogger(__name__)

def _open_i2c_bus(preferred_buses=PREFERRED_I2C_BUSES):
    """Try opening I2C buses in order; return SMBus or None."""
    last_err = None
    for bus_id in preferred_buses:
        try:
            bus = smbus2.SMBus(bus_id)
            logger.info(f"Opened I2C bus {bus_id}")
            return bus
        except Exception as e:
            last_err = e
            logger.debug(f"Failed to open I2C bus {bus_id}: {e}")
    logger.error(f"No usable I2C bus found {preferred_buses}: {last_err}")
    return None

def _bcd_to_int(b: int) -> int:
    """Convert a BCD-encoded byte to int."""
    return ((b >> 4) * 10) + (b & 0x0F)

def _read_rtc_datetime(bus) -> datetime:
    """
    Read date/time from DS3231 and return a timezone-agnostic UTC datetime.
    Registers 0x00..0x06: sec, min, hour, wday, day, month, year(00..99).
    """
    data = bus.read_i2c_block_data(DS3231_ADDR, 0x00, 7)
    sec    = _bcd_to_int(data[0] & 0x7F)
    minute = _bcd_to_int(data[1] & 0x7F)
    hour   = _bcd_to_int(data[2] & 0x3F)  # 24h
    day    = _bcd_to_int(data[4] & 0x3F)
    month  = _bcd_to_int(data[5] & 0x1F)
    year   = 2000 + _bcd_to_int(data[6])
    return datetime(year, month, day, hour, minute, sec)

def _set_system_time_utc(dt: datetime) -> None:
    """
    Set the container's system clock (UTC) from a datetime.
    Uses `date -u -s` so no timezone offset is applied here.
    """
    ts = dt.strftime("%Y-%m-%d %H:%M:%S")
    subprocess.run(["date", "-u", "-s", ts], check=True)

# Main
def main() -> int:
    bus = _open_i2c_bus()
    if bus is None:
        logger.error("I2C bus not available; skipping RTC sync.")
        return 0

    try:
        rtc_dt = _read_rtc_datetime(bus)
        logger.info(f"RTC time (DS3231 @0x{DS3231_ADDR:02X}): {rtc_dt.isoformat()}Z")
        _set_system_time_utc(rtc_dt)
        logger.info("System clock updated from RTC (UTC).")
    except Exception as e:
        logger.error(f"RTC sync failed: {e}")
    finally:
        try:
            bus.close()
        except Exception:
            pass

    return 0

if __name__ == "__main__":
    raise SystemExit(main())
