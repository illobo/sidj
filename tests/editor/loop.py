"""M9 loop record in VICE (port 6512 unless SIDJ_VICE_PORT): piano / jam mode,
loop record (REU: overlays 6 and 4), beat repeat / hold (pl_hold).
Two sessions: a 512 KB REU, then none. Usage: python3 loop.py [prg]"""
import os, re, sys
import vt

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
def m1(a): return vt.mem(a, 1)[0]
def hold(mod, d): return [(mod, None), (mod + d, None), (mod, None), ('', None)]
def keys(*codes): return sum(([('', c), ('', None)] for c in codes), [])
t = vt.tap
PL = 0x1000
pl_playing, pl_phrase, pl_pstep, pl_chain, pl_cstep = PL + 0x20, PL + 0x40, PL + 0x48, PL + 0x30, PL + 0x38
pl_shadow, pl_hold, pl_wait, pl_steplen = PL + 0x50, PL + 0x99, 0x0fe4, 0x0fea
KC_F4, KC_F6, KC_F7, KC_PLUS, KC_MINUS = 0x49, 0x4a, 0x43, 0x44, 0x45
Z, S, X, Q, A = 35, 28, 33, 26, 10
def phrase(p): return vt.mem(0x8000 + p * 64, 64)
def msg(): return ''.join(chr(c + 64) if 1 <= c <= 26 else chr(c) for c in vt.mem(L['msg_buf'], 20)).strip().lower()
def gate(ch): return m1(pl_shadow + 7 * ch + 4) & 1
def help_row(): return vt.screen_text().splitlines()[24][3:43]

def to_phrase():
    vt.script(hold('S', 'R') + hold('S', 'R'))
    eq('on the Phrase screen', m1(L['screen']), 2)

def common(reu):
    to_phrase()
    ch, ph = m1(L['cur_chan']), m1(L['cur_phrase'])
    before = phrase(ph)
    # piano mode: F4, jam on the cursor channel, typing off
    vt.script(keys(KC_F4)); eq('F4: piano on', m1(L['pn_on']), 1)
    eq('help line says piano', help_row()[:15], 'PIANO +-:OCTAVE')
    vt.script(keys(Z), wait=False); vt.sleep(0.3)
    eq('jam: gate on (pl_shadow)', gate(ch), 1)
    eq('jam note C-3 (octave 3)', m1(L['lr_note']), 36)
    vt.script(keys(A, 5)); eq('piano: typing a note does nothing', phrase(ph), before)
    vt.script(keys(KC_PLUS)); eq('+: octave 4', m1(L['pn_oct']), 4)
    vt.script(keys(KC_MINUS, KC_MINUS)); eq('- -: octave 2', m1(L['pn_oct']), 2)
    vt.script(keys(KC_PLUS)); eq('piano writes nothing without recording', phrase(ph), before)
    # beat repeat: pl_hold on every channel while a key is held (br_dbg stands in for the matrix)
    for bits, want, what in ((0x80, 0x17, ', = 8 steps'), (0x10, 0x13, '. = 4 steps'), (0x40, 0x11, '/ = 2 steps'), (0x02, 0x10, '; = 1 step')):
        vt.poke(L['br_dbg'], bits); vt.sleep(0.1)
        eq('beat repeat ' + what, vt.mem(pl_hold, 6), [want] * 6)
    vt.poke(L['br_dbg'], 0); vt.sleep(0.1)
    eq('beat repeat released', vt.mem(pl_hold, 6), [0] * 6)
    # playing: a 4-step repeat keeps the step inside its group of 4
    vt.script(t('T')); eq('RETURN plays the channel', m1(pl_playing) >> ch & 1, 1)
    vt.poke(L['br_dbg'], 0x10); vt.sleep(0.4)
    seen = set()
    for _ in range(12):
        seen.add(m1(pl_pstep + ch)); vt.sleep(0.05)
    eq('beat repeat 4: steps stay in one group of 4', len({s >> 2 for s in seen}) == 1 and len(seen) > 1, True)
    vt.poke(L['br_dbg'], 0); vt.sleep(0.4)
    seen = set()
    for _ in range(20):
        seen.add(m1(pl_pstep + ch)); vt.sleep(0.05)
    eq('released: the phrase runs on', len({s >> 2 for s in seen}) > 1, True)
    return ch, ph

def rec_session():
    ch, ph = common(True)
    eq('channel plays the phrase on screen', m1(pl_phrase + ch), ph)
    # known content: note $30 / instrument 0 on every step, recorded as its own gesture
    vt.poke(0x8000 + ph * 64, *([0x30, 0, 0, 0] * 16))
    vt.script(t('D') + t('U'))
    before = phrase(ph)
    vt.script(keys(KC_F6)); eq('F6: armed (lr_on 15)', m1(L['lr_on']), 15)
    vt.sleep(0.2)
    eq('F6: pl_hold 15 on the channel', vt.mem(pl_hold, 6), [15 if c == ch else 0 for c in range(6)])
    eq('help line says rec', 'REC' in help_row().upper(), True)
    # freeze the player (CIA2 timer A stopped): exact stamps
    cra = m1(0xdd0e)
    vt.poke(0xdd0e, cra & 0xfe); vt.sleep(0.1)
    s, ln = m1(pl_pstep + ch), m1(pl_steplen + ch)
    c, cs = m1(pl_chain + ch), m1(pl_cstep + ch)
    tr = m1(0xc000 + c * 32 + cs * 2 + 1)
    ins = m1(L['last'] + 4)
    if not m1(0xe600 + ins * 16) & 1: tr = 0
    def stored(n): return (n - tr) & 0xff if 0 <= (n - tr) & 0xff < 96 else n
    eq('step length known', ln > 1, True)
    vt.poke(pl_wait + ch, ln)                       # first tick of the step: this step
    vt.script(keys(Z))
    eq(f'early key: written at once into step {s}', phrase(ph)[s * 4:s * 4 + 2], [stored(36), ins])
    vt.poke(pl_wait + ch, 1)                        # last tick: the next step, deferred
    vt.script(keys(X))
    n1 = (s + 1) & 15
    eq('late key: deferred (lr_pend)', (m1(L['lr_pend']), m1(L['lr_pnote'])), (n1, 38))
    eq(f'late key: step {n1} not yet written', phrase(ph)[n1 * 4], 0x30)
    vt.poke(0xdd0e, cra | 0x11); vt.sleep(0.6)
    eq(f'deferred write in step {n1} once the playhead got there', phrase(ph)[n1 * 4:n1 * 4 + 2], [stored(38), ins])
    eq('deferred write done', m1(L['lr_pend']), 0xff)
    p = phrase(ph)
    eq('overdub: other steps kept', [p[i * 4] for i in range(16) if i not in (s, n1)], [0x30] * 14)
    eq('still on the same phrase and chain step', (m1(pl_phrase + ch), m1(pl_cstep + ch)), (ph, cs))
    # C= held erases the steps passed
    vt.script([('B', None)] * 40 + [('', None)])
    p = phrase(ph)
    erased = [i for i in range(16) if p[i * 4] == 0xff and p[i * 4 + 1] == 0xff]
    eq('C= held: steps erased', 0 < len(erased) < 16, True)
    vt.script(keys(KC_F6)); eq('F6: stopped', (m1(L['lr_on']), vt.mem(pl_hold, 6)), (0, [0] * 6))
    took = phrase(ph)
    eq('the take changed the phrase', took != before, True)
    vt.script(keys(KC_F7)); eq('F7: the whole take undone', phrase(ph), before)
    vt.script(keys(0x4b)); eq('SHIFT+F7 (F8): redo', phrase(ph), took)
    # arming needs the phrase on screen playing
    vt.script(t('T')); eq('stopped', m1(pl_playing) >> ch & 1, 0)
    vt.script(keys(KC_F6)); eq('F6 while stopped: not armed', (m1(L['lr_on']), msg()), (0, 'play this phrase'))
    # the channel stopping ends the take
    vt.script(t('T') + keys(KC_F6)); eq('armed again', m1(L['lr_on']), 15)
    vt.script(t('T')); eq('RETURN stops: take ends', (m1(L['lr_on']), m1(pl_hold + ch)), (0, 0))

def plain_session():
    ch, ph = common(False)
    vt.script(keys(KC_F6)); eq('no REU: F6 says needs reu', (m1(L['lr_on']), msg()), (0, 'needs reu'))

for args, fn in ((['-reu', '-reusize', '512'], rec_session), ([], plain_session)):
    print('--- session', ' '.join(args) or 'no REU')
    vt.start(PRG, args); vt.sleep(6)
    try:
        fn()
    finally:
        vt.stop()
print('loop tests:', 'all ok' if not fails else f'{fails} failures')
sys.exit(1 if fails else 0)
