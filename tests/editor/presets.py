import vt, re, sys, os
# Factory presets and preview while browsing.
# usage: python3 presets.py [prg]  (default build/sidj.prg; starts and stops VICE on port 6512)
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
def keys(*codes): return sum(([('', c), ('', None)] for c in codes), [])
INSTR, TABLES = 0xe600, 0xea00
I = 0x10                                            # instrument under test
def ins(o): return m1(INSTR + I*16 + o)
def pid(): return (ins(0) >> 4) | (ins(15) & 0x10)
def tbl(t, col, n=6): return vt.mem(TABLES + col*0x200 + t*16, n)
def row1(): return [l[3:43] for l in vt.screen_text().splitlines()][1][10:19].upper()   # reversed: lower case
def talloc(): return vt.mem(0xf938, 4)
def tbit(t): return (talloc()[t >> 3] >> (t & 7)) & 1
def gate(ch): return m1(0x1050 + 7*ch + 4) & 1
def chk_redraw(name):
    eq('redraw consistent: ' + name, vt.redraw_matches(L['need_clear']), [])

# Song -> chain -> phrase -> instrument, then instrument 10 (unused)
vt.script(hold('S', 'R') * 3)
eq('instrument screen', m1(L['screen']), 3)
vt.script(t('U') * 2 + keys(1, 0) + t('D'))
eq('instr 10, cursor on preset', (m1(L['cur_instr']), m1(L['rowv'] + 3)), (I, 1))
eq('default instrument = preset 0', (pid(), ins(1), ins(14)), (0, 0x40, 0xff))
eq('name custom', row1(), '00 CUSTOM')

# SPACE+Right x6: kick (id 6), table from template 3
vt.script(hold('A', 'R') * 6)
eq('kick id', pid(), 6)
kt = ins(14)
eq('kick bytes', [ins(o) for o in (0, 1, 2, 3, 15)], [0x60, 0x40, 0x07, 0x00, 0x00])
eq('kick table ctl/tr', [tbl(kt, 0), tbl(kt, 1)], [[0x81, 0x41, 0x41, 0x11, 0x11, 0xff], [0, 0xf4, 0xee, 0xea, 0xe7, 0]])
eq('kick table H04 at row 4', [tbl(kt, 2)[4], tbl(kt, 3)[4], tbl(kt, 4)[4]], [8, 4, 0])
eq('kick table allocated', tbit(kt), 1)
eq('name kick', row1(), '06 KICK  ')
chk_redraw('kick')

# SPACE+Up: next category (basses, 14): table freed again
vt.script(hold('A', 'U'))
eq('up -> pulsbs 14', (pid(), ins(0), ins(14), ins(15)), (14, 0xe1, 0xff, 0))
eq('kick table emptied and freed', (tbit(kt), tbl(kt, 0, 1), tbl(kt, 1, 2)), (0, [0xff], [0, 0]))
eq('name pulsbs', row1(), '0E PULSBS')
vt.script(hold('A', 'U'))
eq('up -> pwmld 19: id bit 4 in table speed', (pid(), ins(0), ins(15)), (19, 0x31, 0x10))
eq('name pwmld', row1(), '13 PWMLD ')
chk_redraw('pwmld')
vt.script(hold('A', 'D'))
eq('down -> 14', pid(), 14)
vt.script(hold('A', 'D')); eq('down -> 6', pid(), 6)
vt.script(hold('A', 'D')); eq('down -> 0', pid(), 0)
vt.script(hold('A', 'D')); eq('down at 0 stays', pid(), 0)
vt.script(hold('A', 'L')); eq('left at 0 stays', pid(), 0)
vt.script(hold('A', 'U') * 8); eq('up clamps at the last category (fx, 29)', pid(), 29)
vt.script(hold('A', 'R') * 3); eq('right clamps at 31', pid(), 31)
eq('name zap', row1(), '1F ZAP   ')

# typed hex digits: 1 d -> laser (29): bend row
vt.script(keys(1, 13))
eq('typed 1d -> laser', pid(), 29)
lt = ins(14)
eq('laser table', [tbl(lt, 0, 3), tbl(lt, 1, 3), tbl(lt, 2, 3), tbl(lt, 3, 3)],
   [[0xff, 0xff, 0xff], [0x18, 0x18, 0], [16, 8, 0], [0xc0, 1, 0]])
vt.script(keys(1, 14))
eq('typed 1e -> noisup reuses the laser table', (pid(), ins(14), tbl(lt, 3, 2)), (30, lt, [0x20, 1]))

# ids 0-5 keep their meaning (pre-library bytes; id in flags bits 4-7)
OLD = {1: [0x11,0x40,0x09,0xa9,0x00,0x14,0x18,0x00,0x00,0x00,0x20,0x00,0x34,0x0a,0xff,0x00],
       2: [0x29,0x40,0x09,0xa6,0x00,0x06,0x00,0x30,0x81,0xfe,0x20,0x00,0x00,0x00,0xff,0x00],
       4: [0x41,0x20,0x88,0x8a,0x00,0x08,0x00,0x00,0x00,0x00,0x20,0x00,0x22,0x20,0xff,0x00]}
for i, b in OLD.items():
    vt.script(keys(0, i))
    eq(f'old preset {i} bytes', vt.mem(INSTR + I*16, 16), b)
vt.script(keys(0, 3))
dt = ins(14)
eq('old drum', [ins(0), ins(1), ins(2), ins(15)], [0x30, 0x80, 0x08, 0])
eq('old drum table', [tbl(dt, 0, 4), tbl(dt, 1, 4), tbl(dt, 2, 4)[3], tbl(dt, 3, 4)[3]], [[0x81, 0x41, 0x41, 0x41], [0, 0xfb, 0xf6, 0xf1], 8, 3])
vt.script(keys(0, 5))
eq('old arp reuses the table', [ins(0), ins(14), ins(15)] + tbl(dt, 1, 3) + [tbl(dt, 2, 3)[2]], [0x51, dt, 0x01, 0, 4, 7, 8])
vt.script(keys(0, 0))
eq('custom: table freed', (ins(0), ins(14), tbit(dt)), (0x01, 0xff, 0))
chk_redraw('old presets')

# a preset table another instrument uses is kept: 11 gets this table
vt.script(keys(0, 3)); dt = ins(14)
vt.poke(INSTR + 0x11*16 + 14, dt)
vt.script(keys(0, 5))
eq('shared table not reused: new one', (ins(14) != dt, tbl(dt, 0, 1)), (True, [0x81]))
vt.poke(INSTR + 0x11*16 + 14, 0xff)
vt.script(keys(0, 0))

# preview: SPACE held while the preset changes plays it on the context channel
ch = m1(L['cur_chan'])
vt.script([('A', None)] * 2 + [('AR', None)] + [('A', None)] * 60, wait=False)
vt.sleep(0.5)
eq('preview: note on (gate, pre_timer)', (gate(ch), m1(L['pre_timer']) > 0, pid()), (1, True, 1))
eq('preview: preset instrument on the channel', vt.mem(0x1050 + 7*ch + 5, 2), [0x09, 0xa9])
vt.sleep(1.5)
eq('preview: off after SPACE release', (gate(ch), m1(L['pre_timer'])), (0, 0))
vt.script(keys(1, 13), wait=False); vt.sleep(0.15)
eq('typed preset: preview note on', gate(ch), 1)
vt.sleep(0.8)
eq('typed preset: off after ~0.25 s', gate(ch), 0)
# channel playing: no preview, playback state untouched
vt.script(t('T'))
playing = m1(0x1020)
eq('RETURN plays the context channel', (playing >> ch) & 1, 1)
vt.script(hold('A', 'L'))
eq('no preview while the channel plays', (m1(L['pre_timer']), m1(0x1020)), (0, playing))
vt.script(t('T'))
eq('stopped', m1(0x1020), 0)
chk_redraw('after preview')

print('FAILS', fails)
if started: vt.stop()
