#!/usr/bin/env python3
"""The SIDJ minisite: build/site/ from docs/MANUAL.md, docs/QUICKREF.md and the
screenshots of tools/mkshots.py.

python3 tools/mksite.py [shots dir] [out dir]   (defaults build/site-shots, build/site)

Pages: index.html (title page, screens, download), one page per manual chapter
(same chapters and numbering as MANUAL.md), quickref.html, boxart.html (the
boards of art/boxart/project). Static HTML, no scripts; build/sidj.d64 is
copied next to it for download.
"""
import html, os, re, shutil, sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mkloader import S, I, D, J              # the loader menu's block logo, 16 pixels high


def logo_svg(cls):
    """SIDJ in the loader's block letters: yellow, orange and dark red shadow (box art colours)"""
    runs, x = [], 0
    for letter in (S, I, D, J):
        for y, row in enumerate(letter):
            for m in re.finditer(r"#+", row):
                runs.append((x + m.start(), y, len(m.group())))
        x += len(letter[0]) + 4
    w = x - 4
    d = "".join("M%d %dh%dv1h-%dz" % (rx, ry, n, n) for rx, ry, n in runs)
    layers = "".join('<path transform="translate(%s %s)" fill="%s" d="%s"/>' % (o, o, c, d)
                     for o, c in ((2, "#880000"), (1, "#dd8855"), (0, "#eeee77")))
    return ('<svg class="%s" viewBox="0 0 %d 18" role="img" aria-label="SIDJ" '
            'shape-rendering="crispEdges">%s</svg>' % (cls, w + 2, layers))

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
B = os.path.join(ROOT, "build")
SHOTS = sys.argv[1] if len(sys.argv) > 1 else os.path.join(B, "site-shots")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(B, "site")
BOXART = os.path.join(ROOT, "art", "boxart")
BOARDS = {"box": (("Main", "front", "Front"), ("Back", "back", "Back")),        # art/boxart/project/canvas.json
          "card": (("Card1", "card1", "Side 1"), ("Card2", "card2", "Side 2"))}

# screenshots after a manual section (heading text starts with the key)
FIGS = {
    "Commodore 64 with disk drive": [("loader", "The loader menu: LOAD\"SIDJ\",8,1 and RUN"),
                                     ("dir", "The disk directory")],
    "4.2 ": [("drum", "PHRASE screen, drum view (REU)")],
    "5.1 ": [("help", "Help page for the SONG screen (SHIFT + F1, REU)")],
    "5.2 ": [("song", "SONG screen, the demo playing")],
    "5.3 ": [("chain", "CHAIN screen")],
    "5.4 ": [("phrase", "PHRASE screen, list view"), ("grid", "PHRASE screen, grid view (CLR/HOME)")],
    "5.5 ": [("instr", "INSTR screen")],
    "5.6 ": [("table", "TABLE screen")],
    "5.7 ": [("groove", "GROOVE screen")],
    "5.8 ": [("project", "PROJECT screen")],
    "5.9 ": [("sid", "SID SETUP screen")],
    "5.10 ": [("file", "FILE screen")],
    "10.1 ": [("live", "SONG screen in live mode (blue border)")],
    "CHAPTER 14": [("taste", "T.A.S.T.E., the tune list")],
}
VERSION = open(os.path.join(ROOT, "VERSION")).read().strip()
FULL = {"loader", "dir"}                         # keep the border (raster bars, directory art)


# ---------------------------------------------------------------- markdown
def inline(s):
    s = html.escape(s, quote=False)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"(?<![\w*])\*([^*\s][^*]*?)\*(?![\w*])", r"<em>\1</em>", s)
    return s


def slug(t):
    return re.sub(r"[^a-z0-9]+", "-", t.lower()).strip("-")


def md(lines, figs=None):
    """markdown subset -> html; figs(heading) -> html after that heading's section"""
    out, i, n = [], 0, len(lines)
    pending = ""

    def flush_fig():
        nonlocal pending
        if pending:
            out.append(pending)
            pending = ""

    while i < n:
        l = lines[i]
        if not l.strip():
            i += 1
            continue
        m = re.match(r"(#{1,4}) (.*)", l)
        if m:
            flush_fig()
            lvl, t = len(m.group(1)), m.group(2).strip()
            out.append('<h%d id="%s">%s</h%d>' % (lvl, slug(t), inline(t), lvl))
            if figs:
                pending = figs(t)
            i += 1
            continue
        if l.startswith("```"):
            j = i + 1
            while j < n and not lines[j].startswith("```"):
                j += 1
            out.append("<pre>%s</pre>" % html.escape("\n".join(lines[i + 1:j])))
            i = j + 1
            continue
        if l.strip() == "---":
            i += 1
            continue
        if l.startswith("|"):
            rows = []
            while i < n and lines[i].startswith("|"):
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
                i += 1
            t = ["<div class=\"tw\"><table><thead><tr>"] + ["<th>%s</th>" % inline(c) for c in rows[0]] + ["</tr></thead><tbody>"]
            for r in rows[2:]:
                t += ["<tr>"] + ["<td>%s</td>" % inline(c) for c in r] + ["</tr>"]
            out.append("".join(t) + "</tbody></table></div>")
            continue
        m = re.match(r"(- |\d+\. )", l)
        if m:
            tag = "ul" if l.startswith("- ") else "ol"
            items = []
            while i < n and re.match(r"(- |\d+\. )", lines[i]):
                item = re.sub(r"^(- |\d+\. )", "", lines[i])
                i += 1
                while i < n and lines[i].startswith("  ") and lines[i].strip():
                    item += " " + lines[i].strip()
                    i += 1
                items.append("<li>%s</li>" % inline(item))
            out.append("<%s>%s</%s>" % (tag, "".join(items), tag))
            continue
        para = [l.strip()]
        i += 1
        while i < n and lines[i].strip() and not re.match(r"(#|```|\||- |\d+\. |---)", lines[i]):
            para.append(lines[i].strip())
            i += 1
        p = " ".join(para)
        m = re.match(r"(NOTE|HINT|WARNING): (.*)", p)
        if m:
            out.append('<aside class="%s"><b>%s</b> %s</aside>' % (m.group(1).lower(), m.group(1), inline(m.group(2))))
        else:
            out.append("<p>%s</p>" % inline(p))
    flush_fig()
    return "\n".join(out)


def figure(name, cap):
    return ('<figure><img src="img/%s.png" alt="%s" width="%d" height="%d" loading="lazy">'
            '<figcaption>%s</figcaption></figure>' % (name, html.escape(cap), *SIZES[name], inline(cap)))


def figs_for(heading):
    for k, v in FIGS.items():
        if heading.startswith(k):
            return "".join(figure(n, c) for n, c in v if n in SIZES)
    return ""


# ---------------------------------------------------------------- pages
CSS = """
:root{--bg:#000;--paper:#121212;--ink:#ececec;--mute:#a0a0a0;--line:#333;--acc:#eeee77;--h:#aaff66;
--code:#1f1f1f;--note:#2b2410;--hint:#122a10;--link:#eeee77}
@media (prefers-color-scheme:light){:root:not([data-theme=dark]){--bg:#e9e6dc;--paper:#fffdf7;--ink:#1a1a1a;--mute:#5c5c5c;
--line:#d6d0bf;--acc:#880000;--h:#880000;--code:#f0ece0;--note:#fff4c2;--hint:#e3f4e6;--link:#0066aa}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.6 "IBM Plex Sans",system-ui,sans-serif}
a{color:var(--link)}
header{background:#000;border-bottom:2px solid #333}
header .in{max-width:1100px;margin:0 auto;padding:14px 16px 10px;display:flex;gap:28px;align-items:center;flex-wrap:wrap}
.logo{display:block;line-height:0}.logo svg{display:block;height:36px;width:auto}
header nav a{font:13px/1 "Bungee",sans-serif;letter-spacing:2px;color:#bbb;text-decoration:none;margin-right:18px}
header nav a:hover,header nav a.on{color:#eeee77}
.stripes{display:flex;flex-direction:column;gap:3px;padding:3px 0;background:#000}
.stripes i{display:block;height:4px}
.s1{background:#eeee77}.s2{background:#dd8855}.s3{background:#ff7777}.s4{background:#aaff66}.s5{background:#0088ff}
.hero{position:relative;overflow:hidden;background:#000;color:#fff;margin:-24px -32px 24px;padding:36px 32px 32px;text-align:center}
.hero .band{position:absolute;left:-10%;right:-10%;top:72px;transform:rotate(-7deg);display:flex;flex-direction:column;gap:6px}
.hero .band i{display:block;height:14px}
.hero h1{position:relative;margin:0;line-height:0}
.hero h1 svg{display:block;margin:0 auto;width:min(560px,86%);height:auto}
.hero .tag{position:relative;margin-top:14px;font:18px/1.3 "Bungee",sans-serif;letter-spacing:2px;color:#aaff66}
.hero .by{position:relative;display:inline-block;margin-top:12px;font:13px/1 "Bungee",sans-serif;letter-spacing:1px;
color:#000;background:#eeee77;padding:6px 10px}
.wrap{max-width:1100px;margin:0 auto;padding:24px 16px;display:grid;grid-template-columns:240px 1fr;gap:32px}
.wrap.one{grid-template-columns:1fr;max-width:900px}
aside.toc{font-size:14px;position:sticky;top:16px;align-self:start;max-height:calc(100vh - 32px);overflow:auto}
aside.toc ol{list-style:none;padding:0;margin:0}
aside.toc li{margin:2px 0}
aside.toc a{text-decoration:none;color:var(--mute);display:block;padding:2px 8px;border-left:3px solid transparent}
aside.toc a.on{color:var(--ink);border-left-color:var(--acc);font-weight:600}
aside.toc ol ol a{padding-left:20px;font-size:13px}
main{background:var(--paper);border:1px solid var(--line);padding:24px 32px;min-width:0;overflow:hidden}
h1,h2{font-family:"Bungee",sans-serif;font-weight:400;letter-spacing:1px;line-height:1.15}
h1{font-size:34px;margin:0 0 8px}
h2{font-size:26px;margin:0 0 14px;color:var(--acc)}
h3{font-size:19px;margin:32px 0 8px;padding-top:8px;border-top:1px solid var(--line);color:var(--h)}
h2+h3{border-top:0;margin-top:8px}
h4{font-size:16px;margin:24px 0 6px}
code{font:14px "IBM Plex Mono",monospace;background:var(--code);padding:1px 4px}
pre{font:20px/1.1 "VT323",monospace;background:var(--code);padding:12px;overflow:auto}
.tw{overflow-x:auto;margin:12px 0}
table{border-collapse:collapse;font-size:15px;width:100%}
th,td{border:1px solid var(--line);padding:5px 9px;text-align:left;vertical-align:top}
th{background:var(--code);font-weight:600}
aside.note,aside.hint,aside.warning{padding:10px 14px;margin:14px 0;border-left:4px solid var(--acc)}
aside.note,aside.warning{background:var(--note)}aside.hint{background:var(--hint);border-left-color:#aaff66}
figure{margin:18px 0}
figure img{display:block;width:100%;max-width:640px;height:auto;image-rendering:pixelated;border:1px solid var(--line)}
figcaption{font-size:14px;color:var(--mute);margin-top:4px}
.pn{display:flex;justify-content:space-between;gap:16px;margin-top:40px;padding-top:16px;border-top:1px solid var(--line)}
.gal{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:16px}
.gal figure{margin:0}
.dl{display:inline-block;background:#eeee77;color:#000;padding:10px 16px;text-decoration:none;font:15px/1 "Bungee",sans-serif;
letter-spacing:1px;margin:8px 10px 8px 0;box-shadow:3px 3px 0 #dd8855,6px 6px 0 #880000}
.dl:hover{background:#aaff66}
.lead{font:20px/1.4 "Bungee",sans-serif;letter-spacing:1px;color:var(--acc);margin:4px 0 8px}
.cards{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin:24px 0}
.cards section{border:1px solid var(--line);border-top:4px solid var(--acc);padding:12px 16px;background:var(--code)}
.cards section:nth-child(2){border-top-color:#dd8855}.cards section:nth-child(3){border-top-color:#aaff66}.cards section:nth-child(4){border-top-color:#0088ff}
.cards h4{margin:0 0 6px;font:15px/1.2 "Bungee",sans-serif;letter-spacing:1px}
.cards p,.cards ul{margin:6px 0;font-size:15px}.cards ul{padding-left:18px}
.disk li{margin:4px 0}
.cards ul.keys{list-style:none;padding:0;display:flex;gap:14px;flex-wrap:wrap}
.cards ul.keys code{display:inline-block;min-width:24px;text-align:center;border:1px solid var(--mute);border-bottom-width:3px;background:var(--paper);padding:0 6px;margin-right:4px;font-weight:600}
.boards{display:flex;flex-wrap:wrap;gap:24px;margin:12px 0}
.boards figure{margin:0;max-width:100%}
.boards .art{overflow:auto;max-width:100%;border:1px solid var(--line);line-height:0}
.boards iframe{border:0;display:block}
footer{max-width:1100px;margin:0 auto;padding:16px;color:var(--mute);font-size:13px}
@media (max-width:800px){.wrap{grid-template-columns:1fr}aside.toc{position:static;max-height:none}main{padding:16px}
.hero{margin:-16px -16px 20px;padding:28px 16px}.cards{grid-template-columns:1fr}}
"""

FONTS = ('<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
         '<link href="https://fonts.googleapis.com/css2?family=Bungee&family=IBM+Plex+Mono&family=IBM+Plex+Sans:wght@400;600&family=VT323&display=swap" rel="stylesheet">')


def page(fn, title, body, nav, toc=""):
    links = "".join('<a href="%s"%s>%s</a>' % (h, ' class="on"' if h == nav else "", t)
                    for h, t in (("index.html", "HOME"), ("loading.html", "MANUAL"), ("quickref.html", "QUICK REF"), ("boxart.html", "BOX ART")))
    wrap = '<div class="wrap">%s<main>%s</main></div>' % (toc, body) if toc else '<div class="wrap one"><main>%s</main></div>' % body
    doc = ('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
           '<title>%s</title>%s<link rel="stylesheet" href="style.css"></head><body>'
           '<header><div class="in"><a class="logo" href="index.html">%s</a><nav>%s</nav></div></header><div class="stripes" aria-hidden="true"><i class="s1"></i><i class="s2"></i><i class="s3"></i><i class="s4"></i><i class="s5"></i></div>%s'
           '<footer>SIDJ %s by illobo/netmilk · a DJ-style tracker for the Commodore 64</footer></body></html>'
           % (html.escape(title), FONTS, logo_svg("lg"), links, wrap, VERSION))
    open(os.path.join(OUT, fn), "w").write(doc)


def boxart():
    """art/boxart boards as plain pages in boxart/ (minus the design tool's scripts), shown in boxart.html"""
    os.makedirs(os.path.join(OUT, "boxart", "shots"), exist_ok=True)
    for f in os.listdir(os.path.join(BOXART, "shots")):
        shutil.copy(os.path.join(BOXART, "shots", f), os.path.join(OUT, "boxart", "shots", f))
    figs = {}
    for group, boards in BOARDS.items():
        figs[group] = ""
        for src, fn, cap in boards:
            doc = open(os.path.join(BOXART, "project", src + ".dc.html")).read()
            w, h = map(int, re.search(r'"width":(\d+),"height":(\d+)', doc).groups())
            doc = doc.replace('<script src="./support.js"></script>\n', "").replace('src="../shots/', 'src="shots/')
            doc = re.sub(r'<script type="text/x-dc".*?</script>\n', "", doc, flags=re.S)
            open(os.path.join(OUT, "boxart", fn + ".html"), "w").write(doc)
            figs[group] += ('<figure><div class="art"><iframe src="boxart/%s.html" width="%d" height="%d" title="%s" loading="lazy">'
                            '</iframe></div><figcaption>%s · <a href="boxart/%s.html">open full size</a></figcaption></figure>'
                            % (fn, w, h, html.escape(cap), cap, fn))
    body = ('<h2>Box art</h2><p>The box and the reference card, as HTML pages. Open one full size to print it.</p>'
            '<h3>Box</h3><div class="boards">%s</div><h3>Reference card</h3><div class="boards">%s</div>' % (figs["box"], figs["card"]))
    page("boxart.html", "SIDJ box art", body, "boxart.html")


def main():
    global SIZES
    os.makedirs(os.path.join(OUT, "img"), exist_ok=True)
    SIZES = {}
    for f in sorted(os.listdir(SHOTS)):
        if f.endswith(".png"):
            n = f[:-4]
            im = Image.open(os.path.join(SHOTS, f)).convert("RGB")
            if n not in FULL and im.size == (384, 272):
                im = im.crop((32, 35, 352, 235))            # the 320 x 200 screen, no border
            im = im.resize((im.width * 2, im.height * 2), Image.NEAREST)
            im.save(os.path.join(OUT, "img", f), optimize=True)
            SIZES[n] = im.size
    open(os.path.join(OUT, "style.css"), "w").write(CSS)

    lines = open(os.path.join(ROOT, "docs", "MANUAL.md")).read().splitlines()
    assert "Version %s " % VERSION in "\n".join(lines[:8]), "MANUAL.md title page: not Version %s" % VERSION
    chapters, cur = [], None                        # (file, title, lines)
    head = []
    for l in lines:
        if l.startswith("## "):
            t = l[3:].strip()
            if t == "CONTENTS":
                cur = ("", t, [])                   # dropped: the sidebar is the contents
                continue
            m = re.match(r"CHAPTER (\d+)", t)
            cur = ("ch%02d.html" % int(m.group(1)) if m else slug(t).split("-")[0] + ".html", t, [])
            chapters.append(cur)
        elif cur:
            cur[2].append(l)
        elif l.startswith("A one-page key reference"):
            pass
        elif not chapters:
            head.append(l)

    def toc(active):
        items = []
        for fn, t, ls in chapters:
            sub = ""
            if fn == active:
                subs = [x[4:].strip() for x in ls if x.startswith("### ")]
                sub = "<ol>%s</ol>" % "".join('<li><a href="#%s">%s</a></li>' % (slug(s), inline(s)) for s in subs) if subs else ""
            items.append('<li><a href="%s"%s>%s</a>%s</li>' % (fn, ' class="on"' if fn == active else "", inline(t), sub))
        return '<aside class="toc"><ol>%s</ol></aside>' % "".join(items)

    for k, (fn, t, ls) in enumerate(chapters):
        body = "<h2>%s</h2>" % inline(t)
        if figs_for(t):
            body += figs_for(t)
        body += md(ls, figs_for)
        prev = '<a href="%s">← %s</a>' % (chapters[k - 1][0], inline(chapters[k - 1][1])) if k else "<span></span>"
        nxt = '<a href="%s">%s →</a>' % (chapters[k + 1][0], inline(chapters[k + 1][1])) if k + 1 < len(chapters) else "<span></span>"
        page(fn, "SIDJ manual · %s" % t, body + '<div class="pn">%s%s</div>' % (prev, nxt), "loading.html", toc(fn))

    q = open(os.path.join(ROOT, "docs", "QUICKREF.md")).read().splitlines()
    page("quickref.html", "SIDJ quick reference", md(q), "quickref.html")
    boxart()

    # home: the manual's title page, a download, the screens, the chapters
    d64 = os.path.join(B, "sidj.d64")
    if os.path.exists(d64):
        shutil.copy(d64, os.path.join(OUT, "sidj.d64"))
    gal = "".join(figure(n, c) for n, c in (("loader", "Loader menu"), ("song", "SONG"), ("chain", "CHAIN"),
                                            ("phrase", "PHRASE"), ("grid", "PHRASE, grid view"), ("drum", "PHRASE, drum view (REU)"),
                                            ("instr", "INSTR"), ("table", "TABLE"), ("project", "PROJECT"),
                                            ("live", "Live mode"), ("help", "Help page (REU)"), ("taste", "T.A.S.T.E."))
                  if n in SIZES)
    band = '<div class="band" aria-hidden="true"><i class="s1"></i><i class="s2"></i><i class="s3"></i><i class="s4"></i><i class="s5"></i></div>'
    body = ('<div class="hero">%s<h1>%s</h1><div class="tag">DJ-STYLE TRACKER FOR THE C64</div>'
            '<div class="by">BY ILLOBO/NETMILK · V%s</div></div>' % (band, logo_svg("big"), VERSION.upper())
            + '<p class="lead">SIDJ is a music tracker for the Commodore 64.</p>'
            + '<aside class="note"><b>NOTE</b> SIDJ %s is experimental. Some things may not work as described, '
              'and a crash can lose your work. Save often.</aside>' % VERSION
            + ('<p><a class="dl" href="sidj.d64">DOWNLOAD SIDJ.D64</a><a class="dl" href="loading.html">READ THE MANUAL</a>'
               '<a class="dl" href="quickref.html">QUICK REFERENCE</a></p>')
            + '<div class="cards">'
              '<section><h4>From phrase to song</h4><p>SIDJ sequences phrases of notes and commands for the SID chip, '
              'then chains them into a song.</p><ul><li>A <b>phrase</b> is 16 steps of notes and commands.</li>'
              '<li>A <b>chain</b> plays phrases in a row.</li><li>A <b>song</b> arranges chains on three channels.</li></ul></section>'
              '<section><h4>Live mode</h4><p>Each channel loops its own chain. Queue the next one and it starts on the beat.</p>'
              '<p><b>Beat repeat:</b> hold a key to repeat the last steps of every channel. Let go and the song plays on.</p>'
              '<ul class="keys"><li><code>,</code> 8 steps</li><li><code>.</code> 4 steps</li><li><code>/</code> 2 steps</li>'
              '<li><code>;</code> 1 step</li></ul></section>'
              '<section><h4>What you need</h4><ul><li>A Commodore 64 or C64 Ultimate</li><li>A 1541 disk drive</li></ul></section>'
              '<section><h4>Extras</h4><ul><li><b>RAM Expansion Unit:</b> undo, help pages, drum view, song slots</li>'
              '<li><b>Second SID:</b> six channels</li><li><b>1351 mouse:</b> click to edit, faders for live play</li></ul></section>'
              '</div>'
            + '<h3>The disk</h3><ul class="disk">'
              '<li><b>SIDJ</b>: the loader menu</li>'
              '<li><b>SIDJ.EDITOR</b>: the tracker</li>'
              '<li><b>T.A.S.T.E.</b>: transverts (extracts and approximately converts) most .SID tunes on a disk '
              'into SIDJ songs, a starting point for experimental remixes</li>'
              '<li><b>README</b> and <b>MANUAL</b>: read them on the C64, with music</li>'
              '<li><b>Songs</b>: a demo and ten tracks to load and remix</li>'
              '<li><b>Kits</b>: three drum kits</li></ul>'
            + "<h3>Screens</h3><div class=\"gal\">%s</div>" % gal
            + "<h3>Manual</h3><ol>%s</ol>" % "".join('<li><a href="%s">%s</a></li>' % (fn, inline(t)) for fn, t, _ in chapters))
    page("index.html", "SIDJ · a DJ-style tracker for the C64", body, "index.html")
    print("%s: %d pages, %d images" % (OUT, len(chapters) + 3, len(SIZES)))


if __name__ == "__main__":
    main()
