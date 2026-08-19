#!/usr/bin/env python3
"""Convert a MiSTer .pf font into BDF, optionally adding block glyphs.

The OSD is a 16x8 character grid of 8x8 cells (see osd_u8g2.v), so a fixed
8x8 font sits exactly on it, unlike the proportional face FPGA-Companion
ships with. MiSTer's .pf fonts are 8 bytes per glyph, one bit per pixel, MSB
left, indexed from ASCII 0x20.

BDF is the input bdfconv wants, so the full path to a usable font is:

    ./pf2bdf.py Some_Font.pf out.bdf --blocks
    bdfconv -f 1 -m '32-127,176-179' -n msxnano_font -o msxnano_font.c out.bdf

then point FPGA-Companion's u8g2_SetFont at it and rebuild its firmware.

No font is checked in here. Fonts_MiSTer carries no licence and its files are
traced from arcade and home-computer character ROMs, so supply your own the
same way the BIOS pack is supplied -- this script only converts what you
already have.

Note that MiSTer's fonts already carry a SOLID BLOCK at ASCII 0x7F (a 7x7
filled cell -- it is what draws the loading bar in their OSD screenshots).
0x7F is a legal XML character and a single byte, so it can go straight into a
menu label with no font extension and no UTF-8 handling at all.

--blocks appends what 0x7F does not give you: a hollow square for the empty
half of a bar, plus shading steps, at the CP437-ish codepoints 0xB0-0xB3.
"""
import sys

CELL = 8
BASE = 0x20            # .pf glyph 0 is ASCII 0x20

BLOCKS = {
    # hollow square: the empty segment of a bar, matching the 7x7 metrics of
    # the solid block MiSTer fonts already have at 0x7F
    0xB0: [0xFE, 0x82, 0x82, 0x82, 0x82, 0x82, 0xFE, 0x00],
    0xB1: [0xAA, 0x55] * 4,                      # medium shade
    0xB2: [0xFF, 0x55, 0xFF, 0xAA] * 2,          # dark shade
    0xB3: [0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0x00],  # solid, 7x7
}


def read_pf(path):
    data = open(path, 'rb').read()
    if len(data) % CELL:
        sys.exit(f"{path}: {len(data)} bytes is not a multiple of {CELL}")
    return {BASE + i: list(data[i * CELL:(i + 1) * CELL])
            for i in range(len(data) // CELL)}


def write_bdf(glyphs, out, name):
    codes = sorted(glyphs)
    w = out.write
    w(f"STARTFONT 2.1\nFONT {name}\nSIZE 8 75 75\n")
    w("FONTBOUNDINGBOX 8 8 0 -1\nSTARTPROPERTIES 2\n")
    w("FONT_ASCENT 7\nFONT_DESCENT 1\nENDPROPERTIES\n")
    w(f"CHARS {len(codes)}\n")
    for c in codes:
        w(f"STARTCHAR U+{c:04X}\nENCODING {c}\n")
        w("SWIDTH 500 0\nDWIDTH 8 0\nBBX 8 8 0 -1\nBITMAP\n")
        for row in glyphs[c]:
            w(f"{row:02X}\n")
        w("ENDCHAR\n")
    w("ENDFONT\n")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    glyphs = read_pf(src)

    if '--blocks' in sys.argv:
        overlap = set(glyphs) & set(BLOCKS)
        if overlap:
            sys.exit(f"refusing to overwrite existing glyphs: "
                     f"{[hex(c) for c in sorted(overlap)]}")
        glyphs.update(BLOCKS)

    with open(dst, 'w') as f:
        write_bdf(glyphs, f, 'msxnano')

    lo, hi = min(glyphs), max(glyphs)
    print(f"{dst}: {len(glyphs)} glyphs, 0x{lo:02X}-0x{hi:02X}")
    if '--blocks' in sys.argv:
        print("blocks at 0xB0 light, 0xB1 medium, 0xB2 dark, 0xB3 solid")


if __name__ == '__main__':
    main()
