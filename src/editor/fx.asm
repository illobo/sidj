; Live FX panel, rows 18-23, columns 0-19, on every
; screen. One fader per row:
;   18 cut  cutoff        pl_fxcut   FX_CUT     bar, 00-ff
;   19 res  resonance     pl_fxres   FX_RES     bar, 0-f
;   20 flt  filter mode   pl_fxmode  FX_MODE    four switches lp bp hp 3o
;   21 vol  volume        pl_fxvol   FX_VOL     bar, 0-f
;   22 tap  tempo         HD_TEMPO (player_set_tempo, no override bit)
;   23 trn  transpose     pl_fxtransp FX_TRANSP bar, -12..+12
; Row layout: label cols 0-2, bar cols 4-14 (11 cells, 88 pixels), tempo
; nudge '<' '>' cols 15-16, value right-aligned up to col 19.
; Mouse: press/drag on a bar sets the value from the pointer x (absolute)
; and latches it: the value is written first, then its pl_fxmask bit. A
; click on a switch toggles that mode bit (latched). A click on the label
; latches the value shown. Right click, or C= + click, releases (clears the
; bit). Tempo: click "tap" in time = tap tempo, hold '<' / '>' = nudge.
; Shown: latched = label reversed and yellow; not latched = the effective
; value from the player's SID shadow in light blue (transpose 0).
; Redraw: fx_update compares each row's value and latch state with what is
; drawn (d_fxv/d_fxl) every frame and redraws changed rows; RD_ALL redraws
; all (player_init on load/clean clears pl_fxmask, which shows here).

FX_X0      = 4 * 8              ; bar start in pixels
FX_PX      = 88                 ; bar width in pixels
FX_CELLS   = 11
COL_FXON   = 7                  ; yellow: latched
COL_FXOFF  = 14                 ; light blue: following the player

; HK_* kinds of the M5 parts (hit_test, mouse.asm)
HK_FX      = 4                  ; h_val = fader row 0-5
HK_GRID    = 5                  ; grid / list label on the Phrase screen

        .enc "screen"

; carry clear: A = HK_FX, h_val = row (rows 18-23, cols 0-19)
fx_hit
        lda m_row
        cmp #24
        bcs +
        lda m_col
        cmp #20
        bcs +
        lda m_row
        sec
        sbc #18
        sta h_val
        lda #HK_FX
        clc
        rts
+       sec
        rts

; left press on HK_FX / HK_GRID (m_lpress, A = kind)
fx_lpress
        cmp #HK_GRID
        bne +
        lda h_val               ; "drum" label (cols 12-15) or grid/list
        beq drum_view
        jmp grid_view
+       lda #0
        sta fx_part
        ldx h_val
        stx fx_r
        lda btn                 ; C= + click: release
        and #BT_B
        beq +
        jmp fx_free
+       lda m_col
        cmp #3
        bcs _nl
        cpx #4                  ; label: tap tempo, else latch what is shown
        bne +
        jmp fx_tap
+       lda s_fxv,x
        jmp fx_latch
_nl     cmp #4
        bcc _r
        cpx #2
        beq _mode
        cmp #4 + FX_CELLS
        bcs _nudge
        inc fx_part
        bcc fx_bar
_nudge  cpx #4
        bne _r
        ldy #$f8
        cmp #15
        beq +
        cmp #16
        bne _r
        ldy #8
+       sty fx_nudge
_r      rts
_mode   cmp #15
        bcs _r
        sbc #3                  ; carry clear: col - 4
        jsr div3
        lda bitmask,x
        eor s_fxv+2
        ldx #2
        bne fx_latch

; left button held after a press (m_ldrag, m_hit != HK_FIELD)
fx_hdrag
        lda m_hit
        cmp #HK_FX
        bne +
        lda fx_part
        bne fx_bar
+       rts

; value of fader fx_r from the pointer x
fx_bar
        lda m_x
        sec
        sbc #FX_X0
        tay
        lda m_x+1
        sbc #0
        bcc _lo
        bne _hi
        tya
        cmp #FX_PX
        bcc _px
_hi     lda #FX_PX - 1
        bne _px
_lo     lda #0
_px     ldx #188                ; t = px * 188 / 64: 0-255 over the bar
        jsr mul8
        asl m8b
        rol
        asl m8b
        rol
        ldx fx_r
        jsr fx_v
        cpx #4
        bne fx_latch
        cmp HD_TEMPO            ; tempo: like the Project tempo field
        beq +
        sta HD_TEMPO
        jsr player_set_tempo
        jmp fx_projdirty
+       rts

; X = fader, A = value: write the value, then latch (set the mask bit)
fx_latch
        ldy fx_off,x
        sta pl_fxcut,y
        lda fx_bit,x
        ora pl_fxmask
        sta pl_fxmask
        rts

; X = fader: release (clear the mask bit)
fx_free
        lda fx_bit,x
        eor #$ff
        and pl_fxmask
        sta pl_fxmask
        rts

; tap tempo from the panel (tap_tempo stores like the Project tempo field)
fx_tap
        lda screen
        pha
        lda #SC_PROJECT         ; fld_touch then only requests a row redraw
        sta screen
        jsr tap_tempo
        pla
        sta screen
        ; fall through
fx_projdirty                    ; the Project form shows the tempo
        lda screen
        cmp #SC_PROJECT
        bne +
        jmp dirty_list
+       rts

; nudge_watch: X = keyboard nudge -> X = the panel's while its button is held
fx_nudge_x
        lda m_btn
        and #1
        bne +
        sta fx_nudge
        rts
+       lda fx_nudge
        beq +
        tax
+       rts

; hover help (A = HK_FX / HK_GRID): X = help index, carry clear
fx_hover
        ldx #H_GRIDT
        cmp #HK_GRID
        beq +
        lda h_val
        clc
        adc #H_FX
        tax
+       clc
        rts

; X = fader, A = value -> A = t (0-255 along the bar); keeps X
fx_t    cpx #4
        bne +
        sbc #40                 ; tempo byte: BPM - 40 (carry set)
        rts
+       cpx #5
        bne +
        clc                     ; transpose: (v + 12) * 10 + 5
        adc #12
        sta tmp
        asl
        asl
        adc tmp
        asl
        adc #5
        rts
+       cpx #0
        beq +
        and #$0f                ; nibble * 17
        sta tmp
        asl
        asl
        asl
        asl
        ora tmp
+       rts

; X = fader, A = t -> A = value; keeps X
fx_v    cpx #4
        bne +
        clc
        adc #40
        rts
+       cpx #5
        bne +
        ldx #25
        jsr mul8
        ldx #5
        sec
        sbc #12
        rts
+       cpx #0
        beq +
        lsr
        lsr
        lsr
        lsr
+       rts

; A * X -> A = high byte, m8b = low byte
mul8    sta m8a
        stx m8b
        lda #0
        ldx #8
        lsr m8b
-       bcc +
        clc
        adc m8a
+       ror
        ror m8b
        dex
        bne -
        rts

; ---------------------------------------------------------------------------
; Drawing (update, every frame)
fx_update
        bit dirty
        bpl +
        lda #$ff                ; RD_ALL: every row
        ldx #5
-       sta d_fxl,x
        dex
        bpl -
+       jsr fx_sig
        ldx #0
-       lda s_fxv,x
        cmp d_fxv,x
        bne +
        lda s_fxl,x
        cmp d_fxl,x
        beq ++
+       jsr fx_row
+       inx
        cpx #6
        bne -
        rts

; s_fxv/s_fxl: value and latch state of every row
fx_sig
        lda pl_shadow+$16
        sta s_fxv
        lda pl_shadow+$17
        lsr
        lsr
        lsr
        lsr
        sta s_fxv+1
        lda pl_shadow+$18
        and #$0f
        sta s_fxv+3
        lda pl_shadow+$18
        lsr
        lsr
        lsr
        lsr
        sta s_fxv+2
        lda #0
        sta s_fxv+5
        ldx #5
-       lda #0
        sta s_fxl,x
        lda fx_bit,x
        and pl_fxmask
        beq +
        inc s_fxl,x
        ldy fx_off,x
        lda pl_fxcut,y
        sta s_fxv,x
+       dex
        bpl -
        jsr tempo_byte
        sta s_fxv+4
        lda fx_nudge
        sta s_fxl+4
        rts

; X = fader: draw screen row 18 + X; keeps X
fx_row
        stx fx_i
        lda s_fxv,x
        sta d_fxv,x
        lda s_fxl,x
        sta d_fxl,x
        txa
        sbx #256-18             ; X += 18
        jsr gotoxy0
        ldx fx_i
        lda #COL_TEXT
        ldy s_fxl,x
        beq +
        lda #COL_FXON
        ldy #$80
+       sty drev
        sta dcolor
        txa                     ; label: 3 characters
        asl
        adc fx_i
        tax
        lda fx_lbl,x
        jsr putc
        lda fx_lbl+1,x
        jsr putc
        lda fx_lbl+2,x
        jsr putc
        lda #0
        sta drev
        jsr space
        ldx fx_i
        lda #COL_FXOFF
        ldy s_fxl,x
        beq +
        lda #COL_FXON
+       sta fx_c
        cpx #2
        beq _mode
        lda s_fxv,x
        jsr fx_t
        ldx #FX_CELLS + 1
        jsr mul8
        sta tmp2                ; filled cells
        ldx #0
-       lda fx_c
        ldy #$a0
        cpx tmp2
        bcc +
        lda #COL_DIM
        ldy #$40                ; track: horizontal line
+       sta dcolor
        tya
        jsr putc
        inx
        cpx #FX_CELLS
        bne -
        beq _tail
_mode   ldx #0
-       lda s_fxv+2
        and bitmask,x
        beq +
        lda #$80
        ldy fx_c
        bne ++
+       lda #0
        ldy #COL_DIM
+       sta drev
        sty dcolor
        stx fx_r2
        txa
        asl
        tax
        lda fx_mch,x
        jsr putc
        lda fx_mch+1,x
        jsr putc
        ldx fx_r2
        lda #0
        sta drev
        cpx #3
        beq _tail
        jsr space
        inx
        bne -
_tail   ldx fx_i
        cpx #4
        bne _val
        lda #COL_TEXT
        sta dcolor
        ldy #0
        lda fx_nudge
        cmp #$f8
        bne +
        ldy #$80
+       sty drev
        lda #$3c                ; '<'
        jsr putc
        ldy #0
        lda fx_nudge
        cmp #8
        bne +
        ldy #$80
+       sty drev
        lda #$3e                ; '>'
        jsr putc
_val    lda fx_vcol,x
        jsr pad_to
        lda fx_c
        sta dcolor
        lda s_fxv,x
        cpx #4
        bne +
        jsr putbpm
        jmp _end
+       cpx #5
        bne +
        jsr putshex
        jmp _end
+       cpx #0
        bne +
        jsr puthex
        jmp _end
+       jsr putnib
_end    lda #20
        jsr pad_to
        ldx fx_i
        rts

fx_lbl  .text "cutresfltvoltaptrn"
fx_mch  .text "lpbphp3o"
        .enc "none"
fx_bit  .byte FX_CUT, FX_RES, FX_MODE, FX_VOL, 0, FX_TRANSP
fx_off  .byte 0, 1, 2, 3, 0, 4  ; pl_fxcut + off
fx_vcol .byte 18, 19, 19, 19, 17, 17
        .cerror pl_fxtransp != pl_fxcut + 4 || pl_fxmode != pl_fxcut + 2, "pl_fx* order"

; zero page $60-$7f (editor.asm list); no start values needed (RD_ALL at
; start-up invalidates d_fxl)
s_fxv   = $60                   ; [6] value per row
s_fxl   = $66                   ; [6] latch state per row
d_fxv   = $6c                   ; [6] as drawn
d_fxl   = $72                   ; [6]
fx_i    = $78
fx_c    = $79
fx_r    = $7a                   ; fader being dragged
fx_part = $7b                   ; 1 = the press was on its bar
fx_nudge = $7c                  ; panel nudge while '<' / '>' is held
m8a     = $7d
m8b     = $7e
fx_r2   = $7f
