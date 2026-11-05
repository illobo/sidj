; Overlay 2 (OVWIN, REU only): drum lane view of the Phrase screen, input.
; Lanes = instruments dr_base..dr_base+7 (grid.asm),
; columns = the 16 steps. Called by ov_call (res.asm) from grid.asm:
;   every frame in the drum view (drum_grammar): CRSR / SPACE presses and a
;   left click act here (C clear); C set = the normal grammar (CTRL or
;   RETURN held/pressed, or no CRSR/SPACE/click). C clear and A = 2: SPACE
;   or a click on a cell, drum_grammar has overlay 4 toggle the hit (after
;   the moves of this frame). pcol stays 0 (note) in the drum view (overlay
;   4 sets it on entry).
; Calls resident code only, never ov_call. Redraw: RD_LIST (overlay 3).

dr_op   = $cd                   ; 2: overlay 4 toggles the hit at the cursor
dr_pnote = $cc                  ; note of the hit SPACE just cleared ($ff none)

dr_in   lda btn
        ora press
        and #BT_SELECT | BT_START
        bne _gram
        sta dr_op
        lda m_pr                ; left press on a lane row
        lsr
        bcc _keys
        lda m_row
        sbc #2                  ; (C set)
        cmp #8
        bcs _keys
        sta dr_lane
        lda m_col
        sbc #2                  ; (C clear: - 3)
        cmp #16
        bcs _dirty              ; lane label: only picks the lane
        sta prow
        bcc _sp                 ; a click acts like SPACE (C= + click: off)
_keys   lda press
        and #BT_DIRS | BT_A
        bne +
_gram   sec
        rts
+       and #BT_A
        beq _dirs
_sp     lda #2                  ; SPACE (C= + SPACE: off): overlay 4
        sta dr_op
_dirs   ldx #3
-       stx g_t
        lda press
        and dir_bits,x
        beq +
        jsr dr_dir
+       ldx g_t
        dex
        bpl -
_dirty  lda #RD_LIST
        ora dirty
        sta dirty
        lda dr_op
        clc
        rts

; X = direction (0 up 1 down 2 left 3 right)
dr_dir  lda btn
        and #BT_A
        beq _nsp
        cpx #2                  ; SPACE + Up/Down: note +-1 semitone
        bcs _r
        lda dr_pnote            ; the SPACE press cleared a hit: back first
        cmp #EMPTY
        beq +
        jsr field_ptr
        lda dr_pnote
        ldy #0
        sta (fp),y
        lda dr_lane
        clc
        adc dr_base
        iny
        sta (fp),y
        lda #EMPTY
        sta dr_pnote
+       txa
        eor #3                  ; up -> right (+1), down -> left (-1)
        tax
        jmp edit_dir
_nsp    lda btn
        and #BT_B
        beq _mv
        cpx #2                  ; C= + Up/Down: lanes one instrument lower/higher
        bcs _r
        ldy #NINSTR-8
        lda dr_base
        jsr _step
        sta dr_base
_r      rts
_mv     ldy #7                  ; CRSR: Up/Down lane 0-7
        lda dr_lane
        cpx #2
        bcs +
        jsr _step
        sta dr_lane
        rts
+       ldy #15                 ; Left/Right step 0-15
        lda prow
        jsr _step
        sta prow
        rts

; A = value, Y = max, X = direction (odd: +1, even: -1) -> A within 0..Y
_step   sty g_t2
        pha
        txa
        lsr
        pla
        bcs +
        beq _s
        sbc #0                  ; (C clear: - 1)
_s      rts
+       cmp g_t2
        bcs _s
        adc #1                  ; (C clear)
        rts
