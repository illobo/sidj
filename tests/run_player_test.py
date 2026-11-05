#!/usr/bin/env python3
"""Run build/player_test.prg in VICE (x64sc, warp), dump the trace via the
remote monitor and check it with check_player.py.

Usage: run_player_test.py [--update-golden] [--keep]
Uses only the monitor port below and kills only the VICE it started.
"""
import os, re, socket, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
PRG = os.path.join(BUILD, "player_test.prg")
LABELS = os.path.join(BUILD, "player_test.labels")
DUMP = os.path.join(BUILD, "player_test_dump.prg")
DUMP2 = os.path.join(BUILD, "player_test_live.prg")
DUMP3 = os.path.join(BUILD, "player_test_sid2.prg")
DUMP4 = os.path.join(BUILD, "player_test_hold.prg")
PORT = int(os.environ.get("SIDJ_PLAYER_PORT", 6511))   # override when 6511 is busy


def label(name):
    for line in open(LABELS):
        m = re.match(r"(\S+)\s*= \$([0-9a-fA-F]+)", line)
        if m and m.group(1) == name:
            return int(m.group(2), 16)
    raise KeyError(name)


def mon(sock, cmd, wait_for=b"(C:$", timeout=60):
    sock.sendall(cmd.encode() + b"\n")
    buf = b""
    end = time.time() + timeout
    while time.time() < end:
        try:
            data = sock.recv(4096)
        except socket.timeout:
            continue
        if not data:
            break
        buf += data
        if wait_for in buf:
            return buf.decode(errors="replace")
    raise TimeoutError("monitor: no reply to %r: %r" % (cmd, buf[-300:]))


def main():
    flag = label("RESULTS") + 7
    env = dict(os.environ, GSETTINGS_SCHEMA_DIR="/opt/homebrew/share/glib-2.0/schemas")
    for d in (DUMP, DUMP2, DUMP3, DUMP4):
        if os.path.exists(d):
            os.remove(d)
    log = open(os.path.join(BUILD, "player_test_vice.log"), "w")
    vice = subprocess.Popen(
        ["x64sc", "-default", "-warp", "-sounddev", "dummy",
         "-remotemonitor", "-remotemonitoraddress", "ip4://127.0.0.1:%d" % PORT,
         "-autostart", PRG],
        stdout=log, stderr=subprocess.STDOUT, env=env)
    try:
        sock = None
        for _ in range(100):
            try:
                sock = socket.create_connection(("127.0.0.1", PORT), timeout=1)
                break
            except OSError:
                time.sleep(0.2)
        if sock is None:
            sys.exit("cannot connect to VICE monitor on port %d" % PORT)
        sock.settimeout(0.5)
        # poll the results "done" byte; each poll briefly stops the emulation
        def wait_done(value):
            end = time.time() + 120
            while True:
                out = mon(sock, "m %04x %04x" % (flag, flag))
                m = re.search(r">C:%04x\s+([0-9a-f]{2})" % flag, out)
                if m and m.group(1) == value:
                    return
                if time.time() > end:
                    sys.exit("test program did not finish (phase %s)" % value)
                sock.sendall(b"x\n")
                time.sleep(0.5)
        wait_done("01")
        mon(sock, 'save "%s" 0 2f00 7fff' % DUMP)
        mon(sock, "> %04x 01" % (flag + 5))     # RESULTS+12: go, phase 2
        sock.sendall(b"x\n")
        time.sleep(0.5)
        wait_done("02")
        mon(sock, 'save "%s" 0 2f00 7fff' % DUMP2)
        mon(sock, "> %04x 02" % (flag + 5))     # phase 3 (2SID)
        sock.sendall(b"x\n")
        time.sleep(0.5)
        wait_done("03")
        mon(sock, 'save "%s" 0 2f00 7fff' % DUMP3)
        mon(sock, "> %04x 03" % (flag + 5))     # phase 4 (hold)
        sock.sendall(b"x\n")
        time.sleep(0.5)
        wait_done("04")
        mon(sock, 'save "%s" 0 2f00 7fff' % DUMP4)
        try:
            sock.sendall(b"quit\n")
        except OSError:
            pass
        sock.close()
        for _ in range(50):
            if vice.poll() is not None:
                break
            time.sleep(0.1)
    finally:
        if vice.poll() is None:
            vice.kill()
            vice.wait()
    if not (os.path.exists(DUMP) and os.path.exists(DUMP2) and os.path.exists(DUMP3) and os.path.exists(DUMP4)):
        sys.exit("no dump written")
    args = [sys.executable, os.path.join(ROOT, "tests", "check_player.py"), DUMP, DUMP2, DUMP3, DUMP4]
    args += [a for a in sys.argv[1:] if a == "--update-golden"]
    sys.exit(subprocess.call(args))


if __name__ == "__main__":
    main()
