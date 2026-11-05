; Overlay 3 (OVWIN, REU only): drum lane view of the Phrase screen, drawing.
; Called by ov_call from phr_full / phr_marks (grid.asm)
; after left_setup (item = phrase, xoff = 0): always the whole view (rows
; 12-17 stay blank: the toggle clears the screen). Layout (cols 0-19):
;   row 1      "06-0d" range, reversed "drum" label (cols 12-15), "list"
;   rows 2-9   lane label (instrument, white = cursor lane), then one column
;              per step (cols 3-18): X = hit of this lane, . = none; the
;              cursor cell reversed
;   row 10     "??": steps with a note on an instrument outside the lanes
;   row 11     ^ under the playing step (grid_play)
; g_pd[16] holds the lane per step while drawing: 0-7, 8 = other, $fe none.

        .enc "screen"
dd_draw ldx #1
        jsr line_at
        lda dr_base
        jsr puthex
        lda #$2d
        jsr putc
        lda dr_base
        clc
        adc #7
        jsr puthex
        lda #12
        jsr pad_to
        lda #COL_DIM
        sta dcolor
        jsr prt
        .byte $84, $92, $95, $8d ; reversed "drum"
        .null "list"
        ; lane of each step
        ldx #15
        lda #$fe
-       sta g_pd,x
        dex
        bpl -
        lda item
        cmp #EMPTY
        beq _rows
        jsr phrase_addr
        ldx #15
        ldy #60
-       lda (ptr),y
        cmp #EMPTY
        beq _nx
        iny
        lda (ptr),y
        dey
        sec
        sbc dr_base
        cmp #8
        bcc +
        lda #8
+       sta g_pd,x
_nx     dey
        dey
        dey
        dey
        dex
        bpl -
_rows   lda #0
        sta g_y
_row    ldx g_y
        inx
        inx
        jsr line_at
        ldx g_y
        lda #COL_DIM
        cpx dr_lane
        bne +
        lda #COL_HEAD
+       sta dcolor
        cpx #8
        bcc +
        lda #$3f                ; "??"
        jsr putc
        lda #$3f
        jsr putc
        jmp ++
+       txa
        clc
        adc dr_base
        jsr puthex
+       jsr space
        ldx #0
_cell   stx g_x
        lda #COL_DIM
        sta dcolor
        lda #$57                ; PETSCII 119: empty circle
        ldy g_pd,x
        cpy g_y
        bne +
        lda accent
        sta dcolor
        lda #$51                ; PETSCII 113: filled circle (hit)
+       ldy #0
        cpx prow
        bne +
        ldx g_y
        cpx dr_lane
        bne +
        ldy #$80
+       sty drev
        jsr putc
        ldx g_x
        inx
        cpx #16
        bne _cell
        jsr line_end
        inc g_y
        lda g_y
        cmp #9
        bne _row
        jsr grid_play
        ldx #11
        jsr line_at
        lda #3
        jsr pad_to
        ldx #0
-       stx g_x
        lda #$20
        ldy g_pn,x
        beq +
        lda #$1e                ; up arrow
+       jsr putc
        ldx g_x
        inx
        cpx #16
        bne -
        jsr line_end
        clc
        rts
        .enc "none"
