#!/usr/bin/env python3
"""Demo songs (tools/mksongs.py): file format, limits and references, then
each song rendered to .sid (tools/sidj2sid.py) and played in VICE vsid
(warp, remote monitor on port 6512): pl_playing = 7 and pl_tick advances.
Kills every VICE it starts.

Usage: songs_test.py [DIR]      (default build/songs; run mksongs.py first)
"""
import glob, os, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, os.path.join(ROOT, "tests"))
os.environ["SIDJ_FIO_PORT"] = os.environ.get("SIDJ_SONGS_PORT", "6512")
saved_argv, sys.argv = sys.argv, sys.argv[:1]
import fileio_test                                   # noqa: E402  (Vice, parse_project)
import sidj2sid                                      # noqa: E402
sys.argv = saved_argv

DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "songs")
PHRASES, CHAINS, SONG, INSTR, TABLES = 0x8000, 0xC000, 0xE000, 0xE600, 0xEA00
ALLOC = {"chain": (0xF900, 128), "phrase": (0xF910, 255), "instr": (0xF930, 64), "table": (0xF938, 32)}
PL_PLAYING, PL_TICK, PL_ROW, PL_PSTEP = 0x1020, 0x1023, 0x1028, 0x1048
CMD_A = 1
failures = []


def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures.append(what)


def alloc_set(m, kind):
    a, n = ALLOC[kind]
    return {i for i in range(n) if m[a + (i >> 3)] >> (i & 7) & 1}


def static_checks(path):
    name = os.path.basename(path)
    data = open(path, "rb").read()
    try:
        blocks = fileio_test.parse_project(data)
        check(sorted(blocks) == list(range(1, 9)), "%s: v2 file, blocks 1-8" % name)
    except AssertionError as e:
        check(False, "%s: parse: %s" % (name, e))
        return None
    m = sidj2sid.load_project(data)
    title = sidj2sid.project_name(m)
    stem = os.path.splitext(name)[0]
    check(0 < len(title) <= 16 and title.lower().replace(" ", "_")[:16] == stem and len(stem) <= 16,
          "%s: title %r" % (name, title))
    check(124 <= m[0xF800] <= 140 and m[0xF600:0xF603] == b"\x06\x06\x00", "%s: %d BPM, groove 0 = 6/6"
          % (name, m[0xF800]))
    # song: three channels, rows filled from row 0, nothing in slots 4-6
    song = [[m[SONG + k * 256 + r] for r in range(256)] for k in range(6)]
    nrows = next(r for r in range(257) if r == 256 or song[0][r] == 0xFF)
    ok = nrows > 0 and all(song[k][r] < 0x80 for k in range(3) for r in range(nrows))
    ok &= all(song[k][r] == 0xFF for k in range(3) for r in range(nrows, 256))
    ok &= all(v == 0xFF for k in range(3, 6) for v in song[k])
    check(ok, "%s: %d rows, channels 1-3 only, no gaps" % (name, nrows))
    chains = {song[k][r] for k in range(3) for r in range(nrows)}

    def chain_steps(c):
        out = []
        for s in range(16):
            p = m[CHAINS + c * 32 + s * 2]
            if p == 0xFF:
                break
            out.append(p)
        return out

    lens_ok = all(len({len(chain_steps(song[k][r])) for k in range(3)}) == 1 for r in range(nrows))
    check(lens_ok, "%s: every row's chains equally long" % name)
    phrases = {p for c in chains for p in chain_steps(c)}
    check(all(chain_steps(c) for c in chains), "%s: no empty chains" % name)
    instrs, tables = set(), set()
    bad = []
    for p in phrases:
        for s in range(16):
            n, i, c, v = m[PHRASES + p * 64 + s * 4:PHRASES + p * 64 + s * 4 + 4]
            if not (n < 96 or n == 0xFF) or not (i < 64 or i == 0xFF) or c > 26:
                bad.append((p, s))
            if n < 96 and i == 0xFF:
                bad.append((p, s, "note without instrument"))
            if i < 64:
                instrs.add(i)
            if c == CMD_A and v < 32:
                tables.add(v)
    check(not bad, "%s: phrase steps valid %s" % (name, bad[:3]))
    for i in instrs:
        t = m[INSTR + i * 16 + 14]
        if t != 0xFF:
            tables.add(t)
    used = dict(chain=chains, phrase=phrases, instr=instrs, table=tables)
    for kind, items in used.items():
        a, n = ALLOC[kind]
        check(all(x < n for x in items) and alloc_set(m, kind) == items,
              "%s: %d %ss within %d, alloc bits match" % (name, len(items), kind, n))
    return m


def render(path):
    out = os.path.splitext(path)[0] + ".sid"
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "sidj2sid.py"), path, "-o", out,
                        "--author", "SIDJ"], capture_output=True, text=True)
    check(r.returncode == 0 and os.path.exists(out), "%s: rendered (%s)" % (os.path.basename(out),
                                                                       (r.stdout + r.stderr).strip()))
    return out


def play(sid):
    name = os.path.basename(sid)
    v = fileio_test.Vice(sid, sid=True)
    try:
        time.sleep(3)
        pl = v.mem(PL_PLAYING, 1)[0]
        t0 = v.mem(PL_TICK, 1)[0]
        r0 = v.mem(PL_ROW, 3)
        v.go()
        time.sleep(1)
        t1 = v.mem(PL_TICK, 1)[0]
        pl1 = v.mem(PL_PLAYING, 1)[0]
        for _ in range(4):                     # the monitor may stop the CPU inside a tick: look again
            r1, ps = v.mem(PL_ROW, 3), v.mem(PL_PSTEP, 3)
            if r1[0] == r1[1] == r1[2] and ps[0] == ps[1] == ps[2]:
                break
            v.go()
            time.sleep(0.1)
        check(pl == 7 and pl1 == 7 and t0 != t1, "%s in vsid: pl_playing %d/%d, tick %d -> %d, rows %s -> %s"
              % (name, pl, pl1, t0, t1, list(r0), list(r1)))
        check(r1[0] == r1[1] == r1[2] and ps[0] == ps[1] == ps[2], "%s: channels on the same row and step (%s)"
              % (name, list(ps)))
    finally:
        v.kill()


def main():
    os.makedirs(fileio_test.TMP, exist_ok=True)
    files = sorted(glob.glob(os.path.join(DIR, "*.sidj")))
    check(len(files) == 10, "%d songs in %s" % (len(files), DIR))
    sids = []
    for f in files:
        if static_checks(f) is not None:
            sids.append(render(f))
    for sid in sids:
        if os.path.exists(sid):
            play(sid)
    print("\n%d failure(s)" % len(failures))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
