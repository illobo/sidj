import vt, re, sys, os
# 2SID in VICE: detection (mono, $de00, $d420, $d500), six Song columns, play all
# six, mute/solo by keys and mouse, status flags, live queue on channel 5,
# SID SETUP address cycling (back to three channels and to six again).
# usage: python3 sid2.py [prg]  (VICE on SIDJ_VICE_PORT, default 6512)
# Sound emulation stays on (wav to /dev/null): with -sounddev dummy VICE does
# not emulate the SID and the start-up probe cannot see it.
PRG = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '../../build/sidj.prg'))
L = {}
for l in open(PRG.replace('.prg', '.labels')):
    m = re.match(r'(\S+)\s*= \$([0-9a-f]+)', l)
    if m: L[m.group(1)] = int(m.group(2), 16)
SND = ['-sounddev', 'wav', '-soundarg', '/dev/null']
t = vt.tap
fails = 0
def eq(name, got, want):
    global fails
    ok = got == want; fails += not ok
    print(('ok  ' if ok else 'BAD ') + name, got, '' if ok else f'want {want}')
def m1(a): return vt.mem(a, 1)[0]
def pl(o): return m1(0x1020 + o)
def hold(mod, d): return [(mod, None), (mod + d, None), (mod, None), ('', None)]
def rows(): return [l[3:43] for l in vt.screen_text().splitlines()]
def sid2(): w = vt.mem(0x107e, 2); return w[0] | w[1] << 8
def MS(fr): vt.mscript(fr)
C = vt.click

def boot(extra):
    vt.stop()
    vt.start(PRG, extra + SND)
    vt.sleep(6)

try:
    # mono: nothing found, three channels, the screen as before
    boot([])
    eq('mono: no second SID', (sid2(), pl(7)), (0, 3))
    r = rows()
    eq('mono: song header', r[1][:12], '   1  2  3  ')
    eq('mono: status flags', r[0][23:40], 'P:--- M:---  SIDJ')
    boot(['-sidextra', '1', '-sid2address', '0xd500'])
    eq('$d500 found', (sid2(), pl(7)), (0xd500, 6))

    boot(['-sidextra', '1', '-sid2address', '0xde00'])
    eq('$de00 found (C64 Ultimate UltiSID 2 default)', (sid2(), pl(7)), (0xde00, 6))
    vt.stop()
    boot(['-sidextra', '1', '-sid2address', '0xd420'])
    eq('$d420 found, six channels', (sid2(), pl(7)), (0xd420, 6))
    r = rows()
    eq('song header 1-6', r[1][:20], '   1  2  3  4  5  6 ')
    eq('status: six flags each', r[0][23:40], 'P:------ M:------')
    # channels 4-6 get the demo chains (slots 3-5 = 0, 1, 2 on rows 0-1)
    for s in range(3):
        vt.poke(0xe300 + s * 256, s, s)
    vt.poke(L['need_clear'], 1); vt.sleep(0.2)
    eq('row 0 shows six chains', rows()[2][:20], '00 00 01 02 00 01 02')
    vt.script(t('R') * 7); eq('cursor stops at channel 6', m1(L['scol']), 5)
    vt.script(t('T')); vt.sleep(0.5)
    eq('RETURN plays all six', pl(0), 0x3f)
    eq('status: p:123456', rows()[0][23:31], 'P:123456')
    sh = vt.mem(0x1080, 25)
    eq('SID2 shadow: voices gated', [sh[4] & 1, sh[11] & 1, sh[18] & 1], [1, 1, 1])
    # mute / solo channel 5 (cursor), status flags
    vt.script(t('L')); eq('cursor channel 5', m1(L['scol']), 4)
    vt.script(hold('B', 'S')); eq('C=+CTRL mutes ch5', pl(1), 0x10)
    vt.sleep(0.2); eq('status: m:----5-', rows()[0][32:40], 'M:----5-')
    vt.script(hold('B', 'T')); eq('C=+RETURN solo ch5', pl(1), 0x2f)
    vt.script(hold('B', 'T')); eq('solo again: all on', pl(1), 0)
    # mouse: header of channel 6 (column 17), left = mute, right = solo
    MS(C(17, 1)); eq('click ch6 header: mute', pl(1), 0x20)
    MS(C(17, 1)); eq('click again: unmute', pl(1), 0)
    MS(C(17, 1, 'R')); eq('right click ch6: solo', pl(1), 0x1f)
    MS(C(17, 1, 'R')); eq('right click again: all on', pl(1), 0)
    MS(C(15, 4)); eq('click song cell ch5 row 2', (m1(L['scol']), m1(L['srow'])), (4, 2))
    vt.script(t('T')); eq('RETURN stops', pl(0), 0)
    eq('redraw consistent (six columns)', vt.redraw_matches(L['need_clear']), [])
    # live mode: queue row 1 on channel 5 only
    vt.script(hold('S', 'L')); eq('live on', pl(4), 1)
    vt.script(t('U')); eq('cursor row 1, ch5', (m1(L['scol']), m1(L['srow'])), (4, 1))
    vt.script(t('T')); vt.sleep(0.3)
    eq('live RETURN starts ch5 alone', (pl(0), pl(8 + 4)), (0x10, 1))
    vt.script(t('U')); eq('cursor row 0', m1(L['srow']), 0)
    vt.script(t('T'))
    q = pl(0x50 + 4)
    eq('ch5 queues row 0 (or already switched)', q == 0 or pl(8 + 4) == 0, True)
    vt.sleep(8); eq('ch5 switched to row 0, others idle', (pl(0), pl(8 + 4)), (0x10, 0))
    vt.script(hold('S', 'T')); vt.script(hold('S', 'T'))
    vt.sleep(8); eq('CTRL+RETURN twice: ch5 stops', pl(0) & 0x10, 0)
    vt.script(hold('S', 'L')); eq('live off', pl(4), 0)
    # SID SETUP: SPACE + CRSR cycles the address; off = three channels
    vt.poke(L['screen'], 7); vt.poke(L['need_clear'], 1); vt.sleep(0.2)
    eq('setup shows $d420 (reversed)', rows()[4][:13], '2ND SID $d420')
    vt.script(hold('A', 'R')); eq('spc+R: $d440', sid2(), 0xd440)
    vt.script(hold('A', 'L') + hold('A', 'L')); eq('spc+L twice: off', (sid2(), pl(7)), (0, 3))
    eq('setup shows off, 3 voices', (rows()[4][:11], rows()[5][:9]), ('2ND SID off', 'VOICES  3'))
    eq('song cursor clamped to ch3', m1(L['scol']), 2)
    vt.poke(L['screen'], 0); vt.poke(L['need_clear'], 1); vt.sleep(0.2)
    eq('mono again: song header', rows()[1][:20], '   1  2  3          ')
    vt.script(t('T')); vt.sleep(0.3); eq('plays three', pl(0), 7)
    vt.script(t('T'))
    vt.poke(L['screen'], 7); vt.poke(L['need_clear'], 1); vt.sleep(0.2)
    MS(vt.drag(12, 4, 9, 0)); eq('mouse drag right one step on 2nd sid: $d420', (sid2(), pl(7)), (0xd420, 6))
    vt.script(hold('A', 'L') + hold('A', 'L')); eq('spc+L from $d420 twice: off, then $dfe0', sid2(), 0xdfe0)
    vt.poke(0x107e, 0xe0, 0xd7); vt.script(hold('A', 'R')); eq('spc+R from $d7e0: $de00', sid2(), 0xde00)
    vt.script(hold('A', 'L')); eq('spc+L from $de00: $d7e0', sid2(), 0xd7e0)
    vt.poke(0x107e, 0xe0, 0xdf); vt.script(hold('A', 'R')); eq('spc+R from $dfe0: off', (sid2(), pl(7)), (0, 3))
    vt.script(hold('A', 'R')); eq('spc+R from off: $d420', (sid2(), pl(7)), (0xd420, 6))
    vt.poke(L['screen'], 0); vt.poke(L['need_clear'], 1); vt.sleep(0.2)
    vt.script(t('T')); vt.sleep(0.3); eq('plays six again', pl(0), 0x3f)
    vt.script(t('T'))
finally:
    vt.stop()
print('FAILURES:', fails)
sys.exit(1 if fails else 0)
