#!/usr/bin/env python3
"""Loader menu test in VICE: x64sc, warp, 1541 with true drive emulation,
remote monitor on port 6511 (SIDJ_VICE_PORT overrides).

Boots build/sidj.d64 (LOAD"*",8,1 + RUN through autostart) and checks:
  menu      $0810 = 0 (menu), the loader at $0801, menu text, info line
            (no REU, one SID), CRSR keys move the selection ($0811)
  editor    1 -> SIDJ.EDITOR runs: program bytes, editor debug hook consumed
  taste     2 -> TASTE runs: ui_state $a003 = 1 (file list)
  readme    3 -> README runs: screen $c400 title, pl_tick moving
  manual    4 -> MANUAL runs from the same disk
  error     a disk with only the loader: 1 -> $0810 = 3, KERNAL error 4,
            "LOAD ERROR: SIDJ.EDITOR" and READY.
  probes    -reu -reusize 512 -sidextra 1 -sid2address 0xd420: "REU 512K",
            "2SID $D420"
  ntsc      -ntsc: $0812 = 0 (simple bars), menu, README still chains
  dir       LOAD"$",8 + LIST, screen rows compared with the tools/mkdisks.py
            listing (what build/dirart.png shows)
Keys go through the keyboard buffer ($c6/$0277), which the loader reads.
Screenshots: build/loader_test/*.png. Kills every VICE it starts.

usage: loader_test.py [test ...]
"""
import os, re, socket, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
TMP = os.path.join(BUILD, "loader_test")
D64A = os.path.join(BUILD, "sidj.d64")             # the one release disk
PORT = int(os.environ.get("SIDJ_VICE_PORT", 6511))
ENV = dict(os.environ, GSETTINGS_SCHEMA_DIR="/opt/homebrew/share/glib-2.0/schemas")
STATE, SEL, PAL, ERR = 0x0810, 0x0811, 0x0812, 0x0813
MROW, IROW, PROW = 13, 21, 20
sys.path.insert(0, os.path.join(ROOT, "tools"))
import mkdisks  # noqa: E402


def label(name):
    for line in open(os.path.join(BUILD, "loader", "loader.labels")):
        m = re.match(r"(\S+)\s*= \$([0-9a-fA-F]+)$", line.strip())
        if m and m.group(1) == name:
            return int(m.group(2), 16)
    raise KeyError(name)

failures = []
vices = []


def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures.append(what)
    return cond


class Vice:
    def __init__(self, d64, autostart=True, extra=()):
        args = ["x64sc", "-default", "-warp", "-sounddev", "wav", "-soundarg", "/dev/null", "-remotemonitor",
                "-remotemonitoraddress", "ip4://127.0.0.1:%d" % PORT, "-drive8type", "1541",
                "-drive8truedrive", "-8", d64] + list(extra)
        if autostart:
            args += ["-autostart", d64]
        for _ in range(300):                             # another test's VICE on the port: wait
            try:
                socket.create_connection(("127.0.0.1", PORT), timeout=0.5).close()
                time.sleep(1)
            except OSError:
                break
        else:
            raise RuntimeError("port %d stays busy" % PORT)
        self.log = open(os.path.join(TMP, "vice.log"), "a")
        self.p = subprocess.Popen(args, stdout=self.log, stderr=subprocess.STDOUT, env=ENV)
        vices.append(self)
        for _ in range(150):
            try:
                self.s = socket.create_connection(("127.0.0.1", PORT), timeout=1)
                break
            except OSError:
                time.sleep(0.2)
        else:
            raise RuntimeError("cannot connect to the VICE monitor on port %d" % PORT)
        self.s.settimeout(0.3)
        self.go()

    def kill(self):
        if self.p.poll() is None:
            self.p.terminate()
            try:
                self.p.wait(5)
            except subprocess.TimeoutExpired:
                self.p.kill()
                self.p.wait()

    def cmd(self, c, timeout=60):
        self.s.sendall(c.encode() + b"\n")
        buf, end = b"", time.time() + timeout
        while time.time() < end:
            try:
                d = self.s.recv(65536)
            except socket.timeout:
                if re.search(rb"\(C:\$[0-9a-f]{4}\) $", buf):
                    return buf.decode(errors="replace")
                continue
            buf += d
        raise TimeoutError("monitor: %r" % c)

    def go(self):
        self.s.sendall(b"x\n")
        time.sleep(0.05)
        try:
            self.s.recv(65536)
        except socket.timeout:
            pass

    def mem(self, a, n, go=True):
        self.cmd("bank ram")
        out = self.cmd("m %04x %04x" % (a, a + n - 1))
        vals = []
        for line in out.splitlines():
            m = re.search(r">C:([0-9a-f]{4})\s+((?:[0-9a-f]{2}\s+)+)", line)
            if m:
                vals += [int(x, 16) for x in m.group(2).split()[:16]]
        if go:
            self.go()
        return bytes(vals[:n])

    def poke(self, a, data):
        self.cmd("> %04x %s" % (a, " ".join("%02x" % b for b in data)))

    def key(self, k, wait=0.3):
        """one key through the keyboard buffer, waiting until it is read"""
        self.poke(0x0277, [k])
        self.poke(0xC6, [1])
        self.go()
        for _ in range(100):
            time.sleep(0.05)
            if self.mem(0xC6, 1)[0] == 0:
                break
        time.sleep(wait)

    def typed(self, text):
        """up to 10 PETSCII characters into the KERNAL keyboard buffer"""
        self.poke(0x0277, text)
        self.poke(0xC6, [len(text)])
        self.go()

    def wait(self, what, fn, timeout=40):
        end = time.time() + timeout
        while time.time() < end:
            if fn():
                return True
            time.sleep(0.2)
        return False

    def screen(self, a=0x0400):
        return self.mem(a, 1000)

    def shot(self, name, at=None):
        """screenshot; at = an address to stop at first (the loader's frame
        loop, so the picture has this frame's raster bars)"""
        if at is not None:
            self.cmd("break %04x" % at)
            self.go()
            time.sleep(0.5)
            self.cmd("delete")
        self.cmd('screenshot "%s" 2' % os.path.join(TMP, name + ".png"))
        self.go()


def text_of(codes):
    s = ""
    for b in codes:
        b &= 0x7F
        s += chr(b + 64) if 1 <= b <= 26 else chr(b) if 0x20 <= b <= 0x5A else "@" if b == 0 else "~"
    return s


def row(scr, r):
    return text_of(scr[40 * r:40 * r + 40]).rstrip()


def boot(extra=(), d64=D64A):
    v = Vice(d64, extra=extra)
    ok = v.wait("menu", lambda: v.mem(0x0801, 16) == LOADER[2:18] and v.mem(STATE, 1)[0] == 0
                and "SIDJ EDITOR" in row(v.screen(), MROW), 90)
    check(ok, "loader menu up (%s)" % (" ".join(extra) or "default"))
    if not ok:
        print(text_of(v.screen()))
    time.sleep(0.5)
    return v


def t_menu():
    v = boot()
    try:
        scr = v.screen()
        rows = [row(scr, MROW + 2 * i).strip() for i in range(4)]
        check(rows == ["1  SIDJ EDITOR", "2  T.A.S.T.E.", "3  README", "4  MANUAL"], "menu rows %s" % rows)
        info = row(scr, IROW)
        check("NO REU" in info and "1 SID" in info, "info line without REU: %r" % info)
        check(v.mem(PAL, 1)[0] == 1, "PAL: stable bars")
        v.shot("menu", label("frame"))
        seq = []
        for k in (0x11, 0x11, 0x91, 0x91, 0x91):          # down, down, up, up, up (wraps)
            v.key(k)
            seq.append(v.mem(SEL, 1)[0])
        check(seq == [1, 2, 1, 0, 3], "CRSR moves the selection: %s" % seq)
        v.key(0x91)
        v.key(0x91)
        v.key(0x91)
        check(v.mem(SEL, 1)[0] == 0, "back on entry 1")
        check(v.mem(STATE, 1)[0] == 0, "still in the menu")
    finally:
        v.kill()


def t_editor():
    v = boot()
    try:
        v.key(0x31, 0)
        prg = open(os.path.join(BUILD, "sidj.prg"), "rb").read()
        ok = v.wait("editor", lambda: v.mem(0x0801, 64) == prg[2:66], 60)
        check(ok, "1: SIDJ.EDITOR loaded at $0801")
        ok = False
        for _ in range(8):                               # the editor clears $0c00 while it starts
            v.poke(0x0D00, [0, 0xFF])
            v.poke(0x0C00, [1, 0])
            v.go()
            if v.wait("hook", lambda: v.mem(0x0C00, 2) == bytes([0, 1]), 3):
                ok = True
                break
        check(ok, "editor main loop runs (debug hook consumed)")
        v.shot("editor")
    finally:
        v.kill()


def t_taste():
    v = boot()
    try:
        v.key(0x86, 0)                                   # F3
        ok = v.wait("taste", lambda: v.mem(0xA003, 1)[0] == 1, 60)
        check(ok, "F3: TASTE runs (ui_state $a003 = 1)")
        v.shot("taste")
    finally:
        v.kill()


def reader(v, title):
    ok = v.wait("reader", lambda: title in text_of(v.mem(0xC400, 120)), 60)
    t = []
    for _ in range(6):
        t.append(v.mem(0x1023, 1)[0])
        time.sleep(0.1)
    return ok, len(set(t)) > 1


def t_readme(extra=(), name="readme"):
    v = boot(extra)
    try:
        v.key(0x33, 0)
        ok, tick = reader(v, "READ ME FIRST")
        check(ok, "3: README runs (title on $c400) %s" % " ".join(extra))
        check(tick, "README music tick moves")
        v.shot(name)
    finally:
        v.kill()


def t_manual():
    v = boot()
    try:
        v.key(0x34)
        ok, tick = reader(v, "USER'S MANUAL")
        check(ok, "4: MANUAL runs (same disk)")
        check(tick, "MANUAL music tick moves")
        v.shot("manual")
    finally:
        v.kill()


def t_error():
    d64 = os.path.join(TMP, "err.d64")
    if os.path.exists(d64):
        os.remove(d64)
    subprocess.run(["c1541", "-format", "err,01", "d64", d64, "-write", os.path.join(BUILD, "loader.prg"), "sidj"],
                   capture_output=True)
    v = boot(d64=d64)
    try:
        v.key(0x31, 0)
        ok = v.wait("error", lambda: v.mem(STATE, 1)[0] == 3, 60)
        check(ok, "missing SIDJ.EDITOR: state 3")
        check(v.mem(ERR, 1)[0] == 4, "KERNAL error 4 (file not found): %d" % v.mem(ERR, 1)[0])
        ok = v.wait("ready", lambda: "READY." in text_of(v.screen()), 20)
        scr = text_of(v.screen())
        check(ok and "LOAD ERROR: SIDJ.EDITOR" in scr, "message and READY.")
        v.shot("error")
    finally:
        v.kill()


def t_probes():
    v = boot(("-reu", "-reusize", "512", "-sidextra", "1", "-sid2address", "0xd420"))
    try:
        info = row(v.screen(), IROW)
        check("REU 512K" in info and "2SID $D420" in info and ("6581" in info or "8580" in info),
              "info line with REU and 2SID: %r" % info)
        v.shot("probes", label("frame"))
    finally:
        v.kill()


def t_ntsc():
    v = boot(("-ntsc",))
    try:
        check(v.mem(PAL, 1)[0] == 0, "NTSC detected: simple bars")
        v.shot("ntsc", label("frame"))
        v.key(0x33, 0)
        ok, tick = reader(v, "READ ME FIRST")
        check(ok and tick, "NTSC: README chains and plays")
    finally:
        v.kill()


def listing_check(v, d64, name):
    want = mkdisks.screen_rows(d64)
    v.typed(b'LOAD"$",8\r')
    ok = v.wait("load", lambda: text_of(v.screen()).count("READY.") >= 2, 60)
    check(ok, "%s: LOAD\"$\",8" % name)
    v.typed(b"LIST\r")
    time.sleep(1)
    v.wait("list", lambda: "BLOCKS FREE." in text_of(v.screen()), 20)
    time.sleep(0.5)
    scr = v.screen()
    rows = [scr[40 * r:40 * r + 40] for r in range(25)]
    # the listing ends with BLOCKS FREE. and READY.; match from the bottom
    end = max(i for i, r in enumerate(rows) if b"BLOCKS FREE." in mkdisks.pet_screen(text_of(r).encode()) or "BLOCKS FREE." in text_of(r))
    n = min(len(want), end + 1)
    got = rows[end + 1 - n:end + 1]
    bad = [i for i in range(n) if got[i] != want[len(want) - n + i]]
    check(not bad, "%s: %d listing rows match the art (%s)" % (name, n, "rows %s differ" % bad if bad else "ok"))
    if bad:
        for i in bad[:3]:
            print("   got  %s\n   want %s" % (got[i].hex(), want[len(want) - n + i].hex()))
    v.shot("dir-" + name)


def t_dir():
    for d64, name in ((D64A, ""),):
        v = Vice(d64, autostart=False)
        try:
            v.wait("ready", lambda: "READY." in text_of(v.screen()), 30)
            listing_check(v, d64, name)
        finally:
            v.kill()


TESTS = dict(menu=t_menu, editor=t_editor, taste=t_taste, readme=t_readme, manual=t_manual,
             error=t_error, probes=t_probes, ntsc=t_ntsc, dir=t_dir)

if __name__ == "__main__":
    os.makedirs(TMP, exist_ok=True)
    LOADER = open(os.path.join(BUILD, "loader.prg"), "rb").read()
    names = sys.argv[1:] or list(TESTS)
    try:
        for n in names:
            print("--", n)
            try:
                TESTS[n]()
            except (TimeoutError, RuntimeError, OSError) as ex:
                check(False, "%s: %s" % (n, ex))
    finally:
        for v in vices:
            v.kill()
    print("%d failures" % len(failures) if failures else "all loader tests passed")
    sys.exit(1 if failures else 0)
