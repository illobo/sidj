#!/usr/bin/env python3
"""T.A.S.T.E (The Approximate SidJ Transverter-Encoder) in VICE (x64sc, warp, true drive, fresh
.d64 on drive 8, remote monitor port 6512).

Generates test PSIDs from tests/tx_tune.asm (a tiny row player with known
notes, instruments, gate lengths and hard restart; a VBI tune with two
subtunes, a CIA-speed tune, an RSID and a tune at $a000), drives the
transcriber through the keyboard buffer (waiting on its ui_state byte),
extracts the written projects with c1541 and checks them against a Python
model of the same rules (notes per step, instruments, K, groove, tempo,
song/chain structure, allocation bits, voice selection, start/length,
frames-per-step guess). Finally SIDJ itself loads one of them (fio_load).

Runs twice: without an REU (UI walk-through, refusals, the self-check that
catches a tune writing into T.A.S.T.E) and with a 512 KB REU (a tune at
$a000, one writing RAM outside its load range, a 768-step slice).

Usage: tx_test.py [noreu|reu]
"""
import math, os, re, subprocess, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fileio_test as F

ROOT = F.ROOT
BUILD = F.BUILD
TMP = os.path.join(BUILD, "tx_test")
F.TMP = TMP
F.D64 = D64 = os.path.join(TMP, "tx.d64")
F.PORT = 6512
TX = os.path.join(BUILD, "taste.prg")
UI_STATE = 0xA003
ST_FILES, ST_OPTS, ST_YN, ST_MSG = 1, 2, 3, 4
DOWN, UP, RIGHT, LEFT, RET, DEL, F1 = 0x11, 0x91, 0x1D, 0x9D, 0x0D, 0x14, 0x85
PAL, NTSC = 985248.0, 1022727.0
sys.path.insert(0, os.path.join(ROOT, "tools"))
import sidj2sid

check, failures = F.check, F.failures

# ---------------------------------------------------------------------------
# Test tunes

# instruments: wave, AD, SR, PW lo, PW hi, kind (0 plain, 1 drum, 2 test bit first), gate length
INSTR = [
    (0x40, 0x09, 0xA0, 0x00, 0x08, 0, 0),   # 0 pulse
    (0x20, 0x0A, 0x80, 0x00, 0x00, 0, 0),   # 1 saw
    (0x10, 0x00, 0xF0, 0x00, 0x04, 0, 2),   # 2 triangle, gate 2 frames
    (0x40, 0x00, 0xA9, 0x80, 0x03, 1, 0),   # 3 drum: noise first
    (0x40, 0x22, 0x55, 0x00, 0x06, 2, 0),   # 4 test bit first, then pulse
    (0x40, 0x09, 0xA0, 0x00, 0x08, 0, 0),   # 5 = 0 again (dedupes)
]
OFF = "off"


def song_a():
    """speed 6, 40 rows; voice 1 repeats every 16 rows (dedupe), voice 2
    staccato every 2nd row (K02), voice 3 drum + gate-off rows (K00)"""
    rows = []
    for r in range(40):
        v1 = (36 + [0, 2, 4, 5, 7, 9, 11, 12][r % 8] + (12 if r % 16 >= 8 else 0), 0 if r % 2 == 0 else 1)
        v2 = (48 + (r % 5), 2) if r % 2 == 0 else None
        v3 = (24, 3) if r % 4 == 0 else (OFF, 0) if r % 4 == 2 else None
        rows.append([v1, v2, v3])
    return rows, 6


def song_b():
    """speed 4: voice 1 test-bit instrument, voice 3 a few notes of instrument 5 (= 0)"""
    rows = []
    for r in range(24):
        rows.append([(60 + r % 3, 4), None, (40, 5) if r % 6 == 0 else None])
    return rows, 4


def song_long():
    """speed 2, 250 rows: > 512 steps at 1 frame/step (REU only)"""
    rows = []
    for r in range(250):
        rows.append([(36 + (r * 7) % 24, r % 3), (48 + r % 5, 1) if r % 3 == 0 else None,
                     (24, 3) if r % 8 == 0 else (OFF, 0) if r % 8 == 5 else None])
    return rows, 2


def song_c():
    """speed 3 (CIA tune)"""
    rows = []
    for r in range(48):
        rows.append([(30 + r % 12, 1), (50, 0) if r % 4 == 0 else None, None])
    return rows, 3


def freq_table(clock, cents):
    return [min(65535, int(round(440.0 * 2 ** ((n - 57) / 12.0 + cents / 1200.0) * 16777216 / clock))) for n in range(96)]


def note_byte(e):
    if e is None:
        return 0, 0
    if e[0] == OFF:
        return 0xFF, 0
    return e[0] + 1, e[1]


def make_tune(songs, load=0x1000, cia=False, latch=0, cents=30, clock=PAL, wild=0):
    os.makedirs(TMP, exist_ok=True)
    with open(os.path.join(TMP, "tx_tune_data.inc"), "w") as f:
        f.write("LOAD = $%04x\nCIA = %d\nLATCH = %d\nWILD = $%04x\n" % (load, 1 if cia else 0, latch, wild))
    t = []
    t.append("sp_lo .byte " + ", ".join("<song%d" % i for i in range(len(songs))))
    t.append("sp_hi .byte " + ", ".join(">song%d" % i for i in range(len(songs))))
    t.append("s_speed .byte " + ", ".join(str(s[1]) for s in songs))
    t.append("s_rows .byte " + ", ".join(str(len(s[0])) for s in songs))
    for name, col in (("i_wave", 0), ("i_ad", 1), ("i_sr", 2), ("i_pwlo", 3), ("i_pwhi", 4), ("i_kind", 5), ("i_glen", 6)):
        t.append("%s .byte %s" % (name, ", ".join(str(i[col]) for i in INSTR)))
    ft = freq_table(clock, cents)
    t.append("f_lo .byte " + ", ".join(str(x & 255) for x in ft))
    t.append("f_hi .byte " + ", ".join(str(x >> 8) for x in ft))
    for i, (rows, speed) in enumerate(songs):
        t.append("song%d" % i)
        for row in rows + [[None, None, None]]:
            b = []
            for e in row:
                b += note_byte(e)
            t.append("  .byte " + ", ".join(str(x) for x in b))
    with open(os.path.join(TMP, "tx_tune_tables.inc"), "w") as f:
        f.write("\n".join(t) + "\n")
    out = os.path.join(TMP, "tune.prg")
    r = subprocess.run(["64tass", "-a", "-B", "-I", TMP, os.path.join(ROOT, "tests", "tx_tune.asm"), "-o", out],
                       capture_output=True, text=True)
    if r.returncode:
        sys.exit(r.stdout + r.stderr)
    return open(out, "rb").read()


def psid(prg, songs, name, cia_mask=0, magic=b"PSID", ntsc=False):
    pad = lambda s: s.encode("latin-1")[:32].ljust(32, b"\0")
    load = prg[0] | prg[1] << 8
    flags = (2 if ntsc else 1) << 2 | 2 << 4
    hdr = (magic + (2).to_bytes(2, "big") + (0x7C).to_bytes(2, "big") + (0).to_bytes(2, "big")
           + load.to_bytes(2, "big") + (load + 3).to_bytes(2, "big")
           + songs.to_bytes(2, "big") + (1).to_bytes(2, "big") + cia_mask.to_bytes(4, "big")
           + pad(name) + pad("Tester") + pad("2026 Test") + flags.to_bytes(2, "big") + bytes(4))
    assert len(hdr) == 0x7C
    return hdr + prg


# ---------------------------------------------------------------------------
# Python model of the tune's SID writes and of the transcriber's rules


def simulate(rows, speed, nframes, clock=PAL, cents=30):
    """registers after each play call: per voice [freq, ctl, ad, sr, pwlo, pwhi]"""
    ft = freq_table(clock, cents)
    reg = [[0, 0, 0, 0, 0, 0] for _ in range(3)]
    rows = rows + [[None, None, None]]
    fc = row = 0
    out = []
    for f in range(nframes):
        if row < len(rows) - 1:
            for v in range(3):
                e = rows[row][v]
                r = reg[v]
                if fc == 0:
                    if e is not None:
                        if e[0] == OFF:
                            r[1] &= 0xFE
                        else:
                            w, ad, sr, pl, ph, kind, gl = INSTR[e[1]]
                            r[2], r[3], r[4], r[5] = ad, sr, pl, ph
                            if kind == 1:
                                r[0], r[1] = ft[e[0] + 12], 0x81
                            elif kind == 2:
                                r[0], r[1] = ft[e[0]], 0x09
                            else:
                                r[0], r[1] = ft[e[0]], w | 1
                else:
                    if e is not None and e[0] != OFF:
                        w, ad, sr, pl, ph, kind, gl = INSTR[e[1]]
                        if fc == 1 and kind:
                            r[0], r[1] = ft[e[0]], w | 1
                        if gl and gl == fc:
                            r[1] &= 0xFE
                    if fc + 1 == speed:
                        n = rows[row + 1][v]
                        if n is not None and n[0] != OFF:
                            r[1] &= 0xFE
            fc += 1
            if fc == speed:
                fc, row = 0, row + 1
        out.append([list(r) for r in reg])
    return out


def mids(clock):
    m = []
    for n in range(95):
        x = int(round(440.0 * 2.0 ** ((n + 0.5 - 57) / 12.0) * 16777216.0 / clock))
        m.append(min(x, 65535))
    return m


def freq2note(f, mid):
    n = 0
    while n < 95 and f >= mid[n]:
        n += 1
    return n


def guess(frames, sel, start):
    hist = [0] * 64
    prev = [frames[start - 1][v][1] & 1 if start else 0 for v in range(3)]
    last = [None] * 3
    for g in range(500):
        regs = frames[start + g]
        for v in range(3):
            gate = regs[v][1] & 1
            if gate and not prev[v] and sel[v]:
                if last[v] is not None and g - last[v] < 64:
                    hist[g - last[v]] = min(255, hist[g - last[v]] + 1)
                last[v] = g
            prev[v] = gate
    mx = max(hist[2:])
    if mx == 0:
        return 6
    thr = min(max(mx >> 2, 2), mx)
    fps = next(i for i in range(2, 64) if hist[i] >= thr)
    while fps > 32:
        fps >>= 1
    return fps


def transcribe(frames, sel, start, length, fps, notes=True, instr=True, offs=True, clock=PAL):
    """reference of src/tx/capture.asm: steps[v][k] = [note, instr, cmd, val], instruments, grid frame"""
    mid = mids(clock)
    steps = [[[0xFF, 0xFF, 0, 0] for _ in range(length)] for _ in range(3)]
    ins = []
    prev = [frames[start - 1][v][1] & 1 if start else 0 for v in range(3)]
    pend, pstep, wave0 = [0] * 3, [0] * 3, [0] * 3
    offpend, offstep, offsub = [0] * 3, [0] * 3, [0] * 3
    grid, gridfr, step, sub, tail = False, None, 0, 0, 0
    for f in range(start, len(frames)):
        regs = frames[f]
        for v in range(3):
            if not sel[v]:
                continue
            r = regs[v]
            if pend[v]:
                pend[v] = 0
                note = freq2note(r[0], mid) if notes else 48
                idx = 0
                if instr:
                    w = r[1] if (wave0[v] & 8) or not (wave0[v] & 0xF0) else wave0[v]
                    w &= 0xF6
                    if not w & 0xF0:
                        w |= 0x40
                    key = (w, r[2], r[3], r[5] & 15)
                    if key in [k[:4] for k in ins]:
                        idx = [k[:4] for k in ins].index(key)
                    elif len(ins) < 64:
                        idx = len(ins)
                        ins.append(key + (r[4],))
                    else:
                        raise AssertionError("instrument overflow not modelled")
                steps[v][pstep[v]] = [note, idx, 0, 0]
            g = r[1] & 1
            if g:
                if not prev[v]:
                    offpend[v] = 0
                    if not grid:
                        grid, gridfr = True, f
                    if step < length and steps[v][step][0] == 0xFF:
                        pend[v], pstep[v], wave0[v] = 1, step, r[1]
            elif prev[v]:
                if offs and grid and step < length:
                    offpend[v], offstep[v], offsub[v] = 3, step, sub
            elif offpend[v]:
                offpend[v] -= 1
                if offpend[v] == 0 and steps[v][offstep[v]][2] == 0:
                    steps[v][offstep[v]][2:] = [11, offsub[v]]
            prev[v] = g
        if grid:
            if step >= length:
                tail += 1
                if tail >= 5:
                    break
            else:
                sub += 1
                if sub == fps:
                    sub, step = 0, step + 1
    return steps, ins, gridfr


# ---------------------------------------------------------------------------
# Project checks


def channel_steps(m, slot):
    """follow song -> chains -> phrases of one channel: list of 4-byte steps"""
    out = []
    for row in range(256):
        c = m[0xE000 + slot * 256 + row]
        if c == 0xFF:
            break
        for s in range(16):
            p = m[0xC000 + c * 32 + s * 2]
            if p == 0xFF:
                break
            for k in range(16):
                out.append(list(m[0x8000 + p * 64 + k * 4:0x8000 + p * 64 + k * 4 + 4]))
    return out


def bits(m, addr, n):
    return [i for i in range(n) if m[addr + (i >> 3)] >> (i & 7) & 1]


def check_project(label, data, frames, sel, start_s, length, fps, name, tempo, rate=50, guessed=None,
                  notes=True, instr=True, offs=True):
    if data is None:
        check(False, "%s: project file on disk" % label)
        return None
    try:
        blocks = F.parse_project(data)
    except AssertionError as e:
        check(False, "%s: file format (%s)" % (label, e))
        return None
    check(sorted(blocks) == list(range(1, 9)), "%s: blocks 1-8, valid RLE" % label)
    m = sidj2sid.load_project(data)
    steps, ins, gridfr = transcribe(frames, sel, start_s * rate, length, fps, notes, instr, offs)
    check(m[0xF800] == tempo & 255 and m[0xF801] == 0, "%s: tempo byte %d, transpose 0" % (label, m[0xF800]))
    check(bytes(m[0xF810:0xF820]) == F.scr(name), "%s: name %r" % (label, sidj2sid.project_name(m)))
    check(m[0xF600] == fps and m[0xF601] == fps and m[0xF602] == 0, "%s: groove 0 = %d/%d (%s)" % (
        label, m[0xF600], m[0xF601], "guess" if guessed else "set"))
    nph = (length + 15) // 16
    for v in range(3):
        got = channel_steps(m, v)
        if not sel[v]:
            check(got == [], "%s: channel %d empty (voice off)" % (label, v + 1))
            continue
        exp = steps[v] + [[0xFF, 0xFF, 0, 0]] * (nph * 16 - length)
        bad = [k for k in range(len(exp)) if k >= len(got) or got[k] != exp[k]]
        check(len(got) == nph * 16 and not bad, "%s: channel %d, %d steps as modelled%s" % (
            label, v + 1, len(got), " (first diff step %d: %s != %s)" % (bad[0], got[bad[0]] if bad[0] < len(got) else None, exp[bad[0]]) if bad else ""))
    ni = len(ins)
    for i in range(64):
        exp = bytearray(sidj2sid.DEF_INSTR)
        if instr and i < ni:
            w, ad, sr, ph, pl = ins[i]
            exp[1], exp[2], exp[3], exp[4], exp[5] = w, ad, sr, pl, ph
        if bytes(m[0xE600 + i * 16:0xE610 + i * 16]) != bytes(exp):
            check(False, "%s: instrument %02x %s != %s" % (label, i, m[0xE600 + i * 16:0xE610 + i * 16].hex(), exp.hex()))
            break
    else:
        check(True, "%s: %d instruments as modelled, the rest default" % (label, ni if instr else 0))
    # structure: phrases / chains used = allocation bits, nothing beyond
    used_ch = sorted({m[0xE000 + s * 256 + r] for s in range(3) for r in range(256) if m[0xE000 + s * 256 + r] != 0xFF})
    used_ph = sorted({m[0xC000 + c * 32 + s * 2] for c in used_ch for s in range(16) if m[0xC000 + c * 32 + s * 2] != 0xFF})
    check(bits(m, 0xF900, 128) == used_ch and used_ch == list(range(len(used_ch))), "%s: chain alloc bits = used %s" % (label, used_ch))
    check(bits(m, 0xF910, 255) == used_ph and used_ph == list(range(len(used_ph))), "%s: phrase alloc bits = used (%d)" % (label, len(used_ph)))
    check(bits(m, 0xF930, 64) == list(range(max(1, ni if instr else 0))), "%s: instrument alloc bits" % label)
    rows = [len([r for r in range(256) if m[0xE000 + s * 256 + r] != 0xFF]) for s in range(3)]
    check(all(rows[v] == (nph + 3) // 4 for v in range(3) if sel[v]), "%s: song rows per channel %s" % (label, rows))
    # dedupe: no two equal phrases / chains
    phr = [bytes(m[0x8000 + p * 64:0x8040 + p * 64]) for p in used_ph]
    chs = [bytes(m[0xC000 + c * 32:0xC020 + c * 32]) for c in used_ch]
    check(len(set(phr)) == len(phr) and len(set(chs)) == len(chs), "%s: phrases and chains deduplicated (%d, %d)" % (label, len(phr), len(chs)))
    return m, steps, gridfr


# ---------------------------------------------------------------------------
# VICE driving


def state(v):
    s = v.mem(UI_STATE, 1)[0]
    v.go()
    return s


def wait_state(v, want, timeout=180):
    end = time.time() + timeout
    while time.time() < end:
        s = state(v)
        if s == want:
            return True
        time.sleep(0.2)
    print("     timeout waiting for state %d (now %d), row 24: %r" % (want, state(v), row(v, 24)))
    return False


def keys(v, seq, st):
    """type seq (PETSCII codes) while the program waits in state st"""
    seq = list(seq)
    while seq:
        if not wait_state(v, st):
            raise TimeoutError("ui state %d not reached" % st)
        chunk, seq = seq[:8], seq[8:]
        v.write(0x0277, bytes(chunk))
        v.write(0x00C6, bytes([len(chunk)]))
        v.go()
        end = time.time() + 30
        while time.time() < end:
            n = v.mem(0x00C6, 1)[0]
            v.go()
            if n == 0:
                break
            time.sleep(0.1)


def row(v, r):
    t = F.screen_text(bytes(c & 0x7F for c in v.mem(0x0400 + 40 * r, 40)))
    v.go()
    return " ".join(t.replace("@", " ").split())


def text(s):
    return [ord(c) for c in s.upper()]


def tx_labels():
    out = {}
    for line in open(os.path.join(BUILD, "taste.labels")):
        m = re.match(r"(\w+)\s*= \$([0-9a-f]+)", line)
        if m:
            out[m.group(1)] = int(m.group(2), 16)
    return out


def make_disk(name, tunes):
    global D64
    F.D64 = D64 = os.path.join(TMP, name)
    if os.path.exists(D64):
        os.remove(D64)
    files = []
    for fname, data in tunes:
        path = os.path.join(TMP, fname.replace(" ", "_"))
        open(path, "wb").write(data)
        files += ["-write", path, fname]
    subprocess.run(["c1541", "-format", "tx,01", "d64", D64], capture_output=True)
    print(F.c1541(*files, "-list"))


def transcribe_32(v, label):
    """options: 32 steps, frames/step auto, RETURN; wait for the result"""
    keys(v, [DOWN] * 3 + [0x2D] * 3 + [LEFT] * 2 + [RET], ST_OPTS)
    ok = wait_state(v, ST_MSG)
    shot = [row(v, r) for r in (18, 19, 20, 24)]
    print("     ", shot)
    check(ok, "%s: transcription done" % label)
    return shot


def run_noreu(tunes, fa, fb, fc):
    """no REU: the full UI walk-through, refusals, the self-check"""
    print("--- without REU")
    make_disk("tx.d64", tunes)
    v = F.Vice(TX, D64)
    shots = {}
    try:
        check(wait_state(v, ST_FILES), "file list shown")
        names = [row(v, r) for r in range(3, 9)]
        print("     list:", names)
        check(names == ["> TUNE A.SID", "TUNE CIA.SID", "AN RSID.SID", "HIGH.SID", "WILD.SID", "LONG.SID"], "file list: the 6 PRG files")
        check(row(v, 22) == "REU: NO", "file list: REU: NO (%r)" % row(v, 22))

        # 1: tune A, subtune 1, all voices, 32 steps, frames/step auto, default name
        keys(v, [RET], ST_FILES)
        check(wait_state(v, ST_OPTS), "tune A loaded, options shown")
        info = [row(v, r) for r in range(2, 7)]
        print("     info:", info)
        check(info[0] == "NAME TEST TUNE A" and info[3].startswith("LOAD $1000-$") and "INIT $1000" in info[3]
              and info[4] == "PLAY $1003 SONGS 2 PAL REU: NO", "tune info: name, load range, init/play, songs, clock, REU")
        check(row(v, 16) == "OUTPUT NAME TEST TUNE A", "default output name from the tune name")
        check(row(v, 9).startswith("VOICES 1 2 3"), "voices row shows 1 2 3: %r" % row(v, 9))
        shots[1] = transcribe_32(v, "1")
        check(shots[1][3] == "SAVED TEST TUNE A", "saved TEST TUNE A")
        keys(v, [0x20], ST_MSG)
        check(wait_state(v, ST_OPTS) and row(v, 12) == "FRAMES/STEP AUTO (GUESS 6)", "options show the guess: %r" % row(v, 12))
        check(v.mem(0x0400 + 12, 16) == bytes(c | 0x80 for c in b" <\x1bT.A.S.T.E.\x1d> ".replace(b"T", b"\x14").replace(b"A", b"\x01").replace(b"S", b"\x13").replace(b"E", b"\x05"))
              and v.mem(0x07F8, 2) == b"\x0d\x0d" and row(v, 1) == "THE APPROXIMATE SIDJ TRANSVERTER-ENCODER", "title ~<[T.A.S.T.E.]>~ (tildes = sprites 0/1): %r / %r" % (row(v, 0), row(v, 1)))
        v.cmd("bank io")
        col = [c & 15 for c in v.mem(0xD800 + 40 * 8, 160)]
        v.cmd("bank ram")
        v.go()
        check(col[120 + 2] == 8 and col[120 + 20] == 13 and col[2] == 5, "colours: cursor row orange, values light green, labels green")

        # 2: subtune 2, voice 1 only, 16 steps, 4 frames/step, name SUB2
        keys(v, [UP] * 3 + [RIGHT, 0x32, 0x33] + [DOWN] * 3 + [LEFT, DOWN] + [RIGHT] * 4 + [DOWN] * 4
             + [DEL] * 16 + text("sub2") + [RET], ST_OPTS)
        check(wait_state(v, ST_MSG), "transcription 2 done")
        shots[2] = [row(v, r) for r in (18, 19, 24)]
        print("     ", shots[2])

        # 3: subtune 1 from 1 s, all voices, 16 steps, auto, notes/instruments/note-offs off, name SLICE
        keys(v, [0x20], ST_MSG)
        keys(v, [UP] * 8 + [LEFT, 0x32, 0x33, DOWN, DOWN, RIGHT, DOWN, DOWN] + [LEFT] * 4
             + [DOWN, RIGHT, DOWN, RIGHT, DOWN, RIGHT, DOWN] + [DEL] * 16 + text("slice") + [RET], ST_OPTS)
        check(wait_state(v, ST_MSG), "transcription 3 done")
        shots[3] = [row(v, r) for r in (18, 19, 24)]
        print("     ", shots[3])
        keys(v, [0x20], ST_MSG)
        check(wait_state(v, ST_OPTS) and row(v, 10) == "START (S) 1 (GRID AT FRAME 54)", "start row shows the grid frame: %r" % row(v, 10))

        # 4: same name again: N keeps it, Y replaces it (now 32 steps)
        keys(v, [UP] * 5 + [RIGHT, RET], ST_OPTS)
        check(wait_state(v, ST_YN) and row(v, 24) == "FILE EXISTS. REPLACE IT? (Y/N)", "existing file: asks before replacing")
        keys(v, [0x4E], ST_YN)
        check(wait_state(v, ST_MSG) and row(v, 24) == "NOT SAVED", "N: not saved")
        keys(v, [0x20], ST_MSG)
        keys(v, [RET], ST_OPTS)
        keys(v, [0x59], ST_YN)
        check(wait_state(v, ST_MSG) and row(v, 24) == "SAVED SLICE", "Y: replaced")

        # 5: CIA tune, 32 steps
        keys(v, [0x20], ST_MSG)
        keys(v, [F1], ST_OPTS)
        keys(v, [DOWN, RET], ST_FILES)
        check(wait_state(v, ST_OPTS), "CIA tune loaded")
        shots[5] = transcribe_32(v, "5")
        check(shots[5][1] == "TEMPO 250 BPM, 3 FRAMES/STEP, 100 HZ", "CIA tune: 100 Hz -> 250 BPM, guess 3")

        # 6: refusals
        keys(v, [0x20], ST_MSG)
        keys(v, [F1], ST_OPTS)
        keys(v, [DOWN, DOWN, RET], ST_FILES)
        time.sleep(1)
        check(wait_state(v, ST_FILES) and row(v, 24) == "RSID NOT SUPPORTED", "RSID refused: %r" % row(v, 24))
        keys(v, [DOWN, RET], ST_FILES)
        time.sleep(1)
        r = row(v, 24)
        check(wait_state(v, ST_FILES) and re.fullmatch(r"NO REU: TUNE \$A000-\$A[0-9A-F]{3} WON'T FIT", r), "no REU: tune at $a000 refused: %r" % r)

        # 7: a tune writing into T.A.S.T.E's code: the self-check stops it cleanly
        keys(v, [DOWN, RET], ST_FILES)
        check(wait_state(v, ST_OPTS), "wild tune loaded (its load range fits)")
        keys(v, [RET], ST_OPTS)
        end = time.time() + 60
        r = ""
        while time.time() < end:
            r = row(v, 24)
            if r.startswith("TUNE OVERWRITES"):
                break
            time.sleep(0.5)
        check(r == "TUNE OVERWRITES T.A.S.T.E. KEY: RESET", "no REU: tune writing into T.A.S.T.E -> clean message: %r" % r)
    finally:
        v.kill()

    print(F.c1541("-list"))
    m1 = check_project("A/1 all", F.extract("test tune a"), fa, [1, 1, 1], 0, 32, 6, "TEST TUNE A", 125, guessed=True)
    m2 = check_project("A/2 voice 1", F.extract("sub2"), fb, [1, 0, 0], 0, 16, 4, "SUB2", 125)
    if m2:
        m = m2[0]
        i = channel_steps(m, 0)[0][1]
        check(m[0xE600 + i * 16 + 1] == 0x40 and m[0xE600 + i * 16 + 2] == 0x22, "A/2: test-bit first frame -> pulse instrument, AD 22")
    m3 = check_project("A/1 slice", F.extract("slice"), fa, [1, 1, 1], 1, 32, 6, "SLICE", 125, guessed=True,
                       notes=False, instr=False, offs=False)
    check_project("CIA", F.extract("test cia"), fc, [1, 1, 1], 0, 32, 3, "TEST CIA", 250, rate=100, guessed=True)
    if m1:
        m, steps, gridfr = m1
        ch1, ch2, ch3 = (channel_steps(m, i) for i in range(3))
        check(ch1[0][:2] == [36, 0] and ch1[1][0] == 38 and ch1[8][0] == 48, "A/1: voice 1 notes C-3, D-3 .. C-4 (detuned +30 cents)")
        check(ch2[0][0] == 48 and ch2[0][2:] == [11, 2] and ch2[1] == [0xFF, 0xFF, 0, 0], "A/1: staccato note with K02, next step empty")
        check(ch3[0][0] == 24 and ch3[2] == [0xFF, 0xFF, 11, 0], "A/1: drum note from the second frame, K00 on the gate-off row")
        di = ch3[0][1]
        check(m[0xE600 + di * 16 + 1] == 0x80 and m[0xE600 + di * 16 + 3] == 0xA9, "A/1: drum instrument: noise (edge frame), SR A9")
        p = [m[0xC000 + m[0xE000] * 32 + 2 * s] for s in range(3)]
        check(p[0] == p[1] and p[2] == 0xFF, "A/1: voice 1 phrases 0 and 1 equal -> one phrase twice, chain of 2")
    if m3:
        m, steps, gridfr = m3
        check(gridfr == 54, "slice: grid starts at the first note after 1 s (frame %s)" % gridfr)
        check(all(s[0] in (48, 0xFF) and s[1] in (0, 0xFF) and s[2] == 0 for v in range(3) for s in channel_steps(m, v)),
              "slice: notes off -> C-4, instruments off -> 00, note-offs off -> no K")


def run_reu(tunes, fa, flong):
    """REU: tunes anywhere outside $d000-$dfff, RAM outside the load range, > 512 steps"""
    print("--- with REU (512 KB)")
    make_disk("tx_reu.d64", tunes)
    v = F.Vice(TX, D64, extra=["-reu", "-reusize", "512"])
    try:
        check(wait_state(v, ST_FILES), "REU: file list shown")
        check(row(v, 22) == "REU: YES", "file list: REU: YES (%r)" % row(v, 22))
        keys(v, [RET], ST_FILES)
        check(wait_state(v, ST_OPTS) and row(v, 6) == "PLAY $1003 SONGS 2 PAL REU: YES", "REU: options show REU: YES")
        shot = transcribe_32(v, "REU A/1")
        check(shot[3] == "SAVED TEST TUNE A", "REU: saved TEST TUNE A")
        keys(v, [0x20], ST_MSG)
        for n, label in ((3, "high"), (4, "wild")):
            keys(v, [F1], ST_OPTS)
            keys(v, [DOWN] * n + [RET], ST_FILES)
            check(wait_state(v, ST_OPTS), "REU: %s tune loaded: %r" % (label, row(v, 5)))
            shot = transcribe_32(v, "REU " + label)
            check(shot[3] == "SAVED %s TUNE" % label.upper(), "REU: saved %s TUNE" % label.upper())
            keys(v, [0x20], ST_MSG)
        # long slice: 768 steps at 1 frame/step
        keys(v, [F1], ST_OPTS)
        keys(v, [DOWN] * 5 + [RET], ST_FILES)
        check(wait_state(v, ST_OPTS), "REU: long tune loaded")
        keys(v, [DOWN] * 3 + [0x2B] * 8 + [DOWN, RIGHT, RET], ST_OPTS)
        ok = wait_state(v, ST_MSG)
        shot = [row(v, r) for r in (18, 19, 20, 24)]
        print("     ", shot)
        check(ok and shot[3] == "SAVED LONG TUNE", "REU: 768-step slice saved")
        keys(v, [0x20], ST_MSG)
        keys(v, [F1], ST_OPTS)
        keys(v, [DOWN, DOWN, RET], ST_FILES)
        time.sleep(1)
        check(wait_state(v, ST_FILES) and row(v, 24) == "RSID NOT SUPPORTED", "REU: RSID refused: %r" % row(v, 24))
    finally:
        v.kill()
    print(F.c1541("-list"))
    check_project("REU A/1", F.extract("test tune a"), fa, [1, 1, 1], 0, 32, 6, "TEST TUNE A", 125, guessed=True)
    check_project("REU high ($a000)", F.extract("high tune"), fa, [1, 1, 1], 0, 32, 6, "HIGH TUNE", 125, guessed=True)
    check_project("REU wild (writes $%04x)" % WILD, F.extract("wild tune"), fa, [1, 1, 1], 0, 32, 6, "WILD TUNE", 125, guessed=True)
    r = check_project("REU long", F.extract("long tune"), flong, [1, 1, 1], 0, 768, 1, "LONG TUNE", 125)
    if r:
        m = r[0]
        rows = len([x for x in range(256) if m[0xE000 + x] != 0xFF])
        check(rows == 12, "REU long: 12 song rows (> the 8 of 512 steps): %d" % rows)


WILD = 0


def main():
    global WILD
    os.makedirs(TMP, exist_ok=True)
    L = tx_labels()
    WILD = L["CODE"] + 0x1008 if "CODE" in L else 0xB008
    check(L.get("CODE", 0xA000) <= WILD < L["VARS"], "wild address $%04x inside T.A.S.T.E's code ($%04x-$%04x)" % (WILD, L.get("CODE", 0xA000), L["VARS"]))
    A1, A2, C, LG = song_a(), song_b(), song_c(), song_long()
    tune_a = psid(make_tune([A1, A2]), 2, "Test Tune A")
    tune_c = psid(make_tune([C], cia=True, latch=9850), 1, "Test CIA", cia_mask=1)
    rsid = psid(make_tune([A1]), 1, "An RSID", magic=b"RSID")
    high = psid(make_tune([A1], load=0xA000), 1, "High Tune")
    wild = psid(make_tune([A1], wild=WILD), 1, "Wild Tune")
    long_ = psid(make_tune([LG]), 1, "Long Tune")
    tunes = [("tune a.sid", tune_a), ("tune cia.sid", tune_c), ("an rsid.sid", rsid), ("high.sid", high),
             ("wild.sid", wild), ("long.sid", long_)]

    fa, fb = simulate(*A1, 4000), simulate(*A2, 4000)
    fc = simulate(*C, 4000)
    flong = simulate(*LG, 4000)
    exp_guess_a = guess(fa, [1, 1, 1], 0)
    exp_guess_c = guess(fc, [1, 1, 1], 0)
    check(exp_guess_a == 6 and exp_guess_c == 3, "model: guess 6 for speed 6, 3 for speed 3 (%d, %d)" % (exp_guess_a, exp_guess_c))

    only = sys.argv[1] if len(sys.argv) > 1 else ""
    if only != "reu":
        run_noreu(tunes, fa, fb, fc)
        sidj_loads()
    if only != "noreu":
        run_reu(tunes, fa, flong)
    print("\n%d failure(s)" % len(failures))
    sys.exit(1 if failures else 0)


def sidj_loads():
    """the editor accepts the file"""
    sidj = os.path.join(BUILD, "sidj.prg")
    L = F.labels()
    v = F.Vice(sidj, D64)
    try:
        time.sleep(4)
        a, c, msg = F.fio(v, L, "dir")
        n = v.mem(F.FIO_DIRCOUNT, 1)[0]
        names = [F.screen_text(v.mem(F.FIO_DIR + 16 * i, 16)) for i in range(n)]
        check(c == 0 and "TEST TUNE A" in names, "SIDJ lists the projects: %s" % names)
        if "TEST TUNE A" in names:
            a, c, msg = F.fio(v, L, "load", names.index("TEST TUNE A"))
            exp = sidj2sid.load_project(F.extract("test tune a"))
            got = v.song()
            want = bytes(exp[0x8000:0xD000] + exp[0xE000:0xFA00])
            check(c == 0 and got == F.saved_part(want), "SIDJ fio_load: ok, memory = the file (%s)" % F.diff(got, F.saved_part(want)))
            F.call(v, L, F.PLAYER + 3, a=0)
            time.sleep(0.5)
            pl = v.mem(F.PL_PLAYING, 1)[0]
            v.go()
            check(pl == 7, "SIDJ plays it (pl_playing=%d)" % pl)
    finally:
        v.kill()


if __name__ == "__main__":
    main()
