"""Redraw cost in cycles (py65, stub build): full redraw per screen vs the
partial redraw (update) after a cursor move, an edit, a play-marker change
and an idle frame. Usage: python3 perf.py [build/sidj-stub.prg]"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
prg = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '../../build/sidj-stub.prg')
sys.argv = [sys.argv[0], prg]
exec(open(os.path.join(HERE, 'kbtest.py')).read().split("B = dict(")[0])   # Mem/labels/mpu setup
def call(addr, limit=5_000_000):
    mem[0x1fe] = 0xff; mem[0x1ff] = 0xfe; mpu.sp = 0xfd; mpu.pc = addr
    c0 = mpu.processorCycles
    while mpu.pc != 0xff00:
        mpu.step()
        assert mpu.processorCycles - c0 < limit
    return mpu.processorCycles - c0
L = labels
def poke(name, v, off=0): mem[L[name] + off] = v
def peek(name, off=0): return mem[L[name] + off]
# $d000-$dfff: I/O or RAM by $01 (code and help text live under I/O; the SID
# probes and the VIC writes must not land there). kbtest's devices stay.
_io = {0xd012: 0xff}                       # raster for sid_detect
_get, _set = Mem.__getitem__, Mem.__setitem__
def _iovis(s):
    b = list.__getitem__(s, 1) & 7
    return b & 4 and b & 3
def _mget(s, a):
    if 0xd000 <= a < 0xe000 and a not in (0xdc00, 0xdc01, 0xd419, 0xd41a) and _iovis(s): return _io.get(a, 0)
    return _get(s, a)
def _mset(s, a, v):
    if 0xd000 <= a < 0xe000 and _iovis(s): _io[a] = v; return
    _set(s, a, v)
Mem.__getitem__, Mem.__setitem__ = _mget, _mset
# main calls fio_clean (KERNAL, disk module) at start-up: replace it by an rts
# and pre-fill an empty project the way it would, when it is called (after the
# start-up code has copied the staged blocks out of $8000-$9fff)
def fio_clean():
    for a in list(range(0x8000, 0xd000)) + list(range(0xe000, 0xf900)): list.__setitem__(mem, a, 0xff)
    for a in range(0xf900, 0xfa00): list.__setitem__(mem, a, 0)
    for a in range(0xec00, 0xf600): list.__setitem__(mem, a, 0)   # table columns 1-5
    for a in range(0xf600, 0xf900): list.__setitem__(mem, a, 0)   # grooves + header
    mem[0xf600] = mem[0xf601] = 6; mem[0xf800] = 125
mpu.pc = L['boot']                         # BASIC SYS: boot copies the start-up code to $0200
while mpu.pc != L['editor_main']:
    if mpu.pc == 0x7006:                   # fio_clean (FILEIO+6): emulated, then rts
        fio_clean()
        mpu.pc = (mem[0x100 + ((mpu.sp + 1) & 0xff)] | mem[0x100 + ((mpu.sp + 2) & 0xff)] << 8) + 1
        mpu.sp = (mpu.sp + 2) & 0xff
    mpu.step()
names = ['song', 'chain', 'phrase', 'instr', 'table', 'groove', 'project', 'sid']
print(f"{'screen':8s} {'full':>7s} {'idle':>6s} {'move':>6s} {'edit':>6s} {'marks':>6s}")
for scr, name in list(enumerate(names)) + [(2, 'grid')]:   # grid: the Phrase screen in grid view
    poke('grid_on', name == 'grid')
    poke('screen', scr); poke('need_clear', 0)
    full = call(L['redraw'])
    idle = call(L['update'])
    # cursor one row down (forms: next field line)
    mem[L['rowv'] + scr] = 0 if scr in (0, 1, 2, 6) else 1
    call(L['redraw'])
    mem[L['dirty']] = 0
    if scr in (3, 6):
        mem[L['dir_t']] = 1; call(L['form_move'])
    else:
        mem[L['rowv'] + scr] += 1
    move = call(L['update'])
    poke('dirty', 1)                       # RD_ROW: what a field edit requests
    edit = call(L['update'])
    # player moved: chain/phrase steps of channel 1 and 2 advance
    mem[0x1020] = 7
    for ch in range(3):
        mem[0x1028 + ch] = 0; mem[0x1030 + ch] = ch; mem[0x1040 + ch] = ch
        mem[0x1038 + ch] = 0; mem[0x1048 + ch] = 0
    call(L['play_watch']); call(L['update'])
    for ch in range(3): mem[0x1048 + ch] = 1; mem[0x1038 + ch] = 1
    call(L['play_watch'])
    marks = call(L['update'])
    mem[0x1020] = 0; call(L['play_watch']); call(L['update'])
    print(f"{name:8s} {full:7d} {idle:6d} {move:6d} {edit:6d} {marks:6d}")
print('(PAL frame = 19656 cycles; M1 redrew everything on any change)')
# Live FX panel: fx_update runs every frame inside update
poke('grid_on', 0); poke('screen', 0); call(L['redraw']); mem[L['dirty']] = 0
fx_idle = call(L['fx_update'])
mem[0x1069] ^= 1; fx_row = call(L['fx_update'])     # one row's latch state changed
mem[0x1069] = 0xff; fx_all = call(L['fx_update'])   # five rows at once
mem[0x1069] = 0; call(L['fx_update'])
print('fx panel: idle', fx_idle, ' one row', fx_row, ' five rows', fx_all)
print('grammar idle', call(L['grammar']), ' play_watch', call(L['play_watch']))
