#!/usr/bin/env python3
"""Validate the MT7916 EEPROM inside an HG5585F factory-1m.bin backup.

Layout (from the stock QWRT hotplug script / l1profile.dat):
  offset 0x1000, 4096 bytes, first two bytes 0x16 0x79.

Usage:
  python3 scripts/hg5585f/check-factory-eeprom.py 原厂备份-CT/factory-1m.bin

Exit code 0 = valid; 1 = invalid/missing. The file is per-device: never share
or reuse another device's factory-1m.bin.
"""
import hashlib
import sys

OFFSET = 0x1000
SIZE = 0x1000
MAGIC = b"\x16\x79"


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip())
        return 1
    path = sys.argv[1]
    try:
        with open(path, "rb") as fh:
            data = fh.read()
    except OSError as exc:
        print("ERROR: cannot read %s: %s" % (path, exc))
        return 1

    if len(data) < OFFSET + SIZE:
        print("ERROR: %s is too small (%d bytes; need >= %d)" % (path, len(data), OFFSET + SIZE))
        return 1

    eeprom = data[OFFSET:OFFSET + SIZE]
    magic = eeprom[:2]
    digest = hashlib.sha256(eeprom).hexdigest()
    print("file      : %s" % path)
    print("file size : %d bytes" % len(data))
    print("eeprom    : offset 0x%x, size %d bytes" % (OFFSET, SIZE))
    print("magic     : %s (expect 1679)" % magic.hex())
    print("sha256    : %s" % digest)

    if magic != MAGIC:
        print("RESULT: INVALID (magic mismatch)")
        return 1
    if eeprom == b"\xff" * SIZE:
        print("RESULT: INVALID (all 0xff)")
        return 1
    print("RESULT: OK (per-device calibration; do not share)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
