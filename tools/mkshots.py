#!/usr/bin/env python3
"""Screenshots of every SIDJ editor screen for the minisite (tools/mksite.py).

python3 tools/mkshots.py [out dir]   (default build/site-shots)

Runs build/sidj.prg in VICE (x64sc, port 6513, REU 512 KB, build/sidj.d64 in
drive 8 so SIDJ.HLP loads), plays the demo song and walks the screens through
the editor's debug hooks (tests/editor/vt.py). Copies the loader, reader,
T.A.S.T.E. and directory shots from the loader test (make test-loader).
"""
import os, re, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
B = os.path.join(ROOT, "build")
OUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(B, "site-shots"))
os.environ.setdefault("SIDJ_VICE_PORT", "6513")
sys.path.insert(0, os.path.join(ROOT, "tests", "editor"))
import vt  # noqa: E402

PRG = os.path.join(B, "sidj.prg")
L = {}
for line in open(PRG.replace(".prg", ".labels")):
    m = re.match(r"(\S+)\s*= \$([0-9a-f]+)", line)
    if m:
        L[m.group(1)] = int(m.group(2), 16)

SC = dict(song=0, chain=1, phrase=2, instr=3, table=4, groove=5, project=6, sid=7, file=8)
KG, KD, F2 = 0x4F, 0x4E, 0x48                   # CLR/HOME, SHIFT + CLR/HOME, SHIFT + F1


def keys(*codes):
    return sum(([("", c), ("", None)] for c in codes), [])


def hold(mod, d):
    return [(mod, None), (mod + d, None), (mod, None), ("", None)]


def m1(a):
    return vt.mem(a, 1)[0]


def goto(sc):
    vt.poke(L["screen"], SC[sc])
    vt.poke(L["need_clear"], 1)
    vt.sleep(0.4)


def shot(name):
    vt.sleep(0.5)
    vt.mon('screenshot "%s" 2' % os.path.join(OUT, name + ".png"))
    print("  " + name)


def main():
    os.makedirs(OUT, exist_ok=True)
    vt.start(PRG, ["-reu", "-reusize", "512", "-drive8type", "1541", "-drive8truedrive",
                   "-8", os.path.join(B, "sidj.d64")])
    try:
        vt.sleep(6)
        for _ in range(100):                    # SIDJ.HLP loads at start-up
            if m1(L["hp_n"]):
                break
            vt.sleep(0.5)
        goto("song")
        vt.script(vt.tap("T"))                  # RETURN: play the demo
        vt.sleep(2)
        shot("song")
        for sc in ("chain", "phrase"):
            goto(sc)
            shot(sc)
        vt.script(keys(KG))
        shot("grid")
        vt.script(keys(KG))
        vt.script(keys(KD))
        shot("drum")
        vt.script(keys(KD))
        for sc in ("instr", "table", "groove", "project", "sid", "file"):
            goto(sc)
            shot(sc)
        goto("song")
        vt.script(keys(F2))
        shot("help")
        vt.script(vt.tap("A"))                  # any key closes the page
        vt.script(hold("S", "L"))               # CTRL + LEFT: live mode
        vt.sleep(1)
        shot("live")
    finally:
        vt.stop()
    for src, name in (("loader_test/menu.png", "loader"), ("loader_test/taste.png", "taste"),
                      ("loader_test/readme.png", "readme"), ("loader_test/manual.png", "manual"),
                      ("loader_test/dir-.png", "dir")):
        p = os.path.join(B, src)
        if os.path.exists(p):
            shutil.copy(p, os.path.join(OUT, name + ".png"))
            print("  " + name + " (copied)")
        else:
            print("  " + name + ": missing, run make test-loader")


if __name__ == "__main__":
    main()
