"""REU support in VICE (milestone R1): detection and
size (u_reu = highest bank, r_nslots), the File screen device REU (slots:
save / load / delete, byte-for-byte round trips over $8000-$cfff and
$e000-$f9ff), "needs reu" without an REU, crash/reset recovery after a soft
reset (RECOVERED, same data) and no recovery with C= held at start-up (a
breakpoint on rec_cbm stands in for the key: the debug input hook does not
run that early). Port: SIDJ_VICE_PORT (default 6511 here).
usage: python3 reu.py [prg] [--quick]   (--quick: 512 KB and none only)"""
import os, sys, re, time, socket
os.environ.setdefault('SIDJ_VICE_PORT', '6511')
import vt

args = [a for a in sys.argv[1:] if not a.startswith('--')]
PRG = os.path.abspath(args[0] if args else os.path.join(os.path.dirname(__file__), '../../build/sidj.prg'))
L = {}
for l in open(PRG.replace('.prg', '.labels')):
    m = re.match(r'(\S+)\s*= (\$[0-9a-f]+|\d+)$', l.strip())
    if m: L[m.group(1)] = int(m.group(2)[1:], 16) if m.group(2)[0] == '$' else int(m.group(2))
fails = 0
def eq(name, got, want):
    global fails
    ok = got == want; fails += not ok
    print(('ok  ' if ok else 'BAD ') + name, got, '' if ok else f'want {want}')
t = vt.tap
m1 = lambda a: vt.mem(a, 1)[0]
IDLE = [('', None)] * 12
LO, HI = (0x8000, 0xd000), (0xe000, 0xfa00)
ALLOC = (0xf900 - HI[0] + LO[1] - LO[0], 0xf93c - HI[0] + LO[1] - LO[0])
def song_data():
    """song data; the allocation bitmaps are left out: every load rebuilds
    them from the data (alloc_rebuild), as a disk load does"""
    d = vt.mem(LO[0], LO[1] - LO[0]) + vt.mem(HI[0], HI[1] - HI[0])
    return d[:ALLOC[0]] + d[ALLOC[1]:]
def same(a, b):
    if a == b: return True
    d = [i for i in range(len(a)) if a[i] != b[i]]
    print('     %d bytes differ, first at offset %x' % (len(d), d[0]))
    return False
def msg():
    v = vt.mem(0x0400 + 24*40, 20)
    return ''.join(chr(c + 64) if 1 <= c <= 26 else chr(c) for c in v).strip()
def scr(s):
    return [ord(c) - 0x40 if 'A' <= c <= 'Z' else ord(c) for c in s.upper().ljust(16)]
def fill(seed, name):
    """deterministic pattern over the song data, then the project name"""
    a = ' '.join('%02x' % ((seed * 37 + i * 11) & 255) for i in range(13))
    b = ' '.join('%02x' % ((seed * 53 + i * 7) & 255) for i in range(17))
    vt.mon(f'f 8000 cfff {a}', f'f e000 f9ff {b}')
    vt.poke(0xf810, *scr(name))
def file_screen():
    """Project screen LOAD -> File screen"""
    vt.poke(L['screen'], 6); vt.poke(L['need_clear'], 1)
    vt.poke(L['rowv'] + 6, 4); vt.poke(L['colv'] + 6, 0)
    vt.script(IDLE)
    vt.script(t('A') + IDLE)
    eq('-> file screen', m1(L['screen']), 8)
def row(r):
    """cursor to File screen row r"""
    vt.script(t('U') * 5 + t('D') * r + IDLE)
def panel_device():
    return vt.screen_text().splitlines()[1][23:33]
def dir_names(n):
    v = vt.mem(0x7e00, 16 * n)
    return [bytes(v[i*16:i*16+16]) for i in range(n)]

def boot_again(prg, cbm=False):
    """soft reset (REU keeps its contents), load and start SIDJ again; cbm:
    C= held at start-up (breakpoint on rec_cbm, A = 0)"""
    vt.mon('reset 0', 'r')              # (VICE: reconnecting right after a reset fails)
    time.sleep(1)
    if not cbm:
        vt.mon(f'l "{prg}" 0', f'r pc = {L["boot"]:04x}')
    else:   # one connection: VICE reports the breakpoint on it
        s = socket.create_connection(('127.0.0.1', vt.PORT), timeout=5)
        def until(pat, sec=10):
            buf, end = b'', time.time() + sec
            while time.time() < end and not re.search(pat, buf):
                try: buf += s.recv(65536)
                except socket.timeout: pass
            return buf.decode(errors='replace')
        for c in (f'l "{prg}" 0', f'break {L["rec_cbm"]:04x}', f'r pc = {L["boot"]:04x}'):
            s.sendall((c + '\n').encode()); until(rb'\(C:\$[0-9a-f]{4}\) $')
        s.sendall(b'x\n')
        out = until(rb'\(C:\$%04x\) $' % L['rec_cbm'])
        eq('C= breakpoint reached', ('C:$%04x' % L['rec_cbm']) in out, True)
        for c in ('r a = 00', 'del'):
            s.sendall((c + '\n').encode()); until(rb'\(C:\$[0-9a-f]{4}\) $')
        s.sendall(b'x\n'); s.close()
    vt.sleep(4)

SIZES = [(128, 1, 0), (256, 3, 0), (512, 7, 8), (16384, 255, 32), (None, 0, 0)]
if '--quick' in sys.argv:
    SIZES = [s for s in SIZES if s[0] in (512, None)]
for size, top, nslots in SIZES:
    print('--- REU %s' % (f'{size} KB' if size else 'none'))
    vt.start(PRG, ['-reu', '-reusize', str(size)] if size else ['+reu'])
    try:
        vt.sleep(6)
        eq('u_reu (highest bank)', m1(L['u_reu']), top)
        eq('slots', m1(L['r_nslots']), nslots)
        eq('no recovery on a fresh REU', msg() == 'RECOVERED', False)
        eq('demo song loaded', [m1(0xe000 + c*256) for c in range(3)], [0, 1, 2])
        file_screen()
        if not nslots:
            vt.script(t('R') + IDLE)
            eq('device switch refused', (m1(L['f_reu']), msg()), (0, 'NEEDS REU' if not size else 'REU TOO SMALL'))
            eq('panel: drive', panel_device(), 'DEVICE 08 ')
            continue
        vt.script(t('R') + IDLE)
        eq('device REU', (m1(L['f_reu']), panel_device(), msg()), (1, 'DEVICE REU', 'REU SLOTS'))
        eq('all slots listed, free', (m1(0x7dff), set(dir_names(nslots))), (nslots, {bytes(scr('-'))[:1] + bytes(scr(''))[1:]}))
        # save two projects, round trip both
        fill(1, 'alpha'); p1 = song_data()
        row(0); vt.script(t('A') + IDLE)
        eq('save alpha', (msg(), dir_names(1)[0]), ('SAVED TO REU', bytes(scr('alpha'))))
        fill(2, 'beta'); p2 = song_data()
        vt.script(t('A') + IDLE)
        eq('save beta -> slot 1', (msg(), dir_names(2)[1]), ('SAVED TO REU', bytes(scr('beta'))))
        vt.mon('f 8000 cfff 00', 'f e000 f9ff 00')
        row(1); vt.script(t('A') + t('A') + IDLE * 2)
        eq('load alpha', (msg(), m1(L['screen'])), ('LOADED FROM REU', 0))
        eq('alpha byte for byte', same(song_data(), p1), True)
        eq('player state after load', (m1(0x1020), m1(0x1022)), (0, p1[0xf800 - HI[0] + LO[1] - LO[0]]))
        file_screen()
        eq('device kept', panel_device(), 'DEVICE REU')
        row(2); vt.script(t('A') + t('A') + IDLE * 2)
        eq('load beta', msg(), 'LOADED FROM REU')
        eq('beta byte for byte', same(song_data(), p2), True)
        # same name again: same slot; delete; empty slot
        file_screen()
        vt.poke(0x8000, 0x5a); p2b = song_data()
        row(0); vt.script(t('A') + IDLE)
        eq('save beta again: same slot', (msg(), dir_names(3)[1:]), ('SAVED TO REU', [bytes(scr('beta')), bytes(scr('-'))]))
        row(1); vt.script([('B', None), ('BA', None), ('B', None), ('BA', None), ('B', None), ('', None)] + IDLE)
        eq('delete alpha', (msg(), dir_names(1)[0]), ('SLOT DELETED', bytes(scr('-'))))
        vt.script(t('A') + t('A') + IDLE)
        eq('load a free slot', msg(), 'EMPTY SLOT')
        if size == 512:
            # crash/reset recovery: load beta (mirror = beta), soft reset, start again
            row(2); vt.script(t('A') + t('A') + IDLE * 2)
            eq('load beta again', same(song_data(), p2b), True)
            vt.script(IDLE * 2)
            boot_again(PRG)
            eq('recovered after a reset', (msg(), m1(L['u_reu']), m1(L['screen'])), ('RECOVERED', 7, 0))
            eq('recovered byte for byte', same(song_data(), p2b), True)
            file_screen(); vt.script(t('R') + IDLE)
            eq('slots survive the reset', dir_names(2), [bytes(scr('-')), bytes(scr('beta'))])
            # an edit after recovery is in the mirror too
            vt.poke(L['screen'], 0); vt.poke(L['need_clear'], 1)
            vt.script(IDLE + t('D') * 5 + [('', 4), ('', None), ('', 2), ('', None)] + IDLE * 2)
            edited = song_data()
            eq('edit made', edited != p2b, True)
            boot_again(PRG)
            eq('recovered the edit', (msg(), same(song_data(), edited)), ('RECOVERED', True))
            # C= at start-up: no recovery (demo), recovery is offered again later
            boot_again(PRG, cbm=True)
            eq('C= held: no recovery, demo song', (msg() == 'RECOVERED', [m1(0xe000 + c*256) for c in range(3)]), (False, [0, 1, 2]))
            boot_again(PRG)
            eq('next start recovers the demo (mirror = demo)', (msg(), [m1(0xe000 + c*256) for c in range(3)]), ('RECOVERED', [0, 1, 2]))
    finally:
        vt.stop()
print('FAILS', fails)
sys.exit(1 if fails else 0)
