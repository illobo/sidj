import vt, re, sys, time, os
# usage: python3 tests.py [prg]  (default build/sidj.prg; starts and stops VICE on port 6512)
PRG = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '../../build/sidj.prg'))
L = {}
for l in open(PRG.replace('.prg', '.labels')):
    m = re.match(r'(\S+)\s*= \$([0-9a-f]+)', l)
    if m: L[m.group(1)] = int(m.group(2), 16)
t = vt.tap
fails = 0
started = False
try:
    vt.mon('r')
except OSError:
    vt.start(PRG); started = True; vt.sleep(6)
def eq(name, got, want):
    global fails
    ok = got == want; fails += not ok
    print(('ok  ' if ok else 'BAD ') + name, got, '' if ok else f'want {want}')
def m1(a): return vt.mem(a, 1)[0]
def hold(mod, d): return [(mod, None), (mod + d, None), (mod, None), ('', None)]
song = lambda r, c: m1(0xe000 + c*256 + r)

# Song: SPACE inserts / allocates, double tap allocates a new chain
vt.script(t('D') + t('D') + t('A') + t('R') + t('A') + t('A') + t('R') + t('A') + [('', None)]*30 + t('A'))
eq('song row 2 after taps', [song(2, c) for c in range(3)], [3, 4, 4])
eq('chain alloc bits', m1(0xf900), 0x1f)
vt.script(hold('A', 'R') + hold('A', 'R')); eq('SPACE+R x2', song(2, 2), 6)
vt.script(hold('A', 'U')); eq('SPACE+U', song(2, 2), 0x16)
vt.script(hold('A', 'U') * 8); eq('SPACE+U clamps at 7f', song(2, 2), 0x7f)
vt.script([('', 1), ('', None), ('', 2), ('', None)]); eq('type 1 2', song(2, 2), 0x12)
vt.script(hold('B', 'A')); eq('cut', song(2, 2), 0xff)
vt.script(hold('S', 'A')); eq('paste', song(2, 2), 0x12)
vt.script(hold('A', 'D') * 3); eq('SPACE+D clamps at 0', song(2, 2), 0)
# key repeat: hold down for 60 frames -> moves more than once
vt.script(t('U') + t('U'))
vt.script([('D', None)] * 40 + [('', None)]); r = m1(L['srow']); eq('repeat moved >3 rows', r > 3, True)
vt.script([('B', None), ('BD', None), ('B', None), ('', None)]); eq('C=+D pages 16', m1(L['srow']), r + 16)
vt.script([('B', None), ('BU', None), ('B', None), ('', None)] * 3); eq('C=+U to 0', m1(L['srow']), 0)
eq('song_top', m1(L['song_top']), 0)
# navigation: Song ch3 row 0 (chain 02) -> Chain -> Phrase
vt.script(hold('S', 'R')); eq('ctrl+R -> chain', (m1(L['screen']), m1(L['cur_chain']), m1(L['cur_chan'])), (1, 2, 2))
vt.script(t('D') + hold('S', 'R')); eq('ctrl+R -> phrase 03', (m1(L['screen']), m1(L['cur_phrase'])), (2, 3))
ph = 0x8000 + 3*64
vt.script(hold('A', 'R') + hold('A', 'U')); eq('note C-1 +1 +12', m1(ph), 0x19)
vt.script([('', 14), ('', None), ('', 5), ('', None)]); eq('type E 5', m1(ph), 0x40)
vt.script(t('D') + t('A')); eq('tap empty step: note+instr', vt.mem(ph+4, 2), [0x40, 0])
vt.script(t('R') + t('R') + [('', 20), ('', None)] + t('R') + [('', 0), ('', None), ('', 3), ('', None)])
eq('cmd K03', vt.mem(ph+6, 2), [11, 3])
vt.script(t('L') + hold('B', 'A')); eq('cut cmd clears value', vt.mem(ph+6, 2), [0, 0])
vt.script(hold('S', 'R')); eq('ctrl+R -> instr 00', (m1(L['screen']), m1(L['cur_instr'])), (3, 0))
vt.script(hold('S', 'R')); eq('ctrl+R -> table', m1(L['screen']), 4)
vt.script(hold('S', 'L') + hold('S', 'L') + hold('S', 'U')); eq('-> project', m1(L['screen']), 6)
vt.script(hold('S', 'D') + hold('S', 'L')); eq('-> phrase -> chain', m1(L['screen']), 1)
# double tap new phrase in chain 02 step 2
vt.script(t('D') + t('A') + t('A')); eq('chain new phrase', m1(0xc000 + 2*32 + 4), 4)
vt.script(hold('S', 'L')); eq('-> song', m1(L['screen']), 0)
# playback / mute / solo
vt.script(t('T')); eq('play song', m1(0x1020), 7)
vt.script(hold('B', 'S')); eq('mute ch3', m1(0x1021), 4)
vt.script(hold('B', 'T')); eq('solo ch3', m1(0x1021), 3)
vt.script(hold('B', 'T')); eq('unsolo', m1(0x1021), 0)
vt.script([('', 0x40), ('', None)]); eq('F1 mute', m1(0x1021), 1)
vt.script([('', 0x40), ('', None)] + t('T')); eq('stop', (m1(0x1021), m1(0x1020)), (0, 0))
vt.script(hold('S', 'T')); eq('ctrl+RETURN play all', m1(0x1020), 7)
vt.script(hold('S', 'T')); eq('ctrl+RETURN stop', m1(0x1020), 0)
vt.script(hold('S', 'R') + t('T')); eq('chain RETURN plays ch3', m1(0x1020), 4)
vt.script(t('T')); eq('chain RETURN stops', m1(0x1020), 0)

# ---------------------------------------------------------------------------
# M2: Groove, Instrument, Table, Project, SID screens; partial redraw
def keys(*codes): return sum(([('', c), ('', None)] for c in codes), [])
def chk_redraw(name):
    eq('redraw consistent: ' + name, vt.redraw_matches(L['need_clear']), [])
INSTR, TABLES, GROOVES, HEADER = 0xe600, 0xea00, 0xf600, 0xf800
ins = lambda i, o: m1(INSTR + i*16 + o)
chk_redraw('chain after M1 tests')
vt.script(t('U') * 3 + hold('S', 'R')); eq('-> phrase 03', (m1(L['screen']), m1(L['cur_phrase'])), (2, 3))
ph = 0x8000 + 3*64
vt.script(t('L') * 3 + hold('B', 'U') + t('D') * 5 + t('R') * 2 + keys(16) + t('R') + keys(0, 1))
eq('G01 typed', vt.mem(ph + 5*4 + 2, 2), [7, 1])
chk_redraw('phrase')
vt.script(hold('S', 'D')); eq('phrase ctrl+D -> groove of G cmd', (m1(L['screen']), m1(L['cur_groove'])), (5, 1))
vt.script(t('A')); eq('groove tap inserts 6', m1(GROOVES + 16), 6)
vt.script(t('D') + keys(0, 3)); eq('groove type 03', m1(GROOVES + 17), 3)
vt.script(hold('A', 'U')); eq('groove spc+U', m1(GROOVES + 17), 0x13)
vt.script(t('D') + t('A') + hold('B', 'A')); eq('groove cut = end', m1(GROOVES + 18), 0)
txt = [l[3:43] for l in vt.screen_text().splitlines()]
eq('groove rows shown', [txt[2][0:4], txt[3][0:4], txt[4][0:4]], ['0 06', '1 13', '2 --'])
eq('groove panel ticks', txt[3][20:29], 'TICKS 019')
chk_redraw('groove')
vt.script(t('U') * 4 + hold('A', 'R')); eq('groove title spc+R', m1(L['cur_groove']), 2)
vt.script(hold('B', 'L')); eq('groove c=+L', m1(L['cur_groove']), 1)
chk_redraw('groove title')
vt.script(hold('S', 'U')); eq('groove ctrl+U returns to phrase', m1(L['screen']), 2)
vt.script(hold('S', 'R')); eq('-> instr of step (04)', (m1(L['screen']), m1(L['cur_instr'])), (3, 4))
vt.script(t('U') * 2 + keys(0, 5)); eq('instr title typed 05', m1(L['cur_instr']), 5)
eq('unused instr gets defaults', [ins(5, 0), ins(5, 1), ins(5, 14)], [0x01, 0x40, 0xff])
vt.script(t('D') + hold('A', 'R') * 3)
eq('preset drum', [ins(5, 0) >> 4, ins(5, 1), ins(5, 14)], [3, 0x80, 0])
eq('drum table', [m1(TABLES), m1(TABLES + 1), m1(TABLES + 0x200 + 1), m1(TABLES + 0x400 + 3)], [0x81, 0x41, 0xfb, 8])
eq('table alloc bit', m1(0xf938) & 1, 1)
vt.script(hold('A', 'R') * 2)
eq('preset arp reuses table', [ins(5, 0), ins(5, 14), m1(TABLES)] + vt.mem(TABLES + 0x200, 3), [0x51, 0, 0xff, 0, 4, 7])
chk_redraw('instr preset')
vt.script(t('D') + hold('A', 'R')); eq('wave toggle T', ins(5, 1), 0x50)
vt.script(t('R') * 2 + hold('A', 'L')); eq('wave toggle P', ins(5, 1), 0x10)
vt.script(t('D') + keys(1, 2)); eq('SR typed (nearest field)', ins(5, 3), 0x12)
vt.script(t('D') + hold('A', 'R')); eq('PW sweep mode up', ins(5, 5), 0x18)
vt.script(t('L') + keys(10, 11, 12)); eq('PW typed abc', [ins(5, 4), ins(5, 5)], [0xbc, 0x1a])
vt.script(hold('A', 'U')); eq('PW spc+U +100', [ins(5, 4), ins(5, 5)], [0xbc, 0x1b])
vt.script(t('D') + t('R') * 5); eq('filter res field', m1(L['colv'] + 3), 5)
vt.script(keys(9) + t('L') * 2 + hold('A', 'D')); eq('res 9, HP on', ins(5, 8), 0x94)
vt.script(t('L') * 4 + hold('A', 'R')); eq('filter use', ins(5, 0) & 0x0c, 4)
vt.script(t('D') + t('R') + hold('A', 'L')); eq('fsweep -1', ins(5, 9), 0xff)
txt = [l[3:43] for l in vt.screen_text().splitlines()]; eq('fsweep shown signed', txt[7][17:20], '-01')
vt.script(t('D') * 3 + t('L') * 2); eq('cursor on table field', (m1(L['rowv'] + 3), m1(L['colv'] + 3)), (10, 0))
vt.script(hold('B', 'A')); eq('cut table', ins(5, 14), 0xff)
vt.script(t('A')); eq('tap empty table: new table', (ins(5, 14), m1(0xf938) & 3), (1, 3))
vt.script(hold('B', 'A') + t('A', 2, 1) + t('A', 2, 1)); eq('spc,spc: another new table', (ins(5, 14), m1(0xf938) & 7), (2, 7))
chk_redraw('instr')
# pre-listen: SPACE held while a field changes plays the instrument on the context channel
ch = m1(L['cur_chan'])
vt.script(t('R') + [('A', None)] * 2 + [('AR', None)] + [('A', None)] * 80, wait=False)
vt.sleep(0.6)
eq('pre-listen note on (gate)', (m1(L['pre_timer']) > 0, m1(0x1050 + 7*ch + 4) & 1), (True, 1))
vt.sleep(1.5)
eq('pre-listen off after release', (m1(L['pre_timer']), m1(0x1050 + 7*ch + 4) & 1), (0, 0))
vt.script(t('L') + hold('S', 'R')); eq('ctrl+R -> its table', (m1(L['screen']), m1(L['cur_table'])), (4, 2))
T2 = TABLES + 2*16
vt.script(t('A')); eq('table ctl tap', m1(T2), 0x41)
vt.script(t('R') + hold('A', 'U') + hold('A', 'D') * 2); eq('table transpose -12', m1(T2 + 0x200), 0xf4)
vt.script(t('R') + keys(17) + t('R') + keys(0, 2)); eq('table H02', [m1(T2 + 0x400), m1(T2 + 0x600)], [8, 2])
txt = [l[3:43] for l in vt.screen_text().splitlines()]; eq('table row shown', txt[2][:16], '0 41 -0C H02 ---')
chk_redraw('table')
vt.script(t('L') + hold('B', 'A')); eq('table cut cmd clears value', [m1(T2 + 0x400), m1(T2 + 0x600)], [0, 0])
vt.script(t('U') + hold('A', 'L')); eq('table title spc+L', m1(L['cur_table']), 1)
chk_redraw('table title')
vt.script(hold('S', 'L') + hold('S', 'L') + hold('S', 'U')); eq('-> project', m1(L['screen']), 6)
vt.script(hold('A', 'R')); eq('tempo +1', (m1(HEADER), m1(0x1022)), (126, 126))
vt.script(keys(2, 9, 5)); eq('tempo typed 295', (m1(HEADER), m1(0x1022)), (0x27, 0x27))
vt.script(hold('A', 'R')); eq('tempo clamps at 295', m1(HEADER), 0x27)
vt.script(hold('A', 'D')); eq('tempo 285', m1(HEADER), 0x1d)
vt.script(keys(4, 0) + hold('A', 'L')); eq('tempo 40, clamps', m1(HEADER), 40)
vt.script(keys(1, 2, 5)); eq('tempo typed 125', (m1(HEADER), m1(0x1022)), (125, 125))
txt = [l[3:43] for l in vt.screen_text().splitlines()]; eq('tempo shown', (txt[2][6:9], txt[0][16:22]), ('125', '125BPM'))
vt.script(t('R') + hold('A', 'U') + hold('A', 'D') * 2); eq('global transpose -12', m1(HEADER + 1), 0xf4)
vt.script(hold('B', 'A')); eq('global transpose cut = 0', m1(HEADER + 1), 0)
vt.script(t('D') + t('L') * 14 + keys(28, 18, 13, 19) + hold('A', 'R'))
eq('name typed', vt.mem(HEADER + 0x10, 5), [19, 9, 4, 10, 1])
chk_redraw('project')
vt.script(t('D') * 2); eq('cursor down to CLEAN (nearest column)', (m1(L['rowv'] + 6), m1(L['colv'] + 6)), (4, 2))
vt.script(hold('S', 'R')); eq('-> sid setup', m1(L['screen']), 7)
txt = [l[3:43] for l in vt.screen_text().splitlines()]; eq('chip model shown', txt[3][8:12] in ('6581', '8580', '????'), True)  # ???? with -sounddev dummy (no SID emulation)
# play markers: compare marker cells with the player's positions while it plays
vt.script(hold('S', 'L') + hold('S', 'D') + hold('S', 'L') + hold('S', 'L') + t('U') * 20); eq('-> song', m1(L['screen']), 0)
vt.script(t('T'))
def marks_ok():
    v = vt.mem(0x0400, 1000); st = vt.mem(0x1020, 0x50)
    playing, rows, chains, csteps = st[0], st[8:11], st[0x10:0x13], st[0x18:0x1b]
    item = m1(0xe000 + m1(L['scol']) * 256 + m1(L['srow']))
    for r in range(16):
        for c in range(3):
            want = 0x3e if playing >> c & 1 and rows[c] == r else 0x20
            if v[(r + 2) * 40 + 2 + 3*c] != want: return False
        want = 0x20
        for c in range(3):
            if playing >> c & 1 and chains[c] == item and csteps[c] == r: want = 0x3e
        if v[(r + 2) * 40 + 21] & 0x7f != want: return False
    return True
ok = 0
for i in range(6):
    vt.sleep(0.37)
    ok += any(marks_ok() or vt.sleep(0.03) for _ in range(3))  # the screen may lag the player by a frame
print('   marker samples ok:', ok)
eq('play markers follow the player (6 samples)', ok, 6)
vt.script(t('T')); eq('stopped', m1(0x1020), 0)
chk_redraw('song after playback')

# ---------------------------------------------------------------------------
# M3: live mode (real player), bookmarks, mark/copy/paste/clone, File screen
PL = 0x1020
pl = lambda o: m1(PL + o)
def txt(): return [l[3:43] for l in vt.screen_text().splitlines()]
def wait_for(cond, secs):
    t0 = time.time()
    while time.time() - t0 < secs:
        if cond(): return time.time() - t0
        vt.sleep(0.05)
    return None
def sample(cond, n=12, dt=0.1):
    for _ in range(n):
        if cond(): return True
        vt.sleep(dt)
    return False
SONG = 0xe000
vt.poke(SONG + 5, 1)                                 # row 5 ch1: chain 01 (switch target)
vt.poke(L['need_clear'], 1); vt.sleep(0.2)
vt.script(t('L') * 3 + t('U') * 4)
eq('song cursor at 0/0', (m1(L['srow']), m1(L['scol'])), (0, 0))
vt.script(hold('S', 'L')); eq('ctrl+L: live mode on', pl(4), 1)
eq('status shows LIVE', txt()[0][:9], 'SONG LIVE')
chk_redraw('song live, stopped')
vt.script(t('T')); eq('live RETURN starts ch1 now', (pl(0) & 1, pl(8)), (1, 0))
vt.script(t('R') + t('T')); vt.sleep(0.3); eq('ch2 starts in step', (pl(0) & 2, pl(9)), (2, 0))
vt.script(t('L') + t('D') * 5 + t('T'), wait=False)
while m1(0x0c00): vt.sleep(0.02)          # until the script is consumed
eq('RETURN queues row 5 at chain end', (pl(0x50), pl(0x58)), (5, 0))
eq('queued cell blinks *', sample(lambda: vt.mem(0x0400 + 7*40 + 2, 1)[0] == 0x2a), True)
eq('queue switch at chain end', wait_for(lambda: pl(8) == 5, 5) is not None, True)
eq('after switch: chain 01, queue empty', (pl(0x10), pl(0x50)), (1, 0xff))
eq('playing cell white (live)', vt.mem(0xd800 + 7*40 + 3, 1)[0] & 15, 1)
vt.sleep(4); eq('live: ch2 loops its chain (row 0)', (pl(0) & 2, pl(9)), (2, 0))
vt.script(t('U') * 5 + t('T', 2, 2) + t('T', 2, 2), wait=False)
eq('RETURN,RETURN: queue at phrase end', wait_for(lambda: (pl(0x50), pl(0x58)) == (0, 1), 2) is not None, True)
dt = wait_for(lambda: pl(8) == 0, 5)
print('   switch after', dt)
eq('phrase-end switch within one phrase (<2.4s)', dt is not None and dt < 2.4, True)
vt.poke(0xc000 + 32 + 4, 1, 0, 2, 0, 1, 0, 2, 0)    # chain 01: 6 phrases, a long stop window
vt.script(t('R'))
wait_for(lambda: pl(0x19) == 0 and pl(0x29) < 4, 5)  # early in ch2's chain
vt.script(hold('S', 'T'), wait=False); vt.sleep(0.3)
eq('ctrl+RETURN queues stop ch2', pl(0x51), 0xfe)
def snap2(a, b):                                     # two bytes read while the emulation is paused
    r = vt.mon(f'm {a:04x} {a:04x}', f'm {b:04x} {b:04x}')
    return [int(m, 16) for m in re.findall(r'>C:[0-9a-f]{4}\s+([0-9a-f]{2})', r)]
xs = [snap2(0x0400 + 40 + 5, L['blink']) for _ in range(8) if pl(0x51) == 0xfe]
print('   header samples (char, blink):', xs)
eq('header shows X exactly while blinking on', (any(b and c == 0x18 for c, b in xs), sum((c == 0x18) != bool(b) for c, b in xs) <= 1), (True, True))  # the redraw may trail the blink flag by one frame
eq('ch2 stops at chain end', wait_for(lambda: (pl(0) & 2) == 0, 14) is not None, True)
vt.poke(0xc000 + 32 + 4, *[0xff, 0] * 4)              # chain 01 back to 2 phrases
vt.script(t('D'))
wait_for(lambda: pl(0x18) == 0 and pl(0x28) < 4, 5)  # early in ch1's chain
vt.script([('', None), ('L', None), ('LT', None), ('L', None), ('', None)], wait=False); vt.sleep(0.15)
eq('left+RETURN queues the row (ch1 waits)', pl(0x50), 1)
eq('left+RETURN: all start/switch', wait_for(lambda: pl(0) == 7 and [pl(8), pl(9), pl(10)] == [1, 1, 1], 5) is not None, True)
vt.script(hold('S', 'L')); eq('ctrl+L: live off', pl(4), 0)
vt.script(t('T')); eq('song mode RETURN stops', pl(0), 0)
eq('status without LIVE', txt()[0][:9], 'SONG     ')

# bookmarks
bm = lambda: vt.mem(0xf820, 2)
vt.script(t('U') * 2 + t('D') * 3 + t('B') * 3); eq('C=,C=,C= bookmarks row 3', bm(), [8, 0])
eq('bookmark row number yellow', vt.mem(0xd800 + 5*40, 1)[0] & 15, 7)
vt.script(t('D') * 7 + t('B') * 3); eq('bookmark row 10', bm(), [8, 4])
vt.script(t('U') * 10 + hold('B', 'D')); eq('C=+D jumps to bookmark 3', m1(L['srow']), 3)
vt.script(hold('B', 'D')); eq('C=+D next bookmark 10', m1(L['srow']), 10)
vt.script(hold('B', 'D')); eq('C=+D wraps to 3', m1(L['srow']), 3)
vt.script(hold('B', 'U')); eq('C=+U wraps back to 10', m1(L['srow']), 10)
chk_redraw('song with bookmarks')
vt.script(t('B') * 3 + hold('B', 'U') + t('B') * 3); eq('bookmarks removed', bm(), [0, 0])
vt.script(hold('B', 'D')); eq('no bookmarks: C=+D pages again', m1(L['srow']), 19)

# block mark / copy / paste on Song
mark = [('S', None), ('SB', None), ('S', None), ('', None)]
vt.script(t('U') * 19 + mark); eq('ctrl+C= starts marking', m1(L['mark_on']), 1)
vt.script(t('D') + t('R') * 2)
x = txt(); eq('block shown reversed', (x[2][3:11], x[3][3:11], x[4][3:5]), ('00 01 02', '00 01 02', '03'))
eq('help line in mark mode', x[24][:5], 'MARK:')
rv = vt.mem(0x0400 + 2*40, 3*40)
eq('block cells reversed, outside not', [rv[r*40 + c] >> 7 for r in (0, 1, 2) for c in (3, 10)], [1, 1, 1, 1, 0, 0])
chk_redraw('song marked block')
vt.script(t('B')); eq('C= copies, ends marking', (m1(L['mark_on']), m1(L['clip_w']), m1(L['clip_h1'])), (0, 3, 1))
vt.script(t('L') * 2 + t('D') * 7 + hold('S', 'A'))
eq('ctrl+SPACE pastes the block at row 8', [song(r, c) for r in (8, 9) for c in range(3)], [0, 1, 2, 0, 1, 2])
vt.script(t('R') + mark + t('D') + hold('S', 'A'))
eq('mark + ctrl+SPACE cuts the block', (song(8, 1), song(9, 1), m1(L['mark_on']), m1(L['clip_w']), m1(L['clip_h1'])), (0xff, 0xff, 0, 1, 1))
vt.script(t('U') * 5 + t('R') + hold('S', 'A'))
eq('column paste on another channel', (song(4, 2), song(5, 2)), (1, 1))
vt.script(hold('B', 'A') + t('D') + hold('B', 'A')); eq('c=+spc cuts cells', (song(4, 2), song(5, 2)), (0xff, 0xff))
# deep clone of chain 00 at row 9 ch1
vt.script(t('D') * 4 + t('L') * 2); eq('cursor on row 9 ch1', (m1(L['srow']), m1(L['scol'])), (9, 0))
achains = vt.mem(0xf900, 16); aphr = vt.mem(0xf910, 32)
def first_free(bits, n, start=0):
    for i in range(start, n):
        if not bits[i >> 3] >> (i & 7) & 1: return i
nch = first_free(achains, 128) or 0; nph = first_free(aphr, 255) or 0
clone = [('S', None), ('SB', None), ('S', None), ('SA', None), ('S', None), ('', None)]
vt.script(clone)
eq('deep clone: new chain in the cell', song(9, 0), nch)
c0 = vt.mem(0xc000, 32); cn = vt.mem(0xc000 + nch*32, 32)
eq('deep clone: one new phrase for both steps, transposes kept', cn[:5], [nph, 0, nph, 5, 0xff])
eq('deep clone: phrase copied', vt.mem(0x8000 + nph*64, 64), vt.mem(0x8000, 64))
eq('deep clone: alloc bits', (m1(0xf900 + (nch >> 3)) >> (nch & 7) & 1, m1(0xf910 + (nph >> 3)) >> (nph & 7) & 1), (1, 1))
# clone mode on the Project screen
vt.script(hold('S', 'R') + hold('S', 'R') + hold('S', 'U')); eq('-> project', m1(L['screen']), 6)
vt.script(t('U') + hold('A', 'R')); eq('clone mode slim', m1(0xf802), 1)
eq('slim shown', txt()[6][8:12].upper(), 'SLIM')
chk_redraw('project clone field')
vt.script(hold('S', 'D') + hold('S', 'L') + hold('S', 'L')); eq('-> song', m1(L['screen']), 0)
vt.script(t('R') * 2); nch2 = first_free(vt.mem(0xf900, 16), 128)
vt.script(clone); eq('slim clone: new chain, same phrases', (song(9, 2), vt.mem(0xc000 + nch2*32, 32)), (nch2, vt.mem(0xc000 + 2*32, 32)))
vt.script(t('L') + clone); eq('clone on an empty cell does nothing', song(9, 1), 0xff)
# phrase clone on the Chain screen
vt.script(t('R') + hold('S', 'R')); eq('-> chain of the slim clone', (m1(L['screen']), m1(L['cur_chain'])), (1, nch2))
vt.script(t('U') * 16 + t('L')); nph2 = first_free(vt.mem(0xf910, 32), 255)
vt.script(clone); ch2 = 0xc000 + nch2*32
eq('phrase clone in chain', m1(ch2), nph2)
eq('phrase clone copied', vt.mem(0x8000 + nph2*64, 64), vt.mem(0x8000 + 3*64, 64))
eq('chain 02 untouched', m1(0xc000 + 2*32), 3)
# phrase block: copy notes 0-3, paste at step 8; block edit +1
vt.script(hold('S', 'R')); eq('-> phrase clone', (m1(L['screen']), m1(L['cur_phrase'])), (2, nph2))
P = 0x8000 + nph2*64; notes = lambda a, b: [m1(P + 4*i) for i in range(a, b)]
vt.script(t('U') * 16 + t('L') * 3 + mark + t('D') * 3 + t('B'))
vt.script(t('D') * 5 + hold('S', 'A')); eq('phrase note block pasted at 8', notes(8, 12), notes(0, 4))
before = notes(0, 4)
vt.script(t('U') * 8 + mark + t('D') * 3 + hold('A', 'R') + t('B'))
eq('block SPACE+R: notes +1', notes(0, 4), [n + 1 if n != 0xff else n for n in before])
chk_redraw('phrase after block ops')
# quick-mark: CTRL held, C= again = whole column, again = whole screen
qm = lambda n: [('S', None)] + [('SB', None), ('S', None)] * n + [('', None)]
vt.script(t('U') * 16 + t('R') + qm(2))
eq('quick-mark: column', (m1(L['mark_on']), m1(L['mark_quick']), m1(L['mark_row']), m1(L['rowv'] + 2)), (1, 1, 0, 15))
chk_redraw('phrase quick-marked column')
vt.script(t('B')); eq('C= copies the column', (m1(L['mark_on']), m1(L['clip_w']), m1(L['clip_h1'])), (0, 1, 15))
vt.script(t('U') * 16 + t('L') + qm(3))
eq('quick-mark: screen', (m1(L['mark_quick']), m1(L['mark_col']), m1(L['colv'] + 2)), (2, 0, 3))
vt.script(t('B')); eq('C= copies the screen', (m1(L['clip_w']), m1(L['clip_h1'])), (4, 15))
vt.script(t('L') * 3 + t('U') * 16 + [('S', None), ('SB', None), ('S', None), ('SD', None), ('S', None), ('SB', None), ('S', None), ('', None)])
eq('mark, move, C= (CTRL held) copies', (m1(L['mark_on']), m1(L['clip_w']), m1(L['clip_h1'])), (0, 1, 1))
# instrument clone: CTRL+(C=,SPACE) on the instrument column (slim: same table)
INS = 0xe600; DEF = [1, 64, 9, 160, 0, 8, 0, 0, 0, 0, 32, 0, 0, 0, 255, 0]
def free_instr():
    bits = vt.mem(0xf930, 8)
    return next(i for i in range(64) if not bits[i >> 3] >> (i & 7) & 1 and vt.mem(INS + i*16, 16) == DEF)
vt.script(t('R') + t('U') * 16); src = m1(P + 1); ni = free_instr()
vt.poke(INS + src*16 + 14, 0)                         # give the source table 00
vt.script(clone); eq('instr clone: new number in the step', m1(P + 1), ni)
eq('instr clone: bytes copied, slim shares the table', vt.mem(INS + ni*16, 16), vt.mem(INS + src*16, 16))
eq('instr clone: alloc bit', m1(0xf930 + (ni >> 3)) >> (ni & 7) & 1, 1)
vt.poke(0xf802, 0); ni2 = free_instr()
nt = first_free(vt.mem(0xf938, 4), 32)
vt.script(clone); eq('deep instr clone: new instrument, new table', (m1(P + 1), m1(INS + ni2*16 + 14)), (ni2, nt))
eq('deep instr clone: table copied (6 columns)', [vt.mem(0xea00 + c*512 + nt*16, 16) for c in range(6)], [vt.mem(0xea00 + c*512, 16) for c in range(6)])
# table clone on the Instrument screen's TABLE field
vt.script(hold('S', 'R')); eq('-> instrument of the clone', (m1(L['screen']), m1(L['cur_instr'])), (3, ni2))
vt.poke(L['rowv'] + 3, 10); vt.poke(L['colv'] + 3, 0); vt.sleep(0.1)
nt2 = first_free(vt.mem(0xf938, 4), 32)
vt.script(clone); eq('table clone: instrument gets the new table', m1(INS + ni2*16 + 14), nt2)
eq('table clone: copied', [vt.mem(0xea00 + c*512 + nt2*16, 16) for c in range(6)], [vt.mem(0xea00 + c*512 + nt*16, 16) for c in range(6)])
eq('table clone: mark ended', m1(L['mark_on']), 0)
chk_redraw('instrument after table clone')
vt.poke(0xf802, 1); vt.script(hold('S', 'L')); eq('-> phrase', m1(L['screen']), 2)

# File screen without a drive (every call fails): fio_msg on the help line
def fmsg(): return ''.join(chr(c + 64) if 1 <= c <= 26 else chr(c) for c in vt.mem(0x7022, 20)).rstrip()
def helpmsg(): return txt()[24][:20].rstrip()
def fscript(steps):                                  # disk calls block the editor for a while
    vt.script(steps)
    for _ in range(300):
        if m1(0x0c00) == 0: break
        vt.sleep(0.1)
    vt.sleep(0.3)
vt.script(hold('S', 'U')); eq('-> project', m1(L['screen']), 6)
fscript(t('D') + t('L') * 3 + t('A')); eq('LOAD -> File screen', (m1(L['screen']), m1(L['rowv'] + 8) <= m1(L['fcount'])), (8, True))
x = txt(); print('   fio_msg:', fmsg()); eq('result on the help line', (helpmsg() == fmsg(), len(fmsg()) > 0), (True, True))
eq('save row shows the name', x[2][:7].upper(), 'SV SIDJ')
fscript([('U', None), ('', None)] * 33 + t('A')); eq('save: result shown, cursor on save row', (helpmsg() == fmsg(), m1(L['rowv'] + 8)), (True, 0))
chk_redraw('file screen')
vt.script(t('D') + t('U')); eq('message gone after a key', txt()[24][:4], 'SPC:')
vt.script(hold('S', 'U')); eq('ctrl+U -> project', m1(L['screen']), 6)
s00 = song(0, 0)
vt.script(t('R') * 2 + t('A')); eq('CLEAN asks first', (txt()[24][:18], m1(L['confirm'])), ('SPC AGAIN: CONFIRM', 1))
fscript(t('A')); eq('CLEAN: result shown, project empty, state reset', (helpmsg() == fmsg(), song(0, 0), vt.mem(0xf900, 2), m1(L['srow']), m1(L['screen'])), (True, 0xff, [0, 0], 0, 6))
chk_redraw('project after clean')
vt.script(t('R')); eq('no EXPORT: CLEAN is the last action', (m1(L['rowv'] + 6), m1(L['colv'] + 6)), (4, 2))
# fake a working module (clc/rts) with two directory entries: list, load, delete
fio_orig = vt.mem(0x7000, 18)
vt.poke(0x0cf0, 0x18, 0x60)                          # clc/rts in a free EDITOR_LOW spot
for i in range(6): vt.poke(0x7000 + 3*i, 0x4c, 0xf0, 0x0c)
vt.poke(0x7022, *[ord(c) - 64 if c.isalpha() else 0x20 for c in 'OK FAKE MODULE      '])
vt.poke(0x7dff, 2)
vt.poke(0x7e00, *[ord(c) - 64 for c in 'SONGA'] + [0x20] * 11 + [ord(c) - 64 for c in 'SONGB'] + [0] * 11)
fscript(t('L') * 3 + t('A')); eq('LOAD with entries: cursor on file 1', (m1(L['screen']), m1(L['fcount']), m1(L['rowv'] + 8)), (8, 2, 1))
x = txt(); eq('directory shown', (x[3][:8].upper(), x[4][:8], x[24][:14]), ('00 SONGA', '01 SONGB', 'OK FAKE MODULE'))
chk_redraw('file screen with entries')
fscript(t('D') + [('B', None), ('BA', None), ('B', None), ('BA', None), ('B', None), ('', None)]); eq('delete (x2) refreshes, stays', (m1(L['screen']), m1(L['rowv'] + 8)), (8, 2))
vt.script(t('A')); eq('load needs a second press', (m1(L['screen']), m1(L['confirm'])), (8, 2))
fscript(t('A')); eq('load ok -> song, cursor reset', (m1(L['screen']), m1(L['srow']), m1(L['cur_chain'])), (0, 0, 0))
vt.poke(0x7000, *fio_orig)                           # the real module again
# ---------------------------------------------------------------------------
# M4: mouse grammar through the mouse debug hook (MDBG_* at $0c02/$0c10),
# tap tempo, nudge, Project mouse settings
C, MS = vt.click, vt.mscript
def cur(scr): return (m1(L['rowv'] + scr), m1(L['colv'] + scr))
def help24(): return txt()[24].rstrip()
vt.script(t('L'))
eq('song screen, cursor 0/0', (m1(L['screen']), m1(L['srow']), m1(L['scol'])), (0, 0, 0))
MS(C(6, 5)); eq('click song cell -> row 3 ch2', (m1(L['srow']), m1(L['scol'])), (3, 1))
eq('pointer sprite on, at the click', (m1(0xd015) & 1, m1(0xd000), m1(0xd001), m1(0x07f8)), (1, 6*8+3+24, 5*8+3+50, 0x2f))
MS(C(6, 5) + C(6, 5)); v = song(3, 1); eq('double-click = SPACE (new chain)', v != 0xff, True)
MS(vt.drag(6, 5, 0, -16)); eq('drag up 16px = 2x SPACE+Up', song(3, 1), v + 0x20)
MS(vt.drag(6, 5, 24, 0)); eq('drag right 24px = 3x SPACE+Right', song(3, 1), v + 0x23)
MS(vt.drag(6, 5, -9, 3)); eq('drag left 9px (x axis wins) = -1', song(3, 1), v + 0x22)
MS(vt.drag(6, 5, 3, 20)); eq('drag down 20px = -16 x2, one axis', song(3, 1), v + 0x02)
v = song(3, 1)
MS(C(6, 5), keys=[('B', None)] * 5 + [('', None)]); eq('C= + click = cut', song(3, 1), 0xff)
MS(C(6, 5), keys=[('S', None)] * 5 + [('', None)]); eq('CTRL + click = paste', song(3, 1), v)
MS(C(6, 5, 'R') * 3); eq('right x3 = C=,C=,C= bookmark row 3', vt.mem(0xf820, 2), [8, 0])
MS(C(6, 5, 'R') * 3); eq('right x3 again removes it', vt.mem(0xf820, 2), [0, 0])
MS(C(5, 1)); eq('click header ch2 = mute', pl(1), 2)
MS(C(5, 1)); eq('click header ch2 again = unmute', pl(1), 0)
MS(C(8, 1, 'R')); eq('right-click header ch3 = solo', pl(1), 3)
MS(C(8, 1, 'R')); eq('right-click header again = unsolo', pl(1), 0)
# hover help
MS([(*vt.cell(5, 1), '')] * 3); eq('hover header: help explains it', help24()[:10], 'CLICK:MUTE')
MS([(*vt.cell(26, 20), '')] * 3); eq('hover map', help24()[:9], 'CTRL+CRSR')
vt.script(t('D') + t('U')); eq('keyboard: help back to the cursor field', help24()[:11], 'CHAIN 00-7F')
# live mode: click queues, double-click at phrase end, right-click stops
vt.poke(0x8000, 0x30, 0, 0, 0)
vt.poke(0xc000 + v*32, *[0, 0] * 6 + [0xff, 0])          # 6 phrases: a long chain
vt.poke(SONG + 256 + 4, v)
vt.poke(L['need_clear'], 1); vt.sleep(0.2)
vt.script(hold('S', 'L')); eq('live on', pl(4), 1)
MS([(*vt.cell(6, 5), '')] * 3); eq('hover chain in live mode', help24()[:11], 'CLICK:QUEUE')
MS(C(6, 5)); vt.sleep(0.2); eq('live click starts ch2', pl(0) & 2, 2)
MS(C(6, 6)); eq('live click row 4 queues it', (pl(0x51), pl(0x59)), (4, 0))
MS(C(6, 5) + C(6, 5)); q = (pl(0x51), pl(0x59), pl(9))
eq('live double-click: queue at phrase end (or already switched)', q[:2] == (3, 1) or (q[0] == 0xff and q[2] == 3), True)
MS(C(6, 5, 'R')); eq('live right-click: queue stop', pl(0x51), 0xfe)
vt.script(hold('S', 'L')); eq('live off', pl(4), 0)
if pl(0): vt.script(t('T'))
eq('stopped', pl(0), 0)
chk_redraw('song after mouse')
# map clicks and fields on every screen
MS(C(26, 20)); eq('map click chn', m1(L['screen']), 1)
MS(C(5, 4)); eq('chain: click transpose step 2', cur(1), (2, 1))
MS(C(2, 9)); eq('chain: click phrase step 7', cur(1), (7, 0))
MS(C(30, 20)); eq('map click phr', m1(L['screen']), 2)
MS(C(10, 7)); eq('phrase: click value step 5', cur(2), (5, 3))
MS(C(6, 3)); eq('phrase: click instr step 1', cur(2), (1, 1))
MS(C(9, 4)); eq('phrase: click command step 2', cur(2), (2, 2))
MS(C(34, 20)); eq('map click ins', m1(L['screen']), 3)
MS(C(4, 4)); eq('instr: click AD', cur(3), (4, 0))
ad = m1(INSTR + m1(L['cur_instr'])*16 + 2)
MS(vt.drag(4, 4, 8, 0)); eq('instr: drag AD right +1', m1(INSTR + m1(L['cur_instr'])*16 + 2), (ad + 1) & 255)
MS(C(14, 4)); eq('instr: click SR', cur(3), (4, 1))
MS(C(14, 3)); eq('instr: click wave P', cur(3), (3, 2))
MS(C(3 + 6, 15)); eq('instr: click usage map -> instrument 16+6', m1(L['cur_instr']), 22)
MS(C(2, 0)); eq('instr: click title', cur(3), (0, 0))
chk_redraw('instr after mouse')
MS(C(38, 20)); eq('map click tbl', m1(L['screen']), 4)
MS(C(6, 4)); eq('table: click transpose step 2', cur(4), (3, 1))
MS(C(14, 6)); eq('table: click 2nd value step 4', cur(4), (5, 5))
MS(C(3, 0)); eq('table: click title', cur(4), (0, 0))
MS(C(34, 21)); eq('map click grv', m1(L['screen']), 5)
MS(C(2, 5)); eq('groove: click step 3', cur(5), (4, 0))
MS(C(30, 19)); eq('map click prj', m1(L['screen']), 6)
MS(C(8, 3)); eq('project: click name char 2', cur(6), (1, 2))
MS(C(17, 12)); eq('project: click mouse speed', cur(6), (6, 1))
MS(vt.drag(17, 12, 8, 0)); eq('mouse speed 2 by drag', m1(L['ms_speed']), 2)
MS(vt.drag(17, 12, -8, 0)); eq('mouse speed back to 1', m1(L['ms_speed']), 1)
eq('mouse line shown', txt()[12][:24].upper(), 'MOUSE PRT1  SPD 1 ACC ON')
MS([(*vt.cell(7, 12), '')] * 3); eq('hover mouse port help', help24()[:10], '1351 MOUSE')
chk_redraw('project mouse line')
# tap tempo: RETURN on the tempo field every 25 frames = 120 BPM; clicks every 18 = 167
MS(C(7, 2)); eq('project: click tempo', cur(6), (0, 0))
vt.sleep(2.5)
vt.script(([('T', None)] + [('', None)] * 24) * 5)
eq('tap tempo RETURN x5 / 25 frames = 120 BPM', (m1(HEADER), pl(2)), (120, 120))
vt.sleep(2.5)
MS((C(7, 2) + [(*vt.cell(7, 2), '')] * 13) * 4)
eq('tap tempo by click x4 / 18 frames = 167 BPM', m1(HEADER), 167)
# nudge: C= + Right/Left held on the tempo field
vt.script([('B', None)] + [('BR', None)] * 60 + [('B', None), ('', None)], wait=False); vt.sleep(0.6)
eq('C=+Right held: pl_nudge +8', pl(5), 8)
vt.sleep(1.2); eq('released: pl_nudge 0', pl(5), 0)
vt.script([('B', None)] + [('BL', None)] * 60 + [('B', None), ('', None)], wait=False); vt.sleep(0.6)
eq('C=+Left held: pl_nudge -8', pl(5), 0xf8)
vt.sleep(1.2); eq('released: pl_nudge 0 again', pl(5), 0)
eq('nudge leaves the tempo alone', m1(HEADER), 167)
# double-click LOAD = SPACE: File screen; a click there moves the cursor
MS(C(1, 8)); eq('click LOAD: cursor only', (cur(6), m1(L['screen'])), ((4, 0), 6))
vt.mscript(C(1, 8) + C(1, 8), wait=False)
for _ in range(300):
    if m1(0x0c00) == 0 and m1(0x0c02) == 0 and m1(L['screen']) == 8: break
    vt.sleep(0.1)
vt.sleep(0.5); eq('double-click LOAD -> File screen', m1(L['screen']), 8)
MS(C(3, 2)); eq('file: click save row', cur(8), (0, 0))
vt.script(hold('S', 'U')); eq('back to project', m1(L['screen']), 6)

# Table screen play marker from pl_tbl/pl_tblstep ($0ff0/$0ff6)
vt.poke(INSTR + 14, 0, 3)                            # instrument 0: table 0, speed 3
vt.poke(0x8000, 0x30, 0, 0, 0)
vt.poke(L['cur_table'], 0); vt.poke(L['cur_chan'], 1); vt.poke(L['cur_songrow'], 3)
MS(C(38, 20)); eq('-> table 0', (m1(L['screen']), m1(L['cur_table'])), (4, 0))
vt.script(t('T')); vt.sleep(0.3); eq('RETURN plays ch2', pl(0) & 2, 2)
def tmarks_ok():
    r = vt.mon('m 0400 07e7', 'm 0ff0 0ffb', 'm 1020 1020')
    v = []
    for line in r.splitlines():
        mm = re.search(r'>C:([0-9a-f]{4})\s+((?:[0-9a-f]{2}\s+)+)', line)
        if mm: v += [int(x, 16) for x in mm.group(2).split()[:16]]
    scr, tb, playing = v[:1000], v[1000:1012], v[1012]
    got = [r for r in range(16) if scr[(r + 2) * 40 + 1] == 0x3e]
    if not (playing & 2 and tb[1] == 0): return got == [], None
    return got in ([tb[7]], [(tb[7] - 1) % 16]), tb[7]    # the screen may lag a step
res = []
for i in range(8):
    vt.sleep(0.13)
    res.append(next((x for x in (tmarks_ok() for _ in range(3)) if x[0]), (False, None)))
print('   table marker samples:', res)
eq('table marker follows pl_tblstep (8 samples)', all(r[0] for r in res) and len({r[1] for r in res}) > 1, True)
vt.script(t('T')); eq('stopped again', pl(0), 0)
chk_redraw('table after marker')

# ---------------------------------------------------------------------------
# M5: grid view of the Phrase screen (grid.asm), Live FX panel (fx.asm)
def col(r, c): return vt.mem(0xd800 + r*40 + c, 1)[0] & 15
def scr(r, c): return vt.mem(0x0400 + r*40 + c, 1)[0]
def gc(s, line=0, cx=1): return ((s & 3) * 5 + cx, 2 + (s >> 2) * 4 + line)   # cell of step s: (col, row)
KG = 0x4f                                            # KC_GRID (debug script stand-in for HOME)
PH = 0x8000 + 0x40 * 64
vt.poke(PH, *([0xff, 0xff, 0, 0] * 16))
vt.poke(PH, 0x24, 1, 0, 0); vt.poke(PH + 5*4, 0x34, 2, 3, 0x37); vt.poke(PH + 9*4, 0x13, 0, 0, 0)
MS(C(30, 20)); eq('-> phrase', m1(L['screen']), 2)
vt.poke(L['cur_phrase'], 0x40); vt.poke(L['rowv'] + 2, 0); vt.poke(L['colv'] + 2, 0); vt.poke(L['need_clear'], 1); vt.sleep(0.2)
vt.script(keys(KG)); eq('HOME (KC_GRID) -> grid view', m1(L['grid_on']), 1)
x = txt(); eq('grid header', x[1][:20], '  GRID (HOME)   LIST')
eq('cells: notes, instr, command (reversed = lowercase)', (x[2][0:3], x[6][5:8], x[7][5:7], x[8][5:8], x[10][5:8], x[11][5:7]), ('C-3', 'e-4', '02', 'c37', 'g-1', '00'))
eq('cell colours: octave 3/4/1, empty dark grey, cursor white', (col(2, 3), col(6, 5), col(10, 5), col(2, 5), col(2, 0)), (7, 13, 2, 11, 1))
eq('cursor field unreversed, rest of the cell reversed', (scr(2, 0) >> 7, scr(2, 3) >> 7, scr(3, 0) >> 7, scr(2, 4)), (0, 1, 1, 0x20))
chk_redraw('grid view')
vt.script(t('D') + t('R')); eq('crsr down/right: step 5', m1(L['rowv'] + 2), 5)
vt.script(t('U') + t('L') + t('L')); eq('up = -4, left stops at step 0', m1(L['rowv'] + 2), 0)
vt.script(t('R') * 3 + t('D') * 4); eq('down stops at the last row: step 15', m1(L['rowv'] + 2), 15)
vt.script(t('U') * 2 + t('L') * 2); eq('step 5', m1(L['rowv'] + 2), 5)
eq('help line: grid', help24()[:9], 'GRID C=+L')
vt.script(hold('B', 'R')); eq('C=+Right: field instr', m1(L['colv'] + 2), 1)
vt.script(hold('A', 'R')); eq('SPACE+R: instr +1', m1(PH + 21), 3)
vt.script(hold('B', 'R') * 2 + hold('A', 'U')); eq('C=+R x2: value; SPACE+U: +10', (m1(L['colv'] + 2), m1(PH + 23)), (3, 0x47))
vt.script(hold('B', 'R')); eq('field stops at value', m1(L['colv'] + 2), 3)
vt.script(hold('B', 'L') * 4); eq('C=+L back to note', m1(L['colv'] + 2), 0)
vt.script(hold('A', 'R') + hold('A', 'U')); eq('SPACE+R/U: note +1 +12', m1(PH + 20), 0x41)
eq('cell shows the edit', txt()[6][5:8], 'F-5')
chk_redraw('grid after edits')
vt.script(t('R') + t('A')); eq('SPACE on empty step 6: last note + instr', vt.mem(PH + 24, 2), [0x41, 3])
vt.script(hold('B', 'A')); eq('C=+SPACE cuts the note', m1(PH + 24), 0xff)
vt.script([('S', None), ('SB', None), ('S', None), ('', None)]); eq('no block marking in the grid', m1(L['mark_on']), 0)
chk_redraw('grid after cut')
MS(C(*gc(10))); eq('click empty cell 10: on (last note, instr)', vt.mem(PH + 40, 2), [0x41, 3])
eq('cursor on the clicked cell', (m1(L['rowv'] + 2), m1(L['colv'] + 2)), (10, 0))
MS(C(*gc(10))); eq('click again: off', vt.mem(PH + 40, 2), [0xff, 0xff])
MS(C(*gc(10, 2))); eq('click on line 2: on again, cursor to the note', (vt.mem(PH + 40, 2), m1(L['colv'] + 2)), ([0x41, 3], 0))
MS(vt.drag(*gc(10), 0, -16)); eq('drag up 16px: pitch +2 semitones', m1(PH + 40), 0x43)
MS(vt.drag(*gc(10), 0, 8)); eq('drag down 8px: -1', m1(PH + 40), 0x42)
MS(vt.drag(*gc(10, 1), -8, 0)); eq('drag left 8px: instrument -1', (m1(PH + 41), m1(L['colv'] + 2)), (2, 1))
x0, y0 = vt.cell(*gc(5, 2, 2))
MS([(x0, y0, ''), (x0, y0, 'R')] + [(x0, y0 - 4*i, 'R') for i in range(1, 5)] + [(x0, y0 - 16, 'R'), (x0, y0 - 16, ''), (x0, y0 - 16, '')])
eq('right drag up 16px: command value +20', (m1(PH + 23), m1(L['rowv'] + 2), m1(L['colv'] + 2)), (0x67, 5, 3))
eq('right drag is not C= (no bookmark/cut)', m1(PH + 22), 3)
MS([(*vt.cell(*gc(3)), '')] * 3); eq('hover cell: grid help', help24()[:9], 'GRID C=+L')
MS([(*vt.cell(17, 1), '')] * 3); eq('hover toggle label', help24()[:13], 'HOME OR CLICK')
vt.script(t('L')); chk_redraw('grid after mouse')
# play marker: phrase 40 in chain 30 at song row 20 (ch1)
vt.poke(0xc000 + 0x30*32, 0x40, 0, 0xff, 0); vt.poke(SONG + 0x20, 0x30)
vt.poke(L['cur_chan'], 0); vt.poke(L['cur_songrow'], 0x20)
vt.script(t('T')); vt.sleep(0.3); eq('RETURN plays ch1', pl(0) & 1, 1)
def gmarks_ok():
    r = vt.mon('m d800 dbe7', 'm 1040 1040', 'm 1048 1048', 'm 1020 1020')
    v = []
    for line in r.splitlines():
        mm = re.search(r'>C:([0-9a-f]{4})\s+((?:[0-9a-f]{2}\s+)+)', line)
        if mm: v += [int(x, 16) for x in mm.group(2).split()[:16]]
    c, ph, st, playing = v[:1000], v[1000], v[1001], v[1002]
    white = [s for s in range(16) if c[(2 + (s >> 2) * 4) * 40 + (s & 3) * 5 + 3] & 15 == 1]
    if not (playing & 1 and ph == 0x40): return white == [], None
    return white in ([st], [(st - 1) % 16]), st
res = []
for i in range(8):
    vt.sleep(0.13)
    res.append(next((x for x in (gmarks_ok() for _ in range(3)) if x[0]), (False, None)))
print('   grid marker samples:', res)
eq('grid play cell follows pl_phrase_step (8 samples)', all(r[0] for r in res) and len({r[1] for r in res}) > 1, True)
vt.script(t('T')); eq('stopped', pl(0), 0)
chk_redraw('grid after playback')
MS(C(17, 1)); eq('click LIST label -> list view', m1(L['grid_on']), 0)
eq('list header with the DRUM and GRID labels', txt()[1][:20], '  NTE IN CMDdrumGRID')
chk_redraw('list after grid')
MS(C(17, 1)); eq('click GRID label -> grid', m1(L['grid_on']), 1)
vt.script(keys(KG)); eq('KC_GRID again -> list', m1(L['grid_on']), 0)
# Live FX faders (rows 18-23); pl_fxmask $1069, values $106a-$106e
fx = lambda i: m1(0x106a + i)
fxm = lambda: m1(0x1069)
vt.poke(0x1069, 0); vt.sleep(0.1)
eq('map moved right of the faders', (txt()[20][21:40].upper(), txt()[18][:4]), ('SNG CHN PHR INS TBL', 'CUT '))
MS(vt.drag(4, 18, 84, 0)); eq('drag cut fader to the right end: ff, latched', (fx(0), fxm() & 1), (0xff, 1))
x = txt(); eq('latched: label reversed yellow, value FF', (x[18][:3], col(18, 0), col(18, 5), x[18][18:20]), ('cut', 7, 7, 'FF'))
MS(C(4, 18)); eq('click on the bar start: value from x (8)', fx(0), 8)
MS(C(8, 18, 'R')); eq('right click releases (bit clear, value kept)', (fxm() & 1, fx(0)), (0, 8))
eq('released: label normal, light blue bar', (txt()[18][:3], col(18, 19)), ('CUT', 14))
MS(C(9, 19)); eq('res: click mid bar = 7, latched', (fx(1), fxm() & 2), (7, 2))
MS(C(9, 19), keys=[('B', None)] * 5 + [('', None)]); eq('C= + click releases res', fxm() & 2, 0)
eff = m1(0x1050 + 0x18) >> 4
MS(C(10, 20)); eq('flt: click HP toggles bit 2 of the shown mode, latched', (fx(2), fxm() & 4), (eff ^ 4, 4))
MS(C(4, 20)); eq('click LP toggles bit 0', fx(2), eff ^ 5)
eq('mode switches shown', [scr(20, c) >> 7 for c in (4, 7, 10, 13)], [(eff ^ 5) >> b & 1 for b in range(4)])
MS(vt.drag(9, 21, -60, 0)); eq('vol: drag to the left end: 0', (fx(3), fxm() & 8), (0, 8))
MS(C(1, 21, 'R')); eq('vol released', fxm() & 8, 0)
ev = m1(0x1050 + 0x18) & 15
MS(C(1, 21)); eq('click on the label latches the shown value', (fx(3), fxm() & 8), (ev, 8))
MS(vt.drag(9, 23, 60, 0)); eq('transp: right end +12', (fx(4), fxm() & 16), (12, 16))
MS(vt.drag(9, 23, -60, 0)); eq('transp: left end -12', fx(4), 0xf4)
MS(C(9, 23)); eq('transp: mid 0', fx(4), 0)
eq('transp shown', txt()[23][17:20], '+00')
m0 = fxm()
MS(vt.drag(4, 22, 40, 0)); eq('tempo bar: HD_TEMPO and player, no latch bit', (m1(HEADER), pl(2), fxm()), (166, 166, m0))
eq('tempo shown', (txt()[22][17:20], txt()[0][16:19]), ('166', '166'))
vt.poke(L['tap_on'], 0)                              # a fresh tap sequence
MS((C(1, 22) + [(*vt.cell(1, 22), '')] * 13) * 4); eq('tap x4 / 18 frames = 167 BPM', m1(HEADER), 167)
def snapn(*a):                                       # bytes read in one monitor stop
    r = vt.mon(*[f'm {x:04x} {x:04x}' for x in a])
    return [int(m, 16) for m in re.findall(r'>C:[0-9a-f]{4}\s+([0-9a-f]{2})', r)]
for c, want in ((16, 8), (15, 0xf8)):
    vt.mscript([(*vt.cell(c, 22), '')] + [(*vt.cell(c, 22), 'L')] * 70 + [(*vt.cell(c, 22), '')] * 2, wait=False); vt.sleep(0.5)
    v = snapn(0x1025, 0x0400 + 22*40 + c); eq(f"hold nudge col {c}: pl_nudge, shown reversed", (v[0], v[1] >> 7), (want, 1))
    vt.sleep(1.5); v = snapn(0x1025, 0x0400 + 22*40 + c); eq('released: pl_nudge 0', (v[0], v[1] >> 7), (0, 0))
eq('nudge leaves the tempo alone', m1(HEADER), 167)
MS([(*vt.cell(6, 18), '')] * 3); eq('hover cut fader', help24()[:7], 'CUTOFF:')
MS([(*vt.cell(1, 22), '')] * 3); eq('hover tempo row', help24()[:4], 'TAP:')
vt.script(t('L')); chk_redraw('fx panel')
MS(vt.drag(4, 18, 84, 0)); eq('cut latched again', fxm() & 1, 1)
vt.poke(0x1069, 0); vt.sleep(0.1)
eq('mask cleared elsewhere (player_init): panel follows', txt()[18][:3], 'CUT')
chk_redraw('fx after mask clear')
MS(vt.drag(4, 18, 84, 0) + C(30, 19)); eq('latched, -> project', (fxm() & 1, m1(L['screen'])), (1, 6))
MS(C(11, 8)); vt.script(t('A')); fscript(t('A')); eq('CLEAN done', song(0, 0), 0xff)
eq('panel shows pl_fxmask after CLEAN', txt()[18][:3], 'cut' if fxm() & 1 else 'CUT')
chk_redraw('fx after clean')

# code under the KERNAL (EDHI) still intact after all the file calls above
# (KERNAL RESTOR once overwrote $fd30-$fd4f with its vector table)
img = open(PRG, 'rb').read(); base = img[0] | img[1] << 8
o = L['stage_hi'] - base + 2; n = L['edhi_vars'] - 0xfd00   # code and strings, not the variables after them
eq('EDHI intact after file I/O', vt.mem(0xfd00, n) == list(img[o:o + n]), True)

print('FAILS', fails)
if started: vt.stop()
sys.exit(1 if fails else 0)
