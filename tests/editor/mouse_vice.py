"""SIDJ in VICE with an emulated 1351 in control port 1 (port 6512): the
driver finds it, the pointer sprite is on, an untouched mouse keeps the
pointer still, no button or key is seen, and the keyboard (debug hook) still
drives the editor. The host mouse is not grabbed, so nothing moves it.
usage: python3 mouse_vice.py [prg]"""
import vt, re, sys, time, os
PRG = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '../../build/sidj.prg'))
L = {}
for l in open(PRG.replace('.prg', '.labels')):
    m = re.match(r'(\S+)\s*= \$([0-9a-f]+)', l)
    if m: L[m.group(1)] = int(m.group(2), 16)
fails = 0
def eq(name, got, want):
    global fails
    ok = got == want; fails += not ok
    print(('ok  ' if ok else 'BAD ') + name, got, '' if ok else f'want {want}')
m1 = lambda a: vt.mem(a, 1)[0]
w16 = lambda a: (lambda v: v[0] | v[1] << 8)(vt.mem(a, 2))
vt.start(PRG, ['-controlport1device', '3', '-controlport2device', '1'])
try:
    vt.sleep(6)
    pots = [vt.mem(0xd419, 2) for _ in range(3)]
    print('   POTX/POTY samples:', pots)
    eq('1351 found on port 1', (m1(L['ms_port']), m1(L['ms_found'])), (1, 1))
    eq('pointer sprite on', (m1(0xd015) & 1, m1(0x07f8)), (1, 0x2f))
    pos = [(w16(L['ms_fx']), w16(L['ms_fy']))]
    for _ in range(8):
        vt.sleep(0.25); pos.append((w16(L['ms_fx']), w16(L['ms_fy'])))
    print('   positions:', pos)
    eq('idle mouse: pointer still for 2 s', len(set(pos)), 1)
    eq('no buttons, no keys', (m1(L['in_mbtn']), m1(L['in_btn']), vt.mem(L['kb_mat'], 8)), (0, 0, [0] * 8))
    eq('POT select left on port 1 ($dc00 bits 6/7 = 01)', m1(0xdc00) & 0xc0, 0x40)
    vt.script([('S', None), ('SR', None), ('S', None), ('', None)])
    eq('keyboard (hook) still drives the editor: ctrl+R -> chain', m1(L['screen']), 1)
    vt.script([('S', None), ('SL', None), ('S', None), ('', None)])
    vt.shot('mouse_vice.png')
    vt.poke(L['ms_port'], 2); vt.sleep(1)
    eq('port 2 (joystick there): no 1351, pointer off', (m1(L['ms_found']), m1(0xd015) & 1), (0, 0))
    vt.poke(L['ms_port'], 1); vt.sleep(1)
    eq('back on port 1: found again', m1(L['ms_found']), 1)
    eq('pointer did not jump on re-detection', (w16(L['ms_fx']), w16(L['ms_fy'])), pos[-1])
finally:
    vt.stop()
print('FAILS', fails)
