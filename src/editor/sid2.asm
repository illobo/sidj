; 2SID: channel count and the SID SETUP screen.
; Section sid2_main (main editor area): nch_sync, sid_dir; section sid2_fio
; (rarely used, in the slack behind the file I/O module): hit_sid, sid_full. The second SID is
; found at start-up (boot_sid.asm) or set here; the player runs pl_nch
; channels (3, or 6 with pl_sid2 set), channels 4-6 on the second SID.

        .enc "screen"
; Second SID addresses offered on the SID SETUP screen: off, then every
; $20 step of $d420-$d7e0 and $de00-$dfe0 (the C64 Ultimate's choices)

        .section sid2_main      ; main editor area (editor.asm)
; editor state after the channel count changed (start-up, SID SETUP):
; Song cursor columns, cursor channel, full redraw
nch_sync
        ldx pl_nch
        dex
        stx colmax+SC_SONG
        cpx scol
        bcs +
        stx scol
+       cpx cur_chan
        bcs +
        stx cur_chan
+       lda #RD_ALL
        sta dirty
        lda #1
        sta need_clear
        rts

; SPACE + CRSR without a field (edit_dir): on SID SETUP, right/up = next
; second SID address (+$20), left/down = previous. Playback stops (player_init,
; mute and live mode kept).
sid_dir
        lda screen
        cmp #SC_SID
        bne _r
        lda dir_t
        beq _inc
        cmp #3
        beq _inc
        lda pl_sid2+1           ; previous
        bne +
        lda #$e0                ; off -> $dfe0
        ldx #$df
        bne _set
+       lda pl_sid2
        sec
        sbc #$20
        tay
        lda pl_sid2+1
        sbc #0
        tax
        cpx #$dd                ; $dde0 -> $d7e0
        bne +
        ldx #$d7
+       cpx #$d4                ; $d400 -> off
        bne _sety
        cpy #0
        bne _sety
        ldx #0                  ; (y = 0)
        beq _sety
_inc    lda pl_sid2+1           ; next
        bne +
        ldy #$20                ; off -> $d420
        ldx #$d4
        bne _sety
+       lda pl_sid2
        clc
        adc #$20
        tay
        lda pl_sid2+1
        adc #0
        tax
        cpx #$d8                ; $d800 -> $de00
        bne +
        ldx #$de
+       cpx #$e0                ; $e000 -> off
        bne _sety
        ldx #0
        ldy #0
_sety   tya
_set    sta pl_sid2
        stx pl_sid2+1
        lda pl_mute
        pha
        lda pl_live
        pha
        jsr player_init
        pla
        sta pl_live
        pla
        sta pl_mute
        jmp nch_sync
_r      rts
        .send sid2_main

        .section sid2_fio       ; main.asm, after fileio.asm

; mouse: the 2nd SID row is a field (drag = SPACE + CRSR)
hit_sid lda m_row
        cmp #4
        bne +
        lda #HK_FIELD
        sta h_row
        sta h_col
        clc
        rts
+       sec
        rts

; SID SETUP: chip model (start-up), second SID address, channel count
sid_full
        ldx #3
        jsr line_pt
        .null "model   "
        lda sid_model
        asl
        asl
        tax
        lda #4
        sta tmp3
-       lda sid_names,x
        jsr putc
        inx
        dec tmp3
        bne -
        lda #FORM_W
        jsr pad_to
        ldx #4
        jsr line_pt
        .null "2nd sid "
        lda #$80
        sta drev
        lda pl_sid2+1
        bne +
        jsr prt
        .null "off  "
        jmp ++
+       jsr prt
        .null "$"
        lda pl_sid2+1
        jsr puthex
        lda pl_sid2
        jsr puthex
+       lda #FORM_W
        jsr pad_to
        ldx #5
        jsr line_pt
        .null "voices  "
        lda pl_nch
        ora #$30
        jsr putc
        lda #FORM_W
        jsr pad_to
        ldx #7
        jsr line_pd
        .null "spc+crsr:2nd sid"
        lda #FORM_W
        jsr pad_to
        ldx #9
        jsr line_pd
        .text "sidj ", SIDJ_VER
        .byte 0
        lda #FORM_W
        jmp pad_to

sid_names .text "????65818580"
        .send sid2_fio
        .enc "none"
