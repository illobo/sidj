; Overlay 0 (OVWIN, REU tiers A/B): the REU half of undo (high.asm). Lives
; in the window between other overlay calls (ov_call fetches it back).
        rts                     ; OV_SNAP: nothing to do at a gesture start
        nop
        nop
        jmp ou_step             ; OV_STEP
        jmp ou_key              ; OV_KEY
        .cerror * != OV_KEY + 3, "undo overlay entry points"

; X pages of the scan
ou_step stx u_cnt
-       lax u_p
        tay
        lda #$93
        jsr reu_page
        and #$20
        beq +
        jsr u_record
+       jsr u_nextp
        bcs _done
        dec u_cnt
        bne -
        rts
_done   lda #0
        sta u_state
        rts

; page u_p differs from its mirror: old bytes (mirror) to slot u_head
u_record
        ldx u_head              ; full: drop the oldest gesture
        inx
        cpx u_base
        bne +
-       inc u_base
        ldx u_base
        jsr meta_get
        bpl -
+       lax u_p
        tay
        lda #$92                ; live <-> mirror: live = old
        jsr reu_page
        inc u_bank
        ldx u_p
        ldy u_head
        lda #$90                ; old -> slot
        jsr reu_page
        dec u_bank
        lax u_p
        tay
        lda #$91                ; mirror (new) -> live
        jsr reu_page
        lda u_p
        and #$7f
        ora u_gs
        ldx u_head
        jsr meta_put
        lda #0
        sta u_gs
        inc u_head
        lda u_head
        sta u_top               ; no redo after a new change
        rts

; u_t = 0 undo, 1 redo: A = 0 nothing to do, else done
ou_key  lda u_t
        bne _redo
        ldx u_head
        cpx u_base
        beq _none
-       dec u_head
        ldx u_head
        jsr u_swap
        ldx u_head
        jsr meta_get
        bpl -
        bmi _done
_redo   ldx u_head
        cpx u_top
        beq _none
-       jsr u_swap
        inc u_head
        ldx u_head
        cpx u_top
        beq _done
        jsr meta_get
        bpl -
_done   lda #1
        rts
_none   lda #0
        rts

; X = slot: swap it with its live page, mirror the result
u_swap  stx u_s
        jsr meta_get
        ora #$80
        sta u_p
        tax
        ldy u_s
        lda #REU_UNDOBANK
        sta u_bank
        lda #$92
        jsr reu_page
        dec u_bank
        lax u_p
        tay
        lda #$90
        jmp reu_page

; X = slot -> A = META[X] (N = gesture start); Y clobbered, X kept
meta_get
        ldy #$bd                ; lda META,x
        .byte $2c
; A -> META[X]
meta_put
        ldy #$9d                ; sta META,x
        sty _op
        php
        sei
        ldy #BANK_ALLRAM
        sty $01
_op     sta META,x
        ldy #BANK_RAMIO
        sty $01
        plp
        ora #0                  ; flags of A
        rts
