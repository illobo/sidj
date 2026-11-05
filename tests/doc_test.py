#!/usr/bin/env python3
"""Doc reader test in VICE (x64sc, warp, remote monitor on port 6511).

For build/readme.prg and build/manual.prg: boot, check the chapter menu
against build/doc/*.json, open a chapter (keys through the keyboard buffer
$0277/$c6, since the reader uses GETIN), compare the first text rows with
the generated text, scroll by line and by page, go back to the menu, and
check that the music tick (pl_tick) advances and M stops it.
Screenshots go to build/doc/*.png.

Usage: doc_test.py [readme|manual ...]
"""
import json, os, re, socket, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
TMP = os.path.join(BUILD, "doc")
PORT = int(os.environ.get("SIDJ_VICE_PORT", 6511))
ENV = dict(os.environ, GSETTINGS_SCHEMA_DIR="/opt/homebrew/share/glib-2.0/schemas")
SCR, COLRAM = 0xC400, 0xD800
PL_TICK = 0x1023
TOP_ROW, NROWS, MENU_ROW = 3, 21, 4
failures = []


def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures.append(what)


class Vice:
    def __init__(self, prg):
        args = ["x64sc", "-default", "-warp", "-sounddev", "dummy", "-remotemonitor",
                "-remotemonitoraddress", "ip4://127.0.0.1:%d" % PORT, "-autostartprgmode", "1", "-autostart", prg]
        self.log = open(os.path.join(TMP, "vice.log"), "a")
        self.p = subprocess.Popen(args, stdout=self.log, stderr=subprocess.STDOUT, env=ENV)
        for _ in range(150):
            try:
                self.s = socket.create_connection(("127.0.0.1", PORT), timeout=1)
                break
            except OSError:
                time.sleep(0.2)
        else:
            self.kill()
            sys.exit("cannot connect to the VICE monitor on port %d" % PORT)
        self.s.settimeout(0.3)
        self.go()

    def kill(self):
        self.p.terminate()
        try:
            self.p.wait(5)
        except subprocess.TimeoutExpired:
            self.p.kill()

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

    def mem(self, a, n, bank="ram"):
        self.cmd("bank %s" % bank)
        out = self.cmd("m %04x %04x" % (a, a + n - 1))
        vals = []
        for line in out.splitlines():
            m = re.search(r">C:([0-9a-f]{4})\s+((?:[0-9a-f]{2}\s+)+)", line)
            if m:
                vals += [int(x, 16) for x in m.group(2).split()[:16]]
        return bytes(vals[:n])

    def keys(self, petscii, wait=0.4):
        """one key at a time through the keyboard buffer, waiting until it is read"""
        for k in petscii:
            self.cmd("> 0277 %02x" % k)
            self.cmd("> c6 01")
            self.go()
            for _ in range(50):
                time.sleep(0.05)
                if self.mem(0xC6, 1)[0] == 0:
                    break
            self.go()
            time.sleep(wait)


def scr_code(ch):
    c = ord(ch)
    if "a" <= ch <= "z":
        return c - 96
    if "A" <= ch <= "Z":
        return c
    if ch == "@":
        return 0
    return c


def text_of(codes):
    """screen codes (mixed case) -> text; other glyphs as '?'"""
    s = ""
    for b in codes:
        b &= 0x7F
        s += chr(b + 96) if 1 <= b <= 26 else chr(b) if 0x41 <= b <= 0x5A or 0x20 <= b <= 0x3F else "@" if b == 0 else "?"
    return s.rstrip()


sys.path.insert(0, os.path.join(ROOT, "tools"))
import mkdocs  # noqa: E402


def json_text(t):
    return text_of(bytes(mkdocs.scr(ch) for ch in t))


def rows(v, first, n):
    data = v.mem(SCR + 40 * first, 40 * n)
    v.go()
    return [text_of(data[i * 40:i * 40 + 40]) for i in range(n)]


def tick(v):
    t = v.mem(PL_TICK, 1)[0]
    v.go()
    return t


def ticking(v):
    """True if pl_tick changes between some of five samples"""
    ts = []
    for _ in range(5):
        ts.append(tick(v))
        time.sleep(0.07)
    return len(set(ts)) > 1, ts


def run(name):
    prg = os.path.join(BUILD, name + ".prg")
    doc = json.load(open(os.path.join(TMP, name + ".json")))
    chs = doc["chapters"]
    print("== %s (%d chapters)" % (name, len(chs)))
    v = Vice(prg)
    try:
        time.sleep(3)
        menu = rows(v, MENU_ROW, min(len(chs), 19))
        want = [json_text(c["title"])[:34] for c in chs[:19]]
        got = [r.strip() for r in menu]
        check(got == want, "menu shows the chapter titles")
        if got != want:
            print("     got  %r\n     want %r" % (got[:4], want[:4]))
        title = rows(v, 0, 1)[0]
        check("SIDJ" in title and doc["title"] in title, "title row: %r" % title)
        on, ts = ticking(v)
        check(on, "music: pl_tick advances %s" % ts)
        v.cmd('screenshot "%s" 2' % os.path.join(TMP, name + "-menu.png"))
        v.go()
        # open chapter k: CRSR down k times, RETURN
        k = 1 if len(chs) > 1 else 0
        v.keys([0x11] * k + [0x0D], wait=0.8)
        lines = [json_text(t) for _, t in chs[k]["lines"]]
        page = rows(v, TOP_ROW, NROWS)
        check(page == (lines + [""] * NROWS)[:NROWS], "chapter %d: first %d rows match the text" % (k, NROWS))
        if page != (lines + [""] * NROWS)[:NROWS]:
            for a, b in zip(page, lines):
                if a != b:
                    print("     got  %r\n     want %r" % (a, b))
                    break
        cols = v.mem(COLRAM + 40 * TOP_ROW, 1, "io")[0] & 15
        v.go()
        check(cols == chs[k]["lines"][0][0], "chapter title colour %d" % cols)
        v.cmd('screenshot "%s" 2' % os.path.join(TMP, name + "-text.png"))
        v.go()
        n = len(lines)
        maxtop = max(0, n - NROWS)
        v.keys([0x11, 0x11, 0x11])                          # three lines down
        top = min(3, maxtop)
        check(rows(v, TOP_ROW, NROWS) == (lines[top:] + [""] * NROWS)[:NROWS], "CRSR DOWN x3: top line %d" % top)
        v.keys([0x91])                                      # one up
        top = max(0, top - 1)
        check(rows(v, TOP_ROW, NROWS) == (lines[top:] + [""] * NROWS)[:NROWS], "CRSR UP: top line %d" % top)
        v.keys([0x20])                                      # page down
        top = min(top + NROWS - 1, maxtop)
        check(rows(v, TOP_ROW, NROWS) == (lines[top:] + [""] * NROWS)[:NROWS], "SPACE: top line %d" % top)
        v.keys([0xA0])                                      # page up
        top = max(0, top - NROWS + 1)
        check(rows(v, TOP_ROW, NROWS) == (lines[top:] + [""] * NROWS)[:NROWS], "SHIFT+SPACE: top line %d" % top)
        # every chapter opens and its first rows match (long text, unpacker)
        v.keys([0x03])                                      # RUN/STOP: menu
        check([r.strip() for r in rows(v, MENU_ROW, min(len(chs), 19))] == want, "RUN/STOP: back to the menu")
        v.keys([0x91] * k)
        bad = []
        for j in range(len(chs)):
            v.keys([0x0D], wait=0.5)
            lj = [json_text(t) for _, t in chs[j]["lines"]]
            got = rows(v, TOP_ROW, NROWS)
            if got != (lj + [""] * NROWS)[:NROWS]:
                bad.append(j)
                d = next(i for i in range(NROWS) if got[i] != (lj + [""] * NROWS)[i])
                print("     chapter %d row %d: got %r want %r" % (j, d, got[d], (lj + [""] * NROWS)[d]))
            v.keys([0x13, 0x20] * 0 + [0x85, 0x11], wait=0.3)  # F1 back, next chapter
        check(not bad, "all %d chapters open with the right text %s" % (len(chs), bad or ""))
        # M: music off and on
        v.keys([0x4D])
        on, ts = ticking(v)
        check(not on, "M: music off (pl_tick stays) %s" % ts)
        v.keys([0x4D])
        on, ts = ticking(v)
        check(on, "M again: music on %s" % ts)
    finally:
        v.kill()


def main():
    os.makedirs(TMP, exist_ok=True)
    for name in sys.argv[1:] or ["readme", "manual"]:
        run(name)
    print("\n%d failure(s)" % len(failures))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
