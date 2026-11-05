#!/usr/bin/env python3
"""mkdisks: the release disk (and the local HVSC test disk) with c1541,
then the directory art patched in with Python.

usage: mkdisks.py release   build/sidj.d64 (header SIDJ V + the VERSION file)
       mkdisks.py hvsc      build/sidj-hvsc.d64: the loader, SIDJ.EDITOR, T.A.S.T.E, SIDJ.HLP and the
                            build/hvsc/*.sid tunes that fit, smallest first (local only, not for release)

One disk (the programs are crunched with Exomizer, so it all fits): sidj (the
loader menu, first), the logo as 0-block DEL lines, sidj.editor, taste, readme,
manual, sidj.hlp, a SONGS divider with demo and every build/songs/*.sidj (disk
name = stem in lower case, underscores as spaces, at most 16 characters, if
build/songs exists), a KITS divider with the factory kits (drums.k00, band.k00,
synth.k00).

c1541 can't write arbitrary PETSCII names or DEL entries, so the T18 directory is
rewritten here in the chosen order (art lines: DEL, track/sector 0/0, 0 blocks),
the BAM marks the directory sectors, the header name is patched. A self-check reads
every real file back, compares blocks free and the order from c1541 -dir.
Preview of LOAD"$" + LIST with the ROM font: build/dirart.png
(CHARGEN=path to the character ROM, no default; skipped
if it is missing or PIL is not installed).
Prints each file's size in blocks and the blocks free.
"""
import glob, os, re, subprocess, sys
VERSION = open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "VERSION")).read().strip().upper()

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
B = os.path.join(ROOT, "build")


def c1541(*args):
    r = subprocess.run(["c1541"] + list(args), capture_output=True, text=True, errors="replace")
    return r.stdout + r.stderr


def make(d64, title, files, optional=False):
    if os.path.exists(d64):
        os.remove(d64)
    c1541("-format", title + ",01", "d64", d64)
    for src, name in files:
        if not os.path.exists(src):
            sys.exit("%s missing (run make first)" % src)
        if optional:
            free = int(re.search(r"(\d+) blocks free", c1541(d64, "-dir")).group(1))
            if (os.path.getsize(src) + 253) // 254 > free:
                print("  (no room for %s)" % name)
                continue
        out = c1541(d64, "-write", src, name)
        if "rror" in out:
            if optional:
                print("  (no room for %s)" % name)
                continue
            sys.exit("%s: cannot write %s: %s" % (d64, name, out.strip()))
    d = c1541(d64, "-dir")
    print("%s \"%s\":" % (os.path.relpath(d64, ROOT), title))
    for line in d.splitlines():
        m = re.match(r'^(\d+)\s+"(.*?)"\s+(\w+)', line)
        if m:
            print("  %4s  %s" % (m.group(1), m.group(2)))
    free = int(re.search(r"(\d+) blocks free", d).group(1))
    print("  %4d  blocks free" % free)
    return free


# ---------------------------------------------------------------------------
# Directory art

ART_CHARS = {"▁": 0xA4, "▔": 0xA3, "─": 0xC0, "│": 0xDD, "╭": 0xD5, "╮": 0xC9, "╰": 0xCA,
             "╯": 0xCB, "┌": 0xB0, "┐": 0xAE, "└": 0xAD, "┘": 0xBD}
LOGO = ["▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁",
        " ╭── │ ┌─╮   │  ",
        " ╰─╮ │ │ │   │  ",
        " ──╯ │ └─╯ ╰─╯  ",
        "▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"]
DIR_SECTORS = [1, 4, 7, 10, 13, 16, 2, 5, 8, 11, 14, 17, 3, 6, 9, 12, 15, 18]   # 1541 interleave 3


def petscii(text):
    """art / header text -> PETSCII bytes (upper case set); no quote, $a0 or control codes"""
    out = bytearray()
    for ch in text:
        if ch in ART_CHARS:
            out.append(ART_CHARS[ch])
        else:
            c = ord(ch.upper())
            assert 0x20 <= c <= 0x5F and c != 0x22, repr(ch)
            out.append(c)
    assert len(out) <= 16 and all(0x20 <= b <= 0x7F or 0xA1 <= b <= 0xFE for b in out) and 0x22 not in out
    return bytes(out)


def ts_offset(t, s):
    spt = [21] * 17 + [19] * 7 + [18] * 6 + [17] * 5
    return (sum(spt[:t - 1]) + s) * 256


def read_dir(img):
    """[(32-byte entry without the link bytes)] in directory order, and the sectors used"""
    ents, secs, t, s = [], [], 18, 1
    while t == 18 and s not in secs:
        secs.append(s)
        o = ts_offset(t, s)
        for i in range(8):
            e = img[o + 32 * i:o + 32 * i + 32]
            if e[2]:
                ents.append(bytes(e[2:]))
        t, s = img[o], img[o + 1]
    return ents, secs


def entry_name(e):
    return bytes(e[3:19]).rstrip(b"\xa0")


def art_entry(text):
    name = petscii(text).ljust(16, b"\xa0")
    return bytes([0x80, 0, 0]) + name + bytes(11)          # DEL, 0/0, 0 blocks


def write_dir(img, ents, old_secs):
    for s in old_secs:                                      # old chain: empty, free
        o = ts_offset(18, s)
        img[o:o + 256] = bytes(256)
    need = (len(ents) + 7) // 8
    assert need <= len(DIR_SECTORS), "directory full"
    secs = DIR_SECTORS[:need]
    for k, s in enumerate(secs):
        o = ts_offset(18, s)
        for i, e in enumerate(ents[8 * k:8 * k + 8]):
            img[o + 32 * i + 2:o + 32 * i + 32] = e
        if k + 1 < need:
            img[o], img[o + 1] = 18, secs[k + 1]
        else:
            img[o], img[o + 1] = 0, 0xFF
    bam = ts_offset(18, 0) + 4 + 4 * 17                     # track 18 BAM entry
    used = {0} | set(secs)
    bits = sum(1 << s for s in range(19) if s not in used)
    img[bam:bam + 4] = bytes([19 - len(used), bits & 0xFF, (bits >> 8) & 0xFF, bits >> 16])


def dirart(d64, header, layout):
    """layout: real file names (as c1541 wrote them, lower case) and ("art", text) items;
    real files missing from the layout keep their order at the end"""
    img = bytearray(open(d64, "rb").read())
    ents, secs = read_dir(img)
    by_name = {entry_name(e): e for e in ents}
    out, placed = [], set()
    for item in layout:
        if isinstance(item, tuple):
            out.append(art_entry(item[1]))
        else:
            n = item.encode().upper()
            if n in by_name:
                out.append(by_name[n])
                placed.add(n)
    out += [e for e in ents if entry_name(e) not in placed]
    write_dir(img, out, secs)
    b = ts_offset(18, 0)
    img[b + 0x90:b + 0xA0] = petscii(header).ljust(16, b"\xa0")
    open(d64, "wb").write(img)
    return [entry_name(e) for e in out if e[0] != 0x80]


def listing(d64):
    """LOAD"$" + LIST as screen lines: [(screen codes, reverse)]"""
    img = open(d64, "rb").read()
    b = ts_offset(18, 0)
    lines = [(b"0 ", False)]
    head = b'"' + img[b + 0x90:b + 0xA0].replace(b"\xa0", b" ") + b'" ' + img[b + 0xA2:b + 0xA4] + b" " + img[b + 0xA5:b + 0xA7]
    lines = [(b"0 ", head)]
    for e in read_dir(img)[0]:
        blocks = e[28] + 256 * e[29]
        name = entry_name(e)
        typ = [b"DEL", b"SEQ", b"PRG", b"USR", b"REL"][e[0] & 7]
        txt = str(blocks).encode() + b" " + b" " * (4 - len(str(blocks))) + b'"' + name + b'"' + \
            b" " * (16 - len(name)) + (b" " if e[0] & 0x80 else b"*") + typ + (b"<" if e[0] & 0x40 else b"")
        lines.append((txt, b""))
    free = sum(img[b + 4 + 4 * i] for i in range(35) if i != 17)
    lines.append((("%d BLOCKS FREE." % free).encode(), b""))
    return [(pet_screen(a), pet_screen(r, True)) for a, r in lines]


def pet_screen(bs, rev=False):
    out = []
    for c in bs:
        if 0x40 <= c <= 0x5F:
            c -= 0x40
        elif 0x60 <= c <= 0x7F or 0xC0 <= c <= 0xDF:
            c = c - 0x20 if c < 0x80 else c - 0x80
        elif 0xA0 <= c <= 0xBF or 0xE0 <= c <= 0xFE:
            c -= 0x40 if c < 0xE0 else 0x80
        out.append(c | (0x80 if rev else 0))
    return bytes(out)


def screen_rows(d64):
    """the listing as 40-column screen rows (normal part + reverse part)"""
    rows = []
    for a, r in listing(d64):
        rows.append((a + r)[:40].ljust(40, b" "))
    return rows


def preview(d64, png):
    chargen = os.environ.get("CHARGEN", "")
    try:
        from PIL import Image
        rom = open(chargen, "rb").read()
    except (ImportError, OSError) as ex:
        print("  (no preview: %s)" % ex)
        return
    rows = [b'LOAD"$",8'.ljust(40), b"".ljust(40), b"SEARCHING FOR $".ljust(40), b"LOADING".ljust(40),
            b"READY.".ljust(40), b"LIST".ljust(40), b"".ljust(40)]
    rows = [pet_screen(r) for r in rows] + screen_rows(d64) + [pet_screen(b"READY.".ljust(40))]
    fg, bg = (0x78, 0x69, 0xc4), (0x40, 0x31, 0x8d)            # light blue on blue
    h = max(25, len(rows))
    img = Image.new("RGB", (320 + 64, h * 8 + 64), fg)
    for cy, row in enumerate(rows):
        for cx, code in enumerate(row):
            g = rom[(code & 0x7F) * 8:(code & 0x7F) * 8 + 8]
            for y in range(8):
                bits = g[y] ^ (0xFF if code & 0x80 else 0)
                for x in range(8):
                    img.putpixel((32 + cx * 8 + x, 32 + cy * 8 + y), fg if bits & (0x80 >> x) else bg)
    for cy in range(len(rows), h):
        for y in range(8):
            for x in range(320):
                img.putpixel((32 + x, 32 + cy * 8 + y), bg)
    img.resize((img.width * 2, img.height * 2), Image.NEAREST).save(png)
    print("  preview %s" % os.path.relpath(png, ROOT))


def selfcheck(d64, files, order, free_before):
    d = c1541(d64, "-dir")
    names = []
    for line in d.splitlines():
        m = re.match(r'^(\d+)\s+"(.*?)"\s+(\w+)', line)
        if m and m.group(3).lower() in ("prg", "seq", "usr", "rel"):    # not the header, not art
            names.append(m.group(2).lower())
    want = [n.decode().lower() for n in order]
    assert names == want, "%s: order %s, want %s" % (d64, names, want)
    free = int(re.search(r"(\d+) blocks free", d).group(1))
    assert free == free_before, "%s: %d blocks free, was %d" % (d64, free, free_before)
    tmp = d64 + ".check"
    for src, name in files:
        if os.path.exists(tmp):
            os.remove(tmp)
        c1541(d64, "-read", name, tmp)
        ok = os.path.exists(tmp) and open(tmp, "rb").read() == open(src, "rb").read()
        assert ok, "%s: %s does not read back" % (d64, name)
    if os.path.exists(tmp):
        os.remove(tmp)
    print("  self-check: %d files read back, order and %d blocks free ok" % (len(files), free))



def X(name):
    """the Exomizer-crunched build/x/<name> (make crunch) if present, else build/<name>"""
    x = os.path.join(B, "x", name)
    return x if os.path.exists(x) else os.path.join(B, name)


def release():
    """one disk: programs, then songs and kits (all fits a 1541 disk)"""
    progs = [(X("loader.prg"), "sidj"), (X("sidj.prg"), "sidj.editor"), (X("taste.prg"), "taste"),
             (X("readme.prg"), "readme"), (X("manual.prg"), "manual"), (os.path.join(B, "SIDJ.HLP"), "sidj.hlp")]
    songs = [(os.path.join(B, "goodies", "demo.sidj"), "demo")]
    for s in sorted(glob.glob(os.path.join(B, "songs", "*.sidj"))):
        songs.append((s, os.path.splitext(os.path.basename(s))[0].lower().replace("_", " ")[:16]))
    if len(songs) == 1:
        print("(no build/songs/*.sidj: the disk has only the demo song)")
    kits = [(os.path.join(B, "goodies", k + ".kit"), k + ".k00") for k in ("drums", "band", "synth")]
    files = progs + songs + kits
    d64 = os.path.join(B, "sidj.d64")
    free = make(d64, "sidj", files)
    order = dirart(d64, ("SIDJ V" + VERSION).ljust(16), ["sidj"] + [("art", l) for l in LOGO] + [("art", "  DJ-STYLE C64  "), ("art", " ILLOBO/NETMILK ")]
                   + [n for _, n in progs[1:]]
                   + [("art", "──── SONGS ─────")] + [n for _, n in songs]
                   + [("art", "───── KITS ─────")] + [n for _, n in kits])
    selfcheck(d64, files, order, free)
    preview(d64, os.path.join(B, "dirart.png"))
    for old in ("sidj-a.d64", "sidj-b.d64", "dirart-a.png", "dirart-b.png"):
        if os.path.exists(os.path.join(B, old)):
            os.remove(os.path.join(B, old))


def hvsc():
    f = [(X("loader.prg"), "sidj"), (X("sidj.prg"), "sidj.editor"),
         (X("taste.prg"), "taste"), (os.path.join(B, "SIDJ.HLP"), "sidj.hlp")]
    for s in sorted(glob.glob(os.path.join(B, "hvsc", "*.sid")), key=os.path.getsize):   # small ones first
        n = os.path.basename(s)[:-4].lower().replace("_", "")[:12] + ".sid"
        f.append((s, n))
    make(os.path.join(B, "sidj-hvsc.d64"), "sidj hvsc", f, optional=True)


if __name__ == "__main__":
    {"release": release, "hvsc": hvsc}[sys.argv[1] if len(sys.argv) > 1 else "release"]()
