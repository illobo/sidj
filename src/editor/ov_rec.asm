; Overlay 6 (OVWIN, REU only): loop record while armed,
; called by ov_call from loop.asm (loop_frame); arming is overlay 7
; (ov_arm.asm, F6 while not armed; without an REU ov_call says "needs reu").
;   X = 1  F6: stop (the deferred note goes in). Also when the channel stops.
;   X = 0  every frame: deferred write, C= erase, the note piano_key played
;          this frame (lr_note), "rec" at the end of the help line.
; Armed: lr_on = 15 = pl_hold of lr_chan (hold_frame), piano mode on, the
; take is one undo step (undo_frame: ora lr_on).
; Quantising: the key's stamp (r_st step, r_sw = pl_wait, r_sl = pl_steplen,
; taken by the raster IRQ or input_poll) gives the ticks into the step,
; e = r_sl - r_sw; 2e > r_sl goes to the next step (by the hold mask), else
; this one. This step is written at once (the player is past it); the next
; one when the playhead reaches it (lr_pend), so the note does not sound
; twice. Notes are stored minus the chain transpose (instrument with
; transpose on; as played if that leaves C-0..B-7), with the last
; instrument; other steps stay (overdub).

lr_ov   dex
        beq lr_f6
        ldx lr_chan             ; --- every frame ---
        lda pl_playing
        and bitmask,x
        beq lr_stop             ; the channel stopped: the take ends
        lda lr_pend
        bmi +
        cmp pl_phrase_step,x
        bne +
        jsr lr_flush            ; the playhead is on the deferred step
        ldx lr_chan
+       lda pl_phrase_step,x    ; C= held: each step entered is erased
        cmp lr_last
        beq +
        sta lr_last
        lda btn
        and #BT_B
        beq +
        lda lr_last
        jsr lr_ptr
        lda #EMPTY
        sta (ptr),y
        iny
        sta (ptr),y
        jsr lr_dirty
+       lda lr_note
        cmp #EMPTY
        beq _msg
        lda r_sl                ; ticks into the step, doubled
        sec
        sbc r_sw
        asl
        cmp r_sl
        lda r_st
        bcc _now
        beq _now
        adc #0                  ; C set: + 1 (the phrase loops: pl_hold 15)
        and #15
        pha
        jsr lr_flush            ; an older deferred note goes in now
        pla
        sta lr_pend
        lda lr_note
        sta lr_pnote
        bcc _done               ; (lr_flush returns C clear)
_now    ldy lr_note
        jsr lr_put
_done   lda #EMPTY
        sta lr_note
_msg    ldx #2                  ; "rec" (redrawn every frame)
-       lda s_lrec,x
        sta SCREEN+24*40+37,x
        dex
        bpl -
        clc
        rts

lr_f6
lr_stop jsr lr_flush
        lda #0
        sta lr_on
        lda #$ff                ; the help line without "rec"
        sta d_help
        clc
        rts

; the deferred note, if any, into its step (C clear afterwards)
lr_flush
        lda lr_pend
        bmi +
        ldy lr_pnote
        jsr lr_put
        lda #EMPTY
        sta lr_pend
+       clc
        rts

; A = step, Y = note: note - chain transpose and the last instrument there
lr_put  sta tmp
        sty tmp2
        lda #0
        sta tmp3
        lda last+FT_INSTR       ; transpose on? (INSTR + i*16, IN_FLAGS b0)
        jsr item16
        sta ptr
        txa
        adc #>INSTR
        sta ptr+1
        ldy #IN_FLAGS
        lda (ptr),y
        lsr
        bcc +
        ldx lr_chan             ; the chain step's transpose
        lda pl_chain,x
        jsr chain_addr
        lda pl_chain_step,x
        asl
        tay
        iny
        lda (ptr),y
        sta tmp3
+       lda tmp2
        sec
        sbc tmp3
        cmp #96                 ; out of range: the note as played
        bcc +
        lda tmp2
+       sta tmp2
        lda tmp
        jsr lr_ptr
        lda tmp2
        sta (ptr),y
        iny
        lda last+FT_INSTR       ; (in use: last[] only holds entered ones)
        sta (ptr),y
lr_dirty
        jmp dirty_list

; A = step -> ptr = phrase lr_phr, Y = step * 4
lr_ptr  pha
        lda lr_phr
        jsr phrase_addr
        pla
        asl
        asl
        tay
        rts

        .enc "screen"
s_lrec  .byte $80|$12, $80|$05, $80|$03   ; "rec" reversed
        .enc "none"
