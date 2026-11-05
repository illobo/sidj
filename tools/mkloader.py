#!/usr/bin/env python3
"""mkloader: generated include for the SIDJ loader (src/loader/loader.asm).

usage: mkloader.py OUT.asm

Adapted from the author's raster demo (rasterbars/tools/mktables.py):
  rblock      the unrolled, cycle-exact raster bar loop (one colour per line
              to $d021 and $d020, CIA1 timer A + clockslide), lines FIRST to
              ENDLINE-1 in blocks of 8
  sine        bar positions inside the logo band (lines 56-130)
  freqlo/hi   SID note frequencies (PAL), MIDI note numbers
  logo        the SIDJ logo, 8 rows of ROM quadrant characters (2x2 pixels
              per character, so 16 pixel rows); no charset needed
  scrolltext  the one-line scroller, screen codes, 0 ends it
  byline      the credit row under the subtitle, with the version (VERSION file)

The quadrant screen codes were checked against the character ROM
(a character ROM dump); pass CHARGEN=path to check them again.
"""
import math, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERSION = open(os.path.join(ROOT, "VERSION")).read().strip().upper()
LOOP_ORG = 0x0900               # must match the * = before the include
SLIDE = 40                      # $c9 bytes per clockslide
BAD_SLOT = 4                    # (line & 7) == 4 follows a bad line (YSCROLL 3)
FIRST, ENDLINE = 56, 240        # must match loader.asm
BAND = (56, 130)                # bars stay in the logo band
BARLEN = 13
LOGO_COL = 5

# 2x2 pixel pattern (UL, UR, LL, LR) -> screen code, upper case / graphics set
QUAD = {(0, 0, 0, 0): 0x20, (1, 0, 1, 0): 0x61, (0, 0, 1, 1): 0x62, (0, 0, 0, 1): 0x6c,
        (0, 0, 1, 0): 0x7b, (0, 1, 0, 0): 0x7c, (1, 0, 0, 0): 0x7e, (1, 0, 0, 1): 0x7f,
        (1, 1, 1, 1): 0xa0, (0, 1, 0, 1): 0xe1, (1, 1, 0, 0): 0xe2, (1, 1, 1, 0): 0xec,
        (1, 1, 0, 1): 0xfb, (1, 0, 1, 1): 0xfc, (0, 1, 1, 1): 0xfe, (0, 1, 1, 0): 0xff}

# 14 x 16 pixels per letter (I: 4), strokes 4 pixels, 4 pixels between letters
S = ["..############", ".#############", "##############", "##############",
     "####..........", "####..........",
     "##############", "##############", "##############", "##############",
     "..........####", "..........####",
     "##############", "##############", "#############.", "############.."]
I = ["####"] * 16
D = ["###########...", "############..", "#############.", "##############"] + \
    ["####......####"] * 8 + \
    ["##############", "#############.", "############..", "###########..."]
J = ["..........####"] * 8 + ["####......####"] * 4 + \
    ["##############", "##############", ".#############", "..############"]
SCROLL = ("SIDJ V" + VERSION + "  -  A DJ-STYLE TRACKER FOR THE COMMODORE 64, BY ILLOBO/NETMILK  -  "
          "PICK AN ENTRY WITH CRSR OR JOYSTICK AND PRESS RETURN, OR PRESS 1-4  -  "
          "README AND THE USER'S MANUAL ARE ON THIS DISK TOO  -  HAVE FUN!" + " " * 40)


def table(vals, per_line=16):
    return "\n".join("        .byte " + ",".join("$%02x" % v for v in vals[i:i + per_line])
                     for i in range(0, len(vals), per_line))


def scr(c):
    o = ord(c)
    if "A" <= c <= "Z":
        return o - 64
    if c == "@":
        return 0
    assert 0x20 <= o <= 0x3F, c
    return o


def logo_rows():
    letters = [S, I, D, J]
    w = sum(len(l[0]) for l in letters) + 4 * (len(letters) - 1)
    w += w & 1
    pix = [[0] * w for _ in range(16)]
    x = 0
    for l in letters:
        for y, row in enumerate(l):
            for i, ch in enumerate(row):
                pix[y][x + i] = ch == "#"
        x += len(l[0]) + 4
    rows = []
    for cy in range(8):
        rows.append([QUAD[(pix[2 * cy][2 * cx], pix[2 * cy][2 * cx + 1],
                           pix[2 * cy + 1][2 * cx], pix[2 * cy + 1][2 * cx + 1])] for cx in range(w // 2)])
    return rows


def check_quad(path):
    rom = open(path, "rb").read()
    for (ul, ur, ll, lr), c in QUAD.items():
        top = (0xF0 if ul else 0) | (0x0F if ur else 0)
        bot = (0xF0 if ll else 0) | (0x0F if lr else 0)
        assert list(rom[c * 8:c * 8 + 8]) == [top] * 4 + [bot] * 4, "quadrant $%02x" % c


def rasterloop():
    """Eight handlers per block of 8 lines; X = first line of the block.
    Handler k sets line X+k while the beam is on X+k-1: $d021 at cycle 56,
    $d020 at 60 (both in the right border / blank). The handler after a bad
    line runs fixed code straight from the previous one (see mktables.py)."""
    out, addr = [], LOOP_ORG

    def emit(text, size):
        nonlocal addr
        out.append(text)
        addr += size

    emit("rblock", 0)
    for k in range(8):
        if k == BAD_SLOT:
            emit("h%d      lda buf+%d,x          ; after a bad line: fixed timing" % (k, k), 3)
            for _ in range(5):
                emit("        nop", 1)
            emit("        sta $d021", 3)
            emit("        sta $d020", 3)
            continue
        slide = addr + 14
        if slide >> 8 != (slide + SLIDE + 1) >> 8:          # keep the slide in one page
            target = ((addr + 3 + 0xFF) & ~0xFF) - 14
            if target < addr + 3:
                target += 0x100
            emit("        jmp h%d" % k, 3)
            emit("        .fill %d, 0" % (target - addr), target - addr)
        emit("h%d      ldy $dc04" % k, 3)
        emit("        lda slidetab,y", 3)
        emit("        sta br%d+1" % k, 3)
        emit("        lda buf+%d,x" % k, 3)
        emit("br%d     bpl sl%d" % (k, k), 2)
        emit("sl%d     .byte %s,$c5,$ea" % (k, ",".join(["$c9"] * SLIDE)), SLIDE + 2)
        emit("        .cerror (sl%d >> 8) != ((sl%d + %d) >> 8), \"slide crosses a page\"" % (k, k, SLIDE + 1), 0)
        emit("        sta $d021", 3)
        emit("        sta $d020", 3)
    emit("        txa", 1)
    emit("        clc", 1)
    emit("        adc #8", 2)
    emit("        tax", 1)
    emit("        cpx #ENDLINE", 2)
    emit("        beq rdone", 2)
    emit("        jmp rblock", 3)
    emit("rdone   rts", 1)
    return out


def main(path):
    if os.environ.get("CHARGEN"):
        check_quad(os.environ["CHARGEN"])
    lo, hi = BAND
    mid, amp = (lo + hi - BARLEN) / 2, (hi - BARLEN - lo) / 2
    sine = [round(mid + amp * math.sin(2 * math.pi * i / 256)) for i in range(256)]
    assert min(sine) >= lo and max(sine) + BARLEN <= hi + 1
    freq = [min(0xFFFF, round(440 * 2 ** ((n - 69) / 12) * 2 ** 24 / 985248)) for n in range(96)]
    logo = logo_rows()
    assert LOGO_COL + len(logo[0]) <= 40
    text = [scr(c) for c in SCROLL]
    assert len(text) < 256
    with open(path, "w") as f:
        f.write("; generated by tools/mkloader.py - do not edit\n")
        f.write("LOGO_COL = %d\nLOGO_W = %d\n\n" % (LOGO_COL, len(logo[0])))
        f.write("        .cerror * != $%04x, \"rblock must start at LOOP_ORG\"\n" % LOOP_ORG)
        f.write("\n".join(rasterloop()) + "\n\n")
        f.write("sine\n%s\nfreqlo\n%s\nfreqhi\n%s\n" % (table(sine), table([v & 0xFF for v in freq]),
                                                     table([v >> 8 for v in freq])))
        f.write("logo\n%s\n" % "\n".join(table(r, 40) for r in logo))
        f.write("scrolltext\n%s\n        .byte 0\n" % table(text))
        f.write("byline\n%s\n" % table([scr(c) for c in ("BY ILLOBO/NETMILK  V" + VERSION).center(40)], 40))


if __name__ == "__main__":
    main(sys.argv[1])
