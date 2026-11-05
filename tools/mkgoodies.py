#!/usr/bin/env python3
"""mkgoodies: the demo project and factory kit files for the release disk
(the example songs come from tools/mksongs.py, build/songs).

usage: mkgoodies.py OUTDIR

Writes, in SIDJ's own file formats (src/fileio.asm):
  demo.sidj     the demo song SIDJ starts with (src/main.asm demo_data)
  drums.kit, band.kit, synth.kit   the factory kits (SIDK, version 1)
Instruments come from the factory presets (src/editor/presetdata.asm) with
their table templates, as the PRESET field puts them.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
sys.path.insert(0, HERE)
import sidj2sid  # noqa: E402

BLOCKS = [(1, 0xF800, 0x100), (2, 0xE000, 0x600), (3, 0xC000, 0x1000), (4, 0x8000, 0x3FC0),
          (5, 0xE600, 0x400), (6, 0xEA00, 0xC00), (7, 0xF600, 0x200), (8, 0xF900, 0x100)]
PHRASES, CHAINS, SONG, INSTR, TABLES = 0x8000, 0xC000, 0xE000, 0xE600, 0xEA00
HD_TEMPO, HD_NAME = 0xF800, 0xF810
ALLOC = {"chain": 0xF900, "phrase": 0xF910, "instr": 0xF930, "table": 0xF938}
CMD_HOP, CMD_BEND, CMD_K = 8, 16, 11
NOTES = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def num(t):
    t = t.strip()
    return int(t[1:], 16) if t.startswith("$") else int(t)


def presets():
    src = open(os.path.join(ROOT, "src", "editor", "presetdata.asm")).read()
    pre = [(m.group(1), [num(x) for x in m.group(2).split(",")])
           for m in re.finditer(r'PRESETS \.?\.?:?=\s*\[\("(\w+)",\s*\[([^\]]*)\]\)\]', src)]
    tpl = []
    for m in re.finditer(r"TPLS \.?\.?:?=\s*\[\[(.*?)\]\]", src):
        tpl.append([tuple(num(x) for x in r.split(",")) for r in re.findall(r"\(([^)]*)\)", m.group(1))])
    return pre, tpl


def kits():
    src = open(os.path.join(ROOT, "src", "editor", "kits.asm")).read()
    ids = {m.group(1): num(m.group(2)) for m in re.finditer(r"^(P_\w+)\s*=\s*(\S+)", src, re.M)}
    return [(m.group(1), [ids[x.strip()] for x in m.group(2).split(",")])
            for m in re.finditer(r'KITS \.?\.?:?=\s*\[\("(\w+)",\s*\[([^\]]*)\]\)\]', src)]


PRE, TPL = presets()


def clean_table():
    """16 rows x 6 columns, column order (ctl $ff = empty)"""
    t = bytearray(96)
    t[0:16] = b"\xff" * 16
    return t


def template_table(k):
    t = clean_table()
    for r, (ctl, tr, c) in enumerate(TPL[k]):
        t[r], t[16 + r] = ctl, tr
        if 0x10 <= c <= 0x1F:
            t[32 + r], t[48 + r] = CMD_HOP, c & 15
        elif c:
            t[32 + r], t[48 + r] = CMD_BEND, c
    return t


def preset_instr(pid):
    """(16 instrument bytes with IN_TABLE = template number or $ff, template table or None)"""
    b = bytearray(PRE[pid][1])
    b[0] |= (pid & 15) << 4
    b[15] |= pid & 0x10
    tpl = b[14]
    b[14] = 0xFF
    return b, (template_table(tpl) if tpl != 0xFF else None)


class Project:
    def __init__(self, name, tempo):
        self.m = sidj2sid.clean_memory()
        self.m[HD_TEMPO] = tempo
        n = bytes((ord(c) - 64) if "A" <= c <= "Z" else ord(c) for c in name.upper())
        self.m[HD_NAME:HD_NAME + 16] = n.ljust(16, b"\0")
        self.ntab = 0

    def alloc(self, kind, n):
        self.m[ALLOC[kind] + (n >> 3)] |= 1 << (n & 7)

    def instr(self, i, pid):
        b, tbl = preset_instr(pid)
        if tbl:
            t = self.ntab
            self.ntab += 1
            for c in range(6):
                a = TABLES + c * 0x200 + t * 16
                self.m[a:a + 16] = tbl[c * 16:c * 16 + 16]
            b[14] = t
            self.alloc("table", t)
        self.m[INSTR + i * 16:INSTR + i * 16 + 16] = b
        self.alloc("instr", i)

    def raw_instr(self, i, b):
        self.m[INSTR + i * 16:INSTR + i * 16 + 16] = bytes(b)
        self.alloc("instr", i)

    def phrase(self, p, steps):
        """steps: {step: (note, instr[, cmd, val])}; note as 'C-4' or a number"""
        for s, v in steps.items():
            note = v[0]
            if isinstance(note, str):
                note = NOTES[note[:-1].rstrip("-")] + 12 * int(note[-1])
            a = PHRASES + p * 64 + s * 4
            self.m[a:a + 4] = bytes([note, v[1], v[2] if len(v) > 2 else 0, v[3] if len(v) > 3 else 0])
        self.alloc("phrase", p)

    def chain(self, c, steps):
        for s, v in enumerate(steps):
            p, tr = v if isinstance(v, tuple) else (v, 0)
            self.m[CHAINS + c * 32 + s * 2] = p
            self.m[CHAINS + c * 32 + s * 2 + 1] = tr & 255
        self.alloc("chain", c)

    def song(self, rows):
        for r, chs in enumerate(rows):
            for ch, c in enumerate(chs):
                if c is not None:
                    self.m[SONG + ch * 256 + r] = c

    def file(self):
        out = bytearray(b"SIDJ\x02")
        for tag, addr, length in BLOCKS:
            enc, body = sidj2sid.encode_block(bytes(self.m[addr:addr + length]), sidj2sid.STRIDE[tag])
            out += bytes([tag, enc, length & 255, length >> 8, len(body) & 255, len(body) >> 8]) + body
        out.append(0)
        assert sidj2sid.song_data(sidj2sid.load_project(bytes(out))) == sidj2sid.song_data(self.m)
        return bytes(out)


def demo():
    """src/main.asm demo_data"""
    p = Project("DEMO", 125)
    p.raw_instr(0, [0x09, 0x40, 0x09, 0xa6, 0x00, 0x06, 0x00, 0x30, 0x81, 0xfe, 0x20, 0x00, 0x00, 0x00, 0xff, 0x00])
    p.raw_instr(1, [0x01, 0x40, 0x09, 0xa9, 0x00, 0x14, 0x18, 0x00, 0x00, 0x00, 0x20, 0x00, 0x34, 0x0a, 0xff, 0x00])
    p.raw_instr(2, [0x00, 0x10, 0x06, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0x00])
    p.raw_instr(3, [0x00, 0x80, 0x02, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0x00])
    p.raw_instr(4, [0x00, 0x80, 0x06, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0x00])
    p.phrase(0, {0: ("C-2", 0), 3: ("C-2", 0, CMD_K, 2), 4: ("C-3", 0), 6: ("C-2", 0), 8: ("D#2", 0),
                 10: ("F-2", 0), 12: ("G-2", 0), 14: ("A#1", 0)})
    p.phrase(1, {0: ("G-4", 1), 6: ("A#4", 1), 8: ("C-5", 1, 3, 0x37), 14: ("G-4", 1, CMD_K, 3)})
    p.phrase(2, {0: ("F-4", 1), 4: ("D#4", 1), 8: ("C-4", 1)})
    p.phrase(3, {0: ("C-1", 2), 2: ("C-6", 3), 4: ("C-4", 4), 6: ("C-6", 3), 8: ("C-1", 2), 10: ("C-6", 3),
                 12: ("C-4", 4), 14: ("C-6", 3)})
    p.chain(0, [(0, 0), (0, 5)])
    p.chain(1, [1, 2])
    p.chain(2, [3, 3])
    p.song([(0, 1, 2), (0, 1, 2)])
    return p


def kitfile(pids):
    tables, instrs = [], []
    for pid in pids:
        b, tbl = preset_instr(pid)
        if tbl:
            b[14] = len(tables)
            tables.append(bytes(tbl))
        instrs.append(bytes(b))
    return b"SIDK" + bytes([1, len(pids), len(tables)]) + b"".join(tables) + b"".join(instrs)


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for name, p in (("demo", demo()),):
        data = p.file()
        open(os.path.join(out, name + ".sidj"), "wb").write(data)
        print("%s.sidj: %d bytes" % (name, len(data)))
    for name, pids in kits():
        data = kitfile(pids)
        open(os.path.join(out, name + ".kit"), "wb").write(data)
        print("%s.kit: %d bytes" % (name, len(data)))


if __name__ == "__main__":
    main()
