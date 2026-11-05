#!/usr/bin/env python3
"""Build SIDJ.HLP, the extended help pages (REU).

usage: python3 tools/mkhelp.py OUT.prg [PAGES_DIR]   (default docs/help)

Each page is a text file in PAGES_DIR (sorted by name), 17 lines of at most
40 characters for screen rows 1-17. The first line is the title (white);
text in {braces} is a key (yellow); the rest is light grey. Letters print as
the editor's upper case.

File: PRG (load address 0, never used), then an RLE stream (ESC $E7, count,
value; any other byte literal) that SIDJ (fileio fio_rload) decodes into REU
bank 0 from $2000:
  $2000  "SIDJHLP" (ASCII), version 1, page count
  $2100 + n * $580  page n: 680 screen codes, 680 colours, 40 screen codes
                    for row 24 (page number and keys)
The help area ends at $7000 (14 pages)."""
import sys, os, glob

ROWS, COLS = 17, 40
STRIDE, BASE, END = 0x580, 0x2100, 0x7000
COL_TITLE, COL_KEY, COL_TEXT, ESC = 1, 7, 15, 0xE7
MAXPG = (END - BASE) // STRIDE

def scr(ch):
    c = ord(ch)
    if 'a' <= ch <= 'z': return c - 96
    if 'A' <= ch <= 'Z': return c - 64
    if 0x20 <= c <= 0x3f: return c
    if ch == '@': return 0
    raise ValueError(f'no screen code for {ch!r}')

def page(path):
    lines = open(path).read().rstrip('\n').split('\n')
    if len(lines) > ROWS: sys.exit(f'{path}: {len(lines)} lines (max {ROWS})')
    txt, col = [], []
    for i, l in enumerate(lines + [''] * (ROWS - len(lines))):
        t, c, key = [], [], False
        for ch in l:
            if ch == '{': key = True; continue
            if ch == '}': key = False; continue
            t.append(scr(ch))
            c.append(COL_TITLE if i == 0 else COL_KEY if key else COL_TEXT)
        if len(t) > COLS: sys.exit(f'{path}:{i+1}: {len(t)} characters (max {COLS})')
        txt += t + [0x20] * (COLS - len(t))
        col += c + [COL_TEXT] * (COLS - len(c))
    return txt, col

def rle(data):
    out, i = bytearray(), 0
    while i < len(data):
        v, n = data[i], 1
        while i + n < len(data) and data[i + n] == v and n < 255: n += 1
        if n >= 4 or v == ESC:
            out += bytes([ESC, n, v])
        else:
            out += bytes([v] * n)
        i += n
    return out

def main():
    out = sys.argv[1]
    src = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), '..', 'docs', 'help')
    files = sorted(glob.glob(os.path.join(src, '*.txt')))
    if not 0 < len(files) <= MAXPG: sys.exit(f'{len(files)} pages (1-{MAXPG})')
    img = bytearray([0] * (BASE - 0x2000 + STRIDE * len(files)))
    img[0:9] = b'SIDJHLP' + bytes([1, len(files)])
    for n, f in enumerate(files):
        txt, col = page(f)
        foot = f'help {n+1:02d}/{len(files):02d}  crsr u/d:page  any key:close'
        assert len(foot) == COLS
        rec = bytes(txt) + bytes(col) + bytes(scr(ch) for ch in foot)
        at = BASE - 0x2000 + n * STRIDE
        img[at:at + len(rec)] = rec
    data = bytes([0, 0]) + rle(img)
    open(out, 'wb').write(data)
    print(f'{out}: {len(files)} pages, {len(img)} bytes in the REU, {len(data)} in the file')

if __name__ == '__main__':
    main()
