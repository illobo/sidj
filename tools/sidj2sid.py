#!/usr/bin/env python3
"""sidj2sid: turn a saved SIDJ project into a .sid (PSID v2/v3) or a runnable .prg.

usage: sidj2sid.py PROJECT [-o OUT.sid|OUT.prg] [--author A] [--released R]
                   [--model 8580|6581|any] [--clock pal|ntsc|any] [--sid2 ADDR|off]

2SID: with chains in song channels 4-6 the export plays six channels on
a second SID at $d420 (--sid2 to choose another base, --sid2 off for three):
the .sid becomes PSID v3 with that second SID address, the .prg expects it there.

PROJECT is a project file as saved by SIDJ (extracted from a disk image), or
IMAGE.d64:NAME to read it from a disk image with c1541. The output type
follows the extension of OUT (default: the project name + .sid).

The player code comes from build/sidj-sid.bin and build/sidj-prg.bin, which
`make` assembles from src/standalone.asm together with sidj.prg, so the tool
always uses the same player as the editor it was built with.
"""
import argparse, os, re, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
BUILD = os.path.join(ROOT, "build")

ESC = 0xE7
VERSION = 2                             # project file version (src/fileio.asm)
DEF_INSTR = bytes([0x01, 0x40, 0x09, 0xA0, 0, 0x08, 0, 0, 0, 0, 0x20, 0, 0, 0, 0xFF, 0])
# project file blocks: tag, address, length (src/fileio.asm B_ADDR / B_LEN)
BLOCKS = {1: (0xF800, 0x100), 2: (0xE000, 0x600), 3: (0xC000, 0x1000), 4: (0x8000, 0x3FC0),
          5: (0xE600, 0x400), 6: (0xEA00, 0xC00), 7: (0xF600, 0x200), 8: (0xF900, 0x100)}
# planar stride per block: phrases 4, chains 2, instruments 16
STRIDE = {1: 1, 2: 1, 3: 2, 4: 4, 5: 16, 6: 1, 7: 1, 8: 1}
HD_TEMPO, HD_NAME = 0xF800, 0xF810


def defs():
    """PLAYER_END from src/defs.inc: where the song data starts in the images"""
    txt = open(os.path.join(ROOT, "src", "defs.inc")).read()
    return int(re.search(r"^PLAYER_END\s*=\s*\$([0-9a-fA-F]+)", txt, re.M).group(1), 16)


def rle_decode(data):
    """ESC, count, value = count x value; any other byte is a literal"""
    out, i = bytearray(), 0
    while i < len(data):
        if data[i] == ESC:
            out += bytes([data[i + 2]]) * data[i + 1]
            i += 3
        else:
            out.append(data[i])
            i += 1
    return bytes(out)


def decode_block(enc, raw, body):
    """block body -> raw bytes, None if the loader would skip it. Encoding:
    low nibble 1 = RLE, high nibble = stride S - 1; the RLE stream holds the
    raw bytes in planar order (byte 0 of every S-byte record, then byte 1 ...)"""
    if enc & 15 != 1:
        return None
    s = (enc >> 4) + 1
    dec = rle_decode(body)
    if s == 1:
        return dec
    if raw % s or len(dec) != raw:
        return None
    p = raw // s
    out = bytearray(raw)
    for i, b in enumerate(dec):
        out[(i % p) * s + i // p] = b
    return bytes(out)


def encode_block(raw, s):
    """inverse of decode_block: (encoding, body), as SIDJ saves it"""
    p = len(raw) // s
    planar = bytes(raw[(i % p) * s + i // p] for i in range(len(raw)))
    out, i = bytearray(), 0
    while i < len(planar):
        n = 1
        while n < 255 and i + n < len(planar) and planar[i + n] == planar[i]:
            n += 1
        if n >= 4 or planar[i] == ESC:
            out += bytes([ESC, n, planar[i]])
        else:
            out += bytes([planar[i]]) * n
        i += n
    return (s - 1) << 4 | 1, bytes(out)


def clean_memory():
    """64 KB with the song area as fio_clean leaves it"""
    m = bytearray(0x10000)
    m[0x8000:0xD000] = b"\xff" * 0x5000
    m[0xE000:0xFA00] = b"\xff" * 0x1A00
    m[0xEC00:0xFA00] = bytes(0xFA00 - 0xEC00)             # table columns 1-5 .. allocation
    for a in range(0x8000, 0xC000, 4):                   # phrase command + value
        m[a + 2] = m[a + 3] = 0
    for a in range(0xC001, 0xD000, 2):                   # chain transposes
        m[a] = 0
    for i in range(64):
        m[0xE600 + i * 16:0xE610 + i * 16] = DEF_INSTR
    m[0xF600] = m[0xF601] = 6                            # groove 0 = 6/6
    m[HD_TEMPO] = 125
    return m


def load_project(data):
    if data[:4] != b"SIDJ":
        sys.exit("not a SIDJ project (magic %r)" % data[:4])
    if data[4] != VERSION:
        sys.exit("unsupported SIDJ project version %d (this tool reads %d)" % (data[4], VERSION))
    m = clean_memory()
    i = 5
    while True:
        tag = data[i]
        i += 1
        if tag == 0:
            break
        enc, raw, stored = data[i], data[i + 1] | data[i + 2] << 8, data[i + 3] | data[i + 4] << 8
        i += 5
        body = data[i:i + stored]
        i += stored
        if tag in BLOCKS:
            addr, length = BLOCKS[tag]
            dec = decode_block(enc, raw, body) if (enc >> 4) == 0 or raw == length else None
            if dec is None:
                continue
            dec = dec[:length]
            m[addr:addr + len(dec)] = dec
    return m


def read_input(spec):
    if os.path.exists(spec):
        return open(spec, "rb").read()
    if ":" in spec:
        image, name = spec.rsplit(":", 1)
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "p")
            subprocess.run(["c1541", image, "-read", name.lower(), out], capture_output=True)
            if os.path.exists(out):
                return open(out, "rb").read()
        sys.exit("%s: no file %r on the disk image" % (image, name))
    sys.exit("%s: not found" % spec)


def project_name(m):
    s = ""
    for c in m[HD_NAME:HD_NAME + 16]:
        s += chr(c + 0x40) if 1 <= c <= 26 else chr(c) if 0x20 <= c < 0x40 else " "
    return s.strip()


def song_data(m):
    """phrases, chains, $e000-$f9ff: the order and lengths the images expect"""
    return bytes(m[0x8000:0xBFC0] + m[0xC000:0xD000] + m[0xE000:0xFA00])


def binary(name):
    path = os.path.join(BUILD, name)
    if not os.path.exists(path):
        sys.exit("%s missing: run make first" % path)
    return open(path, "rb").read()


def uses_sid2(m):
    """chains in song slots 3-5 (channels 4-6)"""
    return any(b < 0x80 for b in m[0xE300:0xE600])


def patch_sid2(img, load, sid2):
    """the word right below the song data (PSID) / PLAYER_EXT (.prg)"""
    at = (defs() + 0x100 - 2 if load == 0x1000 else 0x0E00 - 2) - load + 2
    img = bytearray(img)
    assert img[at:at + 2] == b"\0\0", "sid2 word not found in the image"
    img[at:at + 2] = sid2.to_bytes(2, "little")
    return bytes(img)


def make_prg(m, sid2=0):
    img = binary("sidj-prg.bin")              # load address $0801, ends at PLAYER_END
    return patch_sid2(img, 0x0801, sid2) + song_data(m)


def make_sid(m, title, author, released, model, clock, sid2=0):
    player_end = defs()
    img = binary("sidj-sid.bin")              # load address $1000, ends at PLAYER_END + $100
    data = patch_sid2(img, 0x1000, sid2) + song_data(m)
    if 0x1000 + len(data) - 2 > 0xA000:
        sys.exit("image too large")
    pad = lambda s: s.encode("latin-1", "replace")[:32].ljust(32, b"\0")
    mbits = {"6581": 1, "8580": 2, "any": 3}[model]
    flags = {"pal": 1, "ntsc": 2, "any": 3}[clock] << 2 | mbits << 4 | (mbits << 6 if sid2 else 0)
    hdr = (b"PSID" + (3 if sid2 else 2).to_bytes(2, "big") + (0x7C).to_bytes(2, "big")
           + (0).to_bytes(2, "big")                    # load address: first 2 data bytes
           + player_end.to_bytes(2, "big")             # init
           + (player_end + 3).to_bytes(2, "big")       # play
           + (1).to_bytes(2, "big") + (1).to_bytes(2, "big")   # songs, start song
           + (1).to_bytes(4, "big")                    # speed: CIA timer for song 1
           + pad(title) + pad(author) + pad(released)
           + flags.to_bytes(2, "big")
           + bytes([0x04, 0x04])                       # driver space: $0400-$07ff (init fills $8000-$cfff, $e000-$f9ff)
           + bytes([(sid2 >> 4) & 0xFF, 0]))           # 2nd SID ($d420 -> $42), 3rd SID
    assert len(hdr) == 0x7C
    return hdr + data


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("project")
    ap.add_argument("-o", "--out")
    ap.add_argument("--title")
    ap.add_argument("--author", default="")
    ap.add_argument("--released", default="")
    ap.add_argument("--model", default="8580", choices=["8580", "6581", "any"])
    ap.add_argument("--clock", default="pal", choices=["pal", "ntsc", "any"])
    ap.add_argument("--sid2", help="second SID base for channels 4-6 (hex, e.g. d420), or off; "
                    "default d420 if channels 4-6 hold chains")
    a = ap.parse_args()
    m = load_project(read_input(a.project))
    if a.sid2 is None:
        sid2 = 0xD420 if uses_sid2(m) else 0
    else:
        sid2 = 0 if a.sid2.lower() == "off" else int(a.sid2.lstrip("$"), 16)
    if sid2 and not (0xD420 <= sid2 <= 0xDFE0 and sid2 & 0x1F == 0 and not 0xD800 <= sid2 < 0xDE00):
        sys.exit("--sid2: $d420-$d7e0 or $de00-$dfe0, a multiple of $20")
    name = project_name(m) or "untitled"
    out = a.out or name.lower().replace(" ", "_") + ".sid"
    if out.lower().endswith(".prg"):
        data = make_prg(m, sid2)
    elif out.lower().endswith(".sid"):
        data = make_sid(m, a.title or name, a.author, a.released, a.model, a.clock, sid2)
    else:
        sys.exit("output must end in .sid or .prg")
    open(out, "wb").write(data)
    print("%s: %r, %d bytes%s" % (out, name, len(data), ", 2SID at $%04X" % sid2 if sid2 else ""))


if __name__ == "__main__":
    main()
