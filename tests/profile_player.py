#!/usr/bin/env python3
"""Cycle profile of pl.tick in a 6502 simulator (py65), no VICE needed.

Runs build/player_test.prg (or a given PRG) from `start` until the trace
loop is done, timing every call of pl.tick and attributing cycles to the
nearest preceding label (exclusive). Prints the slowest ticks with their
breakdown. VIC/CIA are faked just enough for the test (PAL detect).
Cycle counts follow py65 (no badlines, close to VICE with the screen off).

Usage: profile_player.py [prg] [vice-labels] [--top N] [--tick T] [--tables]
--tables: profile the table scenario (table_test) instead of phase 1.
--six: profile the 2SID scenario (sid2_test: six voices, SID2 in RAM).
"""
import bisect, collections, os, re, sys
from py65.devices.mpu6502 import MPU

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
args = []
_skip = False
for a in sys.argv[1:]:
    if _skip:
        _skip = False
    elif a in ("--top", "--tick"):
        _skip = True
    elif not a.startswith("--"):
        args.append(a)
prg = args[0] if args else os.path.join(ROOT, "build", "player_test.prg")
lab = args[1] if len(args) > 1 else os.path.join(ROOT, "build", "player_test.vlabels")
top = 5
only = None
for i, a in enumerate(sys.argv):
    if a == "--top":
        top = int(sys.argv[i + 1])
    if a == "--tick":
        only = int(sys.argv[i + 1])

labels = {}
for line in open(lab):
    m = re.match(r"al ([0-9a-f]+) \.(\S+)", line)
    if m:
        a = int(m.group(1), 16)
        n = m.group(2).replace(":", ".")
        if a not in labels or len(n) < len(labels[a]):
            labels[a] = n
addrs = sorted(labels)
by_name = {v: k for k, v in labels.items()}


def where(pc):
    i = bisect.bisect_right(addrs, pc) - 1
    return labels[addrs[i]] if i >= 0 else "?"


class Mem(list):
    line = 0

    def __getitem__(self, a):
        if a == 0xd012:
            Mem.line = (Mem.line + 1) % 312
            return Mem.line & 0xff
        if a == 0xd011:
            Mem.line = (Mem.line + 1) % 312
            return 0x80 if Mem.line >= 256 else 0
        return list.__getitem__(self, a)


data = open(prg, "rb").read()
mem = Mem([0] * 65536)
load = data[0] | data[1] << 8
for i, b in enumerate(data[2:]):
    mem[load + i] = b
mpu = MPU(memory=mem)
mpu.pc = by_name["start"]
SENTINEL = 0xfff0
tables = "--tables" in sys.argv
six = "--six" in sys.argv
if tables or six:   # song set up as start does, then table_test / sid2_test alone
    for lbl in ("clear_project", "load_song", "sid2_test" if six else "table_test"):
        mpu.sp = 0xff
        mpu.memory[0x1ff] = (SENTINEL - 1) >> 8
        mpu.memory[0x1fe] = (SENTINEL - 1) & 0xff
        mpu.sp = 0xfd
        mpu.pc = by_name[lbl]
        if lbl in ("table_test", "sid2_test"):
            break
        while mpu.pc != SENTINEL:
            mpu.step()
    mem[0x01] = 0x35
tick = by_name["pl.tick"]
ret_after = None
zp_t = 0x44
ticks = []           # (index, total, Counter)
cur = None
n = 0
while True:
    pc = mpu.pc
    if pc == tick and cur is None:
        cur = collections.Counter()
        t_index = mem[zp_t] | mem[zp_t + 1] << 8
        sp0 = mpu.sp
        c0 = mpu.processorCycles
    before = mpu.processorCycles
    mpu.step()
    if cur is not None:
        cur[where(pc)] += mpu.processorCycles - before
        if mem[pc] == 0x60 and mpu.sp == (sp0 + 2) & 0xff:   # rts out of tick
            ticks.append((t_index, mpu.processorCycles - c0 + 12, cur))
            cur = None
            if t_index >= 511:
                break
    if pc == SENTINEL:
        break
    n += 1
    if n > 50_000_000:
        sys.exit("runaway")

tot = [t[1] for t in ticks]
print("ticks %d: avg %.0f, max %d at t%d" % (
    len(tot), sum(tot) / len(tot), max(tot), ticks[tot.index(max(tot))][0]))
sel = [t for t in ticks if t[0] == only] if only is not None else \
    sorted(ticks, key=lambda t: -t[1])[:top]
for idx, total, cnt in sel:
    print("t%d: %d cycles" % (idx, total))
    for name, c in cnt.most_common(40):
        print("   %5d %s" % (c, name))
