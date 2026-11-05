#!/usr/bin/env python3
"""Instrument kits in VICE (port 6511, true drive emulation, fresh .d64):
factory kits on the Instrument screen (CTRL + SPACE on PRESET), kit save
(C= + SPACE on the File screen's SV row), kit load (SPACE, SPACE on a kit
file) with table remapping, the cut at instrument 3F, errors, the kit file
format (c1541). Gestures go through the editor's debug key hook; direct
calls through fileio_test's trampoline. Kills only the VICE it started.

Usage: kit_test.py [prg [labels]]
"""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fileio_test as F

F.TMP = os.path.join(F.BUILD, "kit_test")
F.D64 = os.path.join(F.TMP, "kit.d64")
INS, TABLES, ALLOC_T = 0xE600, 0xEA00, 0xF938
DEF = F.DEF_INSTR
BT = dict(U=1, D=2, L=4, R=8, A=0x10, B=0x20, S=0x40, T=0x80)
SC_INSTR, SC_FILE = 3, 8


def keys(v, L, steps, wait=0.6):
    """debug key script: list of button strings, one per frame"""
    data = []
    for b in steps:
        data += [sum(BT[c] for c in b), 0xFF]
    v.write(0x0D00, bytes(data))
    v.write(0x0C01, b"\x00")
    v.write(0x0C00, bytes([len(steps)]))
    v.go()
    for _ in range(600):
        time.sleep(0.1)
        if v.mem(0x0C00, 1)[0] == 0:
            break
    time.sleep(wait)


def msg(v, L):
    return F.screen_text(v.mem(L["msg_buf"], 20))


def instr(v, i):
    return v.mem(INS + 16 * i, 16)


def table(v, t):
    return b"".join(v.mem(TABLES + c * 512 + t * 16, 16) for c in range(6))


def pid(b):
    return (b[0] >> 4) | (b[15] & 0x10)


def alloc_t(v):
    bits = v.mem(ALLOC_T, 4)
    return [t for t in range(32) if bits[t >> 3] >> (t & 7) & 1]


def goto(v, L, screen, row, col=0, instr_no=None):
    if instr_no is not None:
        v.write(L["cur_instr"], bytes([instr_no]))
    v.write(L["rowv"] + screen, bytes([row]))
    v.write(L["colv"] + screen, bytes([col]))
    v.write(L["screen"], bytes([screen]))
    v.write(L["need_clear"], b"\x01")
    v.go()
    time.sleep(0.3)


def empty_table():
    return b"\xff" * 16 + bytes(80)


def main():
    os.makedirs(F.TMP, exist_ok=True)
    L = F.labels()
    if os.path.exists(F.D64):
        os.remove(F.D64)
    import subprocess
    subprocess.run(["c1541", "-format", "kits,01", "d64", F.D64], capture_output=True)
    # a kit file with an unknown version and one that needs 3 tables
    def kitfile(ver, n, tables, instrs):
        return b"SIDK" + bytes([ver, n, len(tables)]) + b"".join(tables) + b"".join(instrs)
    t3 = [bytes([0x81] + [0xFF] * 15) + bytes(80)] * 3
    i3 = [bytes(DEF[:14]) + bytes([k, 0]) for k in range(3)]
    for name, data in (("badver.kit", kitfile(2, 3, t3, i3)), ("three.kit", kitfile(1, 3, t3, i3))):
        p = os.path.join(F.TMP, name)
        open(p, "wb").write(data)
        F.c1541("-write", p, name)

    v = F.Vice(F.PRG, F.D64)
    try:
        time.sleep(4)
        check = F.check
        ids = list(v.mem(L["kit_ids"], 24))
        # ---- factory kits ---------------------------------------------------
        goto(v, L, SC_INSTR, 1, 0, 0x10)
        free0 = [t for t in range(32) if t not in alloc_t(v)]
        keys(v, L, ["S", "SA", "S", ""])
        got = [instr(v, 0x10 + i) for i in range(8)]
        check([pid(b) for b in got] == ids[:8], "factory kit 0 -> instruments 10-17: preset ids %s" % [pid(b) for b in got])
        tb = [b[14] for b in got]
        withtbl = [t for t in tb if t < 32]
        check(len(withtbl) == len(set(withtbl)) and all(t in alloc_t(v) for t in withtbl) and set(withtbl) <= set(free0),
              "factory kit: own new tables, allocated (%s)" % tb)
        check(all(table(v, t) != empty_table() for t in withtbl), "factory kit: tables filled")
        check(msg(v, L) == "DRUMS    10-17", "message %r" % msg(v, L))
        check(instr(v, 0x18) == DEF and v.mem(L["cur_instr"], 1)[0] == 0x10, "instrument 18 untouched, cursor instrument kept")
        keys(v, L, ["S", "SA", "S", "SA", "S", ""])
        got = [instr(v, 0x10 + i) for i in range(8)]
        check([pid(b) for b in got] == ids[8:16], "CTRL held, SPACE x2: kits 0, 1 (%s)" % [pid(b) for b in got])
        check(msg(v, L).startswith("BAND"), "message %r" % msg(v, L))
        keys(v, L, ["S", "SA", "S", "SA", "S", "SA", "S", "SA", "S", ""])
        check([pid(instr(v, 0x10 + i)) for i in range(8)] == ids[:8], "SPACE x4: kits 0, 1, 2, 0 (wraps)")
        keys(v, L, ["S", "SA", "S", ""])
        check([pid(instr(v, 0x10 + i)) for i in range(8)] == ids[:8], "CTRL again: back to kit 0")
        goto(v, L, SC_INSTR, 1, 0, 0x3C)
        keys(v, L, ["S", "SA", "S", ""])
        check([pid(instr(v, 0x3C + i)) for i in range(4)] == ids[:4] and msg(v, L) == "DRUMS    3C-3F",
              "bounds: from 3C only 3C-3F (%r)" % msg(v, L))
        goto(v, L, SC_INSTR, 2, 0, 0x30)
        before = instr(v, 0x30)
        keys(v, L, ["S", "SA", "S", ""])
        check(instr(v, 0x30) == before, "CTRL + SPACE elsewhere on the form: nothing")

        # ---- kit save -------------------------------------------------------
        F.call(v, L, F.FILEIO + F.FIO["clean"])
        v.write(F.HD_NAME, F.scr("KITTEST"))
        ta = bytes((7 * i + 1) & 255 for i in range(96))
        tb7 = bytes((5 * i + 3) & 255 for i in range(96))
        for t, d in ((3, ta), (7, tb7)):
            for c in range(6):
                v.write(TABLES + c * 512 + t * 16, d[c * 16:c * 16 + 16])
        kit = [bytes([0x11, 0x41, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 3, 0]),
               bytes([0x21, 0x21, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 3, 1]),
               bytes([0x31, 0x81, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 7, 2]),
               bytes([0x41, 0x11, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 0xFF, 3])]
        for i, d in enumerate(kit):
            v.write(INS + 16 * (0x10 + i), d)
        v.write(INS + 16 * 0x15, bytes([0x55] * 16))      # after the default 14: not in the kit
        goto(v, L, SC_FILE, 0, 0, 0x10)
        keys(v, L, ["B", "BA", "B", ""], wait=1)
        check(msg(v, L) == "KIT SAVED 10-13", "kit save message %r" % msg(v, L))
        check(v.mem(L["screen"], 1)[0] == SC_FILE, "stays on the File screen")
        n = v.mem(F.FIO_DIRCOUNT, 1)[0]
        names = [F.screen_text(v.mem(F.FIO_DIR + 16 * i, 16)) for i in range(n)]
        print("     FIO_DIR:", names)
        check(sorted(names) == ["BADVER.KIT", "KITTEST.K10", "THREE.KIT"], "File screen lists the kit files")
        rows = F.screen_text(v.mem(0x0400 + 40 * 2, 40 * 6))
        check("KITTEST.K10" in rows, "kit shown in the list")

        # ---- kit load with remap -------------------------------------------
        F.call(v, L, F.FILEIO + F.FIO["clean"])
        v.write(TABLES + 0, b"\x81")                     # table 0 holds data
        v.write(ALLOC_T, b"\x06")                        # tables 1, 2 allocated
        F.call(v, L, F.FILEIO + F.FIO["dir"])
        names = [F.screen_text(v.mem(F.FIO_DIR + 16 * i, 16)) for i in range(v.mem(F.FIO_DIRCOUNT, 1)[0])]
        k = names.index("KITTEST.K10")
        goto(v, L, SC_FILE, k + 1, 0, 0x20)
        keys(v, L, ["A", "", "A", ""], wait=1)
        check(msg(v, L) == "KIT LOADED 20-23", "kit load message %r" % msg(v, L))
        got = [instr(v, 0x20 + i) for i in range(4)]
        exp = [kit[0][:14] + bytes([3, 0]), kit[1][:14] + bytes([3, 1]), kit[2][:14] + bytes([4, 2]), kit[3]]
        check(got == exp, "instruments 20-23: bytes, tables 03->03 (shared), 07->04, none stays none")
        check(table(v, 3) == ta and table(v, 4) == tb7, "tables copied into free tables 3 and 4")
        check({1, 2, 3, 4} <= set(alloc_t(v)), "loaded tables allocated %s" % alloc_t(v))
        check(v.mem(L["screen"], 1)[0] == SC_FILE and instr(v, 0x24) == DEF, "File screen kept, instrument 24 untouched")
        # the cut at 3F
        goto(v, L, SC_FILE, k + 1, 0, 0x3E)
        keys(v, L, ["A", "", "A", ""], wait=1)
        check(msg(v, L) == "KIT LOADED 3E-3F", "cut at 3F: %r" % msg(v, L))
        check(instr(v, 0x3E)[:14] == kit[0][:14] and instr(v, 0x3F)[:14] == kit[1][:14], "3E-3F loaded")
        # errors
        for name, want, what in (("BADVER.KIT", "NOT A SIDJ PROJECT", "unknown kit version"),):
            goto(v, L, SC_FILE, names.index(name) + 1, 0, 0x30)
            keys(v, L, ["A", "", "A", ""], wait=1)
            check(msg(v, L) == want and instr(v, 0x30) == DEF, "%s: %r" % (what, msg(v, L)))
        v.write(ALLOC_T, b"\xff\xff\xff\xfe")            # one free table left (31)
        goto(v, L, SC_FILE, names.index("THREE.KIT") + 1, 0, 0x30)
        keys(v, L, ["A", "", "A", ""], wait=1)
        check(msg(v, L) == "NO FREE TABLES" and v.mem(F.FIO_ERR, 1)[0] == 5 and instr(v, 0x30) == DEF,
              "kit needing 3 tables, 1 free: %r" % msg(v, L))
        v.write(F.FIO_DEVICE, b"\x09")
        goto(v, L, SC_FILE, 0, 0, 0x20)
        keys(v, L, ["B", "BA", "B", ""], wait=1)
        check(msg(v, L) == "DEVICE NOT PRESENT", "kit save without a drive: %r" % msg(v, L))
        v.write(F.FIO_DEVICE, b"\x08")
        irq, nmi = F.frames(v, L)
        check(irq and nmi, "editor IRQ and player clock run after the kit calls")
    finally:
        v.kill()

    data = F.extract("KITTEST.K10")
    check = F.check
    check(data is not None, "KITTEST.K10 extracted")
    if data:
        exp = (b"SIDK\x01\x04\x02" + ta + tb7 + kit[0][:14] + bytes([0, 0]) + kit[1][:14] + bytes([0, 1])
               + kit[2][:14] + bytes([1, 2]) + kit[3])
        check(data == exp, "kit file format: SIDK 1, N=4, T=2, tables, instruments with kit table numbers")
    print("\n%d failure(s)" % len(F.failures))
    sys.exit(1 if F.failures else 0)


if __name__ == "__main__":
    main()
