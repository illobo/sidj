; Piano / jam mode, beat repeat and the resident part of loop recording.
; Everything here works without an REU;
; the recording itself (quantising, writes, erase, its help-line message)
; is overlay 6 (ov_rec.asm, REU only: without one F6 says "needs reu").
;
; Piano (F4 on the Phrase screen): Z S X D C V G B H N J M and
; Q 2 W 3 E R 5 T 6 Y 7 U are two octaves from pn_oct; + / - shift the
; octave. A key plays on the cursor channel (player_note_on, last
; instrument); typing notes, hex and commands is off meanwhile. The key's
; release gates the note off (not while the channel plays: jam_release,
; high.asm). Beat repeat (any screen): , . / ; held = hold 8 / 4 / 2 / 1
; steps on every channel (pl_hold), read from the matrix. Loop record (F6)
; holds its channel's phrase (pl_hold = 15) while it is armed.
; Memory: lr_stamp lives in EDLOW, jam_release in EDHI, the tables
; br_val at $0c04 (EDITOR_LOW, beside the debug hooks).

KC_PLUS  = $44                  ; + (input.asm kb_codes)
KC_MINUS = $45                  ; -
KC_F4    = KC_F1+1+KC_SHIFTF    ; SHIFT + F3: piano mode
KC_F6    = KC_F1+2+KC_SHIFTF    ; SHIFT + F5: loop record (overlay 6)

; zero page $80-$93 (main context; k_* belong to the raster IRQ)
pn_on   = $80                   ; 1 = piano mode (Phrase screen)
pn_oct  = $81                   ; octave of the lower piano row (0-6)
lr_on   = $82                   ; 15 = loop record armed (= its pl_hold), else 0
lr_chan = $83                   ; channel recorded (and stamped)
lr_note = $84                   ; note played this frame for the overlay, $ff none
jam_pos = $85                   ; matrix position of the key that jams, $ff none
jam_ch  = $86
br_dbg  = $87                   ; tests: beat-repeat keys as bits (b7 , b6 / b4 . b1 ;)
r_pos   = $88                   ; this frame's key (input_poll copies k_*): matrix
r_st    = $89                   ;   position, phrase step, pl_wait, pl_steplen
r_sw    = $8a
r_sl    = $8b
lr_phr  = $8c                   ; overlay 6: phrase recorded into
lr_pend = $8d                   ;   deferred write: step ($ff none), note
lr_pnote = $8e
lr_last = $8f                   ;   step the playhead was on (erase)
k_pos   = $90                   ; IRQ: same order as r_pos..r_sl
k_st    = $91
k_sw    = $92
k_sl    = $93

; main loop, after input_poll: F6, piano keys, recording, holds
loop_frame
        lda hp_on               ; help viewer open: its keys
        bne lp_r
        lda key
        cmp #KC_F6
        bne _nof6
        jsr lp_eat
        lda #OV_DRUMTG          ; arm (overlay 4, X = 3: ov_arm.asm)
        ldx #3
        ldy lr_on
        beq +
        lda #OV_REC             ; stop (overlay 6, X = 1)
        ldx #1
+       jsr ov_call
_nof6   jsr piano_key
        jsr jam_release
        lda lr_on
        beq hold_frame
        ldx #0                  ; every frame while armed
        lda #OV_REC
        jsr ov_call
        ; fall through

; pl_hold per channel: a beat-repeat key on all of them, else lr_on on the
; recorded channel. A change re-runs lookahead (pl_lapend; start_ch clears
; it on a stopped channel), so it acts from the next step on.
hold_frame
        lda kb_mat+5            ; , b7  . b4
        and #$90
        sta tmp
        lda kb_mat+6            ; / b7  ; b2 -> b6 b1
        and #$84
        lsr
        ora tmp
        ora br_dbg
        ldx #8
-       asl
        bcs +
        dex
        bne -
+       lda br_val,x            ; X = 0: none
        sta tmp
        ldx #NCHAN2-1
-       lda tmp
        bne +
        cpx lr_chan
        bne +
        lda lr_on
+       cmp pl_hold,x
        beq +
        sta pl_hold,x
        lda #1
        sta pl_lapend,x
+       dex
        bpl -
lp_r    rts

lp_eat  lda #KC_NONE
        sta key
        rts

piano_key
        lda screen
        cmp #SC_PHRASE
        bne lp_r
        ldx key
        cpx #KC_F4
        bne +
        lda pn_on               ; (the help line follows: H_PIANO)
        eor #1
        sta pn_on
        bpl lp_eat
+       lda pn_on
        beq lp_r
        cpx #KC_PLUS
        bne +
        lda pn_oct
        cmp #6
        bcs lp_eat
        inc pn_oct
        bcc lp_eat
+       cpx #KC_MINUS
        bne +
        lda pn_oct
        beq lp_eat
        dec pn_oct
        bpl lp_eat
+       cpx #36                 ; digits and letters: piano keys or nothing
        bcs lp_r
        txa
        ldx #23
-       cmp pn_keys,x
        beq +
        dex
        bpl -
        bmi lp_eat
+       lda pn_oct              ; note = octave * 12 + key
        asl
        asl
        sta tmp
        asl
        adc tmp
        stx tmp
        adc tmp
        sta lr_note
        ldx cur_chan
        stx jam_ch
        ldy r_pos
        sty jam_pos
        ldy last+FT_INSTR
        jsr player_note_on
        jmp lp_eat

; br_val beside the debug hooks (main.asm puts it at $0c04)
        .section lowtab1
br_val  .byte 0, 0, $10, 0, 0, $13, 0, $11, $17
        .send lowtab1
pn_keys .byte 35, 28, 33, 13, 12, 31, 16, 11, 17, 23, 19, 22   ; Z S X D C V G B H N J M
        .byte 26, 2, 32, 3, 14, 27, 5, 29, 6, 34, 7, 30         ; Q 2 W 3 E R 5 T 6 Y 7 U
