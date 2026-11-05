"""Undo / redo (F7 / SHIFT+F7) in VICE, with an REU (-reu -reusize 512) and
without (one step). Port: SIDJ_VICE_PORT (default 6511 here).
usage: python3 undo.py [prg] [--reu | --noreu]   (default: both)"""
import os, sys, re, time
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
m1 = lambda a: vt.mem(a, 1)[0]
song = lambda r, c: m1(0xe000 + c*256 + r)
def hold(mod, d): return [(mod, None), (mod + d, None), (mod, None), ('', None)]
def keys(*codes): return sum(([('', c), ('', None)] for c in codes), [])
IDLE = [('', None)] * 12                 # the gesture ends, the scan finishes
F7, F8 = 0x43, 0x4b
def undo(): vt.script(keys(F7) + IDLE)
def redo(): vt.script(keys(F8) + IDLE)
def msg():
    v = vt.mem(0x0400 + 24*40, 20)
    return ''.join(chr(c + 64) if 1 <= c <= 26 else chr(c) for c in v).strip()
def redraw(name):
    eq('redraw consistent: ' + name, vt.redraw_matches(L['need_clear']), [])

for reu in modes:
    print('--- %s REU' % ('with' if reu else 'without'))
    vt.start(PRG, ['-reu', '-reusize', '512'] if reu else ['+reu'])
    try:
        vt.sleep(6)
        eq('REU detected: highest bank', m1(L['u_reu']), 7 if reu else 0)
        if reu:   # start near the end of the ring: slots wrap 255 -> 0
            vt.poke(L['u_head'], 250, 250, 250)
        # Song: row 3 ch1, type 5 then 7 (two gestures)
        vt.script(t('D') * 3 + t('R') + IDLE)
        before = [song(3, c) for c in range(3)]
        vt.script(keys(5) + IDLE + keys(7) + IDLE)
        eq('typed 57', song(3, 1), 0x57)
        undo(); eq('undo -> 05', (song(3, 1), msg()), (0x05 if reu else 0x05, 'UNDO'))
        redraw('song after undo')
        if reu:
            undo(); eq('undo -> empty', song(3, 1), before[1])
            undo(); eq('nothing to undo', (song(3, 1), msg()), (before[1], 'NOTHING TO UNDO'))
            redo(); eq('redo -> 05', (song(3, 1), msg()), (0x05, 'REDO'))
            redo(); eq('redo -> 57', song(3, 1), 0x57)
            redo(); eq('nothing to redo', (song(3, 1), msg()), (0x57, 'NOTHING TO REDO'))
            undo(); eq('undo again -> 05', song(3, 1), 0x05)
        else:
            undo(); eq('one step only', (song(3, 1), msg()), (0x05, 'NOTHING TO UNDO'))
            redo(); eq('redo -> 57', (song(3, 1), msg()), (0x57, 'REDO'))
            redo(); eq('nothing to redo', msg(), 'NOTHING TO REDO')
            undo(); eq('undo -> 05', song(3, 1), 0x05)
        vt.script(keys(9) + IDLE); eq('new edit 59', song(3, 1), 0x59)
        redo(); eq('new edit dropped redo', (song(3, 1), msg()), (0x59, 'NOTHING TO REDO'))
        undo(); eq('undo new edit', song(3, 1), 0x05)
        # SPACE, SPACE on an empty cell: new chain (song page + allocation)
        vt.script(t('D') + IDLE)
        a0 = vt.mem(0xf900, 16)
        vt.script(t('A') + t('A') + IDLE)       # two gestures: last value, then new chain
        new = song(4, 1)
        a1 = vt.mem(0xf900, 16)
        eq('new chain allocated', (new != 0xff, a1[new >> 3] >> (new & 7) & 1), (True, 1))
        undo()
        eq('undo new chain: last value, chain freed', (song(4, 1), a1[new >> 3] != vt.mem(0xf900, 16)[new >> 3]), (0x59, True))
        if reu:
            undo(); eq('undo tap: cell and allocation back', (song(4, 1), vt.mem(0xf900, 16)), (0xff, a0))
            redo()
        redo(); eq('redo new chain', (song(4, 1), vt.mem(0xf900, 16)), (new, a1))
        redraw('song after redo')
        # edits on two screens: phrase 0 step 0 note, then a song cell
        if reu:
            vt.script(t('U') * 4 + t('L') + IDLE)          # row 0 ch0: chain 0
            vt.script(hold('S', 'R') + hold('S', 'R') + IDLE)
            eq('-> phrase 0', (m1(L['screen']), m1(L['cur_phrase'])), (2, 0))
            n0 = m1(0x8000)
            vt.script(hold('A', 'R') + IDLE)
            eq('note +1', m1(0x8000), n0 + 1)
            vt.script(hold('S', 'L') + hold('S', 'L') + IDLE)
            vt.script(t('D') * 6 + keys(3) + IDLE)
            eq('song row 6 typed 3', song(6, 0), 3)
            undo(); undo()
            eq('two undos: both screens back', (song(6, 0), m1(0x8000)), (0xff, n0))
            redo(); redo()
            eq('two redos', (song(6, 0), m1(0x8000)), (3, n0 + 1))
            redraw('song after redos')
            # tempo (header page): undo also resets the player tempo
            vt.poke(L['screen'], 6); vt.poke(L['need_clear'], 1)
            vt.script(IDLE)
            eq('-> project', m1(L['screen']), 6)
            t0 = m1(0xf800)
            vt.script(hold('A', 'R') + IDLE)
            eq('tempo +1', (m1(0xf800), m1(0x1022)), (t0 + 1, t0 + 1))
            undo(); eq('undo tempo: header and player', (m1(0xf800), m1(0x1022)), (t0, t0))
            redraw('project after undo')
            # full ring: the oldest gesture is dropped, the rest stays usable
            h = m1(L['u_head'])
            vt.poke(L['u_base'], (h + 1) & 255)
            vt.script(hold('A', 'R') + IDLE)
            eq('ring full: recorded, base moved', (m1(L['u_head']) == (h + 1) & 255, m1(L['u_base']) != (h + 1) & 255), (True, True))
            undo(); eq('undo after a drop', m1(0xf800), t0)
            # changes at page edges (REU verify: first and last byte)
            for a in (0x8000, 0xcfff, 0xe1ff, 0xf9ff):
                v = m1(a)
                vt.poke(a, v ^ 0x40)
                vt.script(t('D') + IDLE)
                undo(); eq('page edge $%04x undone' % a, m1(a), v)
        # Project CLEAN clears the history
        vt.poke(L['screen'], 6); vt.poke(L['need_clear'], 1)
        vt.poke(L['rowv'] + 6, 4); vt.poke(L['colv'] + 6, 2)   # CLEAN
        vt.script(IDLE)
        vt.script(t('A') + t('A') + IDLE)
        vt.sleep(1)
        eq('clean: project empty', song(0, 0), 0xff)
        undo(); eq('after clean: nothing to undo', (song(0, 0), msg()), (0xff, 'NOTHING TO UNDO'))
        redraw('project after clean')
    finally:
        vt.stop()
print('FAILS', fails)
sys.exit(1 if fails else 0)
