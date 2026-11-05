"""Extended help pages and the REU preset library in VICE.
Port: SIDJ_VICE_PORT (default 6512). Three runs:
  no REU            F2 says NEEDS REU, a help-row click does nothing, nothing redrawn
  REU, no drive     F2 says NO HELP FILE; extended presets and kits
  REU + SIDJ.HLP    (fresh .d64, true drive) every page by screen, paging, close + redraw, mouse
usage: python3 help.py [prg] [--only noreu|presets|pages]"""
import os, sys, re, subprocess
import vt

ONLY = sys.argv[sys.argv.index('--only') + 1] if '--only' in sys.argv else None
args = [a for a in sys.argv[1:] if not a.startswith('--') and a != ONLY]
HERE = os.path.dirname(os.path.abspath(__file__))
PRG = os.path.abspath(args[0] if args else os.path.join(HERE, '../../build/sidj.prg'))
HLP = os.path.join(os.path.dirname(PRG), 'SIDJ.HLP')
L = {}
for l in open(PRG.replace('.prg', '.labels')):
    m = re.match(r'(\S+)\s*= \$([0-9a-f]+)', l)
    if m: L[m.group(1)] = int(m.group(2), 16)
fails = 0
def eq(name, got, want):
    global fails
    ok = got == want; fails += not ok
    print(('ok  ' if ok else 'BAD ') + name, got, '' if ok else f'want {want}')
t = vt.tap
m1 = lambda a: vt.mem(a, 1)[0]
def hold(mod, d): return [(mod, None), (mod + d, None), (mod, None), ('', None)]
def keys(*codes): return sum(([('', c), ('', None)] for c in codes), [])
F2 = 0x48
def rows(): return [l[3:43] for l in vt.screen_text().splitlines()]
def msg(): return rows()[24][:20].strip()
def redraw(name): eq('redraw consistent: ' + name, vt.redraw_matches(L['need_clear']), [])
def goto(sc, row=None):
    if row is not None: vt.poke(L['rowv'] + sc, row)
    vt.poke(L['screen'], sc); vt.poke(L['need_clear'], 1); vt.sleep(0.3)
SC = dict(song=0, chain=1, phrase=2, instr=3, table=4, groove=5, project=6, sid=7, file=8)
INSTR, TABLES = 0xe600, 0xea00
I = 0x10
def ins(o): return m1(INSTR + I*16 + o)
def pid(): return (ins(0) >> 4) | (ins(15) & 0x10)
def tbl(tn, col, n=8): return vt.mem(TABLES + col*0x200 + tn*16, n)
def tbit(tn): return (vt.mem(0xf938, 4)[tn >> 3] >> (tn & 7)) & 1
def row1(): return rows()[1][10:19].upper()

def run(name, extra, body):
    if ONLY and ONLY != name: return
    print('---', name)
    vt.start(PRG, extra)
    try:
        vt.sleep(6)
        body()
    finally:
        vt.stop()

def noreu():
    eq('no REU', m1(L['u_reu']), 0)
    before = vt.screen_state()
    vt.script(keys(F2))
    eq('F2: NEEDS REU', (msg(), m1(L['hp_on'])), ('NEEDS REU', 0))
    vt.mscript(vt.click(5, 24))
    eq('help row click: nothing opens', m1(L['hp_on']), 0)
    eq('extended preset limits off', (m1(L['p_last']), m1(L['p_ncat']), m1(L['k_nk'])), (0x1f, 7, 3))
    redraw('after F2 without REU')

def presets():
    eq('REU 512 KB', m1(L['u_reu']), 7)
    vt.script(keys(F2))
    eq('F2: NO HELP FILE', (msg(), m1(L['hp_on'])), ('NO HELP FILE', 0))
    eq('limits with an REU', (m1(L['p_last']), m1(L['p_ncat']), m1(L['p_ntl']), m1(L['k_nk'])), (0x49, 13, 28, 6))
    vt.script(hold('S', 'R') * 3)
    vt.script(t('U') * 2 + keys(1, 0) + t('D'))
    eq('instr 10, cursor on preset', (m1(L['screen']), m1(L['cur_instr']), m1(L['rowv'] + 3)), (3, I, 1))
    vt.script(keys(1, 15))
    eq('typed 1f: zap', (pid(), row1()), (0x1f, '1F ZAP   '))
    vt.script(hold('A', 'R'))
    eq('right past 1F: 808kik, stored id 0', (pid(), row1()), (0, '20 808KIK'))
    tn = ins(14)
    eq('808kik bytes', vt.mem(INSTR + I*16, 14) + [ins(15)],
       [0x00, 0x10, 0x0b, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x00])
    eq('808kik table (template 14)', [tbl(tn, 0, 8), tbl(tn, 1, 8), tbl(tn, 2, 8)[6], tbl(tn, 3, 8)[6], tbit(tn)],
       [[0x81, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0xff], [0, 0xf4, 0xee, 0xea, 0xe8, 0xe6, 0xe5, 0], 8, 6, 1])
    redraw('808kik')
    vt.script(hold('A', 'R'))
    eq('hrdkik reuses the table', (row1(), ins(14), tbl(tn, 1, 3)), ('21 HRDKIK', tn, [0x0c, 0xfa, 0xf2]))
    vt.script(hold('A', 'U'))
    eq('up: basses 2C, table freed', (row1(), ins(14), tbit(tn), tbl(tn, 0, 1)), ('2C 808BAS', 0xff, 0, [0xff]))
    vt.script(hold('A', 'U') * 8)
    eq('up clamps at fx 44', row1(), '44 SIREN ')
    vt.script(hold('A', 'R') * 8)
    eq('right clamps at 49', row1(), '49 NSFALL')
    vt.script(hold('A', 'D') * 6)
    eq('down: back to 20', row1(), '20 808KIK')
    vt.script(hold('A', 'D'))
    eq('down: fx 1D', (pid(), row1()), (0x1d, '1D LASER '))
    vt.script(hold('A', 'L') * 3 + hold('A', 'R') * 6)
    eq('left/right across 1F/20', row1(), '20 808KIK')
    # the name shows for the instrument given the preset only
    vt.script(hold('B', 'R'))
    eq('next instrument: custom', row1(), '00 CUSTOM')
    vt.script(hold('B', 'L'))
    eq('back: 808kik again', row1(), '20 808KIK')
    vt.script(keys(0, 0))
    eq('typed 00: custom, table freed', (row1(), ins(14)), ('00 CUSTOM', 0xff))
    redraw('custom')
    # factory kits: ELECTRO, CHIP, ROCK after SYNTH
    def kit(n): vt.script([('S', None)] + [('SA', None), ('S', None)] * n + [('', None)]); return msg()[:8].strip()
    eq('kits with an REU (CTRL held, SPACE n times)', [kit(n) for n in (3, 5, 6, 7)], ['SYNTH', 'CHIP', 'ROCK', 'DRUMS'])
    eq('ELECTRO message', kit(4), 'ELECTRO')
    eq('ELECTRO range', msg(), 'ELECTRO  10-17')
    k = [vt.mem(INSTR + (I + j)*16, 16) for j in range(8)]
    eq('ELECTRO: 808kik, elsnar wave/AD', [(b[1], b[2]) for b in k[:2]], [(0x10, 0x0b), (0x80, 0x07)])
    eq('ELECTRO: ophat (id 9), clap (id B)', [k[3][0] >> 4, k[5][0] >> 4], [9, 0xb])
    tabs = [b[14] for b in k if b[14] != 0xff]
    eq('ELECTRO: own tables', (len(tabs), len(set(tabs)), all(tbit(x) for x in tabs)), (7, 7, True))
    redraw('electro kit')

TITLES = ['SONG', 'CHAIN', 'PHRASE', 'GRID VIEW AND DRUM VIEW', 'INSTRUMENT 00-3F', 'TABLE 00-1F', 'GROOVE 00-1F',
          'PROJECT', 'FILE', 'SID SETUP', 'COMMANDS A-K', 'COMMANDS L-Z', 'LIVE MODE (SONG SCREEN)', 'MOUSE']
PAGE = dict(song=0, chain=1, phrase=2, instr=4, table=5, groove=6, project=7, sid=9, file=8)
def title(): return rows()[1].strip()
def foot(): return rows()[24]

def pages():
    for _ in range(100):                      # SIDJ.HLP loads at start-up
        if m1(L['hp_n']): break
        vt.sleep(0.5)
    eq('SIDJ.HLP loaded: 14 pages', m1(L['hp_n']), 14)
    for sc, n in PAGE.items():
        goto(SC[sc])
        before = vt.screen_state()
        vt.script(keys(F2))
        eq(f'F2 on {sc}: page {n + 1}', (m1(L['hp_on']), title().startswith(TITLES[n].split()[0]), foot()[:10]),
           (1, True, f'HELP {n + 1:02d}/14'))
        eq(f'{sc}: rows 0 and 18-23 kept', [before[r*40:(r+1)*40] for r in (0, 18, 23)],
           [vt.screen_state()[r*40:(r+1)*40] for r in (0, 18, 23)])
        vt.script(t('A'))                    # any other key closes, nothing edited
        eq(f'{sc}: SPACE closes', m1(L['hp_on']), 0)
        redraw(f'{sc} after help')
    goto(SC['song'])
    vt.script(keys(F2))
    eq('page title and colours', (title(), vt.mem(0xd828, 1)[0] & 15), ('SONG', 1))
    vt.script(t('D'))
    eq('down: chain page', (title(), foot()[:10]), ('CHAIN', 'HELP 02/14'))
    vt.script(t('U') * 2)
    eq('up twice: wraps to the last page', (title()[:5], foot()[:10]), ('MOUSE', 'HELP 14/14'))
    vt.script(t('D'))
    eq('down: wraps to page 1', title(), 'SONG')
    vt.sleep(0.5)
    eq('still open, not redrawn', title(), 'SONG')
    row = m1(L['rowv'])
    vt.script(keys(0x43))                    # F7 closes, no undo
    eq('F7 closes', (m1(L['hp_on']), m1(L['rowv'])), (0, row))
    redraw('song after paging')
    goto(SC['phrase'])
    vt.poke(L['grid_on'], 1); vt.poke(L['need_clear'], 1); vt.sleep(0.3)
    vt.script(keys(F2))
    eq('grid view: grid page', title(), TITLES[3])
    vt.script(t('S'))
    eq('CTRL closes', m1(L['hp_on']), 0)
    redraw('grid after help')
    vt.poke(L['grid_on'], 0); goto(SC['instr'])
    vt.mscript(vt.click(10, 24))
    eq('click on the help row: instr page', (m1(L['hp_on']), title()), (1, TITLES[4]))
    vt.mscript(vt.click(10, 5))
    eq('click closes', m1(L['hp_on']), 0)
    vt.sleep(0.3)
    redraw('instr after mouse help')
    eq('cursor not moved by the closing click', m1(L['rowv'] + 3) in (0, 1), True)

D64 = os.path.join(os.path.dirname(PRG), 'help_test.d64')
run('noreu', ['+reu'], noreu)
run('presets', ['-reu', '-reusize', '512'], presets)
if not ONLY or ONLY == 'pages':
    if os.path.exists(D64): os.remove(D64)
    subprocess.run(['c1541', '-format', 'help,01', 'd64', D64], capture_output=True, check=True)
    subprocess.run(['c1541', D64, '-write', HLP, 'sidj.hlp'], capture_output=True, check=True)
run('pages', ['-reu', '-reusize', '512', '-drive8type', '1541', '-drive8truedrive', '-8', D64], pages)
print('FAILS', fails)
sys.exit(1 if fails else 0)
