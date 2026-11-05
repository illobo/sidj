import vt, re, sys, os
# Stuck NMI line in VICE: the player runs on the CIA2 timer NMI (falling
# edge). One NMI that nobody acks (the C64 Ultimate or a freezer halting the
# CPU) leaves CIA2 holding the line low, and the player stood still for good.
# The test points $fffa at the player's bare RTI for a moment, so one NMI goes
# unacked, puts the vector back and checks that pl_tick moves again (the
# editor's nmi_watch reads the ICR after 12 frames without a tick).
# usage: python3 nmi.py [prg]  (VICE on SIDJ_VICE_PORT, default 6512)
PRG = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '../../build/sidj.prg'))
LST = PRG.replace('.prg', '.lst')
TICK, PLAYING = 0x1023, 0x1020
fails = 0
def eq(name, got, want):
    global fails
    ok = got == want; fails += not ok
    print(('ok  ' if ok else 'BAD ') + name, got, '' if ok else f'want {want}')
def m1(a): return vt.mem(a, 1)[0]

# the player NMI handler's address and its final RTI, from the listing
src = open(LST).read()
nmi = int(re.search(r'\.([0-9a-f]{4})\s.*\bnmi\s+pha', src).group(1), 16)
rti = int(re.search(r'\.([0-9a-f]{4})\s+40\s+rti', src[src.index('nmi     pha'):]).group(1), 16)

def moving(sec=0.5):
    a = m1(TICK); vt.sleep(sec); return m1(TICK) != a

vt.start(PRG)
try:
    vt.sleep(6)
    vt.script(vt.tap('T'))                  # RETURN on SONG: play the demo
    vt.sleep(0.5)
    eq('demo plays', (m1(PLAYING) != 0, moving()), (True, True))
    eq('vector = player nmi', vt.mem(0xfffa, 2), [nmi & 255, nmi >> 8])
    vt.poke(0xfffa, rti & 255, rti >> 8)    # next NMI: RTI without the ICR read
    vt.sleep(0.2)
    vt.poke(0xfffa, nmi & 255, nmi >> 8)
    vt.sleep(1)                             # 12 frames and more
    eq('player ticks again', moving(), True)
    eq('still playing', m1(PLAYING) != 0, True)
finally:
    vt.stop()
print('nmi:', 'all ok' if not fails else f'{fails} failures')
sys.exit(1 if fails else 0)
