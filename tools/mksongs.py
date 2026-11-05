#!/usr/bin/env python3
"""mksongs: ten techno demo songs for SIDJ, written in a small Python DSL.

usage: mksongs.py [OUTDIR]      (default build/songs)

Writes OUTDIR/<name>.sidj for each song: a SIDJ project file, version 2
(src/fileio.asm), three channels, groove 0 = 6/6, the 32
base factory presets (src/editor/presetdata.asm) with their table templates
as the PRESET field (apply_preset, src/editor/low.asm) puts them.

The DSL
  s = Song("TITLE", bpm, "style", "one line")
  s.ins("bass", 0x10, cut=0x50)        instrument from preset 10, tweaked
  s.kit(k="kick", h="clhat", T=("tom", "G-4"))   drum letters (note C-4 unless given)
  s.dr("beat", "k.h.k.h.k.h.k.h.")     drum phrase: one letter per step
  s.ph("riff", "A-2 . A-3 - ...", "bass")   phrase: 16 tokens
      token = [note | . | -][@instrument][:Cvv]
      note C-4 / C#4, "." no note, "-" note off (K00), Cvv a command (X40, C37)
  s.ch("bassA", ["riff", ("riff", 5), "riff2"])   chain: phrases + transpose
  s.row("drums", "bassA", "lead")      song row: one chain per channel

Phrases and chains get numbers in the order the song first uses them;
identical ones share a number. Instruments get numbers in the order of first
use, tables in the order their instruments get numbers. Every row's chains
must be equally long, so the three channels stay in step.
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
LIMITS = {"chain": 128, "phrase": 255, "instr": 64, "table": 32}
CMD_H, CMD_K, CMD_P = 8, 11, 16
SEMI = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}
NAMES = ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"]
# instrument byte offsets (src/defs.inc IN_*)
FIELDS = dict(flags=0, wave=1, ad=2, sr=3, pwlo=4, pwhi=5, pwspd=6, cut=7, rm=8, fsw=9, hr=10, hrsr=11,
              vib=12, vibdly=13, tspd=15)


def num(t):
    t = t.strip()
    return int(t[1:], 16) if t.startswith("$") else int(t)


def presets():
    """[(name, 16 bytes)], [template rows (ctl, transpose, c)] from presetdata.asm"""
    src = open(os.path.join(ROOT, "src", "editor", "presetdata.asm")).read()
    pre = [(m.group(1), [num(x) for x in m.group(2).split(",")])
           for m in re.finditer(r'PRESETS \.?\.?:?=\s*\[\("(\w+)",\s*\[([^\]]*)\]\)\]', src)]
    tpl = [[tuple(num(x) for x in r.split(",")) for r in re.findall(r"\(([^)]*)\)", m.group(1))]
           for m in re.finditer(r"TPLS \.?\.?:?=\s*\[\[(.*?)\]\]", src)]
    assert len(pre) == 32 and len(tpl) == 14, (len(pre), len(tpl))
    return pre, tpl


PRE, TPL = presets()


def template_table(k):
    """table k as tbl_write fills it: 16 rows x 6 columns, column-major;
    k = template number or a list of rows (ctl, transpose, c) in the same form"""
    t = bytearray(96)
    t[0:16] = b"\xff" * 16
    for r, (ctl, tr, c) in enumerate(TPL[k] if isinstance(k, int) else k):
        t[r], t[16 + r] = ctl, tr
        if 0x10 <= c <= 0x1F:
            t[32 + r], t[48 + r] = CMD_H, c & 15
        elif c:
            t[32 + r], t[48 + r] = CMD_P, c
    return t


def preset_instr(pid):
    """(16 bytes with the preset id in flags/table speed, template number or None)"""
    b = bytearray(PRE[pid][1])
    b[0] |= (pid & 15) << 4
    b[15] |= pid & 0x10
    tpl = b[14]
    b[14] = 0xFF
    return b, (None if tpl == 0xFF else tpl)


def note(s):
    """'C-4' / 'C#4' -> 48 / 49"""
    m = re.fullmatch(r"([A-G])([-#])(\d)", s)
    if not m:
        raise ValueError("bad note %r" % s)
    n = SEMI[m.group(1) + ("#" if m.group(2) == "#" else "")] + 12 * int(m.group(3))
    assert 0 <= n < 96, s
    return n


def nn(n):
    """48 -> 'C-4'"""
    return NAMES[n % 12] + str(n // 12)


def scr(s):
    out = bytearray()
    for c in s.upper():
        o = ord(c) - 0x40 if "A" <= c <= "Z" else ord(c)
        assert 0x01 <= o <= 0x3F, "title character %r" % c
        out.append(o)
    return bytes(out).ljust(16, b" ")


TOKEN = re.compile(r"(?P<n>[A-G][-#]\d|\.|-)?(?:@(?P<i>\w+))?(?::(?P<c>[A-Z])(?P<v>[0-9A-F]{2}))?$")


class Song:
    def __init__(self, title, bpm, style, line):
        assert len(title) <= 16 and 40 <= bpm <= 255
        self.title, self.bpm, self.style, self.line = title, bpm, style, line
        self.insdef, self.drums = {}, {}
        self.phr, self.chn, self.rows = {}, {}, []
        self.ph("rest", REST)
        self.ph("silent", " ".join(["."] * 16))

    @property
    def stem(self):
        return self.title.lower().replace(" ", "_")[:16]

    # --- definitions -------------------------------------------------------
    def ins(self, name, pid, **tw):
        """instrument from preset pid; tweaks by field name (FIELDS), pw = 12-bit
        pulse width, pwmode = sweep mode 0-3, filt = 0 off / 1 use / 2 own"""
        b, tpl = preset_instr(pid)
        for k, v in tw.items():
            if k == "pw":
                b[4], b[5] = v & 255, (b[5] & 0xF0) | (v >> 8)
            elif k == "pwmode":
                b[5] = (b[5] & 0x0F) | v << 4
            elif k == "filt":
                b[0] = (b[0] & ~0x0C) | v << 2
            elif k == "tbl":
                tpl = v                     # another template, a row list (as TPLS) or None
            else:
                b[FIELDS[k]] = v
        self.insdef[name] = (bytes(b), tpl)

    def kit(self, **m):
        for ch, v in m.items():
            self.drums[ch] = v if isinstance(v, tuple) else (v, "C-4")

    def ph(self, name, tokens, ins=None):
        toks = tokens.split()
        assert len(toks) == 16, "%s: %d tokens" % (name, len(toks))
        steps, cur = [], ins
        for t in toks:
            m = TOKEN.match(t)
            if not m:
                raise ValueError("%s: bad token %r" % (name, t))
            n, i, c, v = m.group("n"), m.group("i"), m.group("c"), m.group("v")
            if n in (None, "."):
                nb = 0xFF
            elif n == "-":
                nb = 0xFF
                if c is None:
                    c, v = "K", "00"
            else:
                nb = note(n)
            ib = None
            if nb != 0xFF:
                ib = i or cur
                assert ib in self.insdef, "%s: instrument %r" % (name, ib)
            elif i:
                ib = i
            cb = ord(c) - 0x40 if c else 0
            steps.append((nb, ib, cb, int(v, 16) if v else 0))
        self.phr[name] = steps

    def dr(self, name, pattern, cmds=None):
        """one letter per step (kit letters, '.' empty); cmds {step: 'X40'}"""
        assert len(pattern) == 16, "%s: %d steps" % (name, len(pattern))
        toks = []
        for i, c in enumerate(pattern):
            t = "." if c == "." else "%s@%s" % (self.drums[c][1], self.drums[c][0])
            if cmds and i in cmds:
                t += ":" + cmds[i]
            toks.append(t)
        self.ph(name, " ".join(toks))

    def ch(self, name, items):
        items = [(x, 0) if isinstance(x, str) else x for x in items]
        assert 1 <= len(items) <= 16, name
        for p, _ in items:
            assert p in self.phr, "%s: phrase %r" % (name, p)
        self.chn[name] = items

    def row(self, *chains):
        assert len(chains) == 3
        lens = {len(self.chn[c]) for c in chains}
        assert len(lens) == 1, "row %d: chain lengths %s" % (len(self.rows), chains)
        self.rows.append(chains)

    # --- numbers -----------------------------------------------------------
    def bars(self):
        return sum(len(self.chn[r[0]]) for r in self.rows)

    def seconds(self):
        return self.bars() * 16 * 15.0 / self.bpm

    def build(self):
        """64 KB memory image with the song, as SIDJ holds it"""
        m = sidj2sid.clean_memory()
        m[HD_TEMPO] = self.bpm
        m[HD_NAME:HD_NAME + 16] = scr(self.title)

        def alloc(kind, n):
            assert n < LIMITS[kind], "%s %d over the limit" % (kind, n)
            m[ALLOC[kind] + (n >> 3)] |= 1 << (n & 7)

        insnum, tblnum, phnum, chnum = {}, [0], {}, {}

        def instr(name):
            if name not in insnum:
                b, tpl = self.insdef[name]
                i = len(insnum)
                insnum[name] = i
                b = bytearray(b)
                if tpl is not None:
                    t = tblnum[0]
                    tblnum[0] += 1
                    tb = template_table(tpl)
                    for c in range(6):
                        a = TABLES + c * 0x200 + t * 16
                        m[a:a + 16] = tb[c * 16:c * 16 + 16]
                    b[14] = t
                    alloc("table", t)
                m[INSTR + i * 16:INSTR + i * 16 + 16] = b
                alloc("instr", i)
            return insnum[name]

        def phrase(name):
            data = bytes(b for st in self.phr[name]
                         for b in (st[0], 0xFF if st[1] is None else instr(st[1]), st[2], st[3]))
            if data not in phnum:
                p = len(phnum)
                phnum[data] = p
                m[PHRASES + p * 64:PHRASES + p * 64 + 64] = data
                alloc("phrase", p)
            return phnum[data]

        def chain(name):
            data = bytes(b for p, tr in self.chn[name] for b in (phrase(p), tr & 255))
            if data not in chnum:
                c = len(chnum)
                chnum[data] = c
                m[CHAINS + c * 32:CHAINS + c * 32 + len(data)] = data
                alloc("chain", c)
            return chnum[data]

        assert len(self.rows) <= 255
        for r, chs in enumerate(self.rows):
            for k, c in enumerate(chs):
                m[SONG + k * 256 + r] = chain(c)
        self.counts = dict(phrases=len(phnum), chains=len(chnum), instruments=len(insnum), tables=tblnum[0])
        return m

    def file(self):
        m = self.build()
        out = bytearray(b"SIDJ\x02")
        for tag, addr, length in BLOCKS:
            enc, body = sidj2sid.encode_block(bytes(m[addr:addr + length]), sidj2sid.STRIDE[tag])
            out += bytes([tag, enc, length & 255, length >> 8, len(body) & 255, len(body) >> 8]) + body
        out.append(0)
        assert sidj2sid.song_data(sidj2sid.load_project(bytes(out))) == sidj2sid.song_data(m)
        return bytes(out)


# ---------------------------------------------------------------------------
# Helpers for writing phrases

def arp(root, ivals, order, octave_up=0, cmd=None):
    """16 tokens cycling through chord tones: root note name, intervals,
    order = index pattern into the intervals (len 16, '.' rests)"""
    r = note(root)
    out = []
    for o in order:
        out.append("." if o == "." else nn(r + ivals[int(o)]))
    if cmd:
        out[0] += ":" + cmd
    return " ".join(out)


REST = " ".join(["-"] + ["."] * 15)        # note off, then silence


def common_kit(s, **extra):
    """the usual drum letters; extra letters on top"""
    s.ins("kick", 0x06)
    s.ins("snare", 0x07)
    s.ins("clhat", 0x08)
    s.ins("ophat", 0x09)
    s.ins("clap", 0x0B)
    s.ins("crash", 0x0D)
    s.kit(k="kick", s="snare", h="clhat", o="ophat", c="clap", x="crash", **extra)


# ---------------------------------------------------------------------------
# The songs. Each function returns a Song. Bars = phrases (16 sixteenths).

SONGS = []


def song(f):
    SONGS.append(f)
    return f


def cut(tokens, base, accent=(), boost=0x30, cmd="X"):
    """X (filter cutoff) on every note that has no command: base, + boost on
    accent steps; clamped to $00-$ff (cmd: another letter, e.g. S)"""
    out = []
    for i, t in enumerate(tokens.split()):
        if re.match(r"[A-G][-#]\d", t) and ":" not in t:
            t += ":%s%02X" % (cmd, max(0, min(255, base + (boost if i in accent else 0))))
        out.append(t)
    return " ".join(out)


def chord_tbl(*ivals):
    """table rows for an arpeggio chord (one interval per tick, looping)"""
    rows = [(0xFF, v & 255, 0) for v in ivals]
    rows[-1] = (0xFF, ivals[-1] & 255, 0x10)
    return rows


def rest_chain(s, n, name=None):
    """a chain of n silent bars (note off on step 0)"""
    name = name or "rest%d" % n
    s.ch(name, ["rest"] + ["silent"] * (n - 1))
    return name


@song
def acid_raster():
    s = Song("ACID RASTER", 132, "acid", "A-minor 303 line on the acid preset; X opens the filter bar by bar, "
             "a minor-arp stab answers it, a saw hook over the second drop.")
    common_kit(s)
    s.ins("acid", 0x10, fsw=0xFB)
    s.ins("stab", 0x1B, ad=0x06, sr=0x00)
    s.ins("hook", 0x14, ad=0x0A, sr=0x84)
    s.ins("rise", 0x1E)
    s.dr("d4", "k...k...k...k...")
    s.dr("dh", "k.h.k.h.k.h.k.h.")
    s.dr("dm", "k.h.k.hck.h.k.h.")
    s.dr("dc", "k.h.c.h.k.h.c.ho")
    s.dr("dx", "k.x.k.hck.h.k.h.")
    s.dr("df", "k.h.k.h.k.s.ssss")
    s.dr("dr", "s.ss.ss.ssssssss")
    s.dr("db", "..h...h.c.h...ho")
    s.dr("dz", "x...............")
    A = "A-2 A-2 A-3 . A-2 C-3 . A-2 D#3 E-3:L02 A-2 . G-2 A-2 A-3:L02 -"
    B = "A-2 A-2 A-3 . A-2 C-3 . A-2 G-2 . A-2 C-3 D-3:L02 C-3 A-2 -"
    acc = (2, 8, 14)
    for x in range(0x20, 0x101, 0x10):
        s.ph("a%02x" % min(x, 0xF0), cut(A, min(x, 0xF0), acc), "acid")
        s.ph("b%02x" % min(x, 0xF0), cut(B, min(x, 0xF0), acc), "acid")
    s.ph("st1", ". . A-4 - . . A-4 - . . . . . . C-5 -", "stab")
    s.ph("st2", ". . A-4 - . . A-4 - . . G-4 - . . E-4 -", "stab")
    s.ph("h1", "E-5 . E-5 . D-5 . C-5 . D-5 . . . A-4 . . -", "hook")
    s.ph("h2", "E-5 . E-5 . G-5 . E-5 . D-5 . C-5 . D-5 . . -", "hook")
    s.ph("h3", "C-5 . C-5 . D-5 . E-5 . G-5 . . . E-5 . . -", "hook")
    s.ph("h4", "D-5 . C-5 . A-4 . . . . . . . - . . .", "hook")
    s.ph("ris", "A-3 . . . . . . . . . . . . . . .", "rise")
    s.ph("ris2", ". . . . . . . . . . . . . . . -", "rise")
    s.ch("d_in", ["d4"] * 7 + ["dh"])
    s.ch("d_in2", ["dh"] * 7 + ["df"])
    s.ch("d_bu", ["dm"] * 6 + ["df", "dr"])
    s.ch("d_dr", ["dx", "dm", "dm", "dc", "dm", "dm", "dm", "df"])
    s.ch("d_dr2", ["dx", "dm", "dm", "dc", "dm", "dm", "dc", "dr"])
    s.ch("d_br", ["dz"] + ["db"] * 7)
    s.ch("d_out", ["dx", "dh", "dh", "dh", "d4", "d4", "d4", "dz"])
    s.ch("a_in2", ["a20", "b20", "a20", "b30", "a30", "b30", "a40", "b40"])
    s.ch("a_bu", ["a40", "b50", "a50", "b60", "a60", "b70", "a80", "b90"])
    s.ch("a_dr", ["aa0", "ba0", "ab0", "bb0", ("aa0", 5), ("ba0", 5), "ab0", "bc0"])
    s.ch("a_br", [("a40", 5), ("b40", 5), ("a30", 5), ("b30", 5), "a30", "b30", "a20", "b20"])
    s.ch("a_bu2", ["a30", "b40", "a50", "b60", "a70", "b80", "aa0", "bc0"])
    s.ch("a_dr2", ["ad0", "bd0", "ae0", "bf0", ("ad0", 5), ("bd0", 5), ("ae0", 3), ("bf0", 3)])
    s.ch("a_out", ["ac0", "b90", "a70", "b60", "a40", "b30", "a20", "b20"])
    s.ch("l_dr", ["st1", "st2"] * 4)
    s.ch("l_br", ["st1", "st1", "st2", "st2", "st1", "st1", "st2", "st2"])
    s.ch("l_bu", ["rest"] + ["silent"] * 5 + ["ris", "ris2"])
    s.ch("l_dr2", ["h1", "h2", "h3", "h4"] * 2)
    r8 = rest_chain(s, 8)
    s.row("d_in", r8, r8)
    s.row("d_in2", "a_in2", r8)
    s.row("d_bu", "a_bu", "l_bu")
    s.row("d_dr", "a_dr", "l_dr")
    s.row("d_dr2", "a_dr", "l_dr")
    s.row("d_br", "a_br", "l_br")
    s.row("d_bu", "a_bu2", "l_bu")
    s.row("d_dr", "a_dr2", "l_dr2")
    s.row("d_dr2", "a_dr2", "l_dr2")
    s.row("d_out", "a_out", r8)
    return s


@song
def poke_53280():
    s = Song("POKE 53280", 128, "minimal", "F-minor pulse bass on the off-beats; a pulse blip every third step "
             "drifts against the bar while S widens its pulse; a minor stab in the second drop.")
    s.ins("rim", 0x0C)
    common_kit(s, r="rim")
    s.ins("bass", 0x0E, ad=0x06, sr=0x00)
    s.ins("blip", 0x00, ad=0x04, sr=0x00)
    s.ins("stab", 0x14, ad=0x05, sr=0x00, vib=0, tbl=chord_tbl(0, 3, 7))
    s.dr("m0", "k...k...k...k...")
    s.dr("m1", "k.h.k.h.k.h.k.h.")
    s.dr("m2", "k.hrk.h.k.hrk.ho")
    s.dr("m3", "k.hrk.hrk.h.krho")
    s.dr("mc", "k.hrc.h.k.hrc.ho")
    s.dr("mf", "k.h.k.hrk.rrkrrr")
    s.dr("mb", "..h.r.h...h.r.hh")
    s.dr("mx", "k.xrk.h.k.hrk.ho")
    s.ph("b1", ". . F-2 . . . F-2 F-3 . . F-2 . . . F-2 .", "bass")
    s.ph("b2", ". . F-2 . . . F-2 F-3 . . F-2 . . G#2 F-2 .", "bass")
    s.ph("b3", ". . F-2 . F-2 . F-2 F-3 . . F-2 . C-3 . D#3 .", "bass")
    s.ph("b4", "F-2 . . . . . . . . . . . . . . .", "bass")
    bl = ["C-5 . . G#4 . . C-5 . . D#5 . . C-5 . . G#4",
          ". . D#5 . . C-5 . . G#4 . . C-5 . . D#5 .",
          ". C-5 . . G#4 . . C-5 . . D#5 . . C-5 . ."]
    for pw in (0x08, 0x10, 0x20, 0x40, 0x60, 0x80):
        for i, t in enumerate(bl):
            s.ph("bl%d%02x" % (i, pw), cut(t, pw, cmd="S"), "blip")
    s.ph("c1", ". . F-4 - . . . . . . F-4 - . . . .", "stab")
    s.ph("c2", ". . F-4 - . . . . . F-4 . . D#4 - . .", "stab")
    s.ph("c3", ". . F-4 - . . F-4 - . . . . G#4 - . .", "stab")

    def blips(pws):
        return ["bl%d%02x" % (i % 3, pw) for i, pw in enumerate(pws)]

    s.ch("d_in", ["m0", "m0", "m0", "m1", "m1", "m1", "m1", "m2"])
    s.ch("d_a", ["m2", "m2", "m2", "m3", "m2", "m2", "mc", "mf"])
    s.ch("d_b", ["mx", "m2", "m3", "m2", "mc", "m2", "m3", "mf"])
    s.ch("d_br", ["mb"] * 7 + ["mf"])
    s.ch("d_out", ["m2", "m2", "m1", "m1", "m1", "m0", "m0", "m0"])
    s.ch("b_a", ["b1", "b1", "b1", "b2"] * 2)
    s.ch("b_b", ["b1", "b2", "b1", "b3"] * 2)
    s.ch("b_br", ["b4", "silent", ("b4", -2), "silent", ("b4", 3), "silent", "b1", "b2"])
    s.ch("b_c", [("b1", 0), ("b3", 0), ("b1", -2), ("b3", -2), ("b1", 3), ("b3", 3), "b1", "b3"])
    s.ch("b_out", ["b1", "b1", "b1", "b2", "b1", "b4", "rest", "silent"])
    s.ch("l_a", blips([0x08] * 4 + [0x10] * 4))
    s.ch("l_b", blips([0x20, 0x20, 0x40, 0x40, 0x40, 0x60, 0x60, 0x80]))
    s.ch("l_c", blips([0x80, 0x60, 0x60, 0x40, 0x40, 0x20, 0x20, 0x10]))
    s.ch("l_br", blips([0x10] * 8))
    s.ch("l_d", ["c1", "c2", "c1", "c3"] * 2)
    s.ch("l_e", ["c1", "bl080", "c2", "bl280", "c1", "bl160", "c3", "bl040"])
    s.ch("l_out", blips([0x40, 0x20, 0x20, 0x10, 0x10, 0x08, 0x08]) + ["rest"])
    r8 = rest_chain(s, 8)
    s.row("d_in", r8, r8)
    s.row("d_a", "b_a", r8)
    s.row("d_a", "b_a", "l_a")
    s.row("d_b", "b_a", "l_b")
    s.row("d_b", "b_b", "l_c")
    s.row("d_br", "b_br", "l_br")
    s.row("d_b", "b_b", "l_d")
    s.row("d_b", "b_c", "l_e")
    s.row("d_b", "b_b", "l_b")
    s.row("d_out", "b_out", "l_out")
    return s


@song
def sprite_skies():
    s = Song("SPRITE SKIES", 138, "trance", "Am-F-C-G with a rolling saw bass; a filtered saw arpeggio opens "
             "through the first half, string chords in the break, a 3-3-2 saw hook in the second drop.")
    common_kit(s)
    s.ins("bass", 0x0F, ad=0x05, sr=0x00)
    s.ins("arp", 0x14, ad=0x06, sr=0x00, vib=0, filt=2, cut=0x30, rm=0x41)
    s.ins("pad", 0x19)
    s.ins("lead", 0x14)
    s.ins("rise", 0x1E)
    s.dr("t1", "k.h.k.h.k.h.k.h.")
    s.dr("t2", "k.hhk.h.k.hhk.ho")
    s.dr("tc", "k.h.c.h.k.h.c.hh")
    s.dr("tx", "k.xhk.h.k.hhk.ho")
    s.dr("r1", "k...s...k...s...")
    s.dr("r2", "s.s.s.s.s.s.s.s.")
    s.dr("r3", "ssssssssssssssss")
    s.dr("tb", "..h...h...h...ho")
    s.dr("t0", "x...............")
    s.ph("bass", ". A-2 A-2 A-2 . A-2 A-2 A-3 . A-2 A-2 A-2 . A-2 A-3 A-2", "bass")
    order = "0123432101234321"
    chords = [("am", "A-4", [0, 3, 7, 12, 15]), ("f", "F-4", [0, 4, 7, 12, 16]),
              ("c", "G-4", [0, 5, 9, 12, 17]), ("g", "G-4", [0, 4, 7, 12, 16])]
    for x in range(0x10, 0x101, 0x10):
        for n, root, iv in chords:
            s.ph("%s%02x" % (n, min(x, 0xF0)), cut(arp(root, iv, order), min(x, 0xF0), (0, 8), 0x10), "arp")
    s.ph("pam", "A-3:C37 . . . . . . . . . . . . . . .", "pad")
    s.ph("pf", "F-3:C47 . . . . . . . . . . . . . . .", "pad")
    s.ph("pc", "C-4:C47 . . . . . . . . . . . . . . .", "pad")
    s.ph("pg", "G-3:C47 . . . . . . . . . . . . . . .", "pad")
    s.ph("l1", "E-5 . . E-5 . . D-5 . E-5 . . C-5 . . A-4 .", "lead")
    s.ph("l2", "F-5 . . E-5 . . C-5 . A-4 . . C-5 . . F-5 .", "lead")
    s.ph("l3", "G-5 . . G-5 . . E-5 . G-5 . . C-6 . . B-5 .", "lead")
    s.ph("l4", "B-5 . . . . . A-5 . G-5 . . D-5 . . - .", "lead")
    s.ph("ris", "A-3 . . . . . . . . . . . . . . .", "rise")
    s.ph("ris2", ". . . . . . . . . . . . . . . -", "rise")
    prog = [0, -4, 3, -2]

    def arps(xs):
        return ["%s%02x" % (chords[i % 4][0], x) for i, x in enumerate(xs)]

    s.ch("d_in", ["t1"] * 7 + ["t2"])
    s.ch("d_in2", ["t2"] * 7 + ["r1"])
    s.ch("d_bu", ["t2", "t2", "t2", "tc", "t2", "t2", "r2", "r3"])
    s.ch("d_dr", ["tx", "t2", "t2", "tc"] * 2)
    s.ch("d_dr2", ["tx", "t2", "t2", "tc", "t2", "t2", "tc", "r3"])
    s.ch("d_br", ["t0"] + ["tb"] * 7)
    s.ch("d_bu2", ["r1", "r1", "r1", "r1", "r2", "r2", "r3", "r3"])
    s.ch("d_out", ["tx", "t2", "t2", "t2", "t1", "t1", "t1", "t0"])
    s.ch("b_main", [("bass", t) for t in prog] * 2)
    s.ch("b_out", [("bass", t) for t in prog] + ["rest", "silent", "silent", "silent"])
    s.ch("a_in", arps([0x10] * 8))
    s.ch("a_in2", arps([0x20, 0x20, 0x30, 0x30, 0x40, 0x40, 0x50, 0x50]))
    s.ch("a_bu", arps([0x60, 0x70, 0x80, 0x90, 0xA0, 0xB0, 0xC0, 0xD0]))
    s.ch("a_dr", arps([0xE0, 0xD0, 0xE0, 0xF0] * 2))
    s.ch("a_out", arps([0xC0, 0xA0, 0x80, 0x60, 0x40, 0x30, 0x20, 0x10]))
    s.ch("p_br", ["pam", "pf", "pc", "pg"] * 2)
    s.ch("p_bu", ["pam", "pf", "pc", "pg", "pam", "pf", "ris", "ris2"])
    s.ch("l_dr", ["l1", "l2", "l3", "l4"] * 2)
    s.row("d_in", rest_chain(s, 8), "a_in")
    s.row("d_in2", "b_main", "a_in2")
    s.row("d_bu", "b_main", "a_bu")
    s.row("d_dr", "b_main", "a_dr")
    s.row("d_dr2", "b_main", "a_dr")
    s.row("d_br", "rest8", "p_br")
    s.row("d_bu2", "b_main", "p_bu")
    s.row("d_dr", "b_main", "l_dr")
    s.row("d_dr2", "b_main", "l_dr")
    s.row("d_out", "b_out", "a_out")
    return s


@song
def tape_loop_dub():
    s = Song("TAPE LOOP DUB", 124, "dub techno", "Dm7 pulse stabs through their own low-pass, each followed by three "
             "darker, shorter repeats a dotted eighth apart; triangle sub bass, rim and open-hat shuffle.")
    s.ins("rim", 0x0C)
    common_kit(s, r="rim")
    s.ins("ophat", 0x09, ad=0x06)
    s.ins("bass", 0x11)
    ch = chord_tbl(0, 3, 7, 10)
    stab = dict(filt=2, rm=0x81, fsw=0xFF, sr=0x00, vib=0, vibdly=0, tbl=ch)
    s.ins("stab", 0x18, ad=0x07, cut=0x48, **stab)
    s.ins("ec1", 0x18, ad=0x05, cut=0x36, **stab)
    s.ins("ec2", 0x18, ad=0x04, cut=0x28, **stab)
    s.ins("ec3", 0x18, ad=0x03, cut=0x1C, **stab)
    s.dr("u1", "k...k...k...k...")
    s.dr("u2", "k.o.k.o.k.o.k.o.")
    s.dr("u3", "k.ork.ohk.o.k.or")
    s.dr("u4", "k.ork.ohk.orkho.")
    s.dr("ub", "..o...o.r.o...o.")
    s.dr("uf", "k.ork.ork.r.rrrr")
    s.dr("ux", "k.xrk.ohk.o.k.or")
    for x in range(0x30, 0xB1, 0x10):
        s.ph("e1%02x" % x, ". . D-4@stab:X%02X . . D-4@ec1 . . D-4@ec2 . . D-4@ec3 . . . -" % x)
        s.ph("e2%02x" % x, ". . D-4@stab:X%02X . . D-4@ec1 . . D-4@ec2 . D-4@stab:X%02X . . D-4@ec1 . ."
             % (x, x + 0x10))
    s.ph("db1", "D-2 . . . . . - . . . D-2 . . - C-2 .", "bass")
    s.ph("db2", "D-2 . . . . . - . . . A-1 . . - C-2 .", "bass")
    s.ph("db3", "D-2 . . . . . . . . . . . . . . -", "bass")
    tr = [0, 0, 5, 5, 0, 0, -2, -2]

    def stabs(kind, xs):
        return [("%s%02x" % (kind, x), t) for x, t in zip(xs, tr)]

    s.ch("d_in", ["u1"] * 7 + ["u2"])
    s.ch("d_in2", ["u2"] * 7 + ["uf"])
    s.ch("d_bu", ["u3"] * 7 + ["uf"])
    s.ch("d_dr", ["ux", "u3", "u4", "u3", "u4", "u3", "u4", "uf"])
    s.ch("d_br", ["ub"] * 7 + ["uf"])
    s.ch("d_out", ["ux", "u3", "u3", "u2", "u2", "u1", "u1", "u1"])
    s.ch("b_a", [(b, t) for b, t in zip(["db1", "db2"] * 4, tr)])
    s.ch("b_br", [("db3", t) for t in tr])
    s.ch("b_out", [(b, t) for b, t in zip(["db1", "db2"] * 2, tr)] + ["rest", "silent", "silent", "silent"])
    s.ch("s_in", stabs("e1", [0x30] * 8))
    s.ch("s_in2", stabs("e1", [0x30, 0x30, 0x40, 0x40, 0x40, 0x50, 0x50, 0x50]))
    s.ch("s_bu", stabs("e1", [0x50, 0x60, 0x60, 0x70, 0x70, 0x80, 0x80, 0x90]))
    s.ch("s_dr", stabs("e1", [0x90, 0xA0, 0x90, 0xA0, 0xB0, 0xA0, 0x90, 0x80]))
    s.ch("s_dr2", stabs("e2", [0x80, 0x90, 0xA0, 0x90, 0x80, 0x90, 0xA0, 0x90]))
    s.ch("s_br", stabs("e1", [0x40, 0x40, 0x30, 0x30, 0x40, 0x50, 0x60, 0x70]))
    s.ch("s_out", stabs("e1", [0x70, 0x60, 0x50, 0x40, 0x30, 0x30, 0x30, 0x30]))
    s.row("d_in", rest_chain(s, 8), "s_in")
    s.row("d_in2", "b_a", "s_in2")
    s.row("d_bu", "b_a", "s_bu")
    s.row("d_dr", "b_a", "s_dr")
    s.row("d_dr", "b_a", "s_dr2")
    s.row("d_br", "b_br", "s_br")
    s.row("d_bu", "b_a", "s_bu")
    s.row("d_dr", "b_a", "s_dr2")
    s.row("d_dr", "b_a", "s_dr")
    s.row("d_out", "b_out", "s_out")
    return s


@song
def joyport_electro():
    s = Song("JOYPORT ELECTRO", 128, "electro", "E-minor: plucked filtered pulse bass, a staccato PWM riff, "
             "tom fills at three pitches, rims and claps; a sync lead takes over in the second drop.")
    s.ins("rim", 0x0C)
    s.ins("tom", 0x0A)
    common_kit(s, r="rim", T=("tom", "A-4"), t=("tom", "E-4"), l=("tom", "B-3"))
    s.ins("bass", 0x12, ad=0x07, sr=0x00)
    s.ins("riff", 0x13, ad=0x06, sr=0x00, vib=0)
    s.ins("sync", 0x15)
    s.ins("zap", 0x1F)
    s.ins("laser", 0x1D)
    s.dr("e0", "k...k...k...k..r")
    s.dr("e1", "k.h.k.hck.h.k.hr")
    s.dr("e2", "k.hrk.hck.hrkkhr")
    s.dr("e3", "k.h.c.hrk.hkc.hr")
    s.dr("et", "k.h.k.h.T.Tt.tll")
    s.dr("eu", "k.h.k.h.TTttllcc")
    s.dr("ex", "k.xrk.hck.hrkkhr")
    s.dr("eb", "r..r..r.T..t..l.")
    s.ph("eb1", "E-2 . E-3 . . E-2 . G-2 . E-2 . . D-2 . E-2 B-1", "bass")
    s.ph("eb2", "E-2 . E-3 . . E-2 . G-2 . A-2 . G-2 . E-2 D-2 .", "bass")
    s.ph("eb3", "E-2 . . . . . . . E-2 . . . . . . .", "bass")
    s.ph("r1", "B-4 . B-4 . . B-4 . D-5 . . E-5 . D-5 . B-4 .", "riff")
    s.ph("r2", "B-4 . B-4 . . B-4 . D-5 . . G-5 . F#5 . D-5 .", "riff")
    s.ph("s1", "E-5 . . . G-5 . E-5 . . . D-5 . B-4 . . -", "sync")
    s.ph("s2", "E-5 . . . G-5 . A-5 . . . G-5 . E-5 . D-5 -", "sync")
    s.ph("z1", "C-5@zap . . . . . . . . . . . C-5@zap . C-5@zap .")
    s.ph("z2", ". . . . . . . . E-5@laser . . . E-5@laser . E-5@laser E-5@laser")
    tr = [0, 0, -4, -2]
    s.ch("d_in", ["e0"] * 6 + ["e1", "et"])
    s.ch("d_a", ["e1", "e1", "e1", "et", "e1", "e2", "e3", "eu"])
    s.ch("d_dr", ["ex", "e2", "e1", "e3", "e2", "e2", "e3", "et"])
    s.ch("d_dr2", ["ex", "e2", "e1", "e3", "e2", "e2", "e3", "eu"])
    s.ch("d_br", ["eb"] * 7 + ["eu"])
    s.ch("d_out", ["ex", "e1", "e1", "e1", "e0", "e0", "e0", "e0"])
    s.ch("b_a", [(b, t) for b, t in zip(["eb1", "eb1", "eb1", "eb2"] * 2, tr * 2)])
    s.ch("b_br", [("eb3", t) for t in tr * 2])
    s.ch("b_out", [(b, t) for b, t in zip(["eb1", "eb1", "eb1", "eb2"], tr)] + ["rest", "silent", "silent", "silent"])
    s.ch("l_bu", ["z1", "silent", "silent", "z2"] * 2)
    s.ch("l_a", [(r, t) for r, t in zip(["r1", "r1", "r1", "r2"] * 2, tr * 2)])
    s.ch("l_br", ["s1", "silent", "s2", "rest", "s1", "silent", "z1", "z2"])
    s.ch("l_b", [(r, t) for r, t in zip(["s1", "s2"] * 4, tr * 2)])
    s.ch("l_out", ["z1", "silent", "silent", "silent", "z2", "silent", "silent", "silent"])
    r8 = rest_chain(s, 8)
    s.row("d_in", r8, r8)
    s.row("d_a", "b_a", r8)
    s.row("d_a", "b_a", "l_bu")
    s.row("d_dr", "b_a", "l_a")
    s.row("d_dr2", "b_a", "l_a")
    s.row("d_br", "b_br", "l_br")
    s.row("d_a", "b_a", "l_bu")
    s.row("d_dr", "b_a", "l_b")
    s.row("d_dr2", "b_a", "l_b")
    s.row("d_out", "b_out", "l_out")
    return s


@song
def kernal_panic():
    s = Song("KERNAL PANIC", 138, "hard / industrial", "E phrygian: rolling filtered pulse bass, snare-heavy beat, "
             "ring-modulated bells on the bass voice, noise stabs, lasers and zaps, noise risers into each drop.")
    common_kit(s)
    s.ins("bass", 0x12, ad=0x07, sr=0x00, rm=0x61)
    s.ins("ring", 0x16)
    s.ins("nz", 0x00, wave=0x80, ad=0x08, sr=0x00)
    s.ins("rise", 0x1E)
    s.ins("laser", 0x1D)
    s.ins("zap", 0x1F)
    s.dr("h1", "k.h.k.h.k.h.k.h.")
    s.dr("h2", "k.hhk.hsk.hhk.hs")
    s.dr("h3", "k.hhc.hsk.hhc.hs")
    s.dr("hr", "k.s.k.s.ksssksss")
    s.dr("hx", "k.xhk.hsk.hhk.hs")
    s.dr("hb", "..h...h...h..sss")
    s.dr("hs", "ssssssssssssssss")
    B1 = ". E-2 E-2 E-2 . E-2 E-2 F-2 . E-2 E-2 E-2 . E-2 G-2 F-2"
    B2 = ". E-2 E-2 E-3 . E-2 F-2 E-2 . E-2 E-2 G-2 . F-2 E-2 D-2"
    for x in range(0x20, 0xF1, 0x10):
        s.ph("p%02x" % x, cut(B1, x, (7, 15), 0x20), "bass")
        s.ph("q%02x" % x, cut(B2, x, (3, 11), 0x20), "bass")
    s.ph("i1", "E-4 . . E-4 . . F-4 . . . E-4 . . . . -", "ring")
    s.ph("i2", "E-4 . . E-4 . . F-4 . . . G-4 . F-4 . . -", "ring")
    s.ph("n1", ". . C-6 . . . C-6 . . . C-6 . . C-6 C-6 .", "nz")
    s.ph("n2", ". . C-6 . . . G-5 . . . C-6 . G-5 . E-5 .", "nz")
    s.ph("z1", "C-5@zap . . . . . . . . . . . C-5@zap . C-5@zap .")
    s.ph("z2", "E-5@laser . . . . . . . E-5@laser . . . E-5@laser . E-5@laser .")
    s.ph("ris", "E-3 . . . . . . . . . . . . . . .", "rise")
    s.ph("ris2", ". . . . . . . . . . . . . . . -", "rise")

    def bass(xs, kinds="pppq"):
        return ["%s%02x" % (kinds[i % len(kinds)], x) for i, x in enumerate(xs)]

    s.ch("d_in", ["h1"] * 7 + ["hr"])
    s.ch("d_a", ["h1", "h2", "h1", "h2", "h1", "h2", "h3", "hr"])
    s.ch("d_bu", ["h2", "h2", "h3", "h2", "hr", "hr", "hs", "hs"])
    s.ch("d_dr", ["hx", "h2", "h2", "h3", "h2", "h2", "h3", "hr"])
    s.ch("d_br", ["hb"] * 6 + ["hs", "hs"])
    s.ch("d_out", ["hx", "h2", "h2", "h1", "h1", "h1", "h1", "hx"])
    s.ch("b_in", bass([0x20, 0x20, 0x30, 0x30, 0x40, 0x40, 0x50, 0x50]))
    s.ch("b_bu", bass([0x50, 0x60, 0x70, 0x80, 0x90, 0xA0, 0xB0, 0xC0]))
    s.ch("b_dr", bass([0xC0, 0xB0, 0xC0, 0xD0, 0xC0, 0xB0, 0xD0, 0xE0]))
    s.ch("b_dr2", [(b, t) for b, t in zip(bass([0xD0, 0xC0, 0xD0, 0xE0] * 2), [0, 0, 0, 0, 1, 1, 0, 0])])
    s.ch("b_br", bass([0x30, 0x30, 0x40, 0x40, 0x50, 0x60, 0x70, 0x80], "pq"))
    s.ch("b_out", bass([0xC0, 0xA0, 0x80, 0x60, 0x40, 0x30]) + ["rest", "silent"])
    s.ch("l_bu", ["n1", "n1", "n1", "n2", "z1", "z2", "ris", "ris2"])
    s.ch("l_dr", ["i1", "n1", "i2", "z1", "i1", "n2", "i2", "z2"])
    s.ch("l_dr2", ["i1", "i2", "i1", "i2", ("i1", 1), ("i2", 1), "i1", "z1"])
    s.ch("l_br", ["i1", "silent", "i2", "silent", "n1", "n2", "ris", "ris2"])
    s.ch("l_out", ["z1", "n1", "n1", "n2", "silent", "silent", "z2", "rest"])
    r8 = rest_chain(s, 8)
    s.row("d_in", r8, r8)
    s.row("d_a", "b_in", r8)
    s.row("d_bu", "b_bu", "l_bu")
    s.row("d_dr", "b_dr", "l_dr")
    s.row("d_dr", "b_dr2", "l_dr2")
    s.row("d_br", "b_br", "l_br")
    s.row("d_dr", "b_dr", "l_dr")
    s.row("d_dr", "b_dr2", "l_dr2")
    s.row("d_bu", "b_bu", "l_bu")
    s.row("d_out", "b_out", "l_out")
    return s


@song
def basic_house():
    s = Song("BASIC HOUSE", 124, "piano house", "C-Am-F-G: decaying pulse chords in a syncopated piano rhythm, "
             "a slow low-pass pad in the intro and the break, off-beat saw bass, open hats.")
    common_kit(s)
    s.ins("pno", 0x00, pw=0x500, ad=0x0A, sr=0x00)
    s.ins("pad", 0x17)
    s.ins("bass", 0x0F, ad=0x06, sr=0x00)
    s.dr("y0", "k...k...k...k...")
    s.dr("y1", "k.o.k.o.k.o.k.o.")
    s.dr("y2", "k.ohk.o.k.ohk.oh")
    s.dr("yc", "k.ohc.o.k.ohc.oh")
    s.dr("yx", "k.xhk.o.k.ohk.oh")
    s.dr("yf", "k.ohk.o.k.s.ssss")
    s.dr("yb", "..o...o...o..co.")
    s.dr("y9", "x...............")
    P1 = "C-4:C{0} . . C-4:C{0} . . C-4:C{0} . . . C-4:C{0} . C-4:C{0} . . ."
    P2 = "C-4:C{0} . . C-4:C{0} . . C-4:C{0} . C-4:C{0} . . C-4:C{0} . . C-4:C{0} ."
    s.ph("pM1", P1.format("47"), "pno")
    s.ph("pm1", P1.replace("C-4", "A-3").format("37"), "pno")
    s.ph("pM2", P2.format("47"), "pno")
    s.ph("pm2", P2.replace("C-4", "A-3").format("37"), "pno")
    s.ph("aC", "C-4:C47 . . . . . . . . . . . . . . .", "pad")
    s.ph("aA", "A-3:C37 . . . . . . . . . . . . . . .", "pad")
    s.ph("hb", ". . C-2 . . . C-2 . . . C-2 . . . C-2 C-3", "bass")
    s.ph("hb2", ". . C-2 . . C-3 C-2 . . . C-2 . . C-3 C-2 .", "bass")
    prog = [0, -3, 5, 7]

    def four(maj, mnr):
        return [maj, mnr, (maj, 5), (maj, 7)]

    s.ch("d_in", ["y0", "y0", "y0", "y1", "y1", "y1", "y1", "yf"])
    s.ch("d_a", ["y1", "y2", "y1", "y2", "y1", "y2", "yc", "yf"])
    s.ch("d_dr", ["yx", "y2", "y2", "yc", "y2", "y2", "yc", "yf"])
    s.ch("d_br", ["y9"] + ["yb"] * 6 + ["yf"])
    s.ch("d_out", ["yx", "y2", "y2", "y1", "y1", "y1", "y0", "y9"])
    s.ch("b_a", [("hb", t) for t in prog] * 2)
    s.ch("b_b", [("hb", t) for t in prog] + [("hb2", t) for t in prog])
    s.ch("b_out", [("hb", t) for t in prog] + ["rest", "silent", "silent", "silent"])
    s.ch("a_pad", four("aC", "aA") * 2)
    s.ch("a_mix", four("aC", "aA") + four("pM1", "pm1"))
    s.ch("p_a", four("pM1", "pm1") * 2)
    s.ch("p_b", four("pM2", "pm2") * 2)
    s.ch("p_out", four("pM1", "pm1") + four("aC", "aA")[:3] + ["rest"])
    s.row("d_in", rest_chain(s, 8), "a_pad")
    s.row("d_a", "b_a", "a_mix")
    s.row("d_dr", "b_a", "p_a")
    s.row("d_dr", "b_b", "p_a")
    s.row("d_br", "rest8", "a_pad")
    s.row("d_a", "b_a", "a_mix")
    s.row("d_dr", "b_b", "p_b")
    s.row("d_dr", "b_b", "p_b")
    s.row("d_dr", "b_a", "p_a")
    s.row("d_out", "b_out", "p_out")
    return s


@song
def petscii_bounce():
    s = Song("PETSCII BOUNCE", 130, "chiptune techno", "G-Em-C-D: octave-bouncing pulse bass, table-arpeggio "
             "chord stabs (major and minor presets), a PWM melody with vibrato in the second drop.")
    common_kit(s)
    s.ins("bass", 0x0E, ad=0x06, sr=0x00)
    s.ins("maj", 0x1A, ad=0x06, sr=0x00)
    s.ins("min", 0x1B, ad=0x06, sr=0x00)
    s.ins("lead", 0x13)
    s.ins("rise", 0x1E)
    s.dr("p0", "k...k...k...k...")
    s.dr("p1", "k.h.k.h.k.h.k.h.")
    s.dr("p2", "k.h.k.hsk.h.k.hs")
    s.dr("pc", "k.h.s.h.k.h.s.hs")
    s.dr("px", "k.x.k.hsk.h.k.hs")
    s.dr("pf", "k.h.k.h.k.s.s.ss")
    s.dr("pr", "s.s.s.s.ssssssss")
    s.dr("pb", "..h...h.c.h...ho")
    s.ph("bb", "G-2 . G-3 . G-2 . G-3 . G-2 . G-3 . G-2 . G-3 G-3", "bass")
    s.ph("bb2", "G-2 . G-3 . G-2 . G-3 . G-2 G-2 G-3 . G-2 . A-2 B-2", "bass")
    s.ph("bh", "G-2 . . . . . . . G-2 . . . . . . .", "bass")
    R = ". . {0} . . {0} . . {0} . . {0} . {0} {0} ."
    s.ph("cG", R.format("G-4"), "maj")
    s.ph("cE", R.format("E-4"), "min")
    s.ph("cC", R.format("C-5"), "maj")
    s.ph("cD", R.format("D-5"), "maj")
    s.ph("m1", "D-5 . B-4 . D-5 . G-5 . . . F#5 . G-5 . A-5 .", "lead")
    s.ph("m2", "B-5 . . . G-5 . E-5 . . . G-5 . B-4 . . .", "lead")
    s.ph("m3", "C-5 . E-5 . G-5 . C-6 . . . B-5 . G-5 . E-5 .", "lead")
    s.ph("m4", "F#5 . . . A-5 . . . F#5 . D-5 . A-4 . - .", "lead")
    s.ph("ris", "G-3 . . . . . . . . . . . . . . .", "rise")
    s.ph("ris2", ". . . . . . . . . . . . . . . -", "rise")
    prog = [0, -3, -7, -5]
    s.ch("d_in", ["p0"] * 3 + ["p1"] * 4 + ["pf"])
    s.ch("d_a", ["p1", "p2"] * 3 + ["pc", "pf"])
    s.ch("d_bu", ["p1", "p2", "p1", "p2", "pc", "pc", "pr", "pr"])
    s.ch("d_dr", ["px", "p2", "p1", "p2", "p1", "p2", "pc", "pf"])
    s.ch("d_br", ["pb"] * 7 + ["pr"])
    s.ch("d_out", ["px", "p2", "p1", "p1", "p0", "p0", "p0", "p0"])
    s.ch("b_a", [("bb", t) for t in prog] * 2)
    s.ch("b_b", [("bb", t) for t in prog] + [("bb", t) for t in prog[:3]] + [("bb2", -5)])
    s.ch("b_br", [("bh", t) for t in prog] * 2)
    s.ch("b_out", [("bb", t) for t in prog] + ["rest", "silent", "silent", "silent"])
    s.ch("c_a", ["cG", "cE", "cC", "cD"] * 2)
    s.ch("c_bu", ["cG", "cE", "cC", "cD", "cG", "cE", "ris", "ris2"])
    s.ch("m_a", ["m1", "m2", "m3", "m4"] * 2)
    s.ch("m_br", ["m1", "m2", "m3", "m4", "cG", "cE", "ris", "ris2"])
    s.ch("c_out", ["cG", "cE", "cC", "cD", "cG", "silent", "silent", "rest"])
    r8 = rest_chain(s, 8)
    s.row("d_in", r8, r8)
    s.row("d_a", "b_a", r8)
    s.row("d_bu", "b_a", "c_bu")
    s.row("d_dr", "b_a", "c_a")
    s.row("d_dr", "b_b", "c_a")
    s.row("d_br", "b_br", "m_br")
    s.row("d_dr", "b_a", "m_a")
    s.row("d_dr", "b_b", "m_a")
    s.row("d_dr", "b_b", "c_a")
    s.row("d_out", "b_out", "c_out")
    return s


@song
def under_the_rom():
    s = Song("UNDER THE ROM", 132, "dark rolling", "G minor with a flat-second turn: a rolling PWM bass "
             "whose low-pass X opens and closes over minutes, a plucked saw motif, a slow string line.")
    s.ins("rim", 0x0C)
    common_kit(s, r="rim")
    s.ins("bass", 0x12, ad=0x07, sr=0x00, rm=0x51)
    s.ins("mot", 0x14, ad=0x08, sr=0x00, vib=0)
    s.ins("str", 0x19)
    s.ins("rise", 0x1E)
    s.dr("q0", "k...k...k...k...")
    s.dr("q1", "k.h.k.h.k.h.k.h.")
    s.dr("q2", "k.hrk.h.k.hrk.hr")
    s.dr("q3", "k.hrc.h.k.hrc.hh")
    s.dr("qh", "k.hhk.hhk.hhk.hh")
    s.dr("qx", "k.xrk.h.k.hrk.hr")
    s.dr("qf", "k.h.k.hck.c.cccc")
    s.dr("qb", "..h.r.h...h.r..o")
    B1 = ". G-2 G-2 G-1 . G-2 G-2 G-1 . G-2 G-2 G-1 . G-2 G#2 G-1"
    B2 = ". G-2 G-2 G-1 . G-2 G-2 G-1 . A#2 A#2 G-1 . G-2 F-2 D-2"
    for x in range(0x18, 0x99, 0x10):
        s.ph("u%02x" % x, cut(B1, x, (1, 9), 0x18), "bass")
        s.ph("v%02x" % x, cut(B2, x, (1, 9), 0x18), "bass")
    s.ph("m1", "G-4 . . G-4 . . A#4 . . . D-5 . . C-5 . .", "mot")
    s.ph("m2", "G-4 . . G-4 . . A#4 . . . A-4 . . F-4 . .", "mot")
    s.ph("s1", "D-5 . . . . . . . C-5 . . . A#4 . . .", "str")
    s.ph("s2", "A-4 . . . . . . . . . . . G-4 . . -", "str")
    s.ph("ris", "G-3 . . . . . . . . . . . . . . .", "rise")
    s.ph("ris2", ". . . . . . . . . . . . . . . -", "rise")
    tr = [0, 0, -4, 1] * 2

    def bass(xs):
        return [("%s%02x" % ("uuuv"[i % 4], x), t) for i, (x, t) in enumerate(zip(xs, tr))]

    s.ch("d_in", ["q0"] * 4 + ["q1"] * 3 + ["qf"])
    s.ch("d_a", ["q1", "q2", "q1", "q2", "q1", "q2", "q3", "qf"])
    s.ch("d_dr", ["qx", "q2", "qh", "q3", "q2", "qh", "q3", "qf"])
    s.ch("d_br", ["qb"] * 7 + ["qf"])
    s.ch("d_out", ["qx", "q2", "q2", "q1", "q1", "q0", "q0", "q0"])
    s.ch("b_in", bass([0x18, 0x18, 0x28, 0x28, 0x38, 0x38, 0x48, 0x48]))
    s.ch("b_dr", bass([0x58, 0x58, 0x68, 0x68, 0x78, 0x78, 0x88, 0x98]))
    s.ch("b_dr2", bass([0x98, 0x88, 0x78, 0x88, 0x98, 0x88, 0x78, 0x68]))
    s.ch("b_br", bass([0x28] * 4 + [0x38] * 4))
    s.ch("b_out", bass([0x68, 0x58, 0x48, 0x38, 0x28, 0x18])[:6] + ["rest", "silent"])
    s.ch("l_a", [(m, t) for m, t in zip(["m1", "m1", "m2", "m2"] * 2, tr)])
    s.ch("l_br", [(m, t) for m, t in zip(["s1", "s2"] * 3, tr)] + ["ris", "ris2"])
    s.ch("l_b", [(m, t) for m, t in zip(["s1", "s2", "m1", "m2"] * 2, tr)])
    s.ch("l_out", [(m, t) for m, t in zip(["m1", "m1", "m2", "m2"], tr)] + ["silent", "silent", "silent", "rest"])
    r8 = rest_chain(s, 8)
    s.row("d_in", r8, r8)
    s.row("d_a", "b_in", r8)
    s.row("d_a", "b_dr", "l_a")
    s.row("d_dr", "b_dr2", "l_a")
    s.row("d_dr", "b_dr", "l_a")
    s.row("d_br", "b_br", "l_br")
    s.row("d_dr", "b_dr", "l_b")
    s.row("d_dr", "b_dr2", "l_b")
    s.row("d_dr", "b_dr2", "l_a")
    s.row("d_out", "b_out", "l_out")
    return s


@song
def sys_64738():
    s = Song("SYS 64738", 128, "big room", "F minor closer: PWM pad chords, a snare roll that doubles every two bars "
             "into a noise riser and a half-bar gap, then octave saw stabs over the kick and a triangle sub.")
    common_kit(s)
    s.ins("sub", 0x11, ad=0x07, sr=0x00)
    s.ins("big", 0x14, ad=0x09, sr=0x00, vib=0)
    s.ins("pad", 0x18)
    s.ins("rise", 0x1E)
    s.ins("zap", 0x1F)
    s.dr("g0", "k...k...k...k...")
    s.dr("g1", "k.h.k.h.k.h.k.h.")
    s.dr("g2", "k.hhk.h.k.hhk.ho")
    s.dr("gc", "k.h.c.h.k.hhc.hc")
    s.dr("gx", "k.xhk.h.k.hhk.ho")
    s.dr("s4", "s...s...s...s...")
    s.dr("s8", "s.s.s.s.s.s.s.s.")
    s.dr("sg", "ssssssssssssssss")
    s.dr("sz", "ssssssss........")
    s.dr("gb", "x...............")
    s.dr("gh", "..h...h...h...h.")
    O = "{0}:C0C . . {0}:C0C . . {0}:C0C . . . {1}:C0C . . {2}:C0C . ."
    s.ph("L1", O.format("F-4", "G#4", "F-4"), "big")
    s.ph("L2", O.format("F-4", "C#5", "C-5"), "big")
    s.ph("L3", O.format("D#4", "C-5", "G#4"), "big")
    s.ph("L4", O.format("G-4", "A#4", "G-4"), "big")
    s.ph("L4b", "G-4:C0C . . G-4:C0C . . G-4:C0C . G-4:C0C . G-4:C0C . G-4:C0C G-4:C0C G-4:C0C -", "big")
    s.ph("sb", ". . F-2 . . . F-2 . . . F-2 . . . F-2 .", "sub")
    s.ph("sb2", "F-2 . F-2 . . . F-2 . . . F-2 . F-2 . F-2 .", "sub")
    s.ph("aF", "F-3:C37 . . . . . . . . . . . . . . .", "pad")
    s.ph("aD", "C#3:C47 . . . . . . . . . . . . . . .", "pad")
    s.ph("aA", "G#3:C47 . . . . . . . . . . . . . . .", "pad")
    s.ph("aE", "D#3:C47 . . . . . . . . . . . . . . -", "pad")
    s.ph("ris", "F-3 . . . . . . . . . . . . . . .", "rise")
    s.ph("ris2", ". . . . . . . . - . . . . . . .", "rise")
    s.ph("zz", ". . . . . . . . . . . . C-5@zap . C-5@zap C-5@zap")
    prog = [0, -4, 3, -2]
    s.ch("d_in", ["g0"] * 4 + ["g1"] * 3 + ["g2"])
    s.ch("d_a", ["g1", "g2"] * 3 + ["gc", "s8"])
    s.ch("d_bu", ["s4", "s4", "s8", "s8", "sg", "sg", "sg", "sz"])
    s.ch("d_dr", ["gx", "g2", "g2", "gc", "g2", "g2", "gc", "s8"])
    s.ch("d_dr2", ["gx", "g2", "g2", "gc", "g2", "g2", "gc", "sz"])
    s.ch("d_br", ["gb"] + ["gh"] * 7)
    s.ch("d_out", ["gx", "g2", "g2", "g1", "g1", "g0", "g0", "gb"])
    s.ch("b_a", [("sb", t) for t in prog] * 2)
    s.ch("b_b", [("sb", t) for t in prog] + [("sb2", t) for t in prog])
    s.ch("b_bu", [("sb", t) for t in prog] + [("sb2", t) for t in prog[:3]] + ["rest"])
    s.ch("b_out", [("sb", t) for t in prog] + [("sb", 0), "rest", "silent", "silent"])
    s.ch("a_pad", ["aF", "aD", "aA", "aE"] * 2)
    s.ch("a_bu", ["aF", "aD", "aA", "aE", "aF", "zz", "ris", "ris2"])
    s.ch("l_dr", ["L1", "L2", "L3", "L4", "L1", "L2", "L3", "L4b"])
    s.ch("a_out", ["aF", "aD", "aA", "aE", "aF", "silent", "silent", "silent"])
    r8 = rest_chain(s, 8)
    s.row("d_in", r8, "a_pad")
    s.row("d_a", "b_a", "a_pad")
    s.row("d_bu", "b_bu", "a_bu")
    s.row("d_dr", "b_a", "l_dr")
    s.row("d_dr2", "b_b", "l_dr")
    s.row("d_br", r8, "a_pad")
    s.row("d_bu", "b_bu", "a_bu")
    s.row("d_dr", "b_b", "l_dr")
    s.row("d_dr2", "b_b", "l_dr")
    s.row("d_out", "b_out", "a_out")
    return s


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    out = args[0] if args else os.path.join(ROOT, "build", "songs")
    os.makedirs(out, exist_ok=True)
    for f in SONGS:
        s = f()
        data = s.file()
        path = os.path.join(out, s.stem + ".sidj")
        open(path, "wb").write(data)
        t = s.seconds()
        print("%-24s %-16s %-12s %3d BPM %3d bars %d:%02d %5d bytes  %s" % (
            os.path.relpath(path), s.title, s.style, s.bpm, s.bars(), t // 60, t % 60, len(data),
            " ".join("%s %d" % kv for kv in s.counts.items())))


if __name__ == "__main__":
    main()
