"""Run the editor's kb_scan (and the 1351 driver ms_irq) in py65 against a
simulated C64 keyboard matrix with real electrical behaviour:
  - a pressed key joins its column line and its row line;
  - low sources: columns driven low by CIA1 port A ($dc00 bit = 0), port 2
    lines (joystick / mouse buttons) pulling port A pins low, port 1 lines
    pulling port B (row) pins low;
  - every line connected to a low source reads low, on BOTH ports (so keys
    in a row held low by a port 1 button pull their column's port A pin low:
    the reverse path kb_scan uses to recover them), with ghosting.
A 1351 in port 1 or 2: left button = fire (bit 4), right = up (bit 0);
POTX/POTY return (position mod 64) << 1 | noise only when CIA1 $dc00 bits 6/7
have selected that port for >= 1.6 ms (1351 manual), else $ff (unconnected)."""
import os, sys, re, random
from py65.devices.mpu6502 import MPU

# The editor uses some illegal opcodes (M10, make check-illegal); py65 lacks
# them: LAX (all modes but #) and SBX, as on the 6510.
def _lax(mode, n):
    def op(self):
        self.a = self.x = self.ByteAt(getattr(self, mode)())
        self.FlagsNZ(self.a)
        self.pc += n
    return op
for _op, _mode, _n, _cyc in ((0xa7, 'ZeroPageAddr', 1, 3), (0xb7, 'ZeroPageYAddr', 1, 4),
                             (0xaf, 'AbsoluteAddr', 2, 4), (0xbf, 'AbsoluteYAddr', 2, 4),
                             (0xa3, 'IndirectXAddr', 1, 6), (0xb3, 'IndirectYAddr', 1, 5)):
    MPU.instruct[_op] = _lax(_mode, _n); MPU.cycletime[_op] = _cyc
def _sbx(self):
    t = (self.a & self.x) - self.ByteAt(self.pc)
    self.p = (self.p & ~self.CARRY) | (self.CARRY if t >= 0 else 0)
    self.x = t & 0xff
    self.FlagsNZ(self.x)
    self.pc += 1
MPU.instruct[0xcb] = _sbx; MPU.cycletime[0xcb] = 2

PRG = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../build/sidj.prg')
LAB = PRG.replace('.prg', '.labels')
labels = {}
for l in open(LAB):
    m = re.match(r'(\S+)\s*= \$([0-9a-f]+)', l)
    if m: labels[m.group(1)] = int(m.group(2), 16)

K = dict(RET=(0,1), RT=(0,2), F1=(0,4), F3=(0,5), DN=(0,7), LSH=(1,7), A=(1,2), W=(1,1), Z=(1,4), THREE=(1,0),
         RSH=(6,4), CTRL=(7,2), SPC=(7,4), CBM=(7,5), Q=(7,6), ONE=(7,0), C=(2,4), EQ=(6,5), M=(4,4), J=(4,2))
FRAME = 19656                    # PAL cycles per frame
SETTLE = 1576                    # 1.6 ms

class Mem(list):
    def __init__(s):
        super().__init__([0]*65536)
        s.keys = set(); s.j1 = 0; s.j2 = 0; s.pa = 0xff
        s.mouse = None           # None or dict(port=1/2, x=, y=, noise)
        s.clock = 0; s.sel = 0xff & 0xc0; s.sel_t = -10**9
    def now(s): return s.clock + mpu.processorCycles
    def lines(s):
        """(rows low, cols low) after propagation through pressed keys"""
        cl = {c for c in range(8) if not (s.pa >> c) & 1} | {c for c in range(8) if (s.j2 >> c) & 1}
        rl = {r for r in range(8) if (s.j1 >> r) & 1}
        changed = True
        while changed:
            changed = False
            for (c, r) in s.keys:
                if c in cl and r not in rl: rl.add(r); changed = True
                if r in rl and c not in cl: cl.add(c); changed = True
        return rl, cl
    def __getitem__(s, a):
        if a == 0xdc01:
            rl, _ = s.lines()
            return 0xff & ~sum(1 << r for r in rl)
        if a == 0xdc00:
            _, cl = s.lines()
            return 0xff & ~sum(1 << c for c in cl)
        if a in (0xd419, 0xd41a):
            m = s.mouse
            port = {0x40: 1, 0x80: 2}.get(s.sel)
            if m is None or port != m['port'] or s.now() - s.sel_t < SETTLE:
                return 0xff
            if 'raw' in m: return m['raw'][random.randint(0, 1)]
            pos = m['x'] if a == 0xd419 else m['y']
            noise = random.randint(0, 1) if m.get('noise') else 0
            return ((pos & 63) << 1) | noise | (random.randint(0, 1) << 7 if m.get('b7') else 0)
        return list.__getitem__(s, a)
    def __setitem__(s, a, v):
        if a == 0xdc00:
            s.pa = v
            if (v & 0xc0) != s.sel: s.sel = v & 0xc0; s.sel_t = s.now()
        list.__setitem__(s, a, v)

mem = Mem()
data = open(PRG, 'rb').read()
load = data[0] | data[1] << 8
for i, b in enumerate(data[2:]): list.__setitem__(mem, load + i, b)
mpu = MPU(memory=mem)
def poke(a, v): list.__setitem__(mem, a, v)
def peek(a): return list.__getitem__(mem, a)

def call(label):
    mpu.sp = 0xfd
    poke(0x1fe, 0xff); poke(0x1ff, 0xfe)          # rts -> $feff+1
    mpu.pc = labels[label]
    n = 0
    while mpu.pc != 0xff00:
        mpu.step(); n += 1
        assert n < 20000, label
    return n

def frame():
    """one raster IRQ as the editor runs it: driver, then keyboard scan"""
    mem.clock += FRAME
    call('ms_irq')
    return call('kb_scan')

def scan(keys=(), j1=0, j2=0, clear_char=True):
    mem.keys = {K[k] for k in keys}; mem.j1 = j1; mem.j2 = j2
    if clear_char: poke(labels['in_char'], 0xff)
    n = frame()
    return peek(labels['in_btn']), peek(labels['in_char']), n

B = dict(U=1, D=2, L=4, R=8, A=0x10, B=0x20, S=0x40, T=0x80)
def bits(s): return sum(B[c] for c in s)
fails = 0
def ok(name, cond, info=''):
    global fails
    fails += not cond
    print(f"{'ok ' if cond else 'BAD'} {name:40s} {info}")
def check(name, keys, want_btn, want_char=0xff, want_mb=None, **kw):
    scan((), j1=kw.get('j1', 0), j2=kw.get('j2', 0))   # release keys first (device lines stay)
    btn, ch, cyc = scan(keys, **kw)
    mb = peek(labels['in_mbtn'])
    good = btn == bits(want_btn) and ch == want_char and (want_mb is None or mb == want_mb)
    ok(name, good, f"btn={btn:02x} want={bits(want_btn):02x} char={ch:02x} want={want_char:02x}"
       + (f" mbtn={mb} want={want_mb}" if want_mb is not None else '') + f" steps={cyc}")

# ---------------------------------------------------------------------------
# keyboard alone, no mouse found (port 1 lines count as joystick 1)
poke(labels['ms_port'], 1)
check('nothing', [], '')
check('SPACE', ['SPC'], 'A')
check('CRSR DOWN', ['DN'], 'D')
check('SHIFT+DOWN = up', ['LSH', 'DN'], 'U')
check('RSHIFT+RIGHT = left', ['RSH', 'RT'], 'L')
check('SPACE+SHIFT+RIGHT', ['SPC', 'LSH', 'RT'], 'AL')
check('SPACE+RSHIFT+DOWN', ['SPC', 'RSH', 'DN'], 'AU')
check('CTRL+SHIFT+DOWN', ['CTRL', 'LSH', 'DN'], 'SU')
check('CTRL+RIGHT', ['CTRL', 'RT'], 'SR')
check('C=+CTRL', ['CBM', 'CTRL'], 'BS')
check('C=+RETURN', ['CBM', 'RET'], 'BT')
check('CTRL+RETURN', ['CTRL', 'RET'], 'ST')
check('C=+SPACE', ['CBM', 'SPC'], 'AB')
check('CTRL+SPACE', ['CTRL', 'SPC'], 'AS')
check('SPACE+C=+CTRL', ['SPC', 'CBM', 'CTRL'], 'ABS')
check('C=+SHIFT+DOWN', ['CBM', 'LSH', 'DN'], 'BU')
check('SPACE+DOWN+RIGHT', ['SPC', 'DN', 'RT'], 'ADR')
check('RSHIFT+SPACE+C= (ghost =)', ['RSH', 'SPC', 'CBM'], 'AB')
check('SHIFT+DOWN+RIGHT (ghost A)', ['LSH', 'DN', 'RT'], 'UL')
check('SHIFT+RIGHT+RETURN (live row)', ['LSH', 'RT', 'RET'], 'LT')
check('RSHIFT+RIGHT+RETURN (live row)', ['RSH', 'RT', 'RET'], 'LT')
check('CTRL+SHIFT+RIGHT (live toggle)', ['CTRL', 'LSH', 'RT'], 'SL')
check('CTRL+RSHIFT+RIGHT (live toggle)', ['CTRL', 'RSH', 'RT'], 'SL')
check('CTRL+C=+SPACE (clone)', ['CTRL', 'CBM', 'SPC'], 'ABS')
check('CTRL+DOWN+RIGHT (mark ext.)', ['CTRL', 'DN', 'RT'], 'SDR')
check('C=+RSHIFT+DOWN (bookmark up)', ['CBM', 'RSH', 'DN'], 'BU')
check('letter A', ['A'], '', 10)
check('letter C', ['C'], '', 12)
check('digit 1', ['ONE'], '', 1)
check('Q', ['Q'], '', 26)
check('SHIFT+A ignored', ['LSH', 'A'], '', 0xff)
check('SPACE+A ignored', ['SPC', 'A'], 'A', 0xff)
check('F1', ['F1'], '', 0x40)
check('F3', ['F3'], '', 0x41)
K['HOME'] = (6, 3)                                # grid view toggle (grid.asm reads kb_mat directly)
check('HOME: no button, no char', ['HOME'], '', 0xff)
ok('HOME in kb_mat column 6 bit 3', peek(labels['kb_mat'] + 6) & 8 == 8)
check('joy2 up+fire', [], 'UA', j2=0x11)
check('joy1 right masked', [], '', j1=0x08)
check('joy1 left + C=', ['CBM'], 'B', j1=0x04)
check('joy1 fire + SPACE (recovered)', ['SPC'], 'A', j1=0x10)
check('joy1 fire + F1 (not joy2)', ['F1'], '', 0x40, j1=0x10)

# ---------------------------------------------------------------------------
# 1351 in port 1: driver detection and movement
print('--- 1351 in port 1')
mem.keys = set(); mem.j1 = 0; mem.j2 = 0
poke(labels['ms_found'], 0)
for _ in range(30): frame()
ok('no device: not found', peek(labels['ms_found']) == 0)
mem.mouse = dict(port=1, x=10, y=50, b7=True, noise=True)
for _ in range(3): frame()
ok('1351 found', peek(labels['ms_found']) == 1)
ok('POT select = port 1 after scan ($dc00 bits 6/7 = 01)', mem.pa & 0xc0 == 0x40, f'pa={mem.pa:02x}')
fx = lambda: peek(labels['ms_fx']) | peek(labels['ms_fx'] + 1) << 8
fy = lambda: peek(labels['ms_fy']) | peek(labels['ms_fy'] + 1) << 8
x0, y0 = fx(), fy()
for _ in range(50): frame()                       # still, noise bit + bit 7 flicker
ok('idle: position stable (noise bits ignored)', (fx(), fy()) == (x0, y0), f'{(x0, y0)} -> {(fx(), fy())}')
mem.mouse['raw'] = (0x7f, 0x80)                   # manual: may oscillate $7f/$80 when still
frame(); frame(); x0, y0 = fx(), fy()
for _ in range(50): frame()
ok('idle: $7f/$80 oscillation ignored', (fx(), fy()) == (x0, y0), f'{(x0, y0)} -> {(fx(), fy())}')
del mem.mouse['raw']; mem.mouse['noise'] = False   # moving tests: exact counts
for d in (5, 3): mem.mouse['x'] += d; mem.mouse['y'] += d; frame()   # old values now noise-free
x0, y0 = fx(), fy()
poke(labels['ms_speed'], 1); poke(labels['ms_accel'], 0)
for _ in range(10): mem.mouse['x'] += 3; frame()  # 3 counts/frame right, wraps mod 64 later
ok('right 30 counts: x +30 px (speed 1)', fx() - x0 == 60, f'dfx={fx() - x0} half px')
for _ in range(25): mem.mouse['x'] -= 2; frame() # across the 64 wrap
ok('left 50 counts across the wrap', fx() - x0 == 60 - 100, f'dfx={fx() - x0}')
y1 = fy()
for _ in range(5): mem.mouse['y'] += 2; frame()
ok('POT y up = pointer up', fy() - y1 == -20, f'dfy={fy() - y1}')
poke(labels['ms_accel'], 1); x1 = fx()
for _ in range(4): mem.mouse['x'] += 6; frame()
ok('accelerated: 24 counts fast -> 48 px', fx() - x1 == 96, f'dfx={fx() - x1}')
poke(labels['ms_speed'], 0); poke(labels['ms_accel'], 0); x1 = fx()
for _ in range(4): mem.mouse['x'] += 2; frame()
ok('speed 0: 8 counts -> 4 px', fx() - x1 == 8, f'dfx={fx() - x1}')
poke(labels['ms_speed'], 1)
for _ in range(60): mem.mouse['x'] -= 20; frame()
ok('clamped at the left edge', fx() == 0)
for _ in range(60): mem.mouse['y'] -= 20; frame()
ok('clamped at the bottom edge', fy() == 399)

# buttons and keyboard together (1351 found in port 1)
print('--- 1351 port 1 buttons + keyboard')
L_, R_ = 0x10, 0x01
check('left button alone', [], '', want_mb=1, j1=L_)
check('right button alone', [], '', want_mb=2, j1=R_)
check('both buttons', [], '', want_mb=3, j1=L_ | R_)
check('left + SPACE', ['SPC'], 'A', want_mb=1, j1=L_)
check('left + C=', ['CBM'], 'B', want_mb=1, j1=L_)
check('left + CTRL', ['CTRL'], 'S', want_mb=1, j1=L_)
check('left + C= + SPACE', ['CBM', 'SPC'], 'AB', want_mb=1, j1=L_)
check('left + CTRL + SPACE', ['CTRL', 'SPC'], 'AS', want_mb=1, j1=L_)
check('left + CTRL + C= + SPACE', ['CTRL', 'CBM', 'SPC'], 'ABS', want_mb=1, j1=L_)
check('left + RSHIFT + DOWN', ['RSH', 'DN'], 'U', want_mb=1, j1=L_)
check('left + SPACE + RSHIFT + RIGHT', ['SPC', 'RSH', 'RT'], 'AL', want_mb=1, j1=L_)
check('left + SHIFT + DOWN', ['LSH', 'DN'], 'U', want_mb=1, j1=L_)
check('left + RETURN', ['RET'], 'T', want_mb=1, j1=L_)
check('left + F1 (row 4)', ['F1'], '', 0x40, want_mb=1, j1=L_)
check('left + Z (row 4 letter)', ['Z'], '', 35, want_mb=1, j1=L_)
check('left + M (row 4 letter)', ['M'], '', 22, want_mb=1, j1=L_)
check('right + digit 1 (row 0)', ['ONE'], '', 1, want_mb=2, j1=R_)
check('right + 3 (row 0)', ['THREE'], '', 3, want_mb=2, j1=R_)
check('right + CTRL', ['CTRL'], 'S', want_mb=2, j1=R_)
check('right + SPACE', ['SPC'], 'A', want_mb=2, j1=R_)
check('both + SPACE', ['SPC'], 'A', want_mb=3, j1=L_ | R_)
check('both + CTRL + RETURN', ['CTRL', 'RET'], 'ST', want_mb=3, j1=L_ | R_)
check('keys alone, no button', ['CTRL', 'SPC'], 'AS', want_mb=0)
x1, y1 = fx(), fy()
for _ in range(20): scan(['SPC', 'CBM'], j1=L_)
ok('typing + buttons: pointer still', (fx(), fy()) == (x1, y1))

# ---------------------------------------------------------------------------
# 1351 in port 2 (setting), joystick 2 off
print('--- 1351 in port 2')
poke(labels['ms_port'], 2)
mem.mouse = dict(port=2, x=0, y=0)
for _ in range(4): frame()
ok('found on port 2', peek(labels['ms_found']) == 1)
ok('POT select = port 2 after scan', mem.pa & 0xc0 == 0x80, f'pa={mem.pa:02x}')
x1 = fx()
for _ in range(5): mem.mouse['x'] += 2; frame()
ok('port 2 moves', fx() - x1 == 20, f'dfx={fx() - x1}')
check('p2 left button', [], '', want_mb=1, j2=0x10)
check('p2 right button', [], '', want_mb=2, j2=0x01)
check('p2 left + SPACE', ['SPC'], 'A', want_mb=1, j2=0x10)
check('p2 left + CTRL + SPACE', ['CTRL', 'SPC'], 'AS', want_mb=1, j2=0x10)
check('p2 left + C=', ['CBM'], 'B', want_mb=1, j2=0x10)
check('p2 right + C= + SPACE', ['CBM', 'SPC'], 'AB', want_mb=2, j2=0x01)
check('p2 left + J (column 4 key)', ['J'], '', 19, want_mb=1, j2=0x10)
check('p2 no button: SPACE', ['SPC'], 'A', want_mb=0)
mem.mouse = None
for _ in range(30): frame()
ok('unplugged: not found', peek(labels['ms_found']) == 0)
check('port 2 setting, no mouse: joystick 2 again', [], 'UA', want_mb=0, j2=0x11)
poke(labels['ms_port'], 1)
print('FAILS', fails)
