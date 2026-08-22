#!/usr/bin/env python3
"""Convert a Gowin .fs bitstream to the raw image that lives in flash at address 0.

A .fs file is ASCII: '//' comment lines, then data lines of '0'/'1', one character
per bit. The flash image is those bits packed 8 to a byte, MSB first. That is all
openFPGALoader does before writing, and it is why a 7 MB .fs becomes ~886 KB.

Cores on the SD card should be stored in this packed form: 8x smaller to read, and
the FPGA does not have to parse ASCII while rewriting its own boot flash.

    ./fs2bin.py core.fs core.bin
"""
import sys

def convert(src):
    bits = []
    for line in open(src, 'rb'):
        line = line.strip()
        if not line or line.startswith(b'//'):
            continue
        if set(line) - {ord('0'), ord('1')}:
            raise SystemExit(f"{src}: unexpected characters in a data line")
        bits.append(line)
    data = b''.join(bits)
    if len(data) % 8:
        raise SystemExit(f"{src}: {len(data)} bits is not a whole number of bytes")
    out = bytearray(len(data) // 8)
    for i in range(0, len(data), 8):
        b = 0
        for c in data[i:i+8]:
            b = (b << 1) | (c - ord('0'))
        out[i >> 3] = b
    return bytes(out)

if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    img = convert(sys.argv[1])
    open(sys.argv[2], 'wb').write(img)
    print(f"{len(img)} bytes ({len(img)/1024:.0f} KB)")
