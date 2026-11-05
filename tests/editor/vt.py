"""VICE remote-monitor helper for SIDJ editor tests (port 6512; SIDJ_VICE_PORT overrides;
SIDJ_VICE_ARGS adds x64sc options, e.g. "-reu -reusize 512")."""
import socket, subprocess, time, os, sys, re

PORT = int(os.environ.get('SIDJ_VICE_PORT', 6512))
HERE = os.path.dirname(os.path.abspath(__file__))
WARP = os.environ.get('SIDJ_WARP', '1') == '1'   # SIDJ_WARP=0: real-time VICE
PIDF = os.path.join(HERE, 'vice.pid' if PORT == 6512 else f'vice{PORT}.pid')

def start(prg, extra=()):
    env = dict(os.environ, GSETTINGS_SCHEMA_DIR='/opt/homebrew/share/glib-2.0/schemas')
    extra = [*extra, *os.environ.get('SIDJ_VICE_ARGS', '').split()]   # e.g. SIDJ_VICE_ARGS="-reu -reusize 512"
    p = subprocess.Popen(['x64sc', '-remotemonitor', '-remotemonitoraddress', f'ip4://127.0.0.1:{PORT}',
                          *(['-warp'] if WARP else []), '-sounddev', 'dummy', '-drive8type', '0', *extra, '-autostartprgmode', '1', '-autostart', prg],   # no drive: file calls fail fast (DEVICE NOT PRESENT)
                         env=env, stdout=open(os.path.join(HERE, 'vice.log' if PORT == 6512 else f'vice{PORT}.log'), 'w'), stderr=subprocess.STDOUT)
    open(PIDF, 'w').write(str(p.pid))
    global LABELS
    LABELS = prg.replace('.prg', '.labels')
    return p.pid

def stop():
    if os.path.exists(PIDF):
        pid = int(open(PIDF).read())
        try: os.kill(pid, 15)
        except ProcessLookupError: pass
        os.remove(PIDF)

def mon(*cmds, resume=True):
    s = socket.create_connection(('127.0.0.1', PORT), timeout=5)
    out = []
    need = [2]                   # entering the monitor prints a prompt first
    def readprompt():
        buf = b''
        s.settimeout(5)
        while True:
            try:
                d = s.recv(65536)
            except socket.timeout:
                break
            if not d: break
            buf += d
            if re.search(rb'\(C:\$[0-9a-f]{4}\) $', buf) and \
               len(re.findall(rb'\(C:\$[0-9a-f]{4}\) ', buf)) >= need[0]:
                need[0] = 1
                break                # prompt ends the command's output
        return buf.decode(errors='replace')
    for c in cmds:
        s.sendall((c + '\n').encode())
        out.append(readprompt())
    if resume:
        s.sendall(b'x\n')
    s.close()
    return ''.join(out)

def mem(addr, n):
    r = mon(f'm {addr:04x} {addr+n-1:04x}')
    vals = []
    for line in r.splitlines():
        m = re.search(r'>C:([0-9a-f]{4})\s+((?:[0-9a-f]{2}\s+)+)', line)
        if m: vals += [int(x, 16) for x in m.group(2).split()[:16]]
    return vals[:n]

BT = dict(U=1, D=2, L=4, R=8, A=0x10, B=0x20, S=0x40, T=0x80)
def script(steps, wait=True):
    """steps: list of (buttons-string, char) e.g. ('A', None), ('AR', None), ('', 5)"""
    data = []
    for b, ch in steps:
        v = 0
        for c in b: v |= BT[c]
        data += [v, 0xff if ch is None else ch]
    assert len(data) <= 256
    cmds = [f'> {0xd00+i:04x} ' + ' '.join(f'{x:02x}' for x in data[i:i+16]) for i in range(0, len(data), 16)]
    mon(*cmds, f'> 0c00 {len(steps):02x} 00')
    if wait:
        sleep(len(steps) / 50 + 0.5)
        settle()

def settle(limit=10, extra=0.3):
    """the key script may run slower than one step a frame (e.g. REU undo
    scans finishing at the next gesture): wait until it is consumed"""
    end = time.time() + limit
    if mem(0x0c00, 1)[0]:
        while time.time() < end and mem(0x0c00, 1)[0]:
            time.sleep(0.05)
        if extra: sleep(extra)

MB = dict(L=1, R=2)
def cell(col, row):
    """pointer position (hot spot) inside character cell col/row"""
    return (col * 8 + 3, row * 8 + 3)
def mscript(frames, keys=None, wait=True):
    """mouse debug hook: frames = list of (x, y, buttons 'L'/'R'/'LR'/'');
    keys = optional keyboard script (as script()) started in the same frame"""
    data = []
    for x, y, b in frames:
        f = 0
        for c in b: f |= MB[c]
        data += [x & 255, y, f | (0x80 if x > 255 else 0)]
    assert len(frames) <= 74
    cmds = [f'> {0xc10+i:04x} ' + ' '.join(f'{v:02x}' for v in data[i:i+16]) for i in range(0, len(data), 16)]
    if keys:
        kd = []
        for b, ch in keys:
            v = 0
            for c in b: v |= BT[c]
            kd += [v, 0xff if ch is None else ch]
        cmds += [f'> {0xd00+i:04x} ' + ' '.join(f'{x:02x}' for x in kd[i:i+16]) for i in range(0, len(kd), 16)]
        cmds.append(f'> 0c00 {len(keys):02x} 00 {len(frames):02x} 00')
    else:
        cmds.append(f'> 0c02 {len(frames):02x} 00')
    mon(*cmds)
    if wait:
        sleep(max(len(frames), len(keys or ())) / 50 + 0.5)
def click(col, row, b='L', hold=2, gap=2, at=None):
    """frames: move there, press for hold frames, release"""
    x, y = at or cell(col, row)
    return [(x, y, '')] + [(x, y, b)] * hold + [(x, y, '')] * gap
def drag(col, row, dx, dy, step=4):
    """press at the cell, move by (dx, dy) pixels in steps, release"""
    x, y = cell(col, row)
    fr = [(x, y, ''), (x, y, 'L')]
    n = max(abs(dx), abs(dy)) // step
    for i in range(1, n + 1):
        fr.append((x + dx * i // n, y + dy * i // n, 'L'))
    fr += [(x + dx, y + dy, 'L'), (x + dx, y + dy, ''), (x + dx, y + dy, '')]
    return fr

def tap(b, hold=2, gap=2):
    return [(b, None)] * hold + [('', None)] * gap

def shot(name):
    path = os.path.join(HERE, name)
    mon(f'screenshot "{path}" 2')
    return path

def screen_text():
    v = mem(0x0400, 1000)
    rows = []
    for r in range(25):
        line = ''
        for c in v[r*40:(r+1)*40]:
            cc = c & 0x7f
            if 1 <= cc <= 26: ch = chr(cc + 64)
            elif 32 <= cc < 64: ch = chr(cc)
            elif cc == 0: ch = '@'
            else: ch = '?'
            line += ch.lower() if c & 0x80 else ch   # reversed shown lowercase
        rows.append(line)
    return '\n'.join(f'{i:2d}|{l}|' for i, l in enumerate(rows))

def poke(addr, *vals):
    mon(f'> {addr:04x} ' + ' '.join(f'{v:02x}' for v in vals))

def screen_state():
    """screen codes + colours; the colour of a space is invisible and ignored"""
    s = mem(0x0400, 1000)
    c = mem(0xd800, 1000)
    return s + [(c[i] & 15) if s[i] != 0x20 else -1 for i in range(1000)]

def redraw_matches(need_clear_addr):
    """Partial redraw check: screen + colour RAM now == after a forced full redraw.
    Returns list of differing (row, col) positions (empty = consistent)."""
    a = screen_state()
    poke(need_clear_addr, 1)
    sleep(0.15)
    b = screen_state()
    return sorted({((i % 1000) // 40, i % 40) for i in range(2000) if a[i] != b[i]})

# Emulated-time wait: counts editor frames (in_frame) so warp mode stays
# correct; never waits longer in wall-clock time than the real-time sleep.
LABELS = os.environ.get('SIDJ_LABELS', os.path.join(HERE, '../../build/sidj.labels'))
_in_frame = None
def sleep(sec):
    global _in_frame
    if not WARP:
        time.sleep(sec); return
    if _in_frame is None:
        for l in open(LABELS):
            m = re.match(r'in_frame\s*= \$([0-9a-f]+)', l)
            if m: _in_frame = int(m.group(1), 16)
    n = max(1, round(sec * 50))
    end = time.time() + sec
    last = None
    done = 0
    while done < n and time.time() < end:
        try:
            cur = mem(_in_frame, 1)[0]
        except (OSError, IndexError):   # VICE still starting
            time.sleep(0.05); continue
        if last is not None:
            done += (cur - last) & 255
        last = cur
