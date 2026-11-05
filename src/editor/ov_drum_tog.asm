; Overlay 4 (OVWIN, REU only): drum lane view of the Phrase screen,
; called by ov_call from grid.asm:
;   X = 1  drum_view (CLR, KC_DRUM, the reversed "drum" label; Phrase
;          screen, not while marking): grid_on 0/1 -> 2, 2 -> 0. Without an
;          REU ov_call says "needs reu" instead and nothing changes.
;   X = 2  drum_grammar after overlay 2 asked for it: SPACE / click on the
;          cell (prow, dr_lane)
;   X = 3  loop record: F6 arms (loop.asm; the code is ov_arm.asm, M9)

dr_tog  cpx #3                  ; X = 3: loop record, arming (ov_arm.asm)
        beq lr_arm
        dex
        bne dr_hit
        inc need_clear          ; clean screen, everything redrawn
        lda #EMPTY
        sta dr_pnote
        txa                     ; 0: the drum view edits the note column only
        sta pcol
        lda grid_on
        and #2
        eor #2
        sta grid_on
        lda dr_base             ; first entry: the lanes start at cur_instr
        bpl _r
        lda cur_instr
        cmp #NINSTR-7
        bcc +
        lda #NINSTR-8
+       sta dr_base
_r      clc
        rts

; SPACE on (prow, dr_lane): instrument dr_base + lane into the step; an
; empty step gets C-4 (the drum presets are tuned for it). The lane that is
; lit already clears the step (dr_pnote keeps the note: SPACE + Up/Down
; brings it back, overlay 2), so does C= + SPACE. Command and value stay.
dr_hit  jsr field_ptr           ; fp = note of step prow (pcol 0)
        bcs _r
        ldy #EMPTY
        sty dr_pnote
        lda btn
        and #BT_B
        bne _clr
        lda dr_lane
        adc dr_base             ; (C clear)
        ldy #1
        cmp (fp),y
        sta (fp),y
        bne _on
        dey
        lda (fp),y
        cmp #EMPTY
        beq _on2
        sta dr_pnote            ; lit: off
_clr    lda #EMPTY
        ldy #0
        sta (fp),y
        iny
        sta (fp),y
        jmp fld_touch
_on2    iny
        lda (fp),y
_on     ldx #2                  ; instrument used
        jsr alloc_set
        ldy #0
        lda (fp),y
        cmp #EMPTY
        bne +
        lda #$30                ; C-4
        sta (fp),y
+       jsr fld_touch
        jmp prelisten
_r      rts
