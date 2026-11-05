; Headless player test. Builds a test song, then calls pl.tick directly
; (CIA clock stopped) NTICKS times, recording one frame per tick:
;   $3000 + t*40: +0 pl_shadow[25], +25 pl_playing, +26 pl_row[3],
;   +29 pl_chain_step[3], +32 pl_phrase_step[3], +35 pl_tick,
;   +36/37 CIA2 timer B after the tick (cycles = calib - value + 12)
; Then runs the real NMI clock for one second (CIA1 time base) per tempo.
; Results block at RESULTS (see below). tests/run_player_test.py drives
; VICE and checks the trace.
;   Nudge (real clock, 125 BPM, after the 295 BPM second): NSTAMP CIA1
;   timer A readings (free-running, word each) at STAMPS, one per tick,
;   4 x NSEG with pl_nudge 0 / +8 / -8 / 0 set right after each segment's
;   last stamp; pl.latch_eff after each segment at RESULTS+16 (4 words).
; Phase 2 (live mode), after the runner has saved phase 1 and set RESULTS+12:
; NTICKS2 manual ticks with pl_live = 1 and the events2 list, one FRAME2
; frame per tick at TRACE:
;   +0 pl_playing, +1 pl_row[3], +4 pl_chain_step[3], +7 pl_phrase_step[3],
;   +10 pl_queue[3], +13 voice control[3], +16 freq lo/hi[3], +22 voice 2
;   AD, +23 pl_live, +24/25 CIA2 timer B (cycles as phase 1)
; Then (same dump) the table scenario: song row $20, NTICKS3 manual ticks,
; FRAME3 bytes per tick at TRACE3: +0 pl_tbl[3], +3 pl_tblstep[3],
;   +6 freq lo/hi[3], +12/13 CIA2 timer B; RESULTS+$d0: pl_tbl[3..5] after.
; Live FX overrides (fx_test, song row 0, manual ticks), 40 bytes at FXR:
;   +0 pl_fxmask after player_init (set to $1f before), then records of
;   filter (shadow $16-$18) and/or notes (freq lo/hi of voices 0-2):
;   +1 filter, +4 notes after 3 ticks without FX; +10 filter one tick after
;   latching cut/res/mode/vol; +13 filter one tick after keeping only vol;
;   notes after 3 ticks with HD_TRANSP / pl_fxtransp = 0/+12 (+16),
;   2/+3 (+22), 0/+127 (+28), 0/-30 (+34).
; Then step mode: song row $30 (ch0 only, 1 tick per step), NTICKS4 ticks,
; FRAME4 bytes at TRACE4: pl_tbl[0], pl_tblstep[0], ch0 freq lo/hi.

        .include "defs.inc"

NTICKS  = 512
TRACE   = $3000
FRAME   = 40
RESULTS = $2f00                 ; +0 ntsc, +1/2 latch after T80, +3/4 calib,
                                ; +5 ticks/s @125, +6 ticks/s @295, +7 done
                                ; (1 phase 1, 2 phase 2), +8/9 latch @125,
                                ; +10/11 latch @295, +12 go (runner: phase 2)
NTICKS2 = 720
NSEG    = 21
STAMPS  = RESULTS+$20           ; 4 * NSEG words, up to RESULTS+$c7
NTICKS3 = 120
FRAME3  = 14
TRACE3  = TRACE+NTICKS2*FRAME2
NTICKS4 = 20                    ; step-mode table: one note per tick
FRAME4  = 4
TRACE4  = TRACE3+NTICKS3*FRAME3
        .cerror TRACE4+NTICKS4*FRAME4 > $8000, "table trace too long"
SONGDATA = $0810
NTICKS5 = 256                   ; phase 3 (2SID)
FRAME5  = 80
MUTE5   = 150
FAKE2   = $0c20                 ; "second SID" in RAM for phase 3
        .cerror TRACE+NTICKS5*FRAME5 > $8000, "2SID trace too long"
FRAME2  = 26

zp_p    = $40                   ; trace pointer
zp_ev   = $42                   ; event pointer
zp_t    = $44                   ; tick counter (16 bit)
zp_s    = $46                   ; song data pointer
zp_d    = $48

        * = $0801
        .word (+), 2026
        .null $9e, format("%d", start)
+       .word 0

        * = PLAYER
        .include "player.asm"
        .cerror * > PLAYER_END, "player overflows PLAYER_END"

        * = PLAYER_END          ; test code (song data at SONGDATA)
start   sei
        cld
        ldx #$ff
        txs
        lda #BANK_RAMIO
        sta $01
        lda #$7f
        sta CIA1+$0d
        sta CIA2+$0d
        lda CIA1+$0d
        lda CIA2+$0d
        lda #0
        sta VIC+$1a
        sta VIC+$15             ; no sprites
        lda #$0b                ; screen off: no badlines, exact cycle counts
        sta VIC+$11
        lda #0
        tax
-       sta RESULTS,x
        inx
        bne -
        lda #<rti_
        sta $fffe
        sta $fffa
        lda #>rti_
        sta $ffff
        sta $fffb
        jsr clear_project
        jsr load_song
        jsr player_init
        lda #$7f                ; stop the clock: the test drives ticks
        sta CIA2+$0d
        lda #0
        sta CIA2+$0e
        lda CIA2+$0d
        lda pl.ntsc
        sta RESULTS+0
        ; calibrate: timer value around a bare jsr/rts (12 cycles)
        jsr timer_start
        jsr rti_rts
        jsr timer_stop
        stx RESULTS+3
        sty RESULTS+4

        lda #<TRACE
        sta zp_p
        lda #>TRACE
        sta zp_p+1
        lda #<events
        sta zp_ev
        lda #>events
        sta zp_ev+1
        lda #0
        sta zp_t
        sta zp_t+1
        jsr player_play_song    ; A = 0: row 0

_loop   jsr run_events
        jsr timer_start
        jsr pl.tick
        jsr timer_stop
        txa
        ldy #36
        sta (zp_p),y
        iny
        lda timer_hi
        sta (zp_p),y
        ldy #24
-       lda pl_shadow,y
        sta (zp_p),y
        dey
        bpl -
        ldy #25
        lda pl_playing
        sta (zp_p),y
        ldx #0
-       iny
        lda pl_row,x
        sta (zp_p),y
        inx
        cpx #3
        bne -
        ldx #0
-       iny
        lda pl_chain_step,x
        sta (zp_p),y
        inx
        cpx #3
        bne -
        ldx #0
-       iny
        lda pl_phrase_step,x
        sta (zp_p),y
        inx
        cpx #3
        bne -
        iny
        lda pl_tick
        sta (zp_p),y
        lda zp_p
        clc
        adc #FRAME
        sta zp_p
        bcc +
        inc zp_p+1
+       inc zp_t
        bne +
        inc zp_t+1
+       lda zp_t
        cmp #<NTICKS
        lda zp_t+1
        sbc #>NTICKS
        bcc _loop

        lda pl.latch
        sta RESULTS+1
        lda pl.latch+1
        sta RESULTS+2

        ; real clock: player_init starts CIA2 timer A -> NMI at HD_TEMPO
        jsr player_init
        lda #0
        jsr player_play_song
        lda pl.latch
        sta RESULTS+8
        lda pl.latch+1
        sta RESULTS+9
        jsr one_second
        sta RESULTS+5
        lda #$27                ; 295 BPM
        jsr player_set_tempo
        lda pl.latch
        sta RESULTS+10
        lda pl.latch+1
        sta RESULTS+11
        jsr one_second          ; first second partly at the old latch:
        jsr one_second          ; measure the second one
        sta RESULTS+6
        jsr player_init         ; silence (even tick lengths), HD_TEMPO 125
        jsr nudge_test
        lda #1
        sta RESULTS+7
-       lda RESULTS+12          ; runner saves phase 1, then says go
        beq -
        jsr live_test
        jsr table_test
        jsr step_test
        jsr fx_test
        lda #2
        sta RESULTS+7
-       lda RESULTS+12          ; runner saves phase 2, then says go (2)
        cmp #2
        bne -
        jsr sid2_test
        lda #3
        sta RESULTS+7
-       lda RESULTS+12          ; runner saves phase 3, then says go (3)
        cmp #3
        bne -
        jsr hold_test
        lda #4
        sta RESULTS+7
done    jmp done

; Phase 3 (2SID): song slots 0-2 copied to 3-5, pl_sid2 = FAKE2 (RAM, so
; the writes can be read back), song row 0, NTICKS5 manual ticks, FRAME5
; bytes per tick at TRACE: +0 pl_shadow[25], +25 pl_shadow2[25], +50 the
; FAKE2 "registers"[25], +75 pl_playing, +76 pl_nch, +77/78 CIA2 timer B,
; +79 pl_tick. pl_mute = $20 (channel 6) for ticks MUTE5..MUTE5+49.
; Afterwards back to mono: RESULTS+$fe = pl_nch. Lives at $0c40 (room).
        .section lowtest
; Phase 4 (hold, M9): song row 0, NTICKS6 manual ticks, FRAME6 bytes per
; tick at TRACE: +0 pl_phrase_step[3], +3 pl_chain_step[3], +6 pl_row[3],
; +9 pl_wait[0], +10 pl_steplen[0], +11 pl_hold[0]. Before tick HOLD_ON:
; pl_hold = 3 / 15 / $10 (ch2 also pl_lapend); before HOLD_OFF all 0.
NTICKS6 = 240
FRAME6  = 12
HOLD_ON = 30
HOLD_OFF = 170
hold_test
        jsr player_init
        lda #$7f
        sta CIA2+$0d
        lda #0
        sta CIA2+$0e
        lda CIA2+$0d
        lda #<TRACE
        sta zp_p
        lda #>TRACE
        sta zp_p+1
        lda #0
        sta zp_t
        jsr player_play_song
_loop   lda zp_t
        cmp #HOLD_ON
        bne +
        lda #3
        sta pl_hold
        lda #15
        sta pl_hold+1
        lda #$10
        sta pl_hold+2
        lda #1
        sta pl_lapend+2
        lda zp_t
+       cmp #HOLD_OFF
        bne +
        lda #0
        sta pl_hold
        sta pl_hold+1
        sta pl_hold+2
+       jsr pl.tick
        ldy #0
        ldx #0
-       lda pl_phrase_step,x
        sta (zp_p),y
        iny
        inx
        cpx #3
        bne -
        ldx #0
-       lda pl_chain_step,x
        sta (zp_p),y
        iny
        inx
        cpx #3
        bne -
        ldx #0
-       lda pl_row,x
        sta (zp_p),y
        iny
        inx
        cpx #3
        bne -
        lda pl_wait
        sta (zp_p),y
        iny
        lda pl_steplen
        sta (zp_p),y
        iny
        lda pl_hold
        sta (zp_p),y
        lda zp_p
        clc
        adc #FRAME6
        sta zp_p
        bcc +
        inc zp_p+1
+       inc zp_t
        lda zp_t
        cmp #NTICKS6
        bne _loop
        jmp player_stop

sid2_test
        jsr clear_project
        jsr load_song
        ldx #0
-       lda SONG,x
        sta SONG+$300,x
        lda SONG+$100,x
        sta SONG+$400,x
        lda SONG+$200,x
        sta SONG+$500,x
        inx
        bne -
        lda #<FAKE2
        sta pl_sid2
        lda #>FAKE2
        sta pl_sid2+1
        lda #$5a                ; init must clear the SID2 registers
        ldx #$18
-       sta FAKE2,x
        dex
        bpl -
        jsr fx_init
        lda #<TRACE
        sta zp_p
        lda #>TRACE
        sta zp_p+1
        lda #0
        sta zp_t
        sta zp_t+1
        jsr player_play_song
_loop   ldx #0
        lda zp_t
        cmp #MUTE5
        bcc +
        cmp #MUTE5+50
        bcs +
        ldx #$20
+       stx pl_mute
        jsr timer_start
        jsr pl.tick
        jsr timer_stop
        txa
        ldy #77
        sta (zp_p),y
        iny
        lda timer_hi
        sta (zp_p),y
        iny
        lda pl_tick
        sta (zp_p),y
        ldy #24
-       lda pl_shadow,y
        sta (zp_p),y
        dey
        bpl -
        ldx #24
        ldy #49
-       lda pl_shadow2,x
        sta (zp_p),y
        dey
        dex
        bpl -
        ldx #24
        ldy #74
-       lda FAKE2,x
        sta (zp_p),y
        dey
        dex
        bpl -
        ldy #75
        lda pl_playing
        sta (zp_p),y
        iny
        lda pl_nch
        sta (zp_p),y
        lda zp_p
        clc
        adc #FRAME5
        sta zp_p
        bcc +
        inc zp_p+1
+       inc zp_t
        bne +
        inc zp_t+1
+       lda zp_t+1
        cmp #>NTICKS5
        bne _loop
        lda #0
        sta pl_mute
        sta pl_sid2+1
        jsr player_init         ; mono again
        lda pl_nch
        sta RESULTS+$fe
        jmp player_stop
        .send lowtest

; Phase 2: live mode, manual ticks, events2
live_test
        jsr player_init
        lda #$7f
        sta CIA2+$0d
        lda #0
        sta CIA2+$0e
        lda CIA2+$0d
        lda #1
        sta pl_live
        lda #<TRACE
        sta zp_p
        lda #>TRACE
        sta zp_p+1
        lda #<events2
        sta zp_ev
        lda #>events2
        sta zp_ev+1
        lda #0
        sta zp_t
        sta zp_t+1
_loop   jsr run_events
        jsr timer_start
        jsr pl.tick
        jsr timer_stop
        txa
        ldy #24
        sta (zp_p),y
        iny
        lda timer_hi
        sta (zp_p),y
        ldy #0
        lda pl_playing
        sta (zp_p),y
        ldx #0
-       lda pl_row,x
        ldy ofs_row,x
        sta (zp_p),y
        lda pl_chain_step,x
        ldy ofs_cstep,x
        sta (zp_p),y
        lda pl_phrase_step,x
        ldy ofs_pstep,x
        sta (zp_p),y
        lda pl_queue,x
        ldy ofs_queue,x
        sta (zp_p),y
        ldy ofs_sid,x
        lda pl_shadow+4,y
        pha
        lda pl_shadow+0,y
        pha
        lda pl_shadow+1,y
        ldy ofs_fhi,x
        sta (zp_p),y
        dey
        pla
        sta (zp_p),y
        pla
        ldy ofs_ctl,x
        sta (zp_p),y
        inx
        cpx #3
        bne -
        ldy #22
        lda pl_shadow+14+5
        sta (zp_p),y
        iny
        lda pl_live
        sta (zp_p),y
        lda zp_p
        clc
        adc #FRAME2
        sta zp_p
        bcc +
        inc zp_p+1
+       inc zp_t
        bne +
        inc zp_t+1
+       lda zp_t
        cmp #<NTICKS2
        lda zp_t+1
        sbc #>NTICKS2
        bcc _loop
        rts
ofs_row   .byte 1, 2, 3
ofs_cstep .byte 4, 5, 6
ofs_pstep .byte 7, 8, 9
ofs_queue .byte 10, 11, 12
ofs_ctl   .byte 13, 14, 15
ofs_fhi   .byte 17, 19, 21
ofs_sid   .byte 0, 7, 14

; pl_nudge 0, +8, -8, 0: NSEG tick stamps each (CIA1 timer A, free
; running from $ffff, counts down), pl_nudge changed right after a stamp
nudge_test
        lda #0
        sta CIA1+$0e
        sta CIA1+$0f
        lda #$ff
        sta CIA1+4
        sta CIA1+5
        lda #%00010001          ; TA: load, continuous, start
        sta CIA1+$0e
        lda #<STAMPS
        sta zp_s
        lda #>STAMPS
        sta zp_s+1
        ldx #0
-       jsr stamps
        lda pl.latch_eff
        sta RESULTS+16,x
        lda pl.latch_eff+1
        sta RESULTS+17,x
        inx
        inx
        lda nudges,x
        sta pl_nudge
        cpx #8
        bne -
        rts
nudges  .byte 0, 0, 8, 0, $f8, 0, 0, 0, 0
; NSEG stamps at zp_s: wait for a new tick, read timer A (hi, lo, hi again)
stamps  ldy #0
_st     lda pl_tick
-       cmp pl_tick
        beq -
-       lda CIA1+5
        sta zp_d
        lda CIA1+4
        sta (zp_s),y
        lda CIA1+5
        cmp zp_d
        bne -
        iny
        sta (zp_s),y
        iny
        cpy #NSEG*2
        bne _st
        tya
        clc
        adc zp_s
        sta zp_s
        bcc +
        inc zp_s+1
+       rts

; Table exports: song row $20, manual ticks, FRAME3 per tick at TRACE3
table_test
        jsr player_init
        lda #$7f
        sta CIA2+$0d
        lda #0
        sta CIA2+$0e
        lda CIA2+$0d
        lda #<TRACE3
        sta zp_p
        lda #>TRACE3
        sta zp_p+1
        lda #$20
        jsr player_play_song
        lda #0
        sta zp_t
_loop   jsr timer_start
        jsr pl.tick
        jsr timer_stop
        txa
        ldy #12
        sta (zp_p),y
        iny
        lda timer_hi
        sta (zp_p),y
        ldx #0
-       lda pl_tbl,x
        ldy ofs_tbl,x
        sta (zp_p),y
        lda pl_tblstep,x
        ldy ofs_tstep,x
        sta (zp_p),y
        ldy ofs_sid,x
        lda pl_shadow+1,y
        pha
        lda pl_shadow+0,y
        ldy ofs_flo,x
        sta (zp_p),y
        iny
        pla
        sta (zp_p),y
        inx
        cpx #3
        bne -
        lda zp_p
        clc
        adc #FRAME3
        sta zp_p
        bcc +
        inc zp_p+1
+       inc zp_t
        lda zp_t
        cmp #NTICKS3
        bne _loop
        ldx #5
-       lda pl_tbl,x
        sta RESULTS+$d0,x
        dex
        bpl -
        jmp player_stop
; Step-mode table: song row $30, ch0 frames at TRACE4
step_test
        jsr player_init
        lda #$7f
        sta CIA2+$0d
        lda #0
        sta CIA2+$0e
        lda CIA2+$0d
        lda #<TRACE4
        sta zp_p
        lda #>TRACE4
        sta zp_p+1
        lda #$30
        jsr player_play_song
        ldx #0
_loop   stx zp_t
        jsr pl.tick
        ldy #0
        lda pl_tbl
        sta (zp_p),y
        iny
        lda pl_tblstep
        sta (zp_p),y
        iny
        lda pl_shadow+0
        sta (zp_p),y
        iny
        lda pl_shadow+1
        sta (zp_p),y
        lda zp_p
        clc
        adc #FRAME4
        sta zp_p
        bcc +
        inc zp_p+1
+       ldx zp_t
        inx
        cpx #NTICKS4
        bne _loop
        jmp player_stop

; Live FX overrides, results at FXR (see the top)
FXR     = RESULTS+$d6
fx_test lda #$1f
        sta pl_fxmask
        jsr fx_init
        lda pl_fxmask
        sta FXR
        lda #1
        sta zp_t
        jsr fx_go
        jsr fx_filt
        jsr fx_notes
        ldx #4
-       lda fx_vals,x
        sta pl_fxcut,x
        dex
        bpl -
        lda #FX_CUT|FX_RES|FX_MODE|FX_VOL
        sta pl_fxmask
        jsr pl.tick
        jsr fx_filt
        lda #FX_VOL
        sta pl_fxmask
        jsr pl.tick
        jsr fx_filt
        ldx #0
_tr     stx zp_d
        jsr fx_init
        ldx zp_d
        lda fx_tr,x
        sta HD_TRANSP
        lda fx_tr+1,x
        sta pl_fxtransp
        lda #FX_TRANSP
        sta pl_fxmask
        jsr fx_go
        jsr fx_notes
        ldx zp_d
        inx
        inx
        cpx #8
        bne _tr
        lda #0
        sta HD_TRANSP
        jmp player_stop
fx_vals .byte $a5, $0c, $0a, $07, 0     ; cut, res, mode BP+3OFF, vol, transp
fx_tr   .byte 0, 12, 2, 3, 0, $7f, 0, $e2
fx_init jsr player_init
        lda #$7f
        sta CIA2+$0d
        lda #0
        sta CIA2+$0e
        lda CIA2+$0d
        rts
fx_go   lda #0
        jsr player_play_song
        ldx #3
-       stx zp_d+1
        jsr pl.tick
        ldx zp_d+1
        dex
        bne -
        rts
fx_notes ldx #0
        ldy #6
        bne fx_rec
fx_filt ldx #6
        ldy #9
fx_rec  sty zp_s
-       ldy fx_ofs,x
        lda pl_shadow,y
        ldy zp_t
        sta FXR,y
        inc zp_t
        inx
        cpx zp_s
        bne -
        rts
fx_ofs  .byte 0, 1, 7, 8, 14, 15, $16, $17, $18

ofs_tbl   .byte 0, 1, 2
ofs_tstep .byte 3, 4, 5
ofs_flo   .byte 6, 8, 10

; A = pl_tick increments during one second (CIA1: timer A 10 ms, timer B
; counts 100 underflows). No IRQs; the NMI runs on top.
one_second
        lda #0
        sta CIA1+$0e
        sta CIA1+$0f
        lda #<9852              ; PAL 10 ms
        ldx pl.ntsc
        beq +
        lda #<10227
+       sta CIA1+4
        lda #>9852
        cpx #0
        beq +
        lda #>10227
+       sta CIA1+5
        lda #100
        sta CIA1+6
        lda #0
        sta CIA1+7
        lda pl_tick
        sta zp_d
        lda #%01011001          ; TB: count TA underflows, one-shot, load, start
        sta CIA1+$0f
        lda #%00010001          ; TA: load, continuous, start
        sta CIA1+$0e
-       lda CIA1+$0f            ; one-shot TB clears its start bit at 0
        and #1
        bne -
        lda pl_tick
        sec
        sbc zp_d
        rts

; CIA2 timer B one-shot from $ffff counting cycles
timer_start
        lda #$ff
        sta CIA2+6
        sta CIA2+7
        lda #%00011001
        sta CIA2+$0f
        rts
; -> X = lo, Y = hi (also timer_hi)
timer_stop
        lda #%00001000
        sta CIA2+$0f
        ldx CIA2+6
        ldy CIA2+7
        sty timer_hi
        rts
timer_hi .byte 0

rti_rts rts
rti_    rti

run_events
-       ldy #0
        lda (zp_ev),y
        cmp zp_t
        bne _r
        iny
        lda (zp_ev),y
        cmp zp_t+1
        bne _r
        iny
        lda (zp_ev),y           ; type
        sta zp_d
        iny
        lda (zp_ev),y
        pha
        iny
        lda (zp_ev),y
        tax
        iny
        lda (zp_ev),y
        tay
        pla
        jsr _do
        lda zp_ev
        clc
        adc #6
        sta zp_ev
        bcc -
        inc zp_ev+1
        bne -
_r      rts
_do     pha
        lda zp_d
        cmp #1
        bne +
        pla
        sta pl_mute
        rts
+       cmp #2
        bne +
        pla
        jmp player_note_on
+       cmp #3
        bne +
        pla
        jmp player_note_off
+       cmp #4
        bne +
        pla
        jmp player_play_channel
+       cmp #5
        bne +
        pla
        jmp player_queue
+       cmp #6
        bne +
        pla
        jmp player_queue_stop
+       cmp #7
        bne +
        pla
        sta pl_live
        rts
+       cmp #8
        bne +
        pla
        jmp player_stop
+       cmp #9
        bne +
        stx zp_s
        sty zp_s+1
        pla
        ldy #0
        sta (zp_s),y
        rts
+       pla
        rts

; events: tick (word), type, A, X, Y. 1 mute = A, 2 note_on, 3 note_off,
; 4 play_channel (X = ch, A = row), 5 queue (X = ch, A = row, Y = mode),
; 6 queue_stop (X = ch, Y = mode), 7 pl_live = A, 8 player_stop,
; 9 poke A at X/Y (lo/hi): a song edit during playback
events  .word 300
        .byte 1, $02, 0, 0
        .word 360
        .byte 1, $00, 0, 0
        .word 380
        .byte 2, 57, 2, 1
        .word 400
        .byte 3, 0, 2, 0
        .word 420
        .byte 4, 0, 2, 0
        .word $ffff
        .byte 0, 0, 0, 0

; Phase 2 (tests/check_player.py, live section, explains each one)
EV      .segment
        .word \1
        .byte \2, \3, \4, \5
        .endsegment
events2
        #EV 0, 4, $10, 0, 0     ; ch0 plays row $10 (chain 11: P8 P9)
        #EV 0, 4, $10, 1, 0     ; ch1 plays row $10 (chain 11)
        #EV 20, 5, $11, 0, 0    ; ch0: chain 12 at chain end (t192)
        #EV 20, 5, $11, 1, 1    ; ch1: chain 12 at phrase end (t96)
        #EV 50, 5, $11, 2, 0    ; ch2 stopped: starts with ch0's step (t54)
        #EV 100, 5, $10, 2, 1   ; ch2: HR chain 10 at phrase end (t150)
        #EV 230, 5, $11, 2, 1   ; ch2: back to chain 14 (t246)
        #EV 300, 5, $10, 0, 0   ; ch0: chain 11 at chain end (t384)
        #EV 341, 5, $10, 2, 1   ; ch2: too late for HR, on time (t342)
        #EV 400, 6, 0, 0, 1     ; ch0: stop at phrase end (t480)
        #EV 490, 5, $13, 0, 0   ; ch0 stopped: starts with ch1 (t492), HFF
        #EV 520, 7, 0, 0, 0     ; song mode: ch1 advances at t576
        #EV 600, 7, 1, 0, 0     ; live again: ch1 loops at t672
        #EV 668, 9, 9, <CH(8,0), >CH(8,0) ; chain 8 now P9: after ch1's
                                ; lookahead (t667), before its prep (t670)
        #EV 700, 8, 0, 0, 0     ; stop all
        #EV 702, 5, $10, 1, 0   ; nothing plays: ch1 starts at once
        #EV 703, 5, $11, 2, 0   ; ch2: with ch1's next step (t708)
        #EV 704, 5, $10, 0, 0   ; ch0: pending (t708) ...
        #EV 705, 6, 0, 0, 0     ; ... cancelled
        .word $ffff
        .byte 0, 0, 0, 0

; ---------------------------------------------------------------------------
; Empty project, as main.asm clear_project
clear_project
        lda #$80
        ldx #$50
        jsr fill_pages
        lda #$e0
        ldx #$1a
        jsr fill_pages
        lda #0
        ldx #0
-       sta TABLES+$200,x
        sta TABLES+$300,x
        sta TABLES+$400,x
        sta TABLES+$500,x
        sta TABLES+$600,x
        sta TABLES+$700,x
        sta TABLES+$800,x
        sta TABLES+$900,x
        sta TABLES+$a00,x
        sta TABLES+$b00,x
        sta GROOVES,x
        sta GROOVES+$100,x
        sta HEADER,x
        sta ALLOC_CHAINS,x
        inx
        bne -
        lda #<PHRASES+PH_CMD
        sta zp_s
        lda #>PHRASES
        sta zp_s+1
-       ldy #0
        tya
        sta (zp_s),y
        iny
        sta (zp_s),y
        lda zp_s
        clc
        adc #4
        sta zp_s
        bcc -
        inc zp_s+1
        lda zp_s+1
        cmp #>CHAINS
        bne -
        lda #<CHAINS+1
        sta zp_s
        lda #>CHAINS
        sta zp_s+1
-       ldy #0
        tya
        sta (zp_s),y
        lda zp_s
        clc
        adc #2
        sta zp_s
        bcc -
        inc zp_s+1
        lda zp_s+1
        cmp #$d0
        bne -
        lda #6
        sta GROOVES
        sta GROOVES+1
        lda #125
        sta HD_TEMPO
        rts

fill_pages
        sta zp_s+1
        lda #0
        sta zp_s
        lda #EMPTY
        ldy #0
-       sta (zp_s),y
        iny
        bne -
        inc zp_s+1
        dex
        bne -
        rts

; song records: address (word), count, bytes. Count 0 ends.
load_song
        lda #<song
        sta zp_s
        lda #>song
        sta zp_s+1
_next   ldy #0
        lda (zp_s),y
        sta zp_d
        iny
        lda (zp_s),y
        sta zp_d+1
        iny
        lda (zp_s),y
        beq _done
        tax
        lda zp_s                ; skip header
        clc
        adc #3
        sta zp_s
        bcc +
        inc zp_s+1
+       ldy #0
-       lda (zp_s),y
        sta (zp_d),y
        iny
        dex
        bne -
        tya
        clc
        adc zp_s
        sta zp_s
        bcc _next
        inc zp_s+1
        bne _next
_done   rts

PH      .function p, s
        .endf PHRASES + p*64 + s*4
CH      .function c, s
        .endf CHAINS + c*32 + s*2
IN      .function i
        .endf INSTR + i*16
SG      .function slot, row
        .endf SONG + slot*256 + row
TB      .function col, t, s
        .endf TABLES + col*512 + t*16 + s

; record: address, then bytes
REC     .segment
        .word \1
        .byte len(\2)
        .byte \2
        .endsegment

C_ = 0
Cs = 1
D_ = 2
Ds = 3
E_ = 4
F_ = 5
G_ = 7
A_ = 9
B_ = 11
N       .function n, o
        .endf n + 12*o
cA = 1
cB = 2
cC = 3
cD = 4
cE = 5
cF = 6
cG = 7
cH = 8
cK = 11
cL = 12
cM = 13
cO = 15
cP = 16
cQ = 17
cR = 18
cS = 19
cT = 20
cV = 22
cW = 23
cX = 24

        .cerror * > RESULTS, "test code overflows RESULTS"

        * = SONGDATA            ; $0810-$0bff: free in this test
song
        ; instruments: flags wave AD SR pwlo pwhi pwspd cut resmode fsweep hr hrsr vib vibdly table tblspd
        #REC IN(0), [$09,$40,$09,$a6,$00,$08,$00,$30,$81,$fe,$00,$00,$00,$00,$ff,$00] ; bass: transpose, filter own
        #REC IN(1), [$01,$40,$09,$a9,$00,$14,$18,$00,$00,$00,$21,$00,$32,$0a,$ff,$00] ; lead: HR 2 mode 1, PW up, vib
        #REC IN(2), [$00,$80,$02,$00,$00,$08,$00,$00,$00,$00,$00,$00,$00,$00,$ff,$00] ; drum: no transpose
        #REC IN(3), [$00,$80,$02,$00,$00,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00] ; table drum: table 0
        ; table 0: $81 / $41 -12 / $41 -24 + H02 (hold)
        #REC TB(0,0,0), [$81, $41, $41]
        #REC TB(1,0,0), [$00, $f4, $e8]
        #REC TB(2,0,2), [cH]
        #REC TB(3,0,2), [$02]
        ; groove 1: 8/4 swing
        #REC GROOVES+16, [8, 4]
        ; phrase 0: bass
        #REC PH(0,0), [N(C_,2), 0, 0, 0]
        #REC PH(0,2), [N(C_,3), $ff, 0, 0]
        #REC PH(0,4), [N(C_,2), $ff, 0, 0]
        #REC PH(0,6), [N(C_,3), $ff, cC, $37]
        #REC PH(0,8), [N(Ds,2), $ff, cP, $10]
        #REC PH(0,10), [N(Ds,2), $ff, 0, 0]
        #REC PH(0,12), [N(F_,2), $ff, cV, $42]
        #REC PH(0,14), [N(G_,2), $ff, cK, $02]
        ; phrase 1: bass, command tour
        #REC PH(1,0), [N(C_,2), 0, 0, 0]
        #REC PH(1,2), [N(C_,3), $ff, cL, $06]
        #REC PH(1,4), [N(G_,2), $ff, cD, $03]
        #REC PH(1,6), [N(C_,2), $ff, cS, $40]
        #REC PH(1,8), [N(C_,2), $ff, cW, $20]
        #REC PH(1,10), [N(C_,2), $ff, cX, $80]
        #REC PH(1,11), [$ff, $ff, cO, $1f]
        #REC PH(1,12), [N(C_,2), $ff, cM, $08]
        #REC PH(1,13), [$ff, $ff, cE, $f0]
        #REC PH(1,14), [N(C_,2), 3, 0, 0]
        #REC PH(1,15), [$ff, $ff, cT, $80]
        ; phrase 2: lead on groove 1, Q03 on step 8
        #REC PH(2,0), [N(G_,4), 1, cG, 1]
        #REC PH(2,2), [N(A_,4), $ff, 0, 0]
        #REC PH(2,4), [N(B_,4), $ff, 0, 0]
        #REC PH(2,6), [N(C_,5), $ff, 0, 0]
        #REC PH(2,8), [N(D_,5), $ff, cQ, $03]
        #REC PH(2,10), [N(C_,5), $ff, 0, 0]
        #REC PH(2,12), [N(B_,4), $ff, 0, 0]
        #REC PH(2,14), [N(A_,4), $ff, 0, 0]
        ; phrase 3: drum, H10 on step 13 (hop back to 0 once)
        #REC PH(3,0), [N(C_,4), 2, 0, 0]
        #REC PH(3,4), [N(C_,4), $ff, 0, 0]
        #REC PH(3,8), [N(C_,4), $ff, 0, 0]
        #REC PH(3,12), [N(C_,4), $ff, 0, 0]
        #REC PH(3,13), [$ff, $ff, cH, $10]
        ; phrase 4: H04 on step 3 -> phrase 5 step 4
        #REC PH(4,0), [N(C_,4), 2, 0, 0]
        #REC PH(4,3), [$ff, $ff, cH, $04]
        ; phrase 5: B00 never, B0F always, HFF stop
        #REC PH(5,4), [N(C_,4), 2, 0, 0]
        #REC PH(5,8), [N(D_,4), $ff, cB, $00]
        #REC PH(5,10), [N(E_,4), $ff, cB, $0f]
        #REC PH(5,12), [$ff, $ff, cH, $ff]
        ; chains
        #REC CH(0,0), [0, 0, 0, 5]
        #REC CH(1,0), [1, 0]
        #REC CH(2,0), [2, 0, 2, 12]
        #REC CH(3,0), [3, 12]
        #REC CH(4,0), [4, 0, 5, 0]
        ; song: ch0 0 0 1, ch1 2 2 2, ch2 3 4
        #REC SG(0,0), [0, 0, 1]
        #REC SG(1,0), [2, 2, 2]
        #REC SG(2,0), [3, 4]
        ; phase 2 (live): notes every 4 steps, groove 0 (6 ticks)
        #REC PH(8,0), [N(C_,4), 2, 0, 0]          ; P8 C-4 drum
        #REC PH(8,4), [N(C_,4), $ff, 0, 0]
        #REC PH(8,8), [N(C_,4), $ff, 0, 0]
        #REC PH(8,12), [N(C_,4), $ff, 0, 0]
        #REC PH(9,0), [N(D_,4), 2, 0, 0]          ; P9 D-4
        #REC PH(9,4), [N(D_,4), $ff, 0, 0]
        #REC PH(9,8), [N(D_,4), $ff, 0, 0]
        #REC PH(9,12), [N(D_,4), $ff, 0, 0]
        #REC PH(12,0), [N(F_,4), 2, 0, 0]         ; P12 F-4
        #REC PH(12,4), [N(F_,4), $ff, 0, 0]
        #REC PH(12,8), [N(F_,4), $ff, 0, 0]
        #REC PH(12,12), [N(F_,4), $ff, 0, 0]
        #REC PH(10,0), [N(E_,4), 1, 0, 0]         ; P10 E-4 lead (HR 2)
        #REC PH(10,4), [N(E_,4), $ff, 0, 0]
        #REC PH(10,8), [N(E_,4), $ff, 0, 0]
        #REC PH(10,12), [N(E_,4), $ff, 0, 0]
        #REC PH(14,2), [N(A_,4), 1, 0, 0]         ; P14 step 0 empty, A-4
        #REC PH(15,0), [N(C_,4), 2, 0, 0]         ; P15 C-4, HFF on step 4
        #REC PH(15,4), [$ff, $ff, cH, $ff]
        #REC CH(11,0), [8, 0, 9, 0]
        #REC CH(12,0), [12, 0]
        #REC CH(10,0), [10, 0]
        #REC CH(14,0), [14, 0]
        #REC CH(8,0), [8, 0]
        #REC CH(15,0), [15, 0]
        ; table scenario (row $20): table t row r transposes 16*(t-1)+r+1
        #REC IN(4), [$00,$40,$09,$a9,$00,$08,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00] ; table 1, every tick
        #REC IN(5), [$00,$40,$09,$a9,$00,$08,$00,$00,$00,$00,$00,$00,$00,$00,$02,$03] ; table 2, 3 ticks a row
        #REC IN(7), [$00,$40,$09,$a9,$00,$08,$00,$00,$00,$00,$00,$00,$00,$00,$ff,$00] ; no table
        #REC TB(1,1,0), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
        #REC TB(1,2,0), [17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]
        #REC TB(2,1,5), [cH, 0, cH]   ; table 1: row 5 H25 (2 hops to 3), row 7 H07 (hold)
        #REC TB(3,1,5), [$23, 0, $07]
        #REC TB(2,2,2), [cH]          ; table 2: row 2 H10 (one hop to 0),
        #REC TB(3,2,2), [$10]         ; row 9 H1B (one hop to 11): two
        #REC TB(2,2,9), [cH]          ; counted rows, all cleared on start
        #REC TB(3,2,9), [$1b]
        #REC PH(20,0), [N(C_,1), 4, 0, 0]         ; ch0: table 1, retriggered
        #REC PH(20,8), [N(C_,1), $ff, 0, 0]
        #REC PH(21,0), [N(C_,1), 5, 0, 0]         ; ch1: table 2 for 96 ticks
        #REC PH(22,0), [N(C_,1), 7, 0, 0]         ; ch2: no table, A02, A02
        #REC PH(22,2), [$ff, $ff, cA, $02]        ; again with row 9's hop
        #REC PH(22,6), [$ff, $ff, cA, $02]        ; counter running (must
        #REC PH(22,9), [$ff, $ff, cA, $20]        ; restart), A20, table 1
        #REC PH(22,10), [N(C_,1), 4, 0, 0]        ; by instrument 4, none by
        #REC PH(22,14), [N(C_,1), 7, 0, 0]        ; instrument 7
        #REC CH(20,0), [20, 0]
        #REC CH(21,0), [21, 0]
        #REC CH(22,0), [22, 0]
        #REC SG(0,$20), [20]
        #REC SG(1,$20), [21]
        #REC SG(2,$20), [22]
        ; step-mode scenario (row $30, ch0): tables 3/4 in step mode
        #REC IN(8), [$00,$40,$09,$a9,$00,$08,$00,$00,$00,$00,$00,$00,$00,$00,$03,$80]
        #REC IN(9), [$00,$40,$09,$a9,$00,$08,$00,$00,$00,$00,$00,$00,$00,$00,$04,$80]
        #REC TB(1,3,0), [33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48]
        #REC TB(1,4,0), [49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64]
        #REC TB(2,3,3), [cH, 0, 0, cH]   ; table 3: row 3 H11 (one hop to 1),
        #REC TB(3,3,3), [$11, 0, 0, $06] ; row 6 H06 (to itself: loop guard)
        #REC GROOVES+48, [1]            ; groove 3: 1 tick per step
        #REC PH(30,0), [N(C_,1), 8, cG, 3]
        #REC PH(30,1), [N(C_,1), $ff, 0, 0, N(C_,1), $ff, 0, 0, N(C_,1), $ff, 0, 0, N(C_,1), $ff, 0, 0, N(C_,1), $ff, 0, 0, N(C_,1), $ff, 0, 0, N(C_,1), $ff, 0, 0, N(C_,1), $ff, 0, 0, N(C_,1), $ff, 0, 0]
        #REC PH(30,10), [N(C_,1), 9, 0, 0, N(C_,1), $ff, 0, 0, $ff, $ff, cA, 3, N(C_,1), 9, 0, 0, N(C_,1), $ff, 0, 0, N(C_,1), 8, 0, 0]
        #REC CH(30,0), [30, 0]
        #REC SG(0,$30), [30]
        #REC SG(0,$10), [11, 12, 8, 15]
        #REC SG(1,$10), [11, 12, 8]
        #REC SG(2,$10), [10, 14, 8]
        .word 0
        .byte 0
        .cerror * > EDITOR_LOW, "song data overflows $0c00"

        * = $0c40               ; phase 3 code (FAKE2 at $0c20, PLAYER_EXT from $0e00)
        .dsection lowtest
        .cerror * > PLAYER_EXT, "phase 3 code overflows into PLAYER_EXT"
