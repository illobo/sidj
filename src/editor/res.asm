; Resident editor code at RES2 ($0200-$02ff), every tier. Staged by main.asm
; and copied there as the last start-up step (the start-up code runs at
; $0200 until then). Never called during a fileio KERNAL session (which
; saves, clears and restores $0200-$03ff).

; empty history, mirror = data (editor_init, after a load or clean). With an
; REU the header's recovery flag is off while the mirror is rewritten.
undo_reset
        lda #0
        sta u_state
        sta u_head
        sta u_base
        sta u_top
        sta fb_rs
        sta fb_pair
        sta p_ext               ; no extended preset name (high.asm xp_id)
        sta u_bank              ; the mirror is bank 0
        lda u_reu
        beq u_rts
        jsr rh_valid            ; A = 0: not a whole project for a moment
        lda #UPAGE0
        sta u_p
-       lax u_p
        tay
        lda #$90
        jsr reu_page
        jsr u_nextp
        bcc -
        lda #1
        ; fall through
; A -> header RH_VALID (bank 0)
rh_valid
        sta u_t
        ldx #6
-       lda rh_rx,x
        sta rx,x
        dex
        bpl -
        lda #$90
        jmp reu_xfer
rh_rx   .word u_t, RH_VALID
        .byte 0
        .word 1

; u_p = next data page; C set after the last one
u_nextp inc u_p
        lda u_p
        cmp #(>CHAINS) + $10
        bne +
        lda #UPAGE_A
        sta u_p
+       cmp #UPAGE_END
        rts

; Main loop, after input_poll (before the mouse and the grammar act)
undo_frame
        lda MDBG_COUNT          ; buttons of the mouse frame to come
        beq +
        lda MDBG_IDX
        sta u_t
        asl
        adc u_t
        tax
        lda MDBG_SCRIPT+2,x
        and #3
+       ora in_mbtn
        ora lr_on               ; loop record: the whole take is one step
        ora m_prev              ; (a release acts too)
        ora btn
        ora press
        ldx key
        inx                     ; KC_NONE -> 0
        bne _in
        tax
        bne _in
        lda u_state             ; idle
        beq u_rts
        lsr
        bcc +                   ; 2: scanning
        jsr u_begin             ; 1: the gesture ended
+       ldx #SCANSTEP
        bne OV_STEP
_in     lda u_state
        lsr
        bcs u_rts               ; 1: the gesture goes on
        jsr u_settle            ; 2: finish recording the last one
        inc u_state
        jmp OV_SNAP

; record whatever the open gesture changed (u_state -> 0)
u_settle
        lda u_state
        beq u_rts
        lsr
        bcc +
        jsr u_begin
+       ldx #0                  ; all pages
        beq OV_STEP

u_begin lda #2
        sta u_state
        lda #$80                ; = UPAGE0
        sta u_gs                ; the next record starts a gesture
        sta u_p
        .cerror UPAGE0 != $80
u_rts   rts

; ---------------------------------------------------------------------------
; Code overlays: A = overlay id (1-15), X and Y passed on. The
; overlay is fetched from bank 0 page REU_OVPG + id into OVWIN and called;
; afterwards the undo overlay comes back. Returns the overlay's A and C.
; Without an REU: C set, "needs reu" on the help line.
ov_call pha
        lda u_reu
        beq _no
        pla
        stx ov_x
        sty ov_y
        jsr ov_load
        ldx ov_x
        ldy ov_y
        jsr OVWIN
        php
        pha
        lda #OV_UNDO
        jsr ov_load
        pla
        plp
        rts
_no     pla
        lda #<s_nreu
        ldy #>s_nreu
        jsr msg_set
        sec
        rts

; A = overlay id -> OVWIN
ov_load clc
        adc #REU_OVPG
        tay
        ldx #>OVWIN
        lda #0
        sta u_bank
        lda #$91
        jmp reu_page

ov_x    .byte 0
ov_y    .byte 0
