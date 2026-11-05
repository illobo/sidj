"""Drum lane view of the Phrase screen (REU only: overlays 2-4) in VICE, with
an REU (-reu -reusize 512) and without (CLR says NEEDS REU). Port:
SIDJ_VICE_PORT (default 6511 here).
usage: python3 drum.py [prg] [--reu | --noreu]   (default: both)"""
import os, sys, re
os.environ.setdefault('SIDJ_VICE_PORT', '6511')
import vt

args = [a for a in sys.argv[1:] if not a.startswith('--')]
PRG = os.path.abspath(args[0] if args else os.path.join(os.path.dirname(__file__), '../../build/sidj.prg'))
L = {}
for l in open(PRG.replace('.prg', '.labels')):
    m = re.match(r'(\S+)\s*= \$([0-9a-f]+)', l)
    if m: L[m.group(1)] = int(m.group(2), 16)
modes = [m for m in (True, False) if not (('--reu' in sys.argv and not m) or ('--noreu' in sys.argv and m))]
fails = 0
def eq(name, got, want):
    global fails
    ok = got == want; fails += not ok
    print(('ok  ' if ok else 'BAD ') + name, got, '' if ok else f'want {want}')
t = vt.tap
C, MS = vt.click, vt.mscript
m1 = lambda a: vt.mem(a, 1)[0]
def hold(mod, d): return [(mod, None), (mod + d, None), (mod, None), ('', None)]
def keys(*codes): return sum(([('', c), ('', None)] for c in codes), [])
def txt():
    """screen text; drum cells: filled circle ($51) = X, empty circle ($57) = '.'
    (reversed: x / '.'), as vt.screen_text shows other reversed characters"""
    v = vt.mem(0x0400, 1000)
    out = []
    for r in range(25):
        line = ''
        for c in v[r*40:(r+1)*40]:
            cc = c & 0x7f
            if cc == 0x51: ch = 'X'
            elif cc == 0x57: ch = '.'
            elif 1 <= cc <= 26: ch = chr(cc + 64)
            elif 32 <= cc < 64: ch = chr(cc)
            elif cc == 0: ch = '@'
            else: ch = '?'
            out_ch = ch.lower() if c & 0x80 else ch
            line += out_ch
        out.append(line)
    return out
def redraw(name): eq('redraw consistent: ' + name, vt.redraw_matches(L['need_clear']), [])
IDLE = [('', None)] * 12
KG, KD, F7 = 0x4f, 0x4e, 0x43
PH = 0x8000 + 0x40 * 64
ALLOC_INSTR = 0xf930
step = lambda s: vt.mem(PH + s*4, 4)
pl = lambda i: m1(0x1020 + i)

for reu in modes:
    print('--- %s REU' % ('with' if reu else 'without'))
    vt.start(PRG, ['-reu', '-reusize', '512'] if reu else ['+reu'])
    try:
        vt.sleep(6)
        vt.poke(PH, *([0xff, 0xff, 0, 0] * 16))
        vt.poke(PH, 0x30, 6); vt.poke(PH + 4*4, 0x30, 7); vt.poke(PH + 8*4, 0x30, 6, 3, 0x12)
        vt.poke(PH + 12*4, 0x24, 0x20); vt.poke(PH + 14*4, 0x30, 0xff)
        vt.poke(L['cur_instr'], 6); vt.poke(L['cur_phrase'], 0x40); vt.poke(L['rowv'] + 2, 0); vt.poke(L['colv'] + 2, 2)
        vt.poke(L['screen'], 2); vt.poke(L['need_clear'], 1); vt.sleep(0.3)
        eq('list header with the DRUM label', txt()[1][:20], '  NTE IN CMDdrumGRID')
        vt.script(keys(KD))
        if not reu:
            eq('no REU: CLR -> NEEDS REU, list stays', (m1(L['grid_on']), txt()[24][:9]), (0, 'NEEDS REU'))
            MS(C(13, 1)); eq('no REU: drum label click stays in the list', m1(L['grid_on']), 0)
            redraw('list without REU')
            continue
        eq('CLR -> drum view, base = cur_instr, pcol 0', (m1(L['grid_on']), m1(L['dr_base']), m1(L['colv'] + 2)), (2, 6, 0))
        x = txt()
        eq('header: range, drum + list labels', x[1][:20], '06-0D       drumLIST')
        eq('lanes 06 / 07', (x[2][:19], x[3][:19]), ('06 x.......X.......', '07 ....X...........'))
        eq('lane labels 08-0D', [x[r][:2] for r in range(4, 10)], ['08', '09', '0A', '0B', '0C', '0D'])
        eq('?? row: instrument 20 and none', x[10][:19], '?? ............X.X.')
        eq('help line: drum', txt()[24][:12], 'DRUM SPC:HIT')
        redraw('drum view')
        # SPACE: hit on an empty step (C-4, base + lane), same lane again: off
        vt.script(t('R') * 2 + t('D') + t('A'))
        eq('cursor step 2 lane 1', (m1(L['rowv'] + 2), m1(L['dr_lane'])), (2, 1))
        eq('SPACE on empty step 2: C-4, instrument 07', step(2), [0x30, 7, 0, 0])
        eq('instrument 07 marked used', m1(ALLOC_INSTR) >> 7 & 1, 1)
        eq('drawn', txt()[3][:19], '07 ..x.X...........')
        vt.script(t('A')); eq('SPACE again on the lit lane: off', step(2), [0xff, 0xff, 0, 0])
        # last toggle wins, the note stays
        vt.poke(PH + 4*4, 0x3c)
        vt.script(t('R') * 2 + t('U') + t('A'))
        eq('step 4 lane 0: instrument 06, note kept', step(4), [0x3c, 6, 0, 0])
        x = txt(); eq('one hit per step', (x[2][7], x[3][7]), ('x', '.'))
        # C= + SPACE clears note + instrument, never the command
        vt.script(t('R') * 4 + hold('B', 'A'))
        eq('C=+SPACE on step 8: cleared, command kept', step(8), [0xff, 0xff, 3, 0x12])
        # SPACE + Up/Down: pitch +-1
        vt.script(t('A') + hold('A', 'U') + hold('A', 'U'))
        eq('SPACE (on), SPACE + Up x2: the hit stays, +2 semitones', step(8)[:2], [0x32, 6])
        vt.script(hold('A', 'D'))
        eq('SPACE + Down: -1', step(8)[:2], [0x31, 6])
        redraw('drum after edits')
        # C= + Up/Down: lanes
        vt.script(hold('B', 'D') * 2); eq('C=+Down x2: base 08', m1(L['dr_base']), 8)
        eq('header 08-0F', txt()[1][:5], '08-0F')
        vt.script(hold('B', 'U') * 3); eq('C=+Up x3: base 05', m1(L['dr_base']), 5)
        vt.script(hold('B', 'D')); eq('base 06', m1(L['dr_base']), 6)
        # mouse: a cell toggles, a lane label picks the lane
        MS(C(3 + 10, 2 + 3)); eq('click step 10 lane 3: instrument 09, C-4', (step(10)[:2], m1(L['rowv'] + 2), m1(L['dr_lane'])), ([0x30, 9], 10, 3))
        MS(C(3 + 10, 2 + 3)); eq('click again: off', step(10)[:2], [0xff, 0xff])
        MS(C(0, 2 + 5)); eq('click lane label 0B: lane 5, step unchanged', (m1(L['dr_lane']), m1(L['rowv'] + 2)), (5, 10))
        redraw('drum after mouse')
        # undo (F7) restores the last gesture
        vt.script(t('A') + IDLE); eq('SPACE: step 10 lane 5', step(10)[:2], [0x30, 0x0b])
        vt.script(keys(F7) + IDLE); eq('F7: undone', step(10)[:2], [0xff, 0xff])
        eq('drawn after undo', txt()[7][:19], '0B ................')
        redraw('drum after undo')
        # playhead follows pl_phrase_step: phrase 40 in chain 30 at song row 20 (ch1)
        vt.poke(0xc000 + 0x30*32, 0x40, 0, 0xff, 0); vt.poke(0xe000 + 0x20, 0x30)
        vt.poke(L['cur_chan'], 0); vt.poke(L['cur_songrow'], 0x20)
        vt.script([('T', None), ('', None)]); vt.sleep(0.3); eq('RETURN plays ch1', pl(0) & 1, 1)
        res = []
        for i in range(8):
            vt.sleep(0.13)
            r = vt.mon('m 0400 07e7', 'm 1040 1040', 'm 1048 1048', 'm 1020 1020')
            v = []
            for line in r.splitlines():
                mm = re.search(r'>C:([0-9a-f]{4})\s+((?:[0-9a-f]{2}\s+)+)', line)
                if mm: v += [int(q, 16) for q in mm.group(2).split()[:16]]
            sc, ph, st, playing = v[:1000], v[1000], v[1001], v[1002]
            marks = [s for s in range(16) if sc[11*40 + 3 + s] == 0x1e]
            res.append((marks in ([st & 15], [(st - 1) & 15]) and playing & 1 and ph == 0x40, st & 15))
        print('   play row samples:', res)
        eq('playhead follows pl_phrase_step (8 samples)', all(r[0] for r in res) and len({r[1] for r in res}) > 1, True)
        vt.script([('T', None), ('', None)]); eq('stopped', pl(0) & 1, 0)
        vt.sleep(0.2); eq('no playhead when stopped', txt()[11][:19].strip(), '')
        redraw('drum after playback')
        # HOME / CLR / labels
        vt.script(keys(KG)); eq('HOME in drum view -> list', m1(L['grid_on']), 0)
        vt.script(keys(KD)); eq('CLR again -> drum, base kept', (m1(L['grid_on']), m1(L['dr_base'])), (2, 6))
        MS(C(13, 1)); eq('click drum label -> list', m1(L['grid_on']), 0)
        redraw('list after drum')
        MS(C(13, 1)); eq('click drum label in the list -> drum', m1(L['grid_on']), 2)
        MS(C(17, 1)); eq('click LIST label -> list', m1(L['grid_on']), 0)
        vt.script(keys(KG)); eq('HOME -> grid (unchanged)', m1(L['grid_on']), 1)
        vt.script(keys(KD)); eq('CLR from the grid -> drum', m1(L['grid_on']), 2)
        vt.script([('S', None), ('SB', None), ('S', None), ('', None)]); eq('no block marking in the drum view', m1(L['mark_on']), 0)
        vt.script(hold('S', 'L')); eq('CTRL+Left: normal grammar (-> chain)', m1(L['screen']), 1)
        vt.script(hold('S', 'R')); eq('back on the phrase: still drum', (m1(L['screen']), m1(L['grid_on'])), (2, 2))
        redraw('drum after screen switch')
        vt.script(keys(KD)); eq('CLR -> list', m1(L['grid_on']), 0)
        redraw('list at the end')
    finally:
        vt.stop()
print('FAILS', fails)
sys.exit(1 if fails else 0)
