#!/usr/bin/env python3
"""File I/O round trip in VICE (x64sc, warp, true drive emulation ON, 1541,
fresh .d64 as drive 8) through the remote monitor on port 6511.

Calls the fio_* entries through a trampoline (break at editor_main, jsr,
store A/P, jmp editor_main), compares song data byte for byte, checks the
project file format with c1541 + Python, then runs the exported .prg in a
second VICE. Kills only the VICE processes it started.

Usage: fileio_test.py [prg [labels]]   (default build/sidj.prg, build/sidj.labels)
"""
import os, random, re, socket, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
TMP = os.path.join(BUILD, "fileio_test")
PRG = sys.argv[1] if len(sys.argv) > 1 else os.path.join(BUILD, "sidj.prg")
LABELS = sys.argv[2] if len(sys.argv) > 2 else os.path.join(BUILD, "sidj.labels")
D64 = os.path.join(TMP, "fileio.d64")
PORT = int(os.environ.get("SIDJ_FIO_PORT", 6511))   # SIDJ_FIO_PORT overrides
ENV = dict(os.environ, GSETTINGS_SCHEMA_DIR="/opt/homebrew/share/glib-2.0/schemas")

# defs.inc
FILEIO = 0x7000
FIO = dict(save=0, load=3, clean=6, dir=9, delete=0xc)
FIO_DEVICE, FIO_ERR, FIO_MSG = 0x7020, 0x7021, 0x7022
FIO_DIRCOUNT, FIO_DIR = 0x7DFF, 0x7E00
PLAYER = 0x1000
# exported layout follows PLAYER_END in defs.inc: phrases, chains, then the $e000-$f9ff block
PLAYER_END = int(re.search(r"^PLAYER_END\s*=\s*\$([0-9a-fA-F]+)", open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "defs.inc")).read(), re.M).group(1), 16)
PL_PLAYING, PL_TICK, PL_ROW = 0x1020, 0x1023, 0x1028
LO = (0x8000, 0xD000)            # phrases + chains
HI = (0xE000, 0xFA00)            # song .. allocation
HEADER, HD_NAME, HD_TEMPO = 0xF800, 0xF810, 0xF800
BLOCKS = [(1, 0xF800, 0x100), (2, 0xE000, 0x600), (3, 0xC000, 0x1000), (4, 0x8000, 0x3FC0),
          (5, 0xE600, 0x400), (6, 0xEA00, 0xC00), (7, 0xF600, 0x200), (8, 0xF900, 0x100)]
ESC = 0xE7
DEF_INSTR = bytes([0x01, 0x40, 0x09, 0xA0, 0, 0x08, 0, 0, 0, 0, 0x20, 0, 0, 0, 0xFF, 0])

failures = []


def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures.append(what)


def labels():
    out = {}
    for line in open(LABELS):
        m = re.match(r"(\S+)\s*= (\$[0-9a-fA-F]+|\d+)$", line.strip())
        if m:
            v = m.group(2)
            out[m.group(1)] = int(v[1:], 16) if v[0] == "$" else int(v)
    return out


class Vice:
    def __init__(self, prg, d64=None, sid=False, extra=()):
        args = ["vsid" if sid else "x64sc", "-default", "-warp", "-sounddev", "dummy",
                "-remotemonitor", "-remotemonitoraddress", "ip4://127.0.0.1:%d" % PORT] + list(extra)
        if sid:
            args += [prg]                       # vsid: PSID player
        else:
            args += ["-autostartprgmode", "1"]
            if d64:
                args += ["-drive8type", "1581" if d64.lower().endswith(".d81") else "1541", "-drive8truedrive", "-8", d64]
            args += ["-autostart", prg]
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
        self.cmd("bank ram")
        self.go()

    def kill(self):
        self.p.terminate()
        try:
            self.p.wait(5)
        except subprocess.TimeoutExpired:
            self.p.kill()

    def cmd(self, c, timeout=60):
        """send a monitor command (stops the CPU), return its output"""
        self.s.sendall(c.encode() + b"\n")
        buf = b""
        end = time.time() + timeout
        while time.time() < end:
            try:
                d = self.s.recv(65536)
            except socket.timeout:
                if re.search(rb"\(C:\$[0-9a-f]{4}\) $", buf):
                    return buf.decode(errors="replace")
                continue
            buf += d
        raise TimeoutError("monitor: %r -> %r" % (c, buf[-200:]))

    def go(self):
        self.s.sendall(b"x\n")
        time.sleep(0.05)
        try:
            self.s.recv(65536)
        except socket.timeout:
            pass

    def mem(self, a, n):
        out = self.cmd("m %04x %04x" % (a, a + n - 1))
        vals = []
        for line in out.splitlines():
            m = re.search(r">C:([0-9a-f]{4})\s+((?:[0-9a-f]{2}\s+)+)", line)
            if m:
                vals += [int(x, 16) for x in m.group(2).split()[:16]]
        return bytes(vals[:n])

    def write(self, a, data):
        for i in range(0, len(data), 64):
            chunk = data[i:i + 64]
            self.cmd("> %04x %s" % (a + i, " ".join("%02x" % b for b in chunk)))

    def dump(self, a, b):
        path = os.path.join(TMP, "dump_%04x.bin" % a)
        if os.path.exists(path):
            os.remove(path)
        self.cmd('save "%s" 0 %04x %04x' % (path, a, b - 1))
        return open(path, "rb").read()[2:]

    def upload(self, a, data):
        path = os.path.join(TMP, "up_%04x.bin" % a)
        open(path, "wb").write(data)
        self.cmd('bload "%s" 0 %04x' % (path, a))

    def song(self):
        return self.dump(*LO) + self.dump(*HI)

    def set_song(self, data):
        n = LO[1] - LO[0]
        self.upload(LO[0], data[:n])
        self.upload(HI[0], data[n:])


def call(v, L, target, x=0, a=0, timeout=300):
    """run jsr target with A, X from the editor main loop; return (A, carry)"""
    tramp = 0x0100                  # bottom of the stack page: never reached
    res = tramp + 32
    em = L["editor_main"]
    code = bytes([0xA9, a, 0xA2, x, 0x20, target & 255, target >> 8,
                  0x08, 0x8D, res & 255, res >> 8, 0x68, 0x8D, (res + 1) & 255, res >> 8,
                  0xEE, (res + 2) & 255, res >> 8, 0x4C, em & 255, em >> 8])
    v.cmd("break %04x" % em)
    v.s.sendall(b"x\n")
    buf = b""
    end = time.time() + 30
    while not re.search(rb"\(C:\$[0-9a-f]{4}\) $", buf):
        if time.time() > end:
            raise TimeoutError("editor_main not reached")
        try:
            buf += v.s.recv(65536)
        except socket.timeout:
            pass
    v.cmd("del")
    v.write(tramp, code)
    v.write(res, bytes(3))
    v.cmd("r pc = %04x" % tramp)
    v.go()
    end = time.time() + timeout
    while True:
        time.sleep(0.5)
        r = v.mem(res, 3)
        if r[2]:
            v.go()
            return r[0], r[1] & 1
        v.go()
        if time.time() > end:
            raise TimeoutError("call %04x did not return" % target)


def fio(v, L, name, x=0):
    a, c = call(v, L, FILEIO + FIO[name], x=x)
    msg = screen_text(v.mem(FIO_MSG, 20))
    print("     fio_%s(%d): A=%d C=%d msg=%r" % (name, x, a, c, msg))
    return a, c, msg


def screen_text(b):
    return "".join(chr(c + 0x40) if 1 <= c <= 26 else chr(c) if 0x20 <= c < 0x40 else "@" if c == 0 else "?"
                   for c in b).rstrip()


def scr(s):
    return bytes(ord(c) - 0x40 if "A" <= c <= "Z" else ord(c) for c in s.upper()).ljust(16, b" ")


def frames(v, L):
    """True if the editor raster IRQ and the player NMI clock both advance"""
    f0, t0 = v.mem(L["in_frame"], 1)[0], v.mem(PL_TICK, 1)[0]
    v.go()
    time.sleep(0.5)
    f1, t1 = v.mem(L["in_frame"], 1)[0], v.mem(PL_TICK, 1)[0]
    v.go()
    return f0 != f1, t0 != t1


# ---------------------------------------------------------------------------
# images


def full_index(addr):
    if LO[0] <= addr < LO[1]:
        return addr - LO[0]
    return (LO[1] - LO[0]) + addr - HI[0]


def clean_image():
    m = bytearray(b"\xff" * ((LO[1] - LO[0]) + (HI[1] - HI[0])))
    for a in range(0xEC00, 0xF600):                   # table columns 1-5
        m[full_index(a)] = 0
    for a in range(0xF600, 0xFA00):                   # grooves, header, alloc
        m[full_index(a)] = 0
    for a in range(0x8000, 0xC000, 4):                # phrase cmd + val
        m[full_index(a + 2)] = m[full_index(a + 3)] = 0
    for a in range(0xC001, 0xD000, 2):                # chain transposes
        m[full_index(a)] = 0
    for i in range(64):
        for j in range(16):
            m[full_index(0xE600 + i * 16 + j)] = DEF_INSTR[j]
    m[full_index(0xF600)] = m[full_index(0xF601)] = 6
    m[full_index(HD_TEMPO)] = 125
    return bytes(m)


def saved_part(img):
    """img as a load restores it: the gap after the phrases ($bfc0-$bfff) is
    not saved and keeps the clean project's bytes"""
    g = full_index(0xBFC0)
    return img[:g] + clean_image()[g:g + 0x40] + img[g + 0x40:]


def pattern(seed, name):
    r = random.Random(seed)
    m = bytearray()
    total = (LO[1] - LO[0]) + (HI[1] - HI[0])
    while len(m) < total:
        k = r.random()
        if k < 0.3:
            m += bytes([r.choice([0xFF, 0, ESC, r.randrange(256)])]) * r.randrange(1, 600)
        elif k < 0.4:
            m += bytes([ESC]) * r.randrange(1, 4)
        else:
            m += bytes(r.randrange(256) for _ in range(r.randrange(1, 40)))
    m = m[:total]
    m[full_index(HD_TEMPO)] = 140
    m[full_index(HD_NAME):full_index(HD_NAME) + 16] = scr(name)[:16]
    return bytes(m)


sys.path.insert(0, os.path.join(ROOT, "tools"))
import sidj2sid                                      # noqa: E402  (decode_block / encode_block)

STRIDE = sidj2sid.STRIDE


def rle_encode(raw):
    """plain (stride 1) RLE body"""
    return sidj2sid.encode_block(raw, 1)[1]


def rle_encode_v1(raw):
    return rle_encode(raw)                           # v1 RLE: same byte RLE, no planes


def project_file(img):
    """img as SIDJ v2 saves it: blocks 1-8, planar RLE"""
    out = bytearray(b"SIDJ\x02")
    for tag, addr, length in BLOCKS:
        enc, body = sidj2sid.encode_block(img[full_index(addr):full_index(addr) + length], STRIDE[tag])
        out += bytes([tag, enc, length & 255, length >> 8, len(body) & 255, len(body) >> 8]) + body
    return bytes(out + b"\x00")


def project_file_v1(img):
    """the old v1 layout (plain RLE, version 1): only for size comparisons and the refusal check"""
    out = bytearray(b"SIDJ\x01")
    for tag, addr, length in BLOCKS:
        body = rle_encode_v1(img[full_index(addr):full_index(addr) + length])
        out += bytes([tag, 1, length & 255, length >> 8, len(body) & 255, len(body) >> 8]) + body
    return bytes(out + b"\x00")


def blocks_on_disk(n):
    return (n + 253) // 254


def parse_project(data):
    """validate a v2 project file; return {tag: (encoding, raw length, decoded)}"""
    assert data[:5] == b"SIDJ\x02", "magic/version %r" % data[:5]
    i, blocks = 5, {}
    while True:
        tag = data[i]
        i += 1
        if tag == 0:
            break
        enc, raw, stored = data[i], data[i + 1] | data[i + 2] << 8, data[i + 3] | data[i + 4] << 8
        i += 5
        body = data[i:i + stored]
        assert len(body) == stored, "block %d truncated" % tag
        i += stored
        dec = sidj2sid.decode_block(enc, raw, body)
        if dec is None:
            continue                                 # unknown encoding: skipped
        assert len(dec) == raw, "block %d: decoded %d != raw %d" % (tag, len(dec), raw)
        blocks[tag] = (enc, raw, dec)
    assert i == len(data), "%d bytes after the end tag" % (len(data) - i)
    return blocks


def image_from_blocks(blocks, base):
    m = bytearray(base)
    for tag, addr, length in BLOCKS:
        if tag in blocks and not (blocks[tag][0] >> 4 and blocks[tag][1] != length):   # planar: raw length must match
            d = blocks[tag][2][:length]
            m[full_index(addr):full_index(addr) + len(d)] = d
    return bytes(m)


def c1541(*args):
    r = subprocess.run(["c1541", D64] + list(args), capture_output=True, text=True)
    return r.stdout + r.stderr


def extract(name):
    out = os.path.join(TMP, name.replace(" ", "_") + ".prg")
    if os.path.exists(out):
        os.remove(out)
    c1541("-read", name.lower(), out)
    return open(out, "rb").read() if os.path.exists(out) else None


def diff(a, b):
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            addr = LO[0] + i if i < LO[1] - LO[0] else HI[0] + i - (LO[1] - LO[0])
            return "first difference at $%04x: %02x != %02x" % (addr, x, y)
    return "lengths %d != %d" % (len(a), len(b)) if len(a) != len(b) else "equal"


# ---------------------------------------------------------------------------


def main():
    os.makedirs(TMP, exist_ok=True)
    L = labels()
    if os.path.exists(D64):
        os.remove(D64)
    subprocess.run(["c1541", "-format", "sidj,01", "d64", D64], capture_output=True)
    # not projects: a PRG, a SEQ file with the magic; one hand-made project
    # with an unknown block, a raw block and a missing instrument block
    seq = os.path.join(TMP, "seq.bin")
    open(seq, "wb").write(b"SIDJ\x02" + bytes(20))
    crafted_song = bytes([0, 1, 2] + [0xFF] * (0x600 - 3))
    crafted_phr = bytes((i * 7) & 255 for i in range(0x3FC0))
    crafted_hdr = bytes([150, 3] + [0] * 14) + scr("CRAFTED") + bytes(0xE0)
    blk = lambda tag, enc, raw, body: bytes([tag, enc, raw & 255, raw >> 8, len(body) & 255, len(body) >> 8]) + body
    # v2: header plain RLE, an unknown tag, the song as raw (encoding 0: no
    # longer read, skipped), phrases planar (stride 4), chains planar with a
    # wrong raw length (skipped), no instrument block
    crafted_chn = bytes((i * 5) & 255 for i in range(0x1000))
    crafted = (b"SIDJ\x02" + blk(1, 1, 0x100, rle_encode(crafted_hdr)) + blk(0x63, 7, 10, b"0123456789")
               + blk(2, 0, 0x600, crafted_song) + blk(4, 0x31, 0x3FC0, sidj2sid.encode_block(crafted_phr, 4)[1])
               + blk(3, 0x11, 0xFFE, sidj2sid.encode_block(crafted_chn[:0xFFE], 2)[1]) + b"\x00")
    cpath = os.path.join(TMP, "crafted.bin")
    open(cpath, "wb").write(crafted)
    # a v1 project (as SIDJ v1 saved it): listed (magic), refused on load
    old = crafted_hdr[:16] + scr("OLD V1") + crafted_hdr[32:]
    v1 = (b"SIDJ\x01" + blk(1, 1, 0x100, rle_encode_v1(old)) + blk(4, 1, 0x3FC0, rle_encode_v1(crafted_phr)) + b"\x00")
    v1path = os.path.join(TMP, "oldv1.bin")
    open(v1path, "wb").write(v1)
    c1541("-write", PRG, "other", "-write", seq, "seqfile,s", "-write", cpath, "crafted", "-write", v1path, "old v1")
    print(c1541("-list"))

    v = Vice(PRG, D64)
    try:
        time.sleep(4)
        irq, nmi = frames(v, L)
        check(irq and nmi, "editor IRQ and player clock run after boot")
        demo = v.song()
        nd = bytearray(demo)
        nd[full_index(HD_NAME):full_index(HD_NAME) + 16] = scr("DEMO")
        named_demo = bytes(nd)
        check(demo[full_index(0xF600):full_index(0xF602)] == b"\x06\x06" and demo[full_index(HD_TEMPO)] == 125,
              "start-up via fio_clean: groove 0 = 6/6, 125 BPM")
        check(demo[full_index(0xE600 + 5 * 16):full_index(0xE600 + 6 * 16)] == DEF_INSTR,
              "start-up: unused instrument 5 = default")

        # a disk call while the demo plays
        call(v, L, PLAYER + 3, a=0)
        time.sleep(0.5)
        check(v.mem(PL_PLAYING, 1)[0] == 7, "demo playing")
        v.go()
        p23 = v.mem(0x0200, 0x200)
        vec = v.mem(0xFFFA, 6)
        a, c, msg = fio(v, L, "dir")
        check(c == 0 and a == 0, "fio_dir while playing ok")
        check(v.mem(PL_PLAYING, 1)[0] == 0, "playback stopped by the call")
        check(v.mem(0x0200, 0x200) == p23, "$0200-$03ff restored")
        check(v.mem(0xFFFA, 6) == vec, "NMI/IRQ vectors unchanged")
        v.go()
        irq, nmi = frames(v, L)
        check(irq and nmi, "editor IRQ and player clock resume after a disk call")

        a, c, msg = fio(v, L, "dir")
        n = v.mem(FIO_DIRCOUNT, 1)[0]
        dnames = sorted(screen_text(v.mem(FIO_DIR + 16 * i, 16)) for i in range(n))
        check(c == 0 and dnames == ["CRAFTED", "OLD V1"],
              "fio_dir: CRAFTED, OLD V1 (other PRG, SEQ filtered): %s" % dnames)

        A = pattern(1, "TEST ONE")
        B = pattern(2, "TEST2")
        C = pattern(3, "TEST ONE")
        for img, what in ((A, "TEST ONE"), (B, "TEST2"), (C, "TEST ONE (replace)")):
            v.set_song(img)
            check(v.song() == img, "pattern uploaded for " + what)
            a, c, msg = fio(v, L, "save")
            check(c == 0 and a == 0, "fio_save " + what)
        irq, nmi = frames(v, L)
        check(irq and nmi, "editor IRQ and player clock resume after save")

        a, c, msg = fio(v, L, "dir")
        n = v.mem(FIO_DIRCOUNT, 1)[0]
        names = [screen_text(v.mem(FIO_DIR + 16 * i, 16)) for i in range(n)]
        print("     FIO_DIR:", names, msg)
        check(c == 0 and sorted(names) == ["CRAFTED", "OLD V1", "TEST ONE", "TEST2"], "fio_dir lists the 4 projects")

        a, c, msg = fio(v, L, "clean")
        check(c == 0 and v.song() == clean_image(), "fio_clean image")
        irq, nmi = frames(v, L)
        check(irq and nmi, "editor IRQ and player clock after clean")

        for name, img in (("TEST ONE", C), ("TEST2", B)):
            v.set_song(pattern(9, "JUNK"))
            a, c, msg = fio(v, L, "load", names.index(name))
            got = v.song()
            img = saved_part(img)
            check(c == 0 and got == img, "fio_load %s byte for byte (%s)" % (name, diff(got, img)))
            irq, nmi = frames(v, L)
            check(irq and nmi, "editor IRQ and player clock after load")

        a, c, msg = fio(v, L, "load", names.index("CRAFTED"))
        exp = image_from_blocks(parse_project(crafted), clean_image())
        got = v.song()
        check(c == 0 and got == exp, "load CRAFTED: unknown tag, raw and wrong-length planar blocks skipped, planar phrases, defaults kept (%s)" % diff(got, exp))
        check(got[:0x3FC0] == crafted_phr and got[full_index(0xE000):full_index(0xE003)] == b"\xff\xff\xff",
              "load CRAFTED: phrases de-interleaved, song (raw block) left empty")

        v.set_song(B)
        a, c, msg = fio(v, L, "load", names.index("OLD V1"))
        check(c == 1 and a == 3 and msg.startswith("NOT A SIDJ PROJECT") and v.song() == B,
              "load OLD V1 (version 1): FIO_ERR_FORMAT, song untouched")
        check(v.mem(PL_TICK - 1, 1)[0] == 150, "player tempo from the loaded header")

        a, c, msg = fio(v, L, "delete", names.index("TEST2"))
        check(c == 0 and v.mem(FIO_DIRCOUNT, 1)[0] == 3, "fio_delete TEST2")
        a, c, msg = fio(v, L, "dir")
        n = v.mem(FIO_DIRCOUNT, 1)[0]
        names = [screen_text(v.mem(FIO_DIR + 16 * i, 16)) for i in range(n)]
        check(sorted(names) == ["CRAFTED", "OLD V1", "TEST ONE"], "fio_dir after delete: %s" % names)

        a, c, msg = fio(v, L, "load", 7)
        check(c == 1 and a == 2, "load of a missing entry: FIO_ERR_NOFILE")
        v.write(FIO_DEVICE, b"\x09")
        a, c, msg = fio(v, L, "dir")
        check(c == 1 and a == 1 and msg.startswith("DEVICE NOT PRESENT"), "drive 9 absent: FIO_ERR_NODEV")
        v.write(FIO_DEVICE, b"\x08")
        irq, nmi = frames(v, L)
        check(irq and nmi, "editor IRQ and player clock after a failed call")
        v.set_song(B)
        v.write(FIO_DIR, scr("NOT THERE"))
        a, c, msg = fio(v, L, "load", 0)
        check(c == 1 and a == 2 and v.song() == B, "load of a vanished file: NOFILE, song untouched (%s)" % msg)

        # the demo and a clean project, saved by SIDJ (names: DEMO, UNTITLED)
        v.set_song(named_demo)
        a, c, msg = fio(v, L, "save")
        check(c == 0, "fio_save the demo (DEMO)")
        a, c, msg = fio(v, L, "clean")
        a, c, msg = fio(v, L, "save")
        check(c == 0, "fio_save a clean project (UNTITLED)")
        a, c, msg = fio(v, L, "dir")                 # (also moves the drive head: the image is written)
        n = v.mem(FIO_DIRCOUNT, 1)[0]
        names = [screen_text(v.mem(FIO_DIR + 16 * i, 16)) for i in range(n)]
        check(sorted(names) == ["CRAFTED", "DEMO", "OLD V1", "TEST ONE", "UNTITLED"], "fio_dir after the saves: %s" % names)
    finally:
        v.kill()

    print(c1541("-list"))
    data = extract("TEST ONE")
    check(data is not None, "TEST ONE extracted with c1541")
    if data:
        try:
            blocks = parse_project(data)
            check(sorted(blocks) == list(range(1, 9)), "file has blocks 1-8")
            check({t: b[0] for t, b in blocks.items()} == {t: (STRIDE[t] - 1) << 4 | 1 for t in STRIDE},
                  "encodings: planar RLE, strides %s" % STRIDE)
            check(image_from_blocks(blocks, clean_image()) == saved_part(C), "file decodes to the saved image")
            check(data == project_file(C), "file byte for byte as the reference encoder")
            print("     TEST ONE: %d bytes for %d bytes of data (v1: %d)" % (len(data), len(C), len(project_file_v1(C))))
        except AssertionError as e:
            check(False, "format: %s" % e)
    check(extract("TEST2") is None, "TEST2 scratched on disk")
    for name, img, limit in (("DEMO", named_demo, None), ("UNTITLED", clean_image(), 1024)):
        data = extract(name)
        check(data is not None and data == project_file(img), "%s on disk = reference encoder" % name)
        if data:
            v1n = len(project_file_v1(img))
            print("     %s: %d bytes, %d blocks (v1: %d bytes, %d blocks)" % (
                name, len(data), blocks_on_disk(len(data)), v1n, blocks_on_disk(v1n)))
            if limit:
                check(len(data) < limit, "%s: clean project file < %d bytes" % (name, limit))

    # tools/sidj2sid.py: the demo as a project file -> .prg and .sid
    proj = project_file(demo)
    ppath = os.path.join(TMP, "demo.sidj")
    open(ppath, "wb").write(proj)
    tool = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools", "sidj2sid.py")
    xprg, xsid = os.path.join(TMP, "demo.prg"), os.path.join(TMP, "demo.sid")
    for out in (xprg, xsid):
        r = subprocess.run([sys.executable, tool, ppath, "-o", out, "--author", "test"], capture_output=True, text=True)
        check(r.returncode == 0 and os.path.exists(out), "sidj2sid -> %s %s" % (os.path.basename(out), (r.stdout + r.stderr).strip()))
    exp = open(xprg, "rb").read()
    x_end = PLAYER_END + 0x3FC0 + 0x1000 + 0x1A00
    check(exp[:2] == b"\x01\x08" and len(exp) == 2 + x_end - 0x0801, ".prg: $0801-$%04x (%d bytes)" % (x_end - 1, len(exp)))
    f = lambda a, n: exp[2 + a - 0x0801:2 + a - 0x0801 + n]
    check(f(PLAYER_END, 0x3FC0) + f(PLAYER_END + 0x3FC0, 0x1000) == demo[:0x3FC0] + demo[0x4000:0x5000], ".prg: phrases + chains")
    check(f(PLAYER_END + 0x4FC0, 0x1A00) == demo[full_index(0xE000):], ".prg: $e000-$f9ff block")
    v = Vice(xprg)
    try:
        time.sleep(4)
        got = v.song()
        check(got[:0x3FC0] == demo[:0x3FC0] and got[0x4000:] == demo[0x4000:], ".prg: song data in place")
        r0 = v.mem(PL_ROW, 3)
        pl = v.mem(PL_PLAYING, 1)[0]
        check(pl == 7, ".prg plays (pl_playing=%d, rows %s)" % (pl, list(r0)))
        scrn = screen_text(v.mem(0x0400 + 80 + 4, 11))
        check(scrn == "SIDJ PLAYER", ".prg display: %r" % scrn)
    finally:
        v.kill()
    sid = open(xsid, "rb").read()
    check(sid[:4] == b"PSID" and sid[4:6] == b"\x00\x02" and sid[0x7C:0x7E] == b"\x00\x10"
          and int.from_bytes(sid[0x0A:0x0C], "big") == PLAYER_END and int.from_bytes(sid[0x0C:0x0E], "big") == PLAYER_END + 3
          and sid[0x12:0x16] == b"\x00\x00\x00\x01" and sid[0x36:0x3A] == b"test" and sid[0x78:0x7A] == b"\x04\x04",
          ".sid header: PSID v2, load $1000, init/play, CIA speed, author, driver pages")
    v = Vice(xsid, sid=True)
    try:
        time.sleep(3)
        got = v.song()
        check(got[:0x3FC0] == demo[:0x3FC0] and got[0x4000:] == demo[0x4000:], ".sid in vsid: song data in place")
        pl = v.mem(PL_PLAYING, 1)[0]
        t0 = v.mem(PL_TICK, 1)[0]
        v.go()
        time.sleep(1)
        t1 = v.mem(PL_TICK, 1)[0]
        lat = v.mem(0xDC04, 2)
        check(pl == 7 and t0 != t1, ".sid in vsid plays (pl_playing=%d, tick %d -> %d)" % (pl, t0, t1))
        check(v.mem(0xDD0D, 1) is not None and v.mem(0xFFFA, 2) != b"", ".sid: monitor reachable")
    finally:
        v.kill()

    print("\n%d failure(s)" % len(failures))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
