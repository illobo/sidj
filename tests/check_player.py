#!/usr/bin/env python3
"""Check the player trace written by tests/player_test.asm.

Usage: check_player.py dump.prg [live.prg] [--update-golden]
dump.prg: VICE `save` of $2f00-$7fff (results block + trace), phase 1.
live.prg: the same after phase 2 (live mode trace, FRAME2 bytes per tick).
The song under test is in tests/player_test.asm; expectations below refer
to its phrases. The golden file holds the shadow/state part of every frame
(not the cycle counts) for regression.
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
GOLDEN = os.path.join(HERE, "golden", "player_trace.bin")
NTICKS, FRAME, STATE = 512, 40, 36

args = [a for a in sys.argv[1:] if not a.startswith("--")]
update = "--update-golden" in sys.argv
raw = open(args[0], "rb").read()
assert raw[:2] == b"\x00\x2f", "dump must start at $2f00"
mem = raw[2:]
res, trace = mem[:0x100], mem[0x100:0x100 + NTICKS * FRAME]
frames = [trace[t * FRAME:(t + 1) * FRAME] for t in range(NTICKS)]

fails = []
def check(cond, msg):
    if not cond:
        fails.append(msg)

# --- note table, as the player computes it (PAL) ------------------------
def f6(n, hz=985248.0):
    return int(round(440.0 * 2.0 ** ((n - 57) / 12.0) * 16777216.0 / hz))
OCT6 = [f6(n) for n in range(72, 85)]
def freq(n):
    o, s = divmod(n, 12)
    f = OCT6[s]
    return min(0xffff, f << 1) if o == 7 else f >> (6 - o)
FREQ = [freq(n) for n in range(96)]

def v_freq(t, v): f = frames[t]; return f[v * 7] | f[v * 7 + 1] << 8
def v_pw(t, v): f = frames[t]; return f[v * 7 + 2] | (f[v * 7 + 3] << 8)
def v_ctl(t, v): return frames[t][v * 7 + 4]
def v_ad(t, v): return frames[t][v * 7 + 5]
def v_sr(t, v): return frames[t][v * 7 + 6]
def gate(t, v): return v_ctl(t, v) & 1
def note(t, v):
    f = v_freq(t, v)
    return FREQ.index(f) if f in FREQ else None
def playing(t): return frames[t][25]
def row(t, c): return frames[t][26 + c]
def cstep(t, c): return frames[t][29 + c]
def pstep(t, c): return frames[t][32 + c]
def reg(t, r): return frames[t][r]

def N(name, octave):
    return "C C# D D# E F F# G G# A A# B".split().index(name) + 12 * octave

def expect_note(t, v, n, what):
    check(note(t, v) == n, "t%d v%d %s: note %s, want %d (freq $%04x)" % (
        t, v, what, note(t, v), n, v_freq(t, v)))

# --- results block -------------------------------------------------------
ntsc = res[0]
latch_t80 = res[1] | res[2] << 8
calib = res[3] | res[4] << 8
rate125, rate295 = res[5], res[6]
latch125 = res[8] | res[9] << 8
latch295 = res[10] | res[11] << 8
check(res[7] == 1, "test program did not finish")
check(ntsc == 0, "VICE default is PAL, detected NTSC")
check(latch125 == round(2463120 / 125), "latch @125 = %d" % latch125)
check(latch295 == round(2463120 / 295), "latch @295 = %d" % latch295)
check(latch_t80 == round(2463120 / 128), "T80 latch = %d, want %d" % (latch_t80, round(2463120 / 128)))
check(49 <= rate125 <= 51, "NMI ticks/s @125 BPM = %d, want 50" % rate125)
check(117 <= rate295 <= 119, "NMI ticks/s @295 BPM = %d, want 118" % rate295)

# --- pl_nudge (real clock, 125 BPM): CIA1 stamps, one per tick ------------
# Timer latch = latch - round(latch * nudge / 256); the CIA period is latch + 1.
# A stamp is taken when the NMI returns, so it moves with the tick's length:
# the test silences the player first (even ticks), but the tick that applies
# a new nudge is ~300 cycles longer, so around it pairs are checked. pl_nudge is set right after
# stamp 21k-1; tick 21k loads the new latch, the underflow after it uses it:
# intervals 21k-1 and 21k are old, 21k+1 on new.
NSEG, NUDGES = 21, (0, 8, -8, 0)
def eff(n):
    adj = (latch125 * abs(n) + 128) >> 8
    return latch125 - adj if n > 0 else min(0xffff, latch125 + adj)
les = [res[16 + 2 * k] | res[17 + 2 * k] << 8 for k in range(4)]
check(les == [eff(n) for n in NUDGES], "latch_eff per segment %s, want %s" % (les, [eff(n) for n in NUDGES]))
st = [res[0x20 + 2 * i] | res[0x21 + 2 * i] << 8 for i in range(4 * NSEG)]
iv = [(st[i] - st[i + 1]) & 0xffff for i in range(4 * NSEG - 1)]
nudge_rates = []
for k, n in enumerate(NUDGES):
    want = eff(n) + 1
    lo = 21 * k + 1 + (2 if k == 0 else 0)        # seg 0: tempo just changed
    seg = iv[lo:min(21 * k + 22, len(iv))]         # both ends: apply ticks
    mean = sum(seg) / len(seg)
    nudge_rates.append(985248.0 / mean)
    check(abs(mean - want) <= 1.0, "nudge %+d: mean tick %.1f cycles, want %d" % (n, mean, want))
    check(all(abs(x - want) <= 40 for x in seg[:-2]), "nudge %+d: tick intervals %s" % (n, seg))
    if k:
        old = eff(NUDGES[k - 1]) + 1
        pair = iv[21 * k - 1] + iv[21 * k]
        check(abs(pair - 2 * old) <= 40 and abs(iv[21 * k + 1] - want) <= 40,
              "nudge %+d: not applied on the next tick (intervals %d+%d, %d; old %d new %d)" % (
                  n, iv[21 * k - 1], iv[21 * k], iv[21 * k + 1], old, want))
check(les[3] == latch125, "nudge back to 0: latch_eff %d != latch %d" % (les[3], latch125))

# --- ch0: bass, groove 6, chain transpose, filter own ---------------------
ph0 = {0: N("C", 2), 2: N("C", 3), 4: N("C", 2), 6: N("C", 3), 8: N("D#", 2),
       10: N("D#", 2), 12: N("F", 2), 14: N("G", 2)}
for base, tr, rw in ((0, 0, 0), (96, 5, 0), (192, 0, 1), (288, 5, 1)):
    for s, n in ph0.items():
        t = base + s * 6
        expect_note(t, 0, n + tr, "phrase 0 step %d tr %d" % (s, tr))
        check(row(t, 0) == rw and pstep(t, 0) == s, "t%d ch0 pos row %d step %d" % (t, row(t, 0), pstep(t, 0)))
    for t in range(base, base + 96):          # filter owned by the bass
        check(reg(t, 0x17) == 0x81 and reg(t, 0x18) == 0x1f, "t%d filter $d417/8 %02x %02x" % (t, reg(t, 0x17), reg(t, 0x18)))
        if (t - base) % 12 == 0:
            check(reg(t, 0x16) == 0x2e, "t%d cutoff after trigger $%02x" % (t, reg(t, 0x16)))
        else:
            check(reg(t, 0x16) == (reg(t - 1, 0x16) - 2) & 0xff, "t%d filter sweep" % t)
    # C37 arp on step 6: 0, 3, 7 per tick, continuing into step 7
    for k in range(12):
        expect_note(base + 36 + k, 0, ph0[6] + tr + (0, 3, 7)[k % 3], "arp")
    # P10 bend on step 8: rising every tick, reset by the note on step 10
    for t in range(base + 49, base + 60):
        check(v_freq(t, 0) > v_freq(t - 1, 0), "t%d bend not rising" % t)
    # V42 on step 12: wobbles around F-2 within +-0.375 semitone
    fs = [v_freq(t, 0) for t in range(base + 72, base + 84)]
    centre = FREQ[ph0[12] + tr]
    check(min(fs) < centre < max(fs), "t%d vibrato does not cross the note" % base)
    check(max(fs) < FREQ[ph0[12] + tr + 1] and min(fs) > FREQ[ph0[12] + tr - 1], "t%d vibrato too deep" % base)
    # K02 on step 14: gate for 2 ticks, then off until the next phrase
    for k in range(12):
        check(gate(base + 84 + k, 0) == (1 if k < 2 else 0), "t%d K02 gate" % (base + 84 + k))

# ch0 phrase 1 (row 2, from tick 384): command tour
B = 384
expect_note(B, 0, N("C", 2), "phrase 1 start")
check(v_freq(B + 12, 0) < FREQ[N("C", 3)], "L06: no jump at slide start")
for t in range(B + 13, B + 18):
    check(v_freq(t, 0) > v_freq(t - 1, 0), "t%d L06 slide not rising" % t)
expect_note(B + 17, 0, N("C", 3), "L06 reaches C-3 within 6 ticks")
check(all(gate(t, 0) for t in range(B + 12, B + 24)), "L06 must not retrigger")
for t in range(B + 24, B + 27):
    expect_note(t, 0, N("C", 3), "D03 still old note")
expect_note(B + 27, 0, N("G", 2), "D03 note after 3 ticks")
check(v_pw(B + 36, 0) == 0x400, "S40: PW $%03x" % v_pw(B + 36, 0))
check(v_ctl(B + 48, 0) == 0x21, "W20: ctl $%02x" % v_ctl(B + 48, 0))
check(reg(B + 60, 0x16) == 0x7e, "X80: cutoff $%02x (one sweep step)" % reg(B + 60, 0x16))
check(reg(B + 66, 0x17) == 0xf1 and reg(B + 66, 0x18) == 0x1f, "O1F: res f, mode LP")
check(reg(B + 72, 0x18) == 0x18, "M08: volume ($d418 $%02x)" % reg(B + 72, 0x18))
check(reg(B + 72, 0x17) == 0x81, "own trigger after O restores res/mode")
check(v_sr(B + 78, 0) == 0xf0, "E F0: SR $%02x" % v_sr(B + 78, 0))
# table 0 on step 14 (instrument 3): $81 / $41 -12 / $41 -24 held by H02
check(v_ctl(B + 84, 0) == 0x81, "table row 0 ctl $%02x" % v_ctl(B + 84, 0))
expect_note(B + 84, 0, N("C", 2), "table row 0")
check(v_ctl(B + 85, 0) == 0x41, "table row 1 ctl")
expect_note(B + 85, 0, N("C", 1), "table row 1 -12")
for t in range(B + 86, B + 96):
    expect_note(t, 0, N("C", 0), "table row 2 held by H02")
check(reg(B + 84, 0x17) & 1 == 0, "filter off instrument clears routing")
# song loop: row 3 empty -> back to row 0
check(row(480, 0) == 0 and pstep(480, 0) == 0, "loop to row 0 at t480")
expect_note(480, 0, N("C", 2), "after loop")

# --- ch1: lead on groove 8/4, HR 2 ticks mode 1, Q03 ---------------------
ph2 = [N("G", 4), N("A", 4), N("B", 4), N("C", 5), N("D", 5), N("C", 5), N("B", 4), N("A", 4)]
for p, tr in enumerate((0, 12, 0, 12, 0)):
    base = p * 96
    if base >= NTICKS:
        break
    for k, n in enumerate(ph2):
        t = base + 12 * k
        expect_note(t, 1, n + tr, "lead phrase %d step %d" % (p, 2 * k))
        check(pstep(t, 1) == 2 * k and pstep(t + 8, 1) == 2 * k + 1, "t%d groove 8/4 timing" % t)
        if t >= 300 and t < 360:
            continue                       # muted below
        hr = 3 if k == 4 else 2            # Q03 on step 8
        if t > 0:
            for d in range(1, 5):
                inhr = d <= hr
                tt = t - d
                if 300 <= tt < 360:
                    continue
                check(gate(tt, 1) == (0 if inhr else 1), "t%d HR gate (%d before note)" % (tt, d))
                if inhr:
                    check(v_ad(tt, 1) == 0 and v_sr(tt, 1) == 0, "t%d HR ADSR %02x%02x" % (tt, v_ad(tt, 1), v_sr(tt, 1)))
        check(gate(t, 1) == 1 and v_ad(t, 1) == 0x09 and v_sr(t, 1) == 0xa9, "t%d lead trigger" % t)
for t in range(1, 300):                  # PW sweep up $18/tick, 12-bit wrap
    if pstep(t, 1) == pstep(t - 1, 1) or pstep(t, 1) % 2:
        if not (pstep(t, 1) % 2 == 0 and t % 12 == 0):
            check(v_pw(t, 1) == (v_pw(t - 1, 1) + 0x18) & 0xfff, "t%d PW sweep" % t)
# mute ch1 300..359: sequencing goes on, gate off, SR 0
for t in range(300, 360):
    check(gate(t, 1) == 0 and v_sr(t, 1) == 0, "t%d mute" % t)
    check(playing(t) & 2, "t%d muted channel still plays" % t)
check(pstep(359, 1) != pstep(300, 1), "muted channel keeps sequencing")
check(gate(360, 1) == 1, "unmute")

# --- ch2: drums, transpose off, H10, H04, B, HFF -------------------------
for t in (0, 24, 48, 72, 84, 108, 132, 156, 180, 204):
    expect_note(t, 2, N("C", 4), "drum (chain transpose +12 ignored)")
check(pstep(78, 2) == 13 and pstep(84, 2) == 0, "H10 hops back once")
check(pstep(162, 2) == 13 and pstep(168, 2) == 14 and pstep(174, 2) == 15, "H10 falls through second time")
check(row(180, 2) == 1 and pstep(180, 2) == 0, "next row after phrase 3")
check(cstep(204, 2) == 1 and pstep(204, 2) == 4, "H04: next phrase at step 4")
expect_note(228, 2, N("C", 4), "B00 never plays")
expect_note(240, 2, N("E", 4), "B0F always plays")
check(all(playing(t) & 4 for t in range(0, 252)), "ch2 plays until HFF")
check(not any(playing(t) & 4 for t in range(252, 420)), "HFF stops ch2 at t252")
check(all(gate(t, 2) == 0 for t in range(252, 380)), "stopped channel: gate off")
# preview on the stopped channel, then play_channel
expect_note(380, 2, N("A", 4), "note_on preview")
check(gate(380, 2) == 1 and v_ctl(380, 2) == 0x41 and v_ad(380, 2) == 0x09, "note_on instrument 1")
check(gate(399, 2) == 1 and gate(400, 2) == 0, "note_off")
check(playing(420) & 4 and row(420, 2) == 0 and pstep(420, 2) == 0, "play_channel row 0")
expect_note(420, 2, N("C", 4), "play_channel note")

# --- tick counter --------------------------------------------------------
for t in range(1, NTICKS):
    check(frames[t][35] == (frames[t - 1][35] + 1) & 0xff, "t%d pl_tick" % t)

# --- cycles --------------------------------------------------------------
cyc = [calib - (f[36] | f[37] << 8) for f in frames]
avg = sum(cyc) / len(cyc)
worst = max(cyc)
print("cycles per tick (incl. jsr): avg %.0f, median %d, max %d at t%d" % (
    avg, sorted(cyc)[len(cyc) // 2], worst, cyc.index(worst)))
print("NMI clock: %d ticks/s @125 BPM, %d @295 BPM; latch T80 = %d" % (rate125, rate295, latch_t80))
print("nudge @125 BPM: 0 %.3f, +8 %.3f, -8 %.3f, back to 0 %.3f ticks/s (latch %s)" % (
    tuple(nudge_rates) + (les,)))

# --- phase 2: live mode (events2 in tests/player_test.asm) ----------------
if len(args) > 1:
    NT2, F2 = 720, 26
    raw2 = open(args[1], "rb").read()
    assert raw2[:2] == b"\x00\x2f", "live dump must start at $2f00"
    res2, tr2 = raw2[2:0x102], raw2[0x102:0x102 + NT2 * F2]
    check(res2[7] == 2, "phase 2 did not finish")
    L = [tr2[t * F2:(t + 1) * F2] for t in range(NT2)]
    def lplay(t, c): return (L[t][0] >> c) & 1
    def lrow(t, c): return L[t][1 + c]
    def lcstep(t, c): return L[t][4 + c]
    def lpstep(t, c): return L[t][7 + c]
    def lq(t, c): return L[t][10 + c]
    def lgate(t, v): return L[t][13 + v] & 1
    def lnote(t, v):
        f = L[t][16 + 2 * v] | L[t][17 + 2 * v] << 8
        return FREQ.index(f) if f in FREQ else None
    def lpos(t, c, row, cs, ps, what):
        check((lrow(t, c), lcstep(t, c), lpstep(t, c)) == (row, cs, ps),
              "live t%d ch%d %s: row/cstep/pstep %02x %d %d, want %02x %d %d" % (
                  t, c, what, lrow(t, c), lcstep(t, c), lpstep(t, c), row, cs, ps))
    def lexpect(t, v, n, what):
        check(lnote(t, v) == n, "live t%d v%d %s: note %s, want %d" % (t, v, what, lnote(t, v), n))
    C4, D4, E4, F4, A4 = N("C", 4), N("D", 4), N("E", 4), N("F", 4), N("A", 4)
    check(all(L[t][23] == 1 for t in range(0, 520)), "pl_live = 1")
    # start: ch0 and ch1 play row $10 = chain 11 (P8 C-4, P9 D-4)
    for c in (0, 1):
        check(lplay(0, c), "live t0 ch%d plays" % c)
        lpos(0, c, 0x10, 0, 0, "start")
        lexpect(0, c, C4, "start")
    # queue mode 1 (ch1): chain 12 at the end of the phrase (t96)
    check(all(lq(t, 1) == 0x11 for t in range(20, 96)) and lq(96, 1) == 0xff, "ch1 queue entry until t96")
    lpos(95, 1, 0x10, 0, 15, "before phrase end")
    lpos(96, 1, 0x11, 0, 0, "mode 1 switch")
    lexpect(96, 1, F4, "queued chain 12")
    # queue mode 0 (ch0): the phrase ends at t96 but the chain goes on
    lpos(96, 0, 0x10, 1, 0, "mode 0 waits for chain end")
    lexpect(96, 0, D4, "chain 11 second phrase")
    check(all(lq(t, 0) == 0x11 for t in range(20, 192)) and lq(192, 0) == 0xff, "ch0 queue entry until t192")
    lpos(191, 0, 0x10, 1, 15, "before chain end")
    lpos(192, 0, 0x11, 0, 0, "mode 0 switch")
    lexpect(192, 0, F4, "queued chain 12")
    # live: a chain loops instead of advancing to the next row
    for t in (192, 288):
        lpos(t, 1, 0x11, 0, 0, "loop")
        lexpect(t, 1, F4, "loop")
    lpos(288, 0, 0x11, 0, 0, "loop")
    check(not any(lrow(t, 0) == 0x12 for t in range(0, 480)), "ch0 never reaches row $12 in live mode")
    check(not any(lrow(t, 1) == 0x12 for t in range(0, 576)), "ch1 stays on row $11 while live")
    # queue on a stopped channel: starts with ch0's next step (t54)
    check(not any(lplay(t, 2) for t in range(0, 54)), "ch2 waits for the step boundary")
    check(all(lq(t, 2) == 0x11 for t in range(50, 54)) and lq(54, 2) == 0xff, "ch2 pending queue entry")
    check(lplay(54, 2), "ch2 starts at t54 (ch0 steps at t54)")
    check(lpstep(54, 0) == 9 and lpstep(53, 0) == 8, "t54 is a ch0 step boundary")
    lpos(54, 2, 0x11, 0, 0, "aligned start")
    lexpect(66, 2, A4, "chain 14 step 2")
    # HR sees the queued chain's first note (queued at t100, switch t150)
    lpos(150, 2, 0x10, 0, 0, "queued HR chain")
    lexpect(150, 2, E4, "queued HR chain")
    check(lgate(147, 2) == 1, "A-4 still gated before HR")
    for t in (148, 149):
        check(lgate(t, 2) == 0 and L[t][22] == 0, "t%d HR before the queued note (gate %d AD %02x)" % (t, lgate(t, 2), L[t][22]))
    check(lgate(150, 2) == 1 and L[150][22] == 0x09, "queued note triggers")
    # back to chain 14 (step 0 empty) at t246: no HR, then HR for A-4 at t258
    lpos(246, 2, 0x11, 0, 0, "back to chain 14")
    check(lgate(244, 2) and lgate(245, 2) and lgate(246, 2), "no HR when the queued step has no note")
    check(not lgate(256, 2) and not lgate(257, 2) and lgate(258, 2), "HR for A-4 in chain 14")
    lexpect(258, 2, A4, "chain 14 A-4")
    # late queue (t341, after the HR point): on time, without HR
    check(lgate(340, 2) and lgate(341, 2) and L[341][22] == 0x09, "late queue: no HR")
    lpos(342, 2, 0x10, 0, 0, "late queue on time")
    lexpect(342, 2, E4, "late queue on time")
    check(lgate(342, 2) == 1, "late queue note gated")
    # ch0 back to chain 11 at its chain end (t384), queue_stop mode 1 (t480)
    lpos(384, 0, 0x10, 0, 0, "chain 11 again")
    lexpect(384, 0, C4, "chain 11 again")
    check(all(lq(t, 0) == 0xfe for t in range(400, 480)), "queued stop visible")
    check(all(lplay(t, 0) for t in range(384, 480)) and not lplay(480, 0), "queue_stop mode 1: stops at the phrase end t480")
    check(lgate(480, 0) == 0 and lq(480, 0) == 0xff, "stopped: gate off, queue clear")
    # stopped ch0 queued at t490: starts with ch1's step (t492); HFF stops it (t516)
    check(not lplay(490, 0) and not lplay(491, 0) and lplay(492, 0), "ch0 aligned to ch1 (t492)")
    check(lpstep(492, 1) % 1 == 0 and lpstep(492, 1) != lpstep(491, 1), "t492 is a ch1 step")
    lpos(492, 0, 0x13, 0, 0, "chain 15")
    lexpect(492, 0, C4, "chain 15")
    check(lplay(515, 0) and not lplay(516, 0), "HFF stops the channel in live mode (t516)")
    check(not any(lplay(t, 0) for t in range(516, 720)), "ch0 stays stopped (pending start cancelled)")
    # pl_live = 0 at t520: ch1 advances at its chain end (t576)
    check(L[520][23] == 0 and L[600][23] == 1, "pl_live toggles")
    lpos(575, 1, 0x11, 0, 15, "before song-mode advance")
    lpos(576, 1, 0x12, 0, 0, "song mode advances to the next row")
    lexpect(576, 1, C4, "row $12 chain 8")
    # pl_live = 1 at t600: chain 8 loops at t672 (song mode: back to row $10)
    lpos(672, 1, 0x12, 0, 0, "live again: loop")
    # chain edit at t668 (after lookahead, before prep) plays at once (t672)
    lexpect(672, 1, D4, "chain edit takes effect on the next step")
    # stop_all t700; queue with nothing playing starts at once (t702)
    check(L[700][0] == 0 and L[701][0] == 0, "stop all")
    check(lplay(702, 1) and lq(702, 1) == 0xff, "queue on silence starts immediately")
    lpos(702, 1, 0x10, 0, 0, "immediate start")
    lexpect(702, 1, C4, "immediate start")
    check(not any(lplay(t, 2) for t in range(703, 708)) and lplay(708, 2), "ch2 waits for ch1's step (t708)")
    check(all(lq(t, 2) == 0x11 for t in range(703, 708)), "ch2 pending")
    lpos(708, 2, 0x11, 0, 0, "aligned to ch1")
    check(lq(704, 0) == 0x10 and lq(705, 0) == 0xff, "queue_stop cancels a pending start")
    cyc2 = [calib - (f[24] | f[25] << 8) for f in L]
    print("live phase: cycles per tick avg %.0f, median %d, max %d at t%d" % (
        sum(cyc2) / len(cyc2), sorted(cyc2)[len(cyc2) // 2], max(cyc2), cyc2.index(max(cyc2))))

    # --- table exports (same dump, after the live trace) ------------------
    # Table t row r transposes 16*(t-1)+r+1 from C-1: the frequency tells
    # which row played; pl_tbl/pl_tblstep must name that row ($ff: none).
    NT3, F3 = 120, 14
    o3 = 0x100 + NT2 * F2
    T3 = [raw2[2 + o3 + t * F3:2 + o3 + (t + 1) * F3] for t in range(NT3)]
    def table_rows(hops, speed, n):        # reference: rows from a trigger
        rows, step, cnt, hc = [], 0, 0, {}
        for _ in range(n):
            if cnt:
                cnt -= 1
                rows.append(rows[-1])
                continue
            cnt = max((speed & 15) - 1, 0)
            r = step
            rows.append(r)
            step = (r + 1) & 15
            if r in hops:
                x, y = hops[r]
                if x == 0:
                    step = y
                else:
                    c = hc.get(r, 0) or x + 1
                    hc[r] = c - 1
                    if c - 1:
                        step = y
        return rows
    t1 = table_rows({5: (2, 3), 7: (0, 7)}, 0, 48)
    check(t1[:16] == [0, 1, 2, 3, 4, 5, 3, 4, 5, 3, 4, 5, 6, 7, 7, 7], "reference model %s" % t1[:16])
    t2s3 = table_rows({2: (1, 0), 9: (1, 11)}, 3, 96)
    t2s0 = table_rows({2: (1, 0), 9: (1, 11)}, 0, 24)
    check(t2s0[:13] == t2s0[:12] + [9] and t2s0[13] == 11, "reference model %s" % t2s0)
    want = {0: [(1, r) for r in t1] * 3,
            1: [(2, r) for r in t2s3] + [(2, r) for r in t2s3[:24]],
            2: ([None] * 12 + [(2, r) for r in t2s0] + [(2, r) for r in t2s0[:18]] + [None] * 6
                + [(1, r) for r in t1[:24]] + [None] * 12) * 2}
    C1 = N("C", 1)
    seen = 0
    for t in range(NT3):
        for c in range(3):
            f = T3[t]
            tbl, step = f[c], f[3 + c]
            fr = f[6 + 2 * c] | f[7 + 2 * c] << 8
            n = FREQ.index(fr) if fr in FREQ else None
            if n is None:
                check(False, "tables t%d ch%d: freq $%04x is no note" % (t, c, fr))
                continue
            tr = n - C1
            got = (tbl, step) if tbl != 0xff else None
            fromsid = ((tr - 1) // 16 + 1, (tr - 1) % 16) if tr else None
            check(got == fromsid, "tables t%d ch%d: pl_tbl/pl_tblstep %s, SID trace says %s" % (t, c, got, fromsid))
            check(fromsid == want[c][t], "tables t%d ch%d: row %s, want %s" % (t, c, fromsid, want[c][t]))
            seen += got is not None
    check(seen > 200, "table scenario: tables hardly ran")
    rt = res2[0xd0:0xd6]
    check(list(rt[3:]) == [0xff] * 3, "pl_tbl[3..5] = %s, want $ff" % list(rt[3:]))
    check(list(rt[:3]) == list(T3[-1][:3]), "pl_tbl at the end")
    # step mode (row $30, ch0, a note every tick): one row per note, H rows
    # lead on at once (row 6 H06 loops onto itself: guard), the same table
    # goes on across instruments and the phrase loop, a new one (instrument
    # with another table, or A) restarts at row 0.
    NT4, F4 = 20, 4
    o4 = o3 + NT3 * F3
    T4 = [raw2[2 + o4 + t * F4:2 + o4 + (t + 1) * F4] for t in range(NT4)]
    a3 = [0, 1, 2, 1, 2, 4, 5, 6, 6, 6, 6]          # advances of table 3
    want4 = [(3, r) for r in a3[:10]] + [(4, 0), (4, 1), (3, 0), (4, 0), (4, 1), (3, 0)] \
        + [(3, r) for r in a3[1:11]] + [(4, 0), (4, 1)]
    for t in range(NT4):
        f = T4[t]
        fr = f[2] | f[3] << 8
        n = FREQ.index(fr) if fr in FREQ else None
        sid = ((n - C1 - 1) // 16 + 1, (n - C1 - 1) % 16) if n is not None and n > C1 else None
        check((f[0], f[1]) == want4[t] and sid == want4[t],
              "step mode t%d: pl_tbl/step %s, SID says %s, want %s" % (t, (f[0], f[1]), sid, want4[t]))
    # Live FX overrides (fx_test): song row 0 (ch0 bass C-2, transpose on,
    # filter own LP res 8; ch1 lead G-4, transpose on; ch2 drum C-4, off)
    fx = res2[0xd6:0xd6 + 40]
    def fxnotes(o):
        return [FREQ.index(fx[o + 2 * v] | fx[o + 2 * v + 1] << 8)
                if (fx[o + 2 * v] | fx[o + 2 * v + 1] << 8) in FREQ else None for v in range(3)]
    check(fx[0] == 0, "player_init leaves pl_fxmask $%02x" % fx[0])
    base = fx[1:4]
    check(base[0] <= 0x30 and base[1] == 0x81 and base[2] == 0x1f, "FX base filter %s" % list(base))
    check(fxnotes(4) == [N("C", 2), N("G", 4), N("C", 4)], "FX base notes %s" % fxnotes(4))
    check(list(fx[10:13]) == [0xa5, 0xc1, 0xa7], "FX latched filter %s, want a5 c1 a7" % [hex(b) for b in fx[10:13]])
    check(fx[13] < base[0] and fx[14] == 0x81 and fx[15] == 0x17, "FX vol only %s" % [hex(b) for b in fx[13:16]])
    for o, d, what in ((16, 12, "+12"), (22, 5, "2+3")):
        want = [N("C", 2) + d, N("G", 4) + d, N("C", 4)]
        check(fxnotes(o) == want, "FX transpose %s: %s, want %s" % (what, fxnotes(o), want))
    check(fxnotes(28) == [95, 95, N("C", 4)], "FX transpose +127 clamps: %s" % fxnotes(28))
    check(fxnotes(34) == [0, N("G", 4) - 30, N("C", 4)], "FX transpose -30 clamps: %s" % fxnotes(34))
    cyc3 = [calib - (f[12] | f[13] << 8) for f in T3]
    print("table scenario: cycles per tick avg %.0f, median %d, max %d at t%d" % (
        sum(cyc3) / len(cyc3), sorted(cyc3)[len(cyc3) // 2], max(cyc3), cyc3.index(max(cyc3))))

# --- phase 3: 2SID (sid2_test): slots 3-5 = slots 0-2, SID2 at FAKE2 (RAM) ---
if len(args) > 2:
    NT5, F5, MUTE5 = 256, 80, 150
    raw3 = open(args[2], "rb").read()
    assert raw3[:2] == b"\x00\x2f", "2SID dump must start at $2f00"
    res3, tr3 = raw3[2:0x102], raw3[0x102:0x102 + NT5 * F5]
    check(res3[7] == 3, "2SID phase did not finish")
    check(res3[0xfe] == 3, "pl_nch after going back to mono = %d" % res3[0xfe])
    T5 = [tr3[t * F5:(t + 1) * F5] for t in range(NT5)]
    sh1 = lambda t: T5[t][0:25]
    sh2 = lambda t: T5[t][25:50]
    regs = lambda t: T5[t][50:75]
    check(all(f[76] == 6 for f in T5), "pl_nch not 6 with pl_sid2 set")
    check(all(f[75] == 0x3f for f in T5[:200]), "not all six channels playing: %s" % sorted(set(f[75] for f in T5[:200])))
    # every SID2 register write lands at pl_sid2 (shadow = what was written)
    bad = [t for t in range(NT5) if sh2(t) != regs(t)]
    check(not bad, "SID2 registers differ from pl_shadow2 at %d ticks, first t%d" % (len(bad), bad[0] if bad else 0))
    # SID1 unchanged by the second SID: the phase 1 frames up to its first event (t300)
    bad = [t for t in range(NT5) if sh1(t) != frames[t][:25]]
    check(not bad, "2SID: SID1 shadow differs from phase 1 at %d ticks, first t%d" % (len(bad), bad[0] if bad else 0))
    # channels 4-6 play what 1-3 play: SID2 = SID1, except voice 6 while muted
    for t in range(NT5):
        a, b = sh1(t), sh2(t)
        if MUTE5 <= t < MUTE5 + 50:
            same = [r for r in range(25) if r not in (18, 20)]
            check(all(a[r] == b[r] for r in same), "t%d: SID2 differs from SID1 beyond the muted voice" % t)
            check(b[14 + 4] & 1 == 0 and b[14 + 6] == 0, "t%d: muted channel 6 gate %d SR %02x" % (t, b[18] & 1, b[20]))
        else:
            check(a == b, "t%d: SID2 shadow differs from SID1: %s / %s" % (t, a.hex(), b.hex()))
    cyc5 = [calib - (f[77] | f[78] << 8) for f in T5]
    print("2SID (6 voices): cycles per tick avg %.0f, median %d, max %d at t%d" % (
        sum(cyc5) / len(cyc5), sorted(cyc5)[len(cyc5) // 2], max(cyc5), cyc5.index(max(cyc5))))

# --- phase 4: hold (hold_test): pl_hold 3 / 15 / $10 on ch0-2 ---------------
if len(args) > 3:
    NT6, F6, ON6, OFF6 = 240, 12, 30, 170
    raw4 = open(args[3], "rb").read()
    assert raw4[:2] == b"\x00\x2f", "hold dump must start at $2f00"
    res4, tr4 = raw4[2:0x102], raw4[0x102:0x102 + NT6 * F6]
    check(res4[7] == 4, "hold phase did not finish")
    T6 = [tr4[t * F6:(t + 1) * F6] for t in range(NT6)]
    # same as phase 1 before the hold
    for t in range(ON6):
        for c in range(3):
            check(T6[t][c] == pstep(t, c) and T6[t][3 + c] == cstep(t, c) and T6[t][6 + c] == row(t, c),
                  "hold t%d ch%d: position differs from phase 1 before the hold" % (t, c))
    masks = {0: 3, 1: 15, 2: 0x10}
    for c in range(3):
        m = masks[c] & 15
        moves = [t for t in range(1, NT6) if T6[t][c] != T6[t - 1][c] or T6[t][3 + c] != T6[t - 1][3 + c]]
        held = [t for t in moves if ON6 < t <= OFF6]
        # the step after the hold is set may already be resolved (lookahead), ch2 re-runs it (pl_lapend)
        late = 0 if c == 2 else 1
        for i, t in enumerate(held):
            s0, s1 = T6[t - 1][c], T6[t][c]
            if i < late:
                continue
            want = (s0 & ~m | (s0 + 1) & m) & 15
            check(s1 == want and T6[t][3 + c] == T6[t - 1][3 + c] and T6[t][6 + c] == T6[t - 1][6 + c],
                  "hold ch%d t%d: step %d -> %d (chain step %d -> %d), want %d" % (
                      c, t, s0, s1, T6[t - 1][3 + c], T6[t][3 + c], want))
        if m:
            check(len(held) >= 4, "hold ch%d: only %d steps while held" % (c, len(held)))
        else:                           # one step: the position stands still
            check(len(held) <= late + 1, "hold ch%d: moved while held at %s" % (c, held))
        after = [t for t in moves if t > OFF6 + 24]     # (0: a hop H back to step 0)
        for t in after:
            s0, s1 = T6[t - 1][c], T6[t][c]
            check(s1 in ((s0 + 1) & 15, 0) or T6[t][3 + c] != T6[t - 1][3 + c] or T6[t][6 + c] != T6[t - 1][6 + c],
                  "hold ch%d t%d after release: step %d -> %d" % (c, t, s0, s1))
        check(after, "hold ch%d: no steps after release" % c)
    # ch1 (whole phrase) wrapped at least once and stayed on its chain step
    w = [t for t in range(ON6 + 1, OFF6) if T6[t][1] < T6[t - 1][1]]
    check(w, "hold ch1: phrase never wrapped")
    # pl_wait counts down to 1, pl_steplen = the step's ticks
    for t in range(1, NT6):
        f = T6[t]
        check(1 <= f[9] <= f[10], "t%d pl_wait %d pl_steplen %d" % (t, f[9], f[10]))
        if f[0] != T6[t - 1][0]:
            check(f[9] == f[10], "t%d: new step, pl_wait %d != pl_steplen %d" % (t, f[9], f[10]))
    print("hold phase: ch0 steps %s" % [T6[t][0] for t in range(ON6, OFF6, 6)])

# --- golden --------------------------------------------------------------
state = b"".join(f[:STATE] for f in frames)
if update:
    os.makedirs(os.path.dirname(GOLDEN), exist_ok=True)
    open(GOLDEN, "wb").write(state)
    print("golden trace updated")
elif os.path.exists(GOLDEN):
    gold = open(GOLDEN, "rb").read()
    diff = [t for t in range(NTICKS) if gold[t * STATE:(t + 1) * STATE] != state[t * STATE:(t + 1) * STATE]]
    check(not diff, "differs from golden trace at %d ticks, first t%d" % (len(diff), diff[0] if diff else 0))
else:
    print("no golden trace yet (run with --update-golden)")

if fails:
    for m in fails[:40]:
        print("FAIL", m)
    print("%d failures" % len(fails))
    sys.exit(1)
print("player test: all checks passed")
