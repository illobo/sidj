; SIDJ player engine. Included by main.asm at PLAYER = $1000.
; Contract: defs.inc.
;
; Clock: CIA2 timer A underflow -> NMI, one tick per underflow (24 per beat);
; the latch is the tempo's, nudged by pl_nudge (apply_nudge).
; Tick: sequencer per channel (the step's note, instrument and transpose
; are resolved by prep a few ticks ahead), effects per voice, then one
; unrolled pass fills pl_shadow (25 bytes) and the SID in a safe order.
; 2SID: pl_nch channels run (3, or 6 with pl_sid2 set by the editor
; before init); voices 4-6 go to pl_shadow2 and the second SID (sid2_out),
; each SID has its own filter (filt_one).
; pl_tbl/pl_tblstep (PLAYER_EXT) show each channel's table and its row. Live mode: pl_live makes a
; chain loop; player_queue/queue_stop switch or stop at a chain or phrase
; end (next_pos resolves the queue, so HR look-ahead sees it). Everything is deterministic: the
; only randomness (B, Z) comes from an LFSR seeded by player_init.
;
; Reentrancy: API calls and the NMI share one lock. An NMI that finds the
; lock taken only counts a pending tick; whoever releases the lock runs the
; pending ticks. So the tick never runs twice at once and the player zero
; page ($02-$3f) and variables are only ever touched by one context.

pl      .block                  ; internals stay private (editor shares names)

CLK_PAL   = 2463120             ; CPU clock * 60 / 24: latch = CLK / BPM
CLK_NTSC  = 2556818
HZ_PAL    = 985248.0
HZ_NTSC   = 1022727.0

CMD_B = 2
CMD_D = 4
CMD_G = 7
CMD_H = 8
CMD_L = 12
CMD_Q = 17
CMD_Z = 26

; zero page (player context only, see lock above)
zp_ptr    = ZP_PLAYER+0         ; 2  phrase / chain step
zp_ptr2   = ZP_PLAYER+2         ; 2  song page / table column
zp_ins    = ZP_PLAYER+4         ; 2  instrument
zp_ch     = ZP_PLAYER+6         ; channel = voice being processed
zp_note   = ZP_PLAYER+7
zp_instr  = ZP_PLAYER+8
zp_cmd    = ZP_PLAYER+9
zp_val    = ZP_PLAYER+10
zp_xv     = ZP_PLAYER+11        ; command value inside exec_cmd
zp_t0     = ZP_PLAYER+12
zp_t1     = ZP_PLAYER+13
zp_t2     = ZP_PLAYER+14
zp_t3     = ZP_PLAYER+15
zp_arp    = ZP_PLAYER+16
zp_plo    = ZP_PLAYER+17        ; pitch 8.8: semitone . 1/256
zp_phi    = ZP_PLAYER+18
zp_vlo    = ZP_PLAYER+19        ; vibrato offset, signed 1/256 semitone
zp_vhi    = ZP_PLAYER+20
zp_flo    = ZP_PLAYER+21        ; SID frequency
zp_fhi    = ZP_PLAYER+22
zp_d0     = ZP_PLAYER+23
zp_d1     = ZP_PLAYER+24
zp_r1     = ZP_PLAYER+25
zp_m0     = ZP_PLAYER+27
zp_m1     = ZP_PLAYER+28
zp_q0     = zp_vlo              ; set_tempo never runs inside pitch
zp_q1     = zp_vhi
zp_rem0   = zp_fhi
zp_rem1   = zp_m0
zp_tc1    = zp_arp              ; table row commands (before pitch, and
zp_tv1    = zp_plo              ; set_tempo from T leaves these alone)
zp_tc2    = zp_phi
zp_tv2    = zp_m1
zp_fresh  = ZP_PLAYER+29        ; lookahead ran for this channel this tick
zp_mlo    = ZP_PLAYER+26        ; low byte of a table multiply
; hottest arrays [NV] in zero page: smaller and faster code
NV        = NCHAN2              ; voice/channel array size: 6 (2SID); pl_nch of them run
v_gate    = ZP_PLAYER+30
v_bendlo  = v_gate+NV
v_bendhi  = v_bendlo+NV
v_pwlo    = v_bendhi+NV
v_pwhi    = v_pwlo+NV
zp_mute   = v_pwhi+NV           ; sid_out: pl_mute, shifted per voice
        .cerror zp_mute > ZP_PLAYER_END, "player zero page overflow"

; A * B (bytes, zero page or absolute) -> A = high byte, zp_mlo = low byte; X, Y
; clobbered. Quarter squares: a*b = sq(a+b) - sq(|a-b|), sq(n) = n*n/4.
MUL8    .macro a, b
        lda \a
        sec
        sbc \b
        bcs +
        eor #$ff
        adc #1
+       tay                     ; |a - b|
        lda \a
        clc
        adc \b
        tax                     ; a + b, bit 8 in C
        bcc _l
        jsr mul8h               ; a + b > 255
        jmp _d
_l      lda sq_lo,x
        sec
        sbc sq_lo,y
        sta zp_mlo
        lda sq_hi,x
        sbc sq_hi,y
_d
        .endm

; ---------------------------------------------------------------------------
; Jump table and state block (fixed offsets, defs.inc). Everything else is
; inside block pl; tests reach internals as pl.tick etc.
; ---------------------------------------------------------------------------
        jmp init
        jmp play_song
        jmp stop_all
        jmp play_channel
        jmp stop_channel
        jmp set_tempo_api
        jmp note_on
        jmp note_off
        jmp queue
        jmp queue_stop
        .fill pl_playing - *, 0
        .fill PLAYER_CODE - *, 0        ; state block, set up by init
        .cerror * != PLAYER_CODE, "jump table / state block misplaced"
        .cerror pl_hold < pl_shadow2+25 || pl_hold+6 > PLAYER_CODE, "pl_hold outside the free state block"

; ---------------------------------------------------------------------------
; API (main context, $01 = BANK_RAMIO). inc lock keeps A/X/Y intact.
; ---------------------------------------------------------------------------

; A = song row: every channel starts from that row (empty slot: channel stops)
play_song
        inc lock
        sta zp_t2
        ldx pl_nch
        dex
-       lda zp_t2
        jsr start_ch
        dex
        bpl -
        jmp leave

; X = channel, A = row
play_channel
        inc lock
play_ch_locked
        jsr start_ch
        jmp leave

stop_all
        inc lock
        ldx #NV-1
-       jsr stop_ch
        dex
        bpl -
        bne leave

; X = channel
stop_channel
        inc lock
stop_ch_locked
        jsr stop_ch
        jmp leave

; A = tempo byte
set_tempo_api
        inc lock
        jsr set_tempo
        jmp leave

; X = channel, A = note, Y = instrument: preview, no transpose
note_on
        inc lock
        cmp #96
        bcc +
        lda #95
+       sta zp_note
        sty zp_instr
        stx zp_ch
        jsr trigger
        jmp leave

; X = channel
note_off
        inc lock
        lda #0
        sta v_gate,x
        sta v_del,x
        beq leave

; Live queue. X = channel, A = song row ($00-$fd), Y = 0 switch at
; the end of the playing chain, 1 at the end of the current phrase. The
; switch is resolved by next_pos, so lookahead (HR) sees the queued chain's
; first note; a request after the HR point still plays on time, without HR.
; A channel that is not playing starts on the next step boundary of the
; lowest-numbered playing channel, or on the next tick if none plays.
; queue_stop (X, Y): stop at that boundary; on a stopped channel it cancels.
queue_stop
        lda #$fe
queue
        inc lock
        sta pl_queue,x
        tya
        and #1
        sta pl_qmode,x
        lda pl_playing
        and bit_tab,x
        beq _idle
        lda #1                  ; re-run lookahead: HR for the queued note
        sta ch_lapend,x
        bne leave
_idle   lda pl_queue,x
        cmp #$fe
        beq stop_ch_locked
        ldy #0
-       lda pl_playing
        and bit_tab,y
        bne _sync
        iny
        cpy pl_nch
        bne -
        lda pl_queue,x          ; nothing plays: start now
        bcs play_ch_locked      ; C = 1 (Y = pl_nch)
_sync   lda ch_wait,y           ; ticks to that channel's next step
        sta ch_pend,x           ; falls into leave

; Release the lock, running ticks that NMIs deferred meanwhile.
leave
-       lda pending
        beq +
        dec pending
        jsr tick
        jmp -
+       lda #0                  ; an NMI after this store runs its own tick
        sta lock
        lda pending             ; one that hit before the store waits here
        beq +
        inc lock
        bne -
+       rts

; ---------------------------------------------------------------------------
; NMI: CIA2 timer A. RESTORE also lands here; its ICR has bit 0 clear.
; ---------------------------------------------------------------------------
nmi     pha
        txa
        pha
        tya
        pha
        lda $01
        pha
        lda #BANK_RAMIO
        sta $01
        cld
        lda CIA2+$0d            ; read = ack, re-arms the NMI edge
        lsr
        bcc _out
        lda lock
        beq _run
        inc pending             ; main (or an outer NMI) owns the player
        bcs _out
_run    inc lock
        jsr tick
        jsr leave
_out    pla
        sta $01
        pla
        tay
        pla
        tax
        pla
        rti

; ---------------------------------------------------------------------------
; init: SID reset, PAL/NTSC, CIA2 timer A -> NMI, tempo from HD_TEMPO
; ---------------------------------------------------------------------------
init    lda #$7f                ; clock off while the state is rebuilt
        sta CIA2+$0d
        lda #0
        sta CIA2+$0e
        ldx #ZP_PLAYER_END-ZP_PLAYER
-       sta ZP_PLAYER,x
        dex
        bpl -
        lda CIA2+$0d
        lda #0                  ; all of PLAYER_EXT (tables rebuilt below)
        tax
-       sta PLAYER_EXT,x
        sta PLAYER_EXT+$100,x
        inx
        bne -
        ldx #img_vars_end-img_vars-1
-       sta img_vars,x
        dex
        bpl -
        ldx #pl_sid2-pl_playing-1
-       sta pl_playing,x
        dex
        bpl -
        ldx #PLAYER_CODE-pl_shadow2-1
-       sta pl_shadow2,x
        dex
        bpl -
        ldx #$18
-       sta SID,x
        dex
        bpl -
        jsr sid2_init
        lda #$ff
        ldx #5
-       sta pl_queue,x
        sta pl_tbl,x            ; = v_tbl: no table on any channel
        dex
        bpl -
        ldx #NV-1
-       sta v_kill,x
        sta ch_broll,x
        dex
        bpl -
        lda #$0f
        sta f_vol
        sta f_vol+1
        lda #$e1                ; fixed seed: traces stay reproducible
        sta rng
        lda #$ac
        sta rng+1
        jsr detect
        lda #<nmi
        sta $fffa
        lda #>nmi
        sta $fffb
        lda HD_TEMPO
        jsr set_tempo
        lda #$11                ; timer A: force load, continuous, start
        sta CIA2+$0e
        lda #$81                ; timer A underflow -> NMI
        sta CIA2+$0d
        rts

; PAL has 312 raster lines (last $137), NTSC 263/262 (last $106/$105):
; the highest $d012 seen while bit 8 is set tells them apart.
detect
-       bit VIC+$11
        bmi -
-       bit VIC+$11
        bpl -
        lda #0
        sta zp_t0
-       lda VIC+$12
        cmp zp_t0
        bcc +
        sta zp_t0
+       bit VIC+$11
        bmi -
        ldx #0
        lda zp_t0
        cmp #$20
        bcs +
        inx
+       stx ntsc
        stx pl_ntsc
        lda clk_lo,x
        sta clk
        lda clk_mid,x
        sta clk+1
        lda clk_hi,x
        sta clk+2
        lda oct_ofs,x
        tax
        ; fall through

; f96: every note for this clock from octave 6 (X = offset into oct6_*)
gen_freq
        stx zp_t2
        ldx #0
        lda #6
        sta zp_t1               ; right shifts for this octave, -1 = octave 7
_goct   ldy zp_t2
        lda #12
        sta zp_t3
_gsem   lda oct6_lo,y
        sta zp_flo
        lda oct6_hi,y
        sta zp_fhi
        lda zp_t1
        bmi _gup
        beq _gst
        sta zp_t0
-       lsr zp_fhi
        ror zp_flo
        dec zp_t0
        bne -
        beq _gst
_gup    asl zp_flo
        rol zp_fhi
        bcc _gst
        lda #$ff
        sta zp_flo
        sta zp_fhi
_gst    lda zp_flo
        sta f96_lo,x
        lda zp_fhi
        sta f96_hi,x
        inx
        iny
        dec zp_t3
        bne _gsem
        dec zp_t1
        cpx #96
        bne _goct
        lda #$ff                ; above B-7: interpolation target only
        sta f96_lo+96
        sta f96_hi+96
        rts

; A = tempo byte ($28-$ff = 40-255 BPM, $00-$27 = 256-295 BPM).
; latch = round(CLK / BPM), 24/9-bit division (16 quotient bits); preserves
; nothing.
set_tempo
        sta pl_tempo
        sta zp_d0
        ldx #0
        cmp #$28
        bcs +
        inx
+       stx zp_d1
        txa                     ; dividend = CLK + BPM/2 to round
        lsr
        lda zp_d0
        ror
        clc
        adc clk
        sta zp_q0
        lda clk+1
        adc #0
        sta zp_q1
        lda clk+2               ; < 40 <= BPM: the quotient fits 16 bits,
        adc #0                  ; so the top byte starts as remainder
        sta zp_rem0
        lda #0
        sta zp_rem1
        ldx #16
-       asl zp_q0
        rol zp_q1
        rol zp_rem0
        rol zp_rem1
        lda zp_rem0
        sec
        sbc zp_d0
        tay
        lda zp_rem1
        sbc zp_d1
        bcc +
        sta zp_rem1
        sty zp_rem0
        inc zp_q0
+       dex
        bne -
        lda zp_q0
        sta latch
        lda zp_q1
        sta latch+1
        ; fall through: the nudge applies to the new latch

; Timer latch = latch - round(latch * pl_nudge / 256), pl_nudge signed
; (+ faster, - slower; clamped to $ffff), exactly latch when 0. A running
; timer picks the latch up at its next underflow: the timer is never
; reloaded early, so ticks keep their phase (no drift, no glitch). Runs
; when pl_nudge changed (checked every tick, ~200 cycles then) and after
; set_tempo. Uses zp_d0/d1, zp_m0, zp_mlo only (safe inside commands).
apply_nudge
        lda pl_nudge
        sta nudge_now
        bne +
        lda latch
        ldx latch+1
        jmp _set
+       bpl +
        eor #$ff                ; |nudge|, 1..128
        clc
        adc #1
+       sta zp_m0
        lda latch               ; adj = round(latch * |nudge| / 256)
        jsr nmul
        ldy zp_mlo              ;     = lo*n rounded / 256 + hi*n
        bpl +
        clc
        adc #1
+       sta zp_d0
        lda latch+1
        jsr nmul
        tay
        lda zp_mlo
        clc
        adc zp_d0
        sta zp_d0
        tya
        adc #0
        sta zp_d1
+       bit pl_nudge
        bmi _slow
        lda latch               ; faster: latch - adj
        sec
        sbc zp_d0
        tay
        lda latch+1
        sbc zp_d1
        tax
        tya
        jmp _set
_slow   lda latch               ; slower: latch + adj
        clc
        adc zp_d0
        tay
        lda latch+1
        adc zp_d1
        tax
        tya
        bcc _set
        lda #$ff
        tax
_set    sta latch_eff
        sta CIA2+4
        stx latch_eff+1
        stx CIA2+5
        rts

; A * zp_m0 (MUL8 result); zp_m1 is free while the nudge is applied.
; mul8: zp_m1 * zp_m0 (vibrato, pitch interpolation)
nmul    sta zp_m1
mul8    #MUL8 zp_m1, zp_m0
        rts

; MUL8 for a + b > 255 (X = a + b - 256, Y = |a - b|), with the 256-entry
; tables: sq(256 + m) = sq(m) + 128 m + 16384
mul8h   txa
        lsr                     ; C = m & 1
        lda #0
        ror                     ; (m & 1) << 7, C clear
        adc sq_lo,x
        sta zp_mlo
        php
        txa
        lsr
        plp
        adc #$40
        adc sq_hi,x             ; no carry: at most 255
        pha
        lda zp_mlo
        sec
        sbc sq_lo,y
        sta zp_mlo
        pla
        sbc sq_hi,y
        rts

; ---------------------------------------------------------------------------
; Tick
; ---------------------------------------------------------------------------
tick    inc pl_tick
        lda pl_fxmask           ; transpose for this tick: project + Live FX
        and #FX_TRANSP
        beq _htr
        lda pl_fxtransp
        clc
        adc HD_TRANSP
        bvc _tr
        lda #$7f                ; overflow: C clear = too high, set = too low
        adc #0
        bne _tr
_htr    lda HD_TRANSP
_tr     sta g_transp
        lda pl_nudge
        cmp nudge_now
        beq +
        jsr apply_nudge
+       ldx pl_nch
        dex
_seq    lda pl_playing
        and bit_tab,x
        bne _run
        lda ch_pend,x           ; queued start on a stopped channel
        beq _next
        dec ch_pend,x
        bne _next
        stx zp_ch
        lda pl_queue,x
        jsr start_ch            ; empty slot: stays stopped
        ldx zp_ch
        lda pl_playing
        and bit_tab,x
        beq _next
_run    stx zp_ch
        jsr seq_channel
        ldx zp_ch
_next   dex
        bpl _seq
        ldx pl_nch
-       dex
        stx zp_ch
        jsr voice_tick
        ldx zp_ch
        bne -
        jsr sid_out
        jmp filter_tick

; ---------------------------------------------------------------------------
; Sequencer (X = channel)
; ---------------------------------------------------------------------------
; Load spreading: lookahead runs the tick after a step (HR is never sooner),
; prep 1 + channel ticks before the next one (staggered so aligned channels
; do not prep on the same tick; at most on the lookahead tick), so the step
; tick itself mostly triggers. Steps of 1 tick do all of it in one tick.
seq_channel
        lda ch_lapend,x
        sta zp_fresh
        beq +
        jsr lookahead
+       dec ch_wait,x
        beq step_advance
        lda ch_wait,x
        cmp ch_hrat,x           ; hrat 0 never matches: wait > 0 here
        bne +
        jsr hard_restart
        lda ch_wait,x
+       cmp ch_pat,x
        beq prep
        rts

; Gate off (and ADSR reset / test bit) ch_hrat ticks before the next note,
; using the next note's instrument (resolved by lookahead).
hard_restart
        lda #0
        sta v_gate,x
        lda ch_hrmode,x
        beq +
        lda #0
        sta v_ad,x
        lda ch_hrsr,x
        sta v_sr,x
        lda ch_hrmode,x
        cmp #2
        bcc +
        lda #$08
        sta v_test,x
+       rts

; Prepare the next step (X = channel): re-resolve the position if it leaves
; the phrase, so song/chain/queue edits since lookahead count (HR only if
; they came before it), read the phrase row and the step length into st_*.
prep
        lda #1
        sta ch_prep,x
        lda zp_fresh            ; lookahead resolved it this very tick
        bne _read
        lda nx_ok,x
        cmp #2                  ; start_ch: exactly that step
        beq _read
        lda nx_newph,x          ; within a phrase nothing can change
        beq _read
        lda nx_phrase,x
        sta zp_t0
        lda nx_pstep,x
        sta zp_t1
        jsr next_pos
        lda nx_pstep,x
        cmp zp_t1
        bne _moved
        lda nx_phrase,x
        cmp zp_t0
        beq _read
_moved  lda #$ff                ; lookahead's dice were for another step
        sta ch_broll,x
_read   lda nx_ok,x
        beq _r                  ; the step stops the channel
        lda nx_phrase,x
        ldy nx_pstep,x
        jsr phrase_addr
        ldy #PH_NOTE
        lda (zp_ptr),y
        sta st_note,x
        iny
        lda (zp_ptr),y
        sta st_instr,x
        iny
        lda (zp_ptr),y
        sta zp_cmd
        iny
        lda (zp_ptr),y
        sta zp_val
        lda zp_cmd              ; Z repeats the last other command with
        cmp #CMD_Z              ; a random offset
        bne +
        jsr randomize
        jmp _cmd
+       cmp #CMD_H
        beq _cmd
        cmp #0
        beq _cmd
        sta ch_lastcmd,x
        lda zp_val
        sta ch_lastval,x
_cmd    lda zp_cmd
        sta st_cmd,x
        lda zp_val
        sta st_val,x
        lda ch_gstep,x          ; step length; G counts for this very step
        sta zp_t1
        lda ch_groove,x
        ldy zp_cmd
        cpy #CMD_G
        bne +
        ldy #0
        sty zp_t1
        lda zp_val
        and #NGROOVES-1
+       sta st_groove,x
        jsr groove_calc
        sta st_len,x
        lda zp_t1
        sta st_gstep,x
        lda st_note,x           ; resolve the note now: step_advance only
        cmp #96                 ; checks that the inputs still hold
        bcs _r
        sta zp_note
        lda st_instr,x
        cmp #NINSTR
        bcc +
        lda v_instr,x
+       sta st_ieff,x
        jsr instr_addr
        lda zp_ins
        sta st_ilo,x
        lda zp_ins+1
        sta st_ihi,x
        lda g_transp
        sta st_htr,x
        lda nx_transp,x         ; = ch_transp at the step
        jsr transpose_note
        lda zp_note
        sta st_fnote,x
_r      rts

step_advance
        lda ch_prep,x
        bne +
        jsr prep
+       lda #0
        sta ch_prep,x
        lda nx_ok,x
        bne +
        jmp stop_ch             ; nothing playable left / queued stop
+       lda nx_q,x
        beq +
        lda #$ff                ; queue entry consumed
        sta pl_queue,x
+       lda nx_pstep,x
        sta pl_phrase_step,x
        lda #0
        sta ch_hopmode,x
        ldy nx_newph,x          ; the rest only changes with the phrase
        beq +
        sta ch_hopcnt,x         ; hop counters live per phrase visit
        lda nx_row,x
        sta pl_row,x
        lda nx_cstep,x
        sta pl_chain_step,x
        lda nx_chain,x
        sta pl_chain,x
        lda nx_phrase,x
        sta pl_phrase,x
        lda nx_transp,x
        sta ch_transp,x
+       lda st_note,x
        sta zp_note
        lda st_instr,x
        sta zp_instr
        lda st_cmd,x
        sta zp_cmd
        lda st_val,x
        sta zp_val
        lda st_groove,x
        sta ch_groove,x
        lda st_gstep,x
        sta ch_gstep,x
        lda st_len,x
        sta ch_wait,x
        sta ch_steplen,x
        sec                     ; prep at min(1 + channel, len - 1)
        sbc #1
        cmp pat_tab,x
        bcc +
        lda pat_tab,x
+       sta ch_pat,x
        lda zp_cmd
        beq _play               ; no command: the short way
        cmp #CMD_H
        bne _groove
        lda zp_val
        cmp #$ff
        bne +
        jmp stop_ch             ; HFF: channel stops on this step
+       jsr phrase_hop
_groove ; B: the dice may already have been rolled by lookahead
        lda zp_cmd
        cmp #CMD_B
        bne _play
        lda ch_broll,x
        bpl +
        lda zp_val
        jsr roll_maybe
+       cmp #0
        bne _play
        lda #$ff
        sta zp_note
_play   lda #$ff
        sta ch_broll,x
        lda zp_note
        cmp #96
        bcs _nonote
        lda zp_instr            ; prep resolved it: same inputs?
        cmp #NINSTR
        bcc +                   ; own instrument: fixed pointer
        lda v_instr,x
        cmp st_ieff,x
        bne _slow
+       lda g_transp
        cmp st_htr,x
        bne _slow
        lda st_fnote,x
        sta zp_note
        lda st_ilo,x
        sta zp_ins
        lda st_ihi,x
        sta zp_ins+1
        bne _resd
_slow   jsr resolve_note
_resd   lda zp_cmd
        beq _trig
        cmp #CMD_D
        bne _nodel
        lda zp_val
        beq _nodel
        clc                     ; +1: voice_tick counts down this same tick
        adc #1
        bne +
        lda #$ff
+       sta v_del,x
        lda zp_note
        sta v_delnote,x
        lda zp_instr
        sta v_delins,x
        jmp _defer
_nodel  lda zp_cmd
        cmp #CMD_L
        bne _trig
        lda v_gate,x
        beq _trig               ; nothing sounding: plain note
        jsr slide_to
        jmp _defer
_trig   jsr trigger_ins
        jmp _exec
_nonote lda zp_instr            ; instrument alone selects it for later notes
        cmp #NINSTR
        bcs _exec
        sta v_instr,x
_exec   lda zp_cmd
        beq _defer
        ldy zp_val
        jsr exec_cmd
        ldx zp_ch
_defer  lda #1
        sta ch_lapend,x
        lda #0
        sta ch_hrat,x
        rts

; Resolve the step after this one (nx_*) and, if it holds a note, when to
; hard-restart for it (ch_hrat ticks before the step, < step length).
lookahead
        lda #0
        sta ch_lapend,x
        sta ch_prep,x           ; a re-run (queue) invalidates prep
        sta ch_hrat,x           ; a re-run (queue) may find no note
        jsr next_pos
        lda nx_ok,x
        beq _no
        lda nx_phrase,x
        ldy nx_pstep,x
        jsr phrase_addr
        ldy #PH_NOTE
        lda (zp_ptr),y
        cmp #96
        bcs _no
        ldy #PH_CMD
        lda (zp_ptr),y
        cmp #CMD_L              ; legato slide keeps the gate
        beq _no
        sta zp_t1
        iny
        lda (zp_ptr),y
        sta zp_t2
        lda zp_t1
        cmp #CMD_B
        bne +
        lda zp_t2
        jsr roll_maybe
        sta ch_broll,x
        beq _no
+       ldy #PH_INSTR
        lda (zp_ptr),y
        cmp #NINSTR
        bcc +
        lda v_instr,x
+       jsr instr_addr
        ldy #IN_HRSR
        lda (zp_ins),y
        sta ch_hrsr,x
        dey                     ; IN_HR = IN_HRSR - 1
        .cerror IN_HR != IN_HRSR - 1, "IN_HR/IN_HRSR layout"
        lda (zp_ins),y
        pha
        and #$0f
        sta ch_hrmode,x
        pla
        lsr
        lsr
        lsr
        lsr
        ldy zp_t1
        cpy #CMD_Q              ; Q overrides the HR ticks for this note
        bne +
        lda zp_t2
        and #$0f
+       cmp ch_steplen,x        ; short steps shorten HR
        bcc +
        lda ch_steplen,x
        sbc #1                  ; C = 1
+       sta ch_hrat,x
_no     rts

; Position of the step after the current one -> nx_*, nx_ok = 0 if none.
next_pos
        lda #0
        sta nx_newph,x
        sta nx_q,x
        lda #1
        sta nx_ok,x
        lda pl_row,x
        sta nx_row,x
        lda pl_chain_step,x
        sta nx_cstep,x
        lda pl_chain,x
        sta nx_chain,x
        lda pl_phrase,x
        sta nx_phrase,x
        lda ch_transp,x
        sta nx_transp,x
        ldy pl_hold,x           ; hold (beat repeat / loop record): hops
        bne _inc                ; are ignored, Y = pl_hold at _inc
        ldy ch_hopmode,x
        beq _inc
        lda ch_hopstep,x
        sta nx_pstep,x
        dey
        beq _done               ; 1: back within the phrase
        bne _nextc              ; 2: next phrase at hopstep
_inc    lda pl_phrase_step,x    ; Y = pl_hold: nx = (s & ~m) | ((s + 1) & m),
        clc                     ; m = its bits 0-3 (bit 4 alone = 1 step)
        adc #1
        cpy #0
        beq +
        eor pl_phrase_step,x
        and pl_hold,x
        eor pl_phrase_step,x
+       and #15
        sta nx_pstep,x
        bne _done
        tya                     ; held: step 0 stays in the phrase
        bne _done
_nextc  inc nx_newph,x
        lda pl_queue,x          ; phrase end: queue mode 1 switches here
        cmp #$ff
        beq +
        ldy pl_qmode,x
        bne _queued
+       lda nx_cstep,x
        clc
        adc #1
        sta nx_cstep,x
        cmp #16
        bcs _nextrow
        tay
        lda nx_chain,x
        jsr chain_addr
        ldy #0
        lda (zp_ptr),y
        cmp #$ff
        beq _nextrow
        sta nx_phrase,x
        iny
        lda (zp_ptr),y
        sta nx_transp,x
_done   rts
_nextrow
        lda pl_queue,x          ; chain end: any queue entry switches
        cmp #$ff
        bne _queued
        lda pl_live
        beq _song
        lda nx_chain,x          ; live: loop the playing chain
        jsr chain_c0
        bcs _fail
        rts
_queued cmp #$fe                ; A = queued row or $fe (stop)
        beq _fail
        pha
        lda #1
        sta nx_q,x
        lda #0
        sta nx_pstep,x
        pla
        jsr row_c0
        bcs _fail
        rts
_song   txa
        clc
        adc #>SONG
        sta zp_ptr2+1
        lda #0
        sta zp_ptr2
        lda #16                 ; give up after 16 rows of empty chains
        sta zp_t3
        ldy nx_row,x
_row    iny
        lda (zp_ptr2),y
        cmp #$80
        bcc _have
        dey                     ; empty slot: back to the first row of the
_back   cpy #0                  ; block that holds the row just left
        beq _top
        dey
        lda (zp_ptr2),y
        cmp #$80
        bcc _back
        iny
_top    lda (zp_ptr2),y
        cmp #$80
        bcs _fail
_have   pha
        tya
        sta nx_row,x
        pla
        jsr chain_c0
        bcs _empty
        rts
_empty  dec zp_t3
        beq _fail
        ldy nx_row,x
        jmp _row
_fail   lda #0
        sta nx_ok,x
        rts

; X = channel, A = song row -> nx_row/chain/phrase/transp at chain step 0.
; C set: empty slot or empty chain. Y, zp_ptr, zp_ptr2 clobbered.
row_c0  sta nx_row,x
        tay
        txa
        clc
        adc #>SONG
        sta zp_ptr2+1
        lda #0
        sta zp_ptr2
        lda (zp_ptr2),y
        cmp #$80
        bcs c0_ret
; A = chain: as above from the chain
chain_c0
        sta nx_chain,x
        ldy #0
        pha
        tya
        sta nx_cstep,x
        pla
        jsr chain_addr
        lda (zp_ptr),y
        cmp #$ff                ; C = empty
        beq c0_ret
        sta nx_phrase,x
        iny
        lda (zp_ptr),y
        sta nx_transp,x
c0_ret  rts

; X = channel, A = row: next tick plays step 0 of that row's chain.
start_ch
        jsr row_c0
        bcc +
        bcs stop_ch
+       lda #0
        sta nx_pstep,x
        sta ch_groove,x
        sta ch_gstep,x
        sta ch_hopmode,x
        sta ch_hopcnt,x
        sta ch_hrat,x
        sta ch_lapend,x
        sta ch_pend,x
        sta ch_prep,x
        sta nx_q,x
        sta pl_chain_step,x
        sta pl_phrase_step,x
        lda #1
        sta ch_wait,x
        sta nx_newph,x
        lda #2                  ; step_advance takes nx as is
        sta nx_ok,x
        lda #$ff
        sta ch_broll,x
        sta pl_queue,x
        lda nx_row,x
        sta pl_row,x
        lda nx_chain,x
        sta pl_chain,x
        lda nx_phrase,x
        sta pl_phrase,x
        lda bit_tab,x
        ora pl_playing
        sta pl_playing
        jmp prep                ; outside the tick when called by the API

; X = channel: stop sequencing, gate off (release plays)
stop_ch lda bit_tab,x
        eor #$ff
        and pl_playing
        sta pl_playing
        lda #0
        sta v_gate,x
        sta v_del,x
        sta ch_hrat,x
        sta ch_pend,x
        lda #$ff
        sta v_kill,x
        sta pl_queue,x
        rts

; H in a phrase: H0y next phrase at step y, Hxy (x>0) back to y x times
phrase_hop
        lda zp_val
        cmp #$10
        bcs _back
        sta ch_hopstep,x
        lda #2
        sta ch_hopmode,x
        rts
_back   lda ch_hopcnt,x
        bne +
        lda zp_val              ; arm: x hops, the x+1th visit falls through
        lsr
        lsr
        lsr
        lsr
        clc
        adc #1
+       sec
        sbc #1
        sta ch_hopcnt,x
        beq +
        lda zp_val
        and #$0f
        sta ch_hopstep,x
        lda #1
        sta ch_hopmode,x
+       rts

; Step length: A = groove, zp_t1 = groove step -> A = ticks, zp_t1 = next
; groove step. 0 = end of groove: loop to step 0; empty groove: 6 ticks.
groove_calc
        asl
        asl
        asl
        asl
        sta zp_ptr2
        lda #>GROOVES
        adc #0                  ; C = groove bit 4
        sta zp_ptr2+1
        ldy zp_t1
        lda (zp_ptr2),y
        bne +
        tay
        lda (zp_ptr2),y
        bne +
        lda #6                  ; empty groove: default
+       iny
        pha
        tya
        and #15
        sta zp_t1
        pla
        rts

; zp_note += chain + project transpose if the instrument wants it; clamp.
resolve_note
        lda zp_instr
        cmp #NINSTR
        bcc +
        lda v_instr,x
+       jsr instr_addr
        lda ch_transp,x
; same, zp_ins set, A = chain transpose
transpose_note
        sta zp_t0
        ldy #IN_FLAGS
        lda (zp_ins),y
        lsr
        bcc _r
        lda zp_t0
        clc
        adc g_transp
        clc
        adc zp_note
        bvs _hi                 ; note >= 0, so overflow means too high
        bmi _lo
        cmp #96
        bcc +
_hi     lda #95
        bne +
_lo     lda #0
+       sta zp_note
_r      rts

; L with a sounding note: glide from the current pitch to zp_note over
; zp_val ticks without retrigger. The glide is a bend that decays to 0.
slide_to
        lda v_note,x
        sec
        sbc zp_note
        clc
        adc v_bendhi,x
        sta v_bendhi,x
        lda zp_note
        sta v_note,x
        lda #0
        sta v_bendspd,x
        sta v_slide,x
        lda zp_val
        bne +
        sta v_bendlo,x
        sta v_bendhi,x
        rts
+       sta zp_t2
        lda v_bendlo,x
        sta zp_t0
        lda v_bendhi,x
        sta zp_t1
        bpl +
        lda #0
        sec
        sbc zp_t0
        sta zp_t0
        lda #0
        sbc zp_t1
        sta zp_t1
+       lda zp_t2               ; |bend| / ticks, 16/8 bit
        bmi _div9               ; >= 128 ticks: the remainder needs 9 bits
        lda #0
        asl zp_t0
        rol zp_t1
        .rept 16                ; quotient bits enter as dividend bits leave
        rol
        cmp zp_t2
        bcc +
        sbc zp_t2
+       rol zp_t0
        rol zp_t1
        .endrept
        jmp _q
_div9   lda #0
        ldy #16
-       asl zp_t0
        rol zp_t1
        rol
        bcs +
        cmp zp_t2
        bcc ++
+       sbc zp_t2
        inc zp_t0
+       dey
        bne -
_q      lda zp_t0
        ora zp_t1
        bne +
        inc zp_t0
+       lda zp_t0
        sta v_slrlo,x
        lda zp_t1
        sta v_slrhi,x
        lda #1
        sta v_slide,x
        rts

; Z: repeat the last command, adding 0..x to the high digit, 0..y to the low
randomize
        lda ch_lastcmd,x
        sta zp_cmd
        beq +
        lda zp_val
        lsr
        lsr
        lsr
        lsr
        jsr rand_upto
        asl
        asl
        asl
        asl
        sta zp_t1
        lda zp_val
        and #$0f
        jsr rand_upto
        clc
        adc zp_t1
        clc
        adc ch_lastval,x
        sta zp_val
+       rts

; A = n: random 0..n
rand_upto
        sta zp_t0
        jsr rand
        and #$0f
-       cmp zp_t0
        beq +
        bcc +
        clc
        sbc zp_t0               ; - (n+1)
        jmp -
+       rts

; A = B value: returns A = 1 (play) / 0 (skip), flags set. y/15 chance.
roll_maybe
        and #$0f
        cmp #$0f
        beq _yes
        sta zp_t0
        jsr rand
        and #$0f
        cmp zp_t0
        bcc _yes
        lda #0
        rts
_yes    lda #1
        rts

; 16-bit Galois LFSR, A = new low byte
rand    lda rng
        asl
        rol rng+1
        bcc +
        eor #$2d
+       sta rng
        rts

; A = phrase, Y = step -> zp_ptr
phrase_addr
        pha
        lsr
        lsr
        clc
        adc #>PHRASES
        sta zp_ptr+1
        pla
        and #3
        lsr
        ror
        ror
        sta zp_ptr
        tya
        asl
        asl
        ora zp_ptr
        sta zp_ptr
        rts

; A = chain, Y = step -> zp_ptr
chain_addr
        pha
        lsr
        lsr
        lsr
        clc
        adc #>CHAINS
        sta zp_ptr+1
        pla
        asl
        asl
        asl
        asl
        asl
        sta zp_ptr
        tya
        asl
        ora zp_ptr
        sta zp_ptr
        rts

; A = instrument -> zp_ins
instr_addr
        and #NINSTR-1
        pha
        lsr
        lsr
        lsr
        lsr
        clc
        adc #>INSTR
        sta zp_ins+1
        pla
        asl
        asl
        asl
        asl
        sta zp_ins
        rts

; ---------------------------------------------------------------------------
; Note trigger: X = voice, zp_note = final note, zp_instr = instrument/$ff
; ---------------------------------------------------------------------------
trigger
        lda zp_instr
        cmp #NINSTR
        bcs +
        sta v_instr,x
+       lda v_instr,x
        jsr instr_addr
        jmp trig_go
; same, zp_ins already points at the instrument (resolve_note did it)
trigger_ins
        lda zp_instr
        cmp #NINSTR
        bcs trig_go
        sta v_instr,x
trig_go lda zp_note
        sta v_note,x
        lda v_gate,x            ; still gated (no HR): pulse the gate in sid_out
        sta v_retrig,x
        ldy #IN_WAVE
        lda (zp_ins),y
        and #$fe
        sta v_wave,x
        iny                     ; IN_AD = IN_WAVE + 1
        .cerror IN_AD != IN_WAVE + 1, "IN_WAVE/IN_AD layout"
        lda (zp_ins),y
        sta v_ad,x
        iny
        lda (zp_ins),y
        sta v_sr,x
        iny
        lda (zp_ins),y
        sta v_pwlo,x
        iny
        lda (zp_ins),y
        tay
        and #$0f
        sta v_pwhi,x
        tya
        and #$f0                ; sweep mode * 16
        sta v_pwmode,x
        ldy #IN_PWSPD
        lda (zp_ins),y
        sta v_pwspd,x
        ldy #IN_VIB
        lda (zp_ins),y
        sta v_vib,x
        iny
        lda (zp_ins),y
        sta v_vibdly,x
        lda #64                 ; triangle zero crossing, rising
        sta v_vibph,x
        lda #0
        sta v_bendlo,x
        sta v_bendhi,x
        sta v_pwdir,x
        sta v_bendspd,x
        sta v_slide,x
        sta v_arp,x             ; (v_arppos only counts with v_arp: C sets both)
        sta v_fine,x
        sta v_test,x
        sta v_rtcnt,x
        sta v_del,x
        sta v_tbltr,x
        lda #1
        sta v_pdirty,x
        lda #$ff
        sta v_kill,x
        ldy #IN_FLAGS
        lda (zp_ins),y
        and #INF_FILTER_MASK
        beq _froff
        pha
        lda bit_tab,x
        ora f_route
        sta f_route
        pla
        cmp #INF_FILTER_OWN
        bne _table
        txa                     ; own: last trigger on this SID wins
        pha
        lda sidof,x
        tax
        ldy #IN_CUTOFF
        lda (zp_ins),y
        sta f_cut,x
        iny
        lda (zp_ins),y
        sta f_resmode,x
        iny
        lda (zp_ins),y
        sta f_sweep,x
        pla
        tax
        bcs _table
_froff  lda bit_tab,x
        eor #$ff
        and f_route
        sta f_route
_table  lda #1
        sta v_gate,x
        ldy #IN_TABLE
        lda (zp_ins),y
        cmp #NTABLES
        bcc _tbl
        lda #$ff                ; no table
        sta v_tbl,x
        rts
_tbl    cmp v_tbl,x             ; step mode: the same table goes
        bne tbl_go              ; on, one row per note; a new one restarts
        ldy v_tblspd,x
        bpl tbl_go
        ldy #IN_TBLSPD
        lda (zp_ins),y
        bmi +
        lda v_tbl,x
        jmp tbl_go
+       sta v_tblspd,x
        lda #1
        sta v_tblkick,x
        rts

; ---------------------------------------------------------------------------
; Commands: A = command, Y = value, X = voice. Handlers get A = value.
; B D G H L Q Z are sequencer-level (step_advance / lookahead / tables).
; ---------------------------------------------------------------------------
exec_cmd
        cmp #1
        bcc _r
        cmp #27
        bcs _r
        sty zp_xv
        asl
        tay
        lda cmd_tab-1,y
        pha
        lda cmd_tab-2,y
        pha
        lda zp_xv
_r      rts

cmd_tab .rta cmd_a, cmd_none, cmd_c, cmd_none, cmd_e, cmd_f, cmd_none
        .rta cmd_none, cmd_none, cmd_none, cmd_k, cmd_none, cmd_m, cmd_none
        .rta cmd_o, cmd_p, cmd_none, cmd_r, cmd_s, cmd_t, cmd_none
        .rta cmd_v, cmd_w, cmd_x, cmd_none, cmd_none

cmd_a   jmp table_start
cmd_c   sta v_arp,x             ; chord 0, x, y per tick (y = 0: 0, x)
        lda #0
        sta v_arppos,x
dirty   lda #1                  ; pitch must be recomputed
        sta v_pdirty,x
cmd_none
        rts
cmd_e   sta v_sr,x
        rts
cmd_f   sta v_fine,x            ; signed, 1/128 semitone
        jmp dirty
cmd_k   sta v_kill,x            ; gate off after n ticks
        rts
cmd_m   and #$0f
        ldy sidof,x
        sta f_vol,y
        rts
cmd_o   pha                     ; x = mode bits, y = resonance
        asl
        asl
        asl
        asl
        sta zp_t0
        pla
        lsr
        lsr
        lsr
        lsr
        ora zp_t0
        ldy sidof,x
        sta f_resmode,y
        rts
cmd_p   sta v_bendspd,x         ; signed, 1/64 semitone per tick
        lda #0
        sta v_slide,x
        rts
cmd_r   pha                     ; y = rate (0 once), x = signed sustain step
        and #$0f
        sta v_rtrate,x
        bne +
        lda #1
+       sta v_rtcnt,x
        pla
        lsr
        lsr
        lsr
        lsr
        sta v_rtfade,x
        rts
cmd_s   pha                     ; PW = value * 16
        asl
        asl
        asl
        asl
        sta v_pwlo,x
        pla
        lsr
        lsr
        lsr
        lsr
        sta v_pwhi,x
        rts
cmd_t   jsr set_tempo
        ldx zp_ch
        rts
cmd_v   sta v_vib,x
        lda #0
        sta v_vibdly,x
        beq dirty
cmd_w   and #$fe                ; the engine owns the gate
        sta v_wave,x
        rts
cmd_x   ldy sidof,x
        sta f_cut,y
        rts

; ---------------------------------------------------------------------------
; Tables: A = table ($20+ stops), X = voice
; ---------------------------------------------------------------------------
table_start
        cmp #NTABLES
        bcs tbl_off
        pha
        lda v_instr,x
        jsr instr_addr
        pla
; same, zp_ins = this voice's instrument
table_start_ins
        cmp #NTABLES
        bcs tbl_off
tbl_go  sta v_tbl,x
        lda #0
        sta v_tblstep,x
        sta pl_tblstep,x        ; row 0 plays next (this tick on a trigger)
        sta v_tblcnt,x
        sta v_tbltr,x
        ldy v_hcused,x          ; hop counters only where an H counted
        beq _hcok
        sta v_hcused,x
        iny
        beq _hcall
        tya                     ; one row: Y = row + 2
        clc
        adc voff16,x
        tay
        lda #0
        sta tbl_hc-2,y
        beq _hcok
_hcall  ldy voff16,x
        .for i := 0, i < 16, i += 1
        sta tbl_hc+i,y
        .next
_hcok   lda #1
        sta v_tblkick,x
        ldy #IN_TBLSPD
        lda (zp_ins),y
        sta v_tblspd,x
        rts
tbl_off lda #$ff
        sta v_tbl,x
        lda #0
        sta v_tbltr,x
        jmp dirty

table_tick
        lda v_tbl,x
        bmi _r
        lda v_tblspd,x
        bpl _tick
        lda v_tblkick,x         ; step mode: one row per note
        beq _r
        lda #0
        sta v_tblkick,x
        lda #16                 ; a row with H leads on at once (the note
        sta tbl_guard           ; plays the row it leads to), 16 rows at most
-       lda #0
        sta tbl_h
        jsr table_row
        lda tbl_h
        beq _r
        lda v_tbl,x             ; an A in the row: that table starts anew
        bmi _r
        lda v_tblkick,x
        bne _r
        dec tbl_guard
        bne -
        rts
_tick   lda v_tblcnt,x
        beq +
        dec v_tblcnt,x
_r      rts
+       lda v_tblspd,x          ; n ticks per row (0 = 1)
        and #$0f
        beq +
        sec
        sbc #1
+       sta v_tblcnt,x
        ; fall through

; one table row: columns at TABLES + col*512, Y = row offset in the page
TROW    .macro o
        lda TABLES+\o,y
        cmp #$ff
        beq +
        and #$fe
        sta v_wave,x
+       lda TABLES+$200+\o,y
        sta v_tbltr,x
        lda TABLES+$400+\o,y
        sta zp_tc1
        lda TABLES+$600+\o,y
        sta zp_tv1
        lda TABLES+$800+\o,y
        sta zp_tc2
        lda TABLES+$a00+\o,y
        sta zp_tv2
        .endm
table_row
        lda v_tblstep,x
        sta zp_t2
        sta pl_tblstep,x        ; the row playing now
        lda v_tbl,x             ; table * 16 + row; C = table bit 4
        asl
        asl
        asl
        asl
        ora zp_t2
        tay
        bcs _hi
        #TROW 0
        jmp _cmds
_hi     #TROW $100
_cmds   lda zp_t2
        clc
        adc #1
        and #$0f
        sta v_tblstep,x
        lda zp_tc1
        beq +
        ldy zp_tv1
        jsr table_cmd
+       lda zp_tc2
        bne +
        rts
+       ldy zp_tv2
        ; fall through

; A = command, Y = value. H in tables: Hxy hops to y, x times (0 = forever)
table_cmd
        cmp #CMD_H
        beq +
        jmp exec_cmd
+       sta tbl_h               ; step mode: follow this row
        tya
        and #$0f
        sta zp_t3
        tya
        lsr
        lsr
        lsr
        lsr
        beq _go
        sta zp_t1
        ldy zp_t2               ; table_start clears this row's counter
        iny                     ; (v_hcused = row + 1; $ff: several rows)
        tya
        cmp v_hcused,x
        beq _cnt
        ldy v_hcused,x
        beq +
        lda #$ff
+       sta v_hcused,x
_cnt    lda voff16,x
        clc
        adc zp_t2
        tay
        lda tbl_hc,y
        bne +
        lda zp_t1
        clc
        adc #1
+       sec
        sbc #1
        sta tbl_hc,y
        beq _r
_go     lda zp_t3
        sta v_tblstep,x
_r      rts

; ---------------------------------------------------------------------------
; Per voice, every tick (X = voice)
; ---------------------------------------------------------------------------
voice_tick
        lda v_del,x             ; D: delayed note
        beq +
        dec v_del,x
        bne +
        lda v_delnote,x
        sta zp_note
        lda v_delins,x
        sta zp_instr
        jsr trigger
+       lda v_rtcnt,x           ; R: retrig
        beq +
        dec v_rtcnt,x
        bne +
        jsr retrig
+       lda v_tbl,x
        bmi +
        jsr table_tick
+       lda v_kill,x            ; K: gate off when the count runs out
        cmp #$ff
        beq +
        cmp #0
        bne _kdec
        sta v_gate,x
        lda #$ff
        sta v_kill,x
        bne +
_kdec   dec v_kill,x
+       lda v_pdirty,x          ; static pitch: the shadow frequency stands
        ora v_arp,x
        ora v_slide,x
        ora v_bendspd,x
        bne _pitch
        lda v_vib,x
        cmp #$10
        bcs _pitch
        lda v_tbl,x
        bmi _static
_pitch  jsr pitch
        lda #0
        sta v_pdirty,x
        ldy voff,x
        lda zp_flo
        sta pl_shadow+0,y
        lda zp_fhi
        sta pl_shadow+1,y
_static ldy v_pwmode,x           ; the rest of the shadow: sid_out
        bne pulse_y
        rts

retrig  lda v_rtrate,x
        sta v_rtcnt,x
        lda v_gate,x
        sta v_retrig,x
        lda #1
        sta v_gate,x
        lda v_rtfade,x
        beq _r
        cmp #8
        bcc +
        ora #$f0
+       sta zp_t0
        lda v_sr,x
        lsr
        lsr
        lsr
        lsr
        clc
        adc zp_t0
        bpl +
        lda #0
+       cmp #16
        bcc +
        lda #15
+       asl
        asl
        asl
        asl
        sta zp_t0
        lda v_sr,x
        and #$0f
        ora zp_t0
        sta v_sr,x
_r      rts

; Pitch in 8.8 semitones -> SID frequency in zp_flo/zp_fhi.
pitch
        lda #0                  ; C: arpeggio 0, x, y
        sta zp_arp
        lda v_arp,x
        beq _noarp
        ldy v_arppos,x
        beq _a0
        dey
        beq _a1
        and #$0f
        ldy #0
        beq _aset
_a0     ldy #1
        lda #0
        beq _aset
_a1     lsr
        lsr
        lsr
        lsr
        sta zp_arp
        ldy #2
        lda v_arp,x
        and #$0f
        bne +
        tay
+       lda zp_arp
_aset   sta zp_arp
        tya
        sta v_arppos,x
_noarp
        lda v_slide,x           ; L: bend decays to 0 at v_slr per tick
        beq _bend
        lda v_bendhi,x
        bmi _sup
        lda v_bendlo,x
        sec
        sbc v_slrlo,x
        sta v_bendlo,x
        lda v_bendhi,x
        sbc v_slrhi,x
        sta v_bendhi,x
        bpl _vib
        bmi _send
_sup    lda v_bendlo,x
        clc
        adc v_slrlo,x
        sta v_bendlo,x
        lda v_bendhi,x
        adc v_slrhi,x
        sta v_bendhi,x
        bmi _vib
_send   lda #0
        sta v_bendlo,x
        sta v_bendhi,x
        sta v_slide,x
        beq _vib
_bend   lda v_pdirty,x          ; P and V start the tick after a trigger
        bne _vib0
        ldy #0                  ; (before the load: bpl below tests the speed's sign)
        lda v_bendspd,x         ; P: bend += speed * 4, kept in +-$6000
        beq _vib
        sta zp_t0
        bpl +
        dey
+       sty zp_t1
        asl zp_t0
        rol zp_t1
        asl zp_t0
        rol zp_t1
        lda v_bendlo,x
        clc
        adc zp_t0
        sta v_bendlo,x
        lda v_bendhi,x
        adc zp_t1
        sta v_bendhi,x
        cmp #$60
        bcc _vib
        cmp #$a0
        bcs _vib
        cmp #$80
        lda #$60
        bcc +
        lda #$a0
+       sta v_bendhi,x
        lda #0
        sta v_bendlo,x
_vib    lda v_pdirty,x
        bne _vib0
        sta zp_vlo              ; A = 0. V: triangle, +-depth
        sta zp_vhi
        lda v_vib,x
        cmp #$10
        bcc _novib              ; speed 0 = off
        lda v_vibdly,x
        beq +
        dec v_vibdly,x
        bcs _novib
+       lda v_vib,x
        and #$f0
        lsr
        lsr                     ; C = 0
        adc v_vibph,x
        sta v_vibph,x
        bpl +
        eor #$ff
+       asl
        sta zp_m0               ; 0..254
        lda v_vib,x
        and #$0f
        tay
        lda vib_amp,y
        sta zp_m1               ; depth in 1/16 semitone
        jsr mul8
        ldx zp_ch
        lsr                     ; tri * amp / 8 - amp * 16
        ror zp_mlo
        lsr
        ror zp_mlo
        lsr
        ror zp_mlo
        sta zp_vhi
        lda zp_m1
        asl
        asl
        asl
        asl
        sta zp_t0
        lda zp_m1
        lsr
        lsr
        lsr
        lsr
        sta zp_t1
        lda zp_mlo
        sec
        sbc zp_t0
        sta zp_vlo
        lda zp_vhi
        sbc zp_t1
        sta zp_vhi
        jmp _novib
_vib0   lda #0
        sta zp_vlo
        sta zp_vhi
_novib  lda v_note,x            ; semitone: note + arp + table transpose
        clc
        adc zp_arp
        clc
        adc v_tbltr,x
        bvc +
        lda #127
        bne ++
+       bpl +
        lda #0
+       sta zp_phi
        lda v_fine,x            ; no offset: straight from f96
        ora zp_vlo
        ora zp_vhi
        ora v_bendlo,x
        ora v_bendhi,x
        bne +
        ldy zp_phi
        cpy #96
        bcc _f96
        ldy #95
        bne _f96
+       lda v_fine,x            ; offset = fine*2 + vibrato + bend
        ldy #0
        asl
        bcc +
        dey
+       clc
        adc zp_vlo
        sta zp_plo
        tya
        adc zp_vhi
        sta zp_t1
        lda zp_plo
        clc
        adc v_bendlo,x
        sta zp_plo
        lda zp_t1
        adc v_bendhi,x
        clc
        adc zp_phi
        bvs _pmax
        bmi _pmin
        cmp #96
        bcs _pmax
        sta zp_phi
        bcc _freq
_pmax   lda #95
        sta zp_phi
        lda #0
        sta zp_plo
        beq _freq
_pmin   lda #0
        sta zp_phi
        sta zp_plo
_freq   ldy zp_phi
        lda zp_plo
        bne _interp
_f96    lda f96_lo,y
        sta zp_flo
        lda f96_hi,y
        sta zp_fhi
        rts
_interp sta zp_m0               ; A = zp_plo (frac)
        lda f96_lo+1,y          ; linear to the next semitone (f96[96]
        sec                     ; = $ffff, so B-7 works too)
        sbc f96_lo,y
        sta zp_m1               ; delta low
        lda f96_hi+1,y
        sbc f96_hi,y
        sta zp_d1
        lda f96_lo,y
        sta zp_flo
        lda f96_hi,y
        sta zp_fhi
        jsr mul8                ; + delta * frac / 256: low part
        clc
        adc zp_flo
        sta zp_flo
        bcc +
        inc zp_fhi
+       lda zp_d1               ; delta >= 256 (octave 4 up): d1 part
        beq +
        jsr nmul
        tay
        lda zp_mlo
        clc
        adc zp_flo
        sta zp_flo
        tya
        adc zp_fhi
        sta zp_fhi
+       ldx zp_ch
        rts

; Pulse width sweep: 1 up, 2 down (12-bit wrap), 3 ping-pong $080-$f80
pulse_y lda v_pwspd,x            ; Y = v_pwmode (mode * 16), not 0
        cpy #$10
        beq _add
        cpy #$20
        beq _sub
        ldy v_pwdir,x
        bne _sub
_add    clc
        adc v_pwlo,x
        sta v_pwlo,x
        bcc _chk
        inc v_pwhi,x
        bcs _chk
_sub    sta zp_t0
        lda v_pwlo,x
        sec
        sbc zp_t0
        sta v_pwlo,x
        bcs _chk
        dec v_pwhi,x
_chk    lda v_pwmode,x
        cmp #$30
        beq _ping
        lda v_pwhi,x
        and #$0f
        sta v_pwhi,x
_r      rts
_ping   lda v_pwhi,x
        bmi _bot
        beq _low
        cmp #$0f
        bcc _r
        bne _top
        lda v_pwlo,x
        cmp #$80
        bcc _r
_top    lda #$0f
        ldy #1
        bne _lim
_low    lda v_pwlo,x
        cmp #$80
        bcs _r
_bot    lda #0
        tay
_lim    sta v_pwhi,x
        tya
        sta v_pwdir,x
        lda #$80
        sta v_pwlo,x
        rts

; Filters, one per SID: SID1 into pl_shadow, then (2SID) SID2's voices
; and filter into pl_shadow2 and the second SID.
filter_tick
        ldx #0
        ldy #0
        jsr filt_one
        ldx #3
-       lda pl_shadow+$15,x
        sta SID+$15,x
        dex
        bpl -
        lda pl_nch
        cmp #NV
        bne _r
        jsr sid2_out
        ldx #1
        ldy #$30
        jsr filt_one
        lda #$30+$15
        ldy #$30+$18
        jmp s2copy
_r      rts

; X = SID (0/1), Y = its shadow offset (0 / $30): sweep, then the four
; filter bytes into the shadow (routing: f_route bits 0-2 / 3-5)
filt_one
        lda f_sweep,x
        beq _set
        bmi _neg
        clc
        adc f_cut,x
        bcc +
        lda #$ff
        bne +
_neg    clc
        adc f_cut,x
        bcs +
        lda #0
+       sta f_cut,x
_set    lda #0                  ; cutoff bits 0-2 stay 0
        sta pl_shadow+$15,y
        lda f_route
        cpx #0
        beq +
        lsr
        lsr
        lsr
+       and #7
        sta zp_t2
        lda pl_fxmask
        and #FX_CUT|FX_RES|FX_MODE|FX_VOL
        bne fx_filter
        lda f_cut,x
        sta pl_shadow+$16,y
        lda f_resmode,x
        and #$f0
        ora zp_t2
        sta pl_shadow+$17,y
        lda f_resmode,x
        asl
        asl
        asl
        asl
        ora f_vol,x
        sta pl_shadow+$18,y
        rts

; Live FX latched (A = pl_fxmask & $0f): the overridden values replace
; cutoff, resonance, mode (LP/BP/HP/3OFF) and volume on both SIDs; routing stays.
fx_filter
        lsr
        sta zp_t0               ; b0 res, b1 mode, b2 vol
        lda f_cut,x
        bcc +
        lda pl_fxcut
+       sta pl_shadow+$16,y
        lda f_resmode,x
        lsr zp_t0
        bcc +
        lda pl_fxres
        asl
        asl
        asl
        asl
+       and #$f0
        ora zp_t2
        sta pl_shadow+$17,y
        lda f_resmode,x
        lsr zp_t0
        bcc +
        lda pl_fxmode
+       asl
        asl
        asl
        asl
        sta zp_t1
        lda f_vol,x
        lsr zp_t0
        bcc +
        lda pl_fxvol
        and #$0f
+       ora zp_t1
        sta pl_shadow+$18,y
        rts

; SID2 voices (channels 4-6) -> pl_shadow2 and SID2, same order as OUTV.
; The sta s2..,y operands point at pl_sid2 - $30 (sid2_init patches them).
sid2_out
        ldx #3
s2_v      ldy voff,x
        lda v_wave,x
        ora v_test,x
        lsr zp_mute
        bcs s2_m
        ora v_gate,x
        sta pl_shadow+4,y
        lda v_sr,x
        bcc s2_c                  ; C clear from lsr
s2_m      sta pl_shadow+4,y
        lda #0
s2_c      sta pl_shadow+6,y
        lda v_retrig,x
        beq s2_nr
        lda #0
        sta v_retrig,x
        lda pl_shadow+4,y
        and #$fe                ; retrigger: a fresh gate edge
s2a     sta SID+4-$30,y
s2_nr     lda v_pwlo,x
        sta pl_shadow+2,y
s2b     sta SID+2-$30,y
        lda v_pwhi,x
        sta pl_shadow+3,y
s2c     sta SID+3-$30,y
        lda v_ad,x
        sta pl_shadow+5,y
s2d     sta SID+5-$30,y
        lda pl_shadow+6,y
s2e     sta SID+6-$30,y
        lda pl_shadow+0,y
s2f     sta SID+0-$30,y
        lda pl_shadow+1,y
s2g     sta SID+1-$30,y
        lda pl_shadow+4,y
s2h     sta SID+4-$30,y
        inx
        cpx #NV
        bne s2_v
        rts

; pl_shadow+Y down to pl_shadow+A (both in pl_shadow2) -> SID2
s2copy  sta zp_t0
-       lda pl_shadow,y
s2w     sta SID-$30,y
        dey
        cpy zp_t0
        bcs -
        rts

; init: pl_nch from pl_sid2; with a SID2, point the s2 operands at it
; (operand = pl_sid2 - $30 + register) and clear its registers
sid2_init
        ldx #NCHAN
        lda pl_sid2+1
        beq _n
        lda pl_sid2
        sec
        sbc #$30
        sta zp_t1
        lda pl_sid2+1
        sbc #0
        sta zp_t2
        ldy #0
-       ldx s2tab,y
        lda s2tab+1,y
        clc
        adc zp_t1
        sta s2a+1,x             ; operand (x = site - s2a)
        lda zp_t2
        adc #0
        sta s2a+2,x
        iny
        iny
        cpy #s2tab_end-s2tab
        bne -
        lda #$30
        ldy #$30+$18
        jsr s2copy              ; pl_shadow2 is clear: SID2 reset
        ldx #NV
_n      stx pl_nch
        rts

; Voice registers -> pl_shadow and SID, unrolled, after every voice_tick
; (pitch already put the frequency into the shadow). Per voice: gate low
; first on a retrigger, then PW, AD, SR, frequency, control last. Muted:
; no gate, SR 0 (fast release). The filter follows (filter_tick).
OUTV    .macro v
S       = 7 * \v
        lda v_wave+\v
        ora v_test+\v
        lsr zp_mute
        bcs _m
        ora v_gate+\v
        ldy v_sr+\v
        bcc _c                  ; C clear from lsr
_m      ldy #0
_c      sta pl_shadow+S+4
        sty pl_shadow+S+6
        ldx v_retrig+\v
        beq _nr
        and #$fe                ; retrigger: a fresh gate edge
        sta SID+S+4
        lda #0
        sta v_retrig+\v
_nr     lda v_pwlo+\v
        sta pl_shadow+S+2
        sta SID+S+2
        lda v_pwhi+\v
        sta pl_shadow+S+3
        sta SID+S+3
        lda v_ad+\v
        sta pl_shadow+S+5
        sta SID+S+5
        sty SID+S+6
        lda pl_shadow+S+0
        sta SID+S+0
        lda pl_shadow+S+1
        sta SID+S+1
        lda pl_shadow+S+4
        sta SID+S+4
        .endm
sid_out
        lda pl_mute
        sta zp_mute
        .for i := 0, i < NCHAN, i += 1
        #OUTV i
        .next
        rts

; ---------------------------------------------------------------------------
; Constant tables
; ---------------------------------------------------------------------------
bit_tab .for i := 0, i < NV, i += 1  ; per channel / voice
        .byte 1 << i
        .next
pat_tab .for i := 1, i <= NV, i += 1
        .byte i
        .next
voff    .for i := 0, i < NV, i += 1  ; shadow offset: pl_shadow / pl_shadow2
        .byte 7 * i + (i >= 3 ? $30 - 21 : 0)
        .next
sidof   .byte 0, 0, 0, 1, 1, 1
; SID2 write sites (sid_out2, s2copy): offset from s2a, register
s2tab   .for site, reg in [(s2a, 4), (s2b, 2), (s2c, 3), (s2d, 5), (s2e, 6), (s2f, 0), (s2g, 1), (s2h, 4), (s2w, 0)]
        .byte site - s2a, reg
        .next
        .cerror s2w - s2a > 255, "SID2 write sites too far apart"
s2tab_end
voff16  .for i := 0, i < NV, i += 1
        .byte 16 * i
        .next
vib_amp .byte 2, 4, 6, 8, 12, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128
clk_lo  .byte <CLK_PAL, <CLK_NTSC
clk_mid .byte >CLK_PAL, >CLK_NTSC
clk_hi  .byte `CLK_PAL, `CLK_NTSC

; Equal temperament, A-4 (note $39) = 440 Hz. Only octave 6 is stored per
; clock; gen_freq shifts it into f96. B-7 exceeds the PAL range: $ffff.
FREQ    .function n, hz
        .endf int(round(440.0 * 2.0 ** ((n - 57) / 12.0) * 16777216.0 / hz))
oct_ofs .byte 0, 12
oct6_lo
        .for n := 72, n < 84, n += 1
        .byte <FREQ(n, HZ_PAL)
        .next
        .for n := 72, n < 84, n += 1
        .byte <FREQ(n, HZ_NTSC)
        .next
oct6_hi
        .for n := 72, n < 84, n += 1
        .byte >FREQ(n, HZ_PAL)
        .next
        .for n := 72, n < 84, n += 1
        .byte >FREQ(n, HZ_NTSC)
        .next

; Note table (built by init) and the 256-entry quarter-square tables for
; MUL8 (a + b > 255 goes through mul8h), page aligned (no page-crossing
; cycles), at the top of the player area: the free space stays in one piece below.
f96_lo    .fill 97              ; SID frequency of every note (this clock),
f96_hi    .fill 97              ; [96] = $ffff
img_vars                        ; [NV] arrays that do not fit PLAYER_EXT (init clears them)
ch_hopmode .fill NV              ; 0 none, 1 back in phrase, 2 next phrase
ch_hopstep .fill NV
ch_hopcnt  .fill NV
ch_lastcmd .fill NV
ch_lastval .fill NV
v_hcused  .fill NV               ; a table H counted since the table started
st_ieff   .fill NV               ; prep: instrument the note resolved with,
st_htr    .fill NV               ; g_transp then, final note and instrument
st_fnote  .fill NV               ; pointer (step_advance uses them if the
st_ilo    .fill NV               ; first two still match)
st_ihi    .fill NV
img_vars_end
SQ_TABLES = PLAYER_END - $200
        .cerror * > SQ_TABLES, "player code runs into the multiply tables"
free_space                              ; up to SQ_TABLES: unused
        .fill SQ_TABLES - *, 0
sq_lo   .for n := 0, n < 256, n += 1
        .byte <((n * n) >> 2)
        .next
sq_hi   .for n := 0, n < 256, n += 1
        .byte >((n * n) >> 2)
        .next

; ---------------------------------------------------------------------------
; Variables and generated tables in PLAYER_EXT ($0e00-$0fff): not part of the
; code image, init clears all of it. Voice/channel arrays are [NV] = 6; the
; note table f96 and the arrays from img_vars live in the player area.
; ---------------------------------------------------------------------------
        .virtual PLAYER_EXT
lock      .fill 1
pending   .fill 1
ntsc      .fill 1
clk       .fill 3
latch     .fill 2               ; tempo latch (set_tempo)
latch_eff .fill 2               ; CIA2 timer A latch: latch with pl_nudge
nudge_now .fill 1               ; pl_nudge that latch_eff was made for
rng       .fill 2
f_cut     .fill 2               ; filter per SID [2]
f_resmode .fill 2               ; hi resonance, lo mode bits
f_route   .fill 1               ; bit per voice (SID2: bits 3-5)
f_vol     .fill 2
f_sweep   .fill 2
tbl_hc    .fill NV*16        ; table hop counters per voice and row
ch_groove  .fill NV
ch_gstep   .fill NV
ch_hrat    .fill NV              ; HR when ch_wait reaches this (0 = none)
ch_hrmode  .fill NV
ch_hrsr    .fill NV
ch_transp  .fill NV
ch_broll   .fill NV              ; B dice for the next step, $ff = not rolled
nx_transp  .fill NV
nx_ok      .fill NV
nx_newph   .fill NV
ch_pend   .fill NV               ; stopped channel: ticks to its queued start
nx_q      .fill NV               ; nx_* came from the queue
ch_prep   .fill NV               ; st_* hold the next step (prep ran)
ch_pat    .fill NV               ; prep when ch_wait reaches this
st_note   .fill NV
st_instr  .fill NV
st_cmd    .fill NV
st_val    .fill NV
st_len    .fill NV               ; its length in ticks
st_groove .fill NV
st_gstep  .fill NV
v_pwdir   .fill NV
v_bendspd .fill NV
v_slide   .fill NV
v_arp     .fill NV
v_arppos  .fill NV
v_fine    .fill NV
v_test    .fill NV
v_rtcnt   .fill NV
v_del     .fill NV
v_pdirty  .fill NV
v_instr   .fill NV
v_note    .fill NV
v_wave    .fill NV
v_ad      .fill NV
v_sr      .fill NV
v_pwmode  .fill NV
v_pwspd   .fill NV
v_slrlo   .fill NV
v_slrhi   .fill NV
v_vib     .fill NV
v_vibdly  .fill NV
v_vibph   .fill NV
v_kill    .fill NV
v_delnote .fill NV
v_delins  .fill NV
v_retrig  .fill NV
v_rtrate  .fill NV
v_rtfade  .fill NV
v_tblstep .fill NV
v_tblcnt  .fill NV
v_tblspd  .fill NV
v_tbltr   .fill NV
v_tblkick .fill NV
nx_row    .fill NV               ; next step (lookahead): row, chain step, phrase step, chain, phrase
nx_cstep  .fill NV
nx_pstep  .fill NV
nx_chain  .fill NV
nx_phrase .fill NV
tbl_h     .fill 1               ; table_row ran an H (step mode follows it)
tbl_guard .fill 1
g_transp  .fill 1                ; HD_TRANSP + Live FX transpose (tick)
ext_end
        .cerror * > pl_lapend, "PLAYER_EXT overflow (pl_lapend at $0fde)"
        .endv
ch_lapend = pl_lapend            ; [6] exported: lookahead due on the next tick
ch_wait   = pl_wait              ; [6] exported: ticks left in the current step
ch_steplen = pl_steplen          ; [6] exported: length of the current step
        .cerror pl_wait != pl_lapend+6 || pl_steplen != pl_wait+6 || pl_tbl != pl_steplen+6, "pl_lapend/pl_wait/pl_steplen layout"
v_tbl     = pl_tbl               ; [6] exported: running table, $ff none
        .cerror pl_tblstep != pl_tbl+6 || PLAYER_EXT+$200 < pl_tblstep+6, "pl_tbl/pl_tblstep layout"
        .bend
