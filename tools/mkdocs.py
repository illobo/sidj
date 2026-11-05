#!/usr/bin/env python3
"""mkdocs: Markdown -> 40-column C64 text for the SIDJ doc reader (src/doc/).

usage: mkdocs.py OUT.asm OUT.json TITLE [--song PROJECT] FILE.md [FILE.md ...]

Each "## " heading starts a chapter (a "# " heading in a file without "## "
headings makes that whole file one chapter). CONTENTS chapters are skipped.
The text is word-wrapped to 40 columns; tables become aligned text.

Text stream per chapter (before compression): every line starts with a byte
$80 + colour, then screen codes ($00-$7f, mixed-case charset); $ff ends the
chapter. Compression: byte-pair encoding with one dictionary for all
chapters. Codes 0..NLIT-1 are literals (doc_lit maps them to bytes), codes
NLIT..255 are pairs (doc_left / doc_right, which may be pairs themselves);
the 6502 side expands them recursively (src/doc/reader.asm unpack).

OUT.asm: 64tass source with the dictionary, chapter names, chapter streams
and (with --song) the song (see song_segments). OUT.json: the rendered text,
for tests/doc_test.py.
"""
import json, re, sys, os

W = 40
# colours (C64 palette numbers)
C_TEXT, C_CHAPTER, C_HEAD, C_NOTE, C_TABLE, C_CODE, C_TH = 15, 7, 13, 10, 14, 8, 3

# custom glyphs the reader puts into its RAM charset (screen code: 8 bytes)
GLYPHS = {
    0x5c: (0x00, 0x3c, 0x7e, 0x7e, 0x7e, 0x7e, 0x3c, 0x00),   # filled circle (PETSCII 113)
    0x5e: (0x00, 0x3c, 0x66, 0x42, 0x42, 0x66, 0x3c, 0x00),   # empty circle (PETSCII 119)
    0x5f: (0x00, 0x08, 0x0c, 0xfe, 0xfe, 0x0c, 0x08, 0x00),   # right arrow
    0x69: (0x18, 0x18, 0x18, 0x18, 0x7e, 0x3c, 0x18, 0x00),   # down arrow
    0x7a: (0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00),   # middle dot
    0x7f: (0x18, 0x18, 0x7e, 0x18, 0x18, 0x00, 0x7e, 0x00),   # plus-minus
}
UNI = {
    "–": "-", "—": "-", "−": "-", "×": "x", "…": "...", "’": "'", "‘": "'", "“": '"', "”": '"',
    "⇄": "<>", "~": "-", "{": "(", "}": ")", "\\": "/", "`": "",
}
GLYPH_OF = {"●": 0x5c, "○": 0x5e, "⇨": 0x5f, "→": 0x5f, "⇩": 0x69, "↓": 0x69, "⇧": 0x1e, "↑": 0x1e,
            "⇦": 0x1f, "←": 0x1f, "·": 0x7a, "±": 0x7f, "|": 0x5d, "│": 0x5d, "─": 0x40,
            "└": 0x6d, "┘": 0x7d, "┌": 0x70, "┐": 0x6e, "_": 0x64, "[": 0x1b, "]": 0x1d, "£": 0x1c}


def scr(ch):
    """one character -> screen code (mixed-case charset)"""
    if ch in GLYPH_OF:
        return GLYPH_OF[ch]
    c = ord(ch)
    if "a" <= ch <= "z":
        return c - 96
    if "A" <= ch <= "Z":
        return c
    if ch == "@":
        return 0
    if 0x20 <= c <= 0x3f:
        return c
    raise ValueError("no screen code for %r" % ch)


def clean(s):
    """inline Markdown -> plain text (bold and code markers dropped)"""
    s = s.replace("**", "").replace("`", "")
    for a, b in UNI.items():
        s = s.replace(a, b)
    return s


def wrap(text, width, first="", rest=""):
    words, lines, cur = text.split(), [], first
    lead = first
    for w in words:
        if len(cur) > len(lead) and len(cur) + 1 + len(w) > width:
            lines.append(cur)
            cur = lead = rest
        while len(w) > width - len(cur):              # very long word: hard split
            room = width - len(cur)
            lines.append(cur + w[:room])
            w, cur = w[room:], rest
            lead = rest
        cur = cur + (" " if len(cur) > len(lead) else "") + w
    if len(cur) > len(lead) or not lines:
        lines.append(cur)
    return lines


def table_lines(rows):
    """rows of cells (header first) -> [(colour, text)]"""
    rows = [[clean(c).strip() for c in r] for r in rows]
    head, body = rows[0], rows[1:]
    n = max(len(r) for r in rows)
    rows = [r + [""] * (n - len(r)) for r in rows]
    head, body = rows[0], rows[1:]
    has_head = any(head)
    allr = rows if has_head else body
    wid = [max(len(r[i]) for r in allr) for i in range(n)]
    out = []
    if sum(wid) + 2 * (n - 1) <= W or sum(wid) + (n - 1) <= W:
        gap = 2 if sum(wid) + 2 * (n - 1) <= W else 1
        for k, r in enumerate(allr):
            t = (" " * gap).join(r[i].ljust(wid[i]) for i in range(n)).rstrip()
            out.append((C_TH if has_head and k == 0 else C_TABLE, t))
        return out
    if n == 2:
        k = min(wid[0], 14)
        if has_head:
            out.append((C_TH, head[0].ljust(k) + " " + head[1] if len(head[0]) <= k else head[0] + " " + head[1]))
        for r in body:
            if len(r[0]) <= k:
                for t in wrap(r[1], W, r[0].ljust(k) + " ", " " * (k + 1)):
                    out.append((C_TABLE, t))
            else:
                for t in wrap(r[0], W, "", "  "):
                    out.append((C_TABLE, t))
                for t in wrap(r[1], W, " " * (k + 1), " " * (k + 1)):
                    out.append((C_TABLE, t))
        return out
    # wide table with more columns: one record per row, "header: value"
    for r in body:
        for t in wrap(r[0], W, "", "  "):
            out.append((C_TABLE, t))
        for i in range(1, n):
            if not r[i] or r[i] == "-":
                continue
            lab = (head[i] + ": ") if has_head and head[i] else ""
            for t in wrap(r[i], W, "  " + lab, "    "):
                out.append((C_TEXT, t))
    return out


def render(md_lines):
    """Markdown body of one chapter -> [(colour, text)]"""
    out, i, para = [], 0, []

    def blank():
        if out and out[-1][1] != "":
            out.append((C_TEXT, ""))

    def flush():
        if para:
            t = clean(" ".join(para))
            col = C_NOTE if re.match(r"(NOTE|HINT|WARNING):", t) else C_TEXT
            out.extend((col, s) for s in wrap(t, W))
            para.clear()
            blank()

    while i < len(md_lines):
        l = md_lines[i].rstrip()
        s = l.strip()
        if s.startswith("```"):
            flush()
            i += 1
            while i < len(md_lines) and not md_lines[i].strip().startswith("```"):
                t = clean(md_lines[i].rstrip())
                while len(t) > W:
                    out.append((C_CODE, t[:W]))
                    t = "  " + t[W:]
                out.append((C_CODE, t))
                i += 1
            blank()
        elif s.startswith("|"):
            flush()
            rows = []
            while i < len(md_lines) and md_lines[i].strip().startswith("|"):
                cells = md_lines[i].strip().strip("|").split("|")
                if not all(re.fullmatch(r"\s*:?-+:?\s*", c) for c in cells):
                    rows.append(cells)
                i += 1
            out.extend(table_lines(rows))
            blank()
            continue
        elif s.startswith("#"):
            flush()
            t = clean(s.lstrip("#").strip())
            out.extend((C_HEAD, x) for x in wrap(t, W))
            out.append((C_HEAD, chr(0x40) * 0))       # (no underline)
            out.pop()
        elif s == "---" or s == "":
            flush()
        elif re.match(r"(- |\* |\d+\. )", s):
            flush()
            m = re.match(r"(- |\* |\d+\. )(.*)", s)
            mark = "- " if m.group(1) in ("- ", "* ") else m.group(1)
            item = [m.group(2)]
            i += 1
            while i < len(md_lines) and md_lines[i].strip() and not re.match(r"\s*(- |\* |\d+\. |\||#|```)", md_lines[i]):
                item.append(md_lines[i].strip())
                i += 1
            t = clean(" ".join(item))
            col = C_NOTE if re.match(r"(NOTE|HINT):", t) else C_TEXT
            out.extend((col, x) for x in wrap(t, W, mark, " " * len(mark)))
            if i < len(md_lines) and not md_lines[i].strip():
                blank()
            continue
        else:
            para.append(s)
        i += 1
    flush()
    while out and out[-1][1] == "":
        out.pop()
    return out


def chapters(path):
    """[(title, [md lines])] of one Markdown file"""
    lines = open(path, encoding="utf-8").read().split("\n")
    if not any(l.startswith("## ") for l in lines):
        t = next(l for l in lines if l.startswith("# "))
        body = [l for l in lines if l is not t]
        return [(re.sub(r"^SIDJ\W+", "", clean(t[2:].strip()).replace(chr(0xb7), "-")).strip(), body)]
    res, cur = [], None
    for l in lines:
        if l.startswith("## "):
            cur = (clean(l[3:].strip()), [])
            res.append(cur)
        elif cur is not None:
            cur[1].append(l)
    return [c for c in res if c[0] != "CONTENTS"]


def stream(title, lines):
    """chapter -> byte stream: title line, blank, text, $ff"""
    b = bytearray()
    for col, t in [(C_CHAPTER, title), (C_TEXT, "")] + lines:
        assert len(t) <= W, (title, t)
        b.append(0x80 | col)
        b += bytes(scr(ch) for ch in t)
    b.append(0xff)
    return bytes(b)


def bpe(streams):
    """byte-pair encoding over all chapters: (literals, pairs, encoded)"""
    lits = sorted(set(b for s in streams for b in s))
    code = {b: i for i, b in enumerate(lits)}
    seqs = [[code[b] for b in s] for s in streams]
    pairs = []
    nxt = len(lits)
    while nxt < 256:
        cnt = {}
        for s in seqs:
            prev = None
            for k in range(len(s) - 1):
                p = (s[k], s[k + 1])
                if p == prev:              # do not count overlapping aa in aaa twice
                    prev = None
                    continue
                cnt[p] = cnt.get(p, 0) + 1
                prev = p
        if not cnt:
            break
        best = max(cnt, key=cnt.get)
        if cnt[best] < 3:
            break
        pairs.append(best)
        for j, s in enumerate(seqs):
            o, k = [], 0
            while k < len(s):
                if k + 1 < len(s) and (s[k], s[k + 1]) == best:
                    o.append(nxt)
                    k += 2
                else:
                    o.append(s[k])
                    k += 1
            seqs[j] = o
        nxt += 1
    return lits, pairs, [bytes(s) for s in seqs]


def unbpe(lits, pairs, enc):
    nl = len(lits)
    out = bytearray()

    def ex(c):
        if c < nl:
            out.append(lits[c])
        else:
            l, r = pairs[c - nl]
            ex(l)
            ex(r)
    for c in enc:
        ex(c)
    return bytes(out)


def depth(lits, pairs):
    nl = len(lits)
    memo = {}

    def d(c):
        if c < nl:
            return 0
        if c not in memo:
            memo[c] = 1 + max(d(pairs[c - nl][0]), d(pairs[c - nl][1]))
        return memo[c]
    return max([d(nl + i) for i in range(len(pairs))] or [0])


# ---------------------------------------------------------------------------
# song: the parts of a project the player reads, as RLE segments
ESC = 0xE7


def song_segments(path):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import sidj2sid
    m = sidj2sid.load_project(open(path, "rb").read())
    chains = set(b for b in m[0xE000:0xE600] if b < 0x80)
    phrases = set()
    for c in chains:
        for st in range(16):
            p = m[0xC000 + c * 32 + st * 2]
            if p != 0xFF:
                phrases.add(p)
    nph = max(phrases) + 1 if phrases else 0
    nch = max(chains) + 1 if chains else 0
    segs = [(0x8000, m[0x8000:0x8000 + nph * 64]), (0xC000, m[0xC000:0xC000 + nch * 32]),
            (0xE000, m[0xE000:0xFA00])]
    return segs, 0x8000 + nph * 64, 0xC000 + nch * 32


def rle(data):
    out, i = bytearray(), 0
    while i < len(data):
        v, n = data[i], 1
        while i + n < len(data) and data[i + n] == v and n < 255:
            n += 1
        if n >= 4 or v == ESC:
            out += bytes([ESC, n, v])
        else:
            out += bytes([v] * n)
        i += n
    return bytes(out)


def asm_bytes(label, data):
    s = [label] if label else []
    for k in range(0, len(data), 16):
        s.append("        .byte " + ",".join("$%02x" % b for b in data[k:k + 16]))
    return "\n".join(s) + "\n"


def main():
    a = sys.argv[1:]
    out_asm, out_json, title = a[0], a[1], a[2]
    a = a[3:]
    song = None
    if a[0] == "--song":
        song, a = a[1], a[2:]
    chs = []
    for f in a:
        chs += chapters(f)
    rendered = [(t, render(body)) for t, body in chs]
    streams = [stream(t, ls) for t, ls in rendered]
    lits, pairs, enc = bpe(streams)
    for s, e in zip(streams, enc):
        assert unbpe(lits, pairs, e) == s
    raw = sum(len(s) for s in streams)
    packed = sum(len(e) for e in enc) + len(lits) + 2 * len(pairs)
    src = ["; generated by tools/mkdocs.py from %s; do not edit\n" % " ".join(os.path.basename(f) for f in a)]
    src.append("DOC_NCH = %d\nDOC_NLIT = %d\nDOC_DEPTH = %d\nDOC_MAXRAW = %d\nDOC_MAXLINES = %d\n" % (
        len(chs), len(lits), depth(lits, pairs), max(len(s) for s in streams),
        max(len(l) + 2 for _, l in rendered)))
    src.append("        .enc \"screen\"\n")
    tt = bytes(scr(ch) for ch in title.ljust(16)[:16])
    src.append(asm_bytes("doc_title", tt))
    src.append("DOC_NGLYPH = %d\n" % len(GLYPHS))
    src.append(asm_bytes("doc_gcode", bytes(GLYPHS)))
    src.append(asm_bytes("doc_gdata", bytes(b for g in GLYPHS.values() for b in g)))
    src.append(asm_bytes("doc_lit", bytes(lits)))
    src.append(asm_bytes("doc_left", bytes(p[0] for p in pairs) or b"\0"))
    src.append(asm_bytes("doc_right", bytes(p[1] for p in pairs) or b"\0"))
    names = []
    for k, (t, _) in enumerate(chs):
        t = t if len(t) <= 34 else t[:34]
        names.append(bytes(scr(ch) for ch in t.ljust(34)))
    src.append(asm_bytes("doc_names", b"".join(names)))
    src.append("doc_chlo .byte " + ",".join("<doc_ch%d" % k for k in range(len(chs))) + "\n")
    src.append("doc_chhi .byte " + ",".join(">doc_ch%d" % k for k in range(len(chs))) + "\n")
    song_info = None
    if song:
        segs, ph_end, ch_end = song_segments(song)
        src.append("SONG_PH_END = $%04x\nSONG_CH_END = $%04x\n" % (ph_end, ch_end))
        body = bytearray()
        for addr, data in segs:
            r = rle(data)
            body += bytes([addr & 255, addr >> 8, len(r) & 255, len(r) >> 8]) + r
        body += b"\0\0"
        src.append(asm_bytes("song_data", bytes(body)))
        song_info = {"file": song, "bytes": len(body), "phrases_end": ph_end, "chains_end": ch_end}
    else:
        src.append("SONG_PH_END = $8000\nSONG_CH_END = $c000\n")
    for k, e in enumerate(enc):
        # a chapter that does not fit below DOC_AEND goes on at DOC_B (the reader sets both)
        src.append("        .if * + %d > DOC_AEND && * <= DOC_AEND\n        * = DOC_B\n        .fi\n" % len(e))
        src.append(asm_bytes("doc_ch%d" % k, e))
    info = {"title": title, "raw": raw, "packed": packed, "literals": len(lits), "pairs": len(pairs),
            "depth": depth(lits, pairs), "chapters": [{"title": t, "lines": [[c, x] for c, x in [(C_CHAPTER, t), (C_TEXT, "")] + ls]}
                                                      for t, ls in rendered]}
    if song_info:
        info["song"] = song_info
    src.append("        .enc \"none\"\n")
    open(out_asm, "w").write("".join(src))
    json.dump(info, open(out_json, "w"), indent=0)
    print("%s: %d chapters, %d bytes text -> %d bytes (%.1f%%), %d literals, %d pairs, depth %d%s" % (
        out_asm, len(chs), raw, packed, 100.0 * packed / raw, len(lits), len(pairs), depth(lits, pairs),
        ", song %d bytes" % info["song"]["bytes"] if song else ""))


if __name__ == "__main__":
    main()
