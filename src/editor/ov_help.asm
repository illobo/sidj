; Overlay 5 (OVWIN, REU only): extended help viewer,
; called by ov_call from high.asm (hp_mouse, help_open):
;   X = 0  open: the page for this screen (Phrase in grid or drum view: the
;          grid page), hp_on = 1
;   X = 1  one frame while open: CRSR Up / Down page (wrapping), any other
;          key, button or mouse button closes (hp_on = 0, full redraw)
; A page is HLP_TEXT screen codes for rows 1-17, as many colours and the
; row 24 line (page number and keys, 40 screen codes), at bank 0
; $2100 + n * HLP_STRIDE (SIDJ.HLP, loaded at start-up). Rows 0 and 18-23
; stay as they were.
HV_ROW  = SCREEN + 24*40

        dex
        bpl hv_frame
        ldx screen              ; open
        lda hv_map,x
        tax
        jsr grid_act            ; Phrase screen in grid or drum view: grid page
        beq +
        ldx #HP_GRID
+       cpx hp_n
        bcc +
        ldx #0
+       stx hp_pg
        lda m_btn
        sta hp_mb
        inc hp_on
        bne hv_show

hv_frame
        lda MDBG_COUNT          ; mouse buttons: debug hook, else the driver
        beq _hw
        dec MDBG_COUNT
        ldx MDBG_IDX
        inc MDBG_IDX
        stx tmp
        txa
        asl
        adc tmp
        tax
        lda MDBG_SCRIPT+2,x
        bcc +                   ; carry clear from the adc (was .byte $2c: in_mbtn is absolute)
_hw     lda in_mbtn
+       and #3
        tax
        eor hp_mb               ; newly pressed = changed and down
        stx hp_mb
        stx tmp
        and tmp
        bne hv_close
        lda key
        cmp #KC_NONE
        bne hv_close
        lda press
        beq _r
        ldx hp_pg
        cmp #BT_UP
        beq _up
        cmp #BT_DOWN
        bne hv_close
        inx
        cpx hp_n
        bcc _set
        ldx #0
        beq _set
_up     dex
        bpl _set
        ldx hp_n
        dex
_set    stx hp_pg
        jmp hv_show
_r      rts

hv_close
        dec hp_on
        inc need_clear          ; clean screen, everything redrawn
        lda hp_mb               ; a held button does not count as a new press
        sta m_prev
        lda #$ff
        sta m_hit
        rts

; page hp_pg: text, colours and the row 24 line by DMA
hv_show
        lda hp_pg               ; REU address $2100 + n * $580
        lsr
        sta tmp                 ; n / 2
        lda #0
        ror
        sta rx+2                ; (n & 1) * $80
        lda hp_pg
        asl
        asl
        adc hp_pg
        adc tmp
        adc #REU_HLPPG + 1
        sta rx+3
        ldy #0
        sty rx+4
-       lda hv_dlo,y
        sta rx
        lda hv_dhi,y
        sta rx+1
        lda hv_len,y
        sta rx+5
        lda hv_lenh,y
        sta rx+6
        sty tmp
        lda #$91
        jsr reu_xfer
        ldy tmp
        clc                     ; the next part follows HLP_TEXT bytes on
        lda rx+2
        adc #<HLP_TEXT
        sta rx+2
        lda rx+3
        adc #>HLP_TEXT
        sta rx+3
        iny
        cpy #3
        bne -
        ldx #39
        lda #COL_HELP
-       sta COLORRAM + 24*40,x
        dex
        bpl -
        rts

hv_dlo  .byte <(SCREEN + 40), <(COLORRAM + 40), <HV_ROW
hv_dhi  .byte >(SCREEN + 40), >(COLORRAM + 40), >HV_ROW
hv_len  .byte <HLP_TEXT, <HLP_TEXT, 40
hv_lenh .byte >HLP_TEXT, >HLP_TEXT, 0
        .cerror 2 * HLP_TEXT + 40 > HLP_STRIDE, "help page record"

; help page per screen (SC_* order): Song Chain Phrase Instr Table Groove
; Project SID File; the grid page follows Phrase
HP_GRID = 3
hv_map  .byte 0, 1, 2, 4, 5, 6, 7, 9, 8
        .cerror * - hv_map != NSCREENS, "hv_map: one page per screen"
