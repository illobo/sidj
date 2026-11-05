; Screen output: row 0 status, rows 1-17 screen (cols
; 0-19, forms 0-25; Phrase: list or grid, grid.asm) and context panel (the
; rest), rows 18-23 Live FX faders (cols 0-19, fx.asm) and the screen map
; (rows 19-21, cols 21-39), row 24 help. Rows are always written to full
; width, so a redraw needs no clear and does not flicker; the screen is
; cleared only when it changes.
;
; Partial redraw: update runs every frame and compares what is on screen
; (d_* snapshot) with the editor state. It redraws only what differs:
;   whole left part  item number or song scroll changed, or RD_LIST
;   cursor rows      old and new cursor row, or the row on RD_ROW/column move
;   play markers     marker columns only, on RD_MARKS (player moved)
;   panel            the panel's item changed (e.g. chain under the cursor)
;   status / help    their inputs changed (signature compare)
;   Live FX rows     value or latch state changed (fx_update, per row)
; A screen switch (need_clear) sets RD_ALL: everything incl. the map.

MARK = $3e                      ; '>' marks the playing row/step

        .enc "screen"           ; inline strings below are screen codes

; full redraw (kept for tests/perf)
redraw
        lda #RD_ALL
        ora dirty
        sta dirty
        ; fall through

update
        lda need_clear
        beq +
        jsr clear_screen
        lda #0
        sta need_clear
        lda #RD_ALL
        ora dirty
        sta dirty
+       bit dirty
        bpl _part
        lda #RD_LIST | RD_PANEL
        ora dirty
        sta dirty
        lda #$ff
        sta d_help
        sta d_stat
        jsr draw_map
_part   jsr left_setup
        jsr left_sig
        cmp d_item
        bne _left
        lda song_top
        cmp d_top
        bne _left
        lda dirty
        and #RD_LIST
        beq _rows
_left   jsr left_sig
        sta d_item
        lda song_top
        sta d_top
        ldx screen
        lda lfull_lo,x
        ldy lfull_hi,x
        jsr vcall
        jmp _panel
_rows   ldx screen
        lda rowv,x
        cmp d_row
        beq _same
        lda d_row               ; the old cursor row, now unselected
        jsr row_call
        jmp _new
_same   lda dirty
        and #RD_ROW
        bne _new
        ldx screen
        lda colv,x
        cmp d_col
        beq _marks
_new    ldx screen
        lda rowv,x
        jsr row_call
_marks  lda dirty
        and #RD_MARKS
        beq _panel
        jsr left_setup
        ldx screen
        lda lmark_lo,x
        ldy lmark_hi,x
        jsr vcall
_panel  jsr panel_sig
        cmp d_pitem
        bne _pf
        cpx d_paux
        bne _pf
        lda dirty
        and #RD_PANEL
        bne _pf
        lda dirty
        and #RD_MARKS
        beq _stat
        jsr panel_sig
        sta item
        ldx screen
        lda pmark_lo,x
        ldy pmark_hi,x
        jsr vcall
        jmp _stat
_pf     jsr panel_sig
        sta d_pitem
        stx d_paux
        sta item
        ldx screen
        lda panel_lo,x
        ldy panel_hi,x
        jsr vcall
_stat   jsr status_sig
        ldx #NSTAT-1
-       lda s_stat,x
        cmp d_stat,x
        bne _sd
        dex
        bpl -
        bmi _help
_sd     ldx #NSTAT-1
-       lda s_stat,x
        sta d_stat,x
        dex
        bpl -
        jsr draw_status
_help   jsr help_index
        cpx d_help
        beq +
        stx d_help
        jsr draw_help
+       jsr fx_update           ; Live FX panel, rows 18-23 (fx.asm)
        ldx screen
        lda rowv,x
        sta d_row
        lda colv,x
        sta d_col
        lda #0
        sta dirty
        rts

; A/Y = lo/hi of a routine: call it
vcall   sta jv
        sty jv+1
        jmp (jv)

; A = cursor row (rowv terms) of the left part: redraw it
row_call
        pha
        jsr left_setup
        pla
        ldx screen
        ldy lrow_hi,x
        sty jv+1
        ldy lrow_lo,x
        sty jv
        jmp (jv)

;        SONG        CHAIN        PHRASE        INSTR      TABLE        GROOVE        PROJECT    SID      FILE
LFULL = [song_full, chain_full, phr_full, form_full, table_full, groove_full, form_full, sid_full, file_full]
LROW  = [song_rowa, list_rowa, phr_row, form_line, step_rowa, step_rowa, form_line, no_draw, file_rowa]
LMARK = [song_marks, chain_lmarks, phr_marks, no_draw, table_marks, no_draw, no_draw, no_draw, no_draw]
PANEL = [song_panel, chain_panel, phrase_panel, instr_panel, table_panel, groove_panel, proj_panel, no_draw, file_panel]
PMARK = [chain_pmarks, phrase_pmarks, no_draw, no_draw, no_draw, no_draw, no_draw, no_draw, no_draw]
        .cerror len(LFULL) != NSCREENS || len(PMARK) != NSCREENS, "screen tables"

lfull_lo .byte <LFULL
lfull_hi .byte >LFULL
lrow_lo  .byte <LROW
lrow_hi  .byte >LROW
lmark_lo .byte <LMARK
lmark_hi .byte >LMARK
panel_lo .byte <PANEL
panel_hi .byte >PANEL
pmark_lo .byte <PMARK
pmark_hi .byte >PMARK

no_draw rts

; Context of the left part: xoff 0, accent = context channel colour,
; item = shown item, lrow = cursor step, curf = cursor field
left_setup
        lda #0
        sta xoff
        ldx cur_chan
        lda chan_col,x
        sta accent
        jsr left_sig
        sta item
        ldx screen
        lda colv,x
        sta curf
        lda rowv,x
        cpx #SC_TABLE
        bcc +
        sbc #1                  ; Table/Groove: row 0 is the title (carry set)
+       sta lrow
        cpx #SC_INSTR
        beq +
        cpx #SC_PROJECT
        bne ++
+       jmp form_setup
+       rts

; A = item shown on the left: chain, phrase, instrument, table, groove
left_sig
        ldx screen
        cpx #SC_FILE
        bne +
        lda file_top            ; File: the list scrolls
        rts
+       cpx #0
        beq +
        cpx #SC_GROOVE+1
        bcs +
        lda cur_chain-1,x
        rts
+       lda #0
        rts

; A = item of the panel, X = extra (colour channel on Song)
panel_sig
        lda screen
        bne _ch
        jsr song_cell
        ldx scol
        rts
_ch     ldx #0
        cmp #SC_CHAIN
        bne _ph
        lda cur_chain
        bmi +
        jsr chain_cell
        ldx #0
+       rts
_ph     cmp #SC_PHRASE
        bne _in
        jsr phrase_instr
        ldx #0
        rts
_in     cmp #SC_INSTR
        bne _tb
        jsr instr_fix
        ldy #IN_TABLE
        lda (ptr),y
        ldx #0
        rts
_tb     cmp #SC_TABLE
        bne _gr
        lda cur_instr
        rts
_gr     cmp #SC_GROOVE
        bne +
        lda cur_groove
        rts
+       cmp #SC_FILE
        bne +
        lda fcount
        rts
+       lda #0
        rts

; status line inputs -> s_stat
NSTAT = 8
status_sig
        lda screen
        sta s_stat
        jsr left_sig
        sta s_stat+1
        jsr cursor_chan
        stx s_stat+2
        jsr tempo_byte
        sta s_stat+3
        lda pl_playing
        sta s_stat+4
        lda pl_mute
        sta s_stat+5
        jsr title_sel
        sta s_stat+6
        lda pl_live
        sta s_stat+7
        rts

; A = $80 if the cursor is on the title number (Instr/Table/Groove row 0)
title_sel
        ldx screen
        cpx #SC_INSTR
        bcc +
        cpx #SC_GROOVE+1
        bcs +
        lda rowv,x
        bne +
        lda #$80
        rts
+       lda #0
        rts

; ---------------------------------------------------------------------------
; Primitives. putc and friends keep X; Y is free for callers only between
; calls. Colour RAM row = screen row + (COLORRAM - SCREEN).

; X = row: start a line at (row, xoff) in the default text colour;
; line_atc: in colour A; line_0c: at column 0 in colour A
line_at lda #COL_TEXT
line_atc ldy xoff
        .byte $2c               ; skip the ldy #0
line_0c ldy #0
        sta dcolor
        lda #0
        sta drev
        .byte $2c               ; skip the ldy #0
gotoxy0 ldy #0                  ; X = row, column 0

; X = row, Y = column
gotoxy  sty dx
        lda row_lo,x
        sta dp
        sta cp
        lda row_hi,x
        sta dp+1
        clc
        adc #>(COLORRAM - SCREEN)
        sta cp+1
        rts

; A = screen code -> (dx), reversed if drev = $80
putc    ora drev
        ldy dx
        sta (dp),y
        lda dcolor
        sta (cp),y
        inc dx
        rts

space   lda #$20
        bne putc

; A = byte as two hex digits
puthex  pha
        lsr
        lsr
        lsr
        lsr
        jsr putnib
        pla
putnib  and #$0f
        tay
        lda hexdig,y
        jmp putc

; A = byte, $ff shows as "--"
puthex_e
        cmp #EMPTY
        bne puthex
dash2   lda #$2d
        jsr putc
        lda #$2d
        bne putc

; A = note, $ff shows as "---"; else C-3 / D#4
putnote cmp #EMPTY
        bne +
        lda #$2d
        jsr putc
        jmp dash2
+       stx tmp3
        jsr div12
        tax
        lda note_l,x
        jsr putc
        lda note_s,x
        jsr putc
        lda tmp
        ora #$30
        jsr putc
        ldx tmp3
        rts

; spaces up to (excluding) column A; a space needs no colour. Clears drev.
pad_to  sta tmp3
        lda #0
        sta drev
        ldy dx
        lda #$20
-       cpy tmp3
        bcs +
        sta (dp),y
        iny
        bne -
+       sty dx
        rts

; A/Y = lo/hi of a 0-terminated string
putstr  sta ptr
        sty ptr+1
        lda #0
        sta sidx
-       ldy sidx
        lda (ptr),y
        beq +
        jsr putc
        inc sidx
        bne -
+       rts

; jsr prt / .null "text": prints the inline string, returns after it
prt     pla
        sta ptr
        pla
        sta ptr+1
-       inc ptr
        bne +
        inc ptr+1
+       ldy #0
        lda (ptr),y
        beq +
        jsr putc
        jmp -
+       lda ptr+1
        pha
        lda ptr
        pha
        rts

; X = field index: drev = rowsel if it is the cursor field, $80 if it lies
; in the marked block (msel set for this row), else 0
sel_field
        lda #0
        cpx curf
        bne +
        lda rowsel
+       bit msel
        bpl _st
        cpx mc0
        bcc _st
        cpx mc1
        beq _in
        bcs _st
_in     lda #$80
_st     sta drev
        rts

; line_at, then prt: the string follows the jsr (COL_HEAD, COL_DIM, COL_TEXT)
line_ph lda #COL_HEAD
        .byte $2c               ; skip the next lda #
line_pd lda #COL_DIM
        .byte $2c
line_pt lda #COL_TEXT
        jsr line_atc
        jmp prt

; finish a line at xoff + 20 (at most column 40)
line_end
        lda xoff
        clc
        adc #20
        cmp #41
        bcc +
        lda #40
+       jmp pad_to

clear_screen
        ldx #0
-       lda #$20
        sta SCREEN,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$2e8,x
        lda #COL_TEXT
        sta COLORRAM,x
        sta COLORRAM+$100,x
        sta COLORRAM+$200,x
        sta COLORRAM+$2e8,x
        inx
        bne -
        rts

; ---------------------------------------------------------------------------
; Row 0: "PHRASE 0A   C1  125BPM  P:1--  M:-2-   SIDJ"
draw_status
        ldx #0
        lda #COL_HEAD
        jsr line_0c
        ldx screen
        lda scr_name_lo,x
        ldy scr_name_hi,x
        jsr putstr
        lda screen
        bne +
        lda pl_live
        beq +
        jsr prt
        .null " live"
+       jsr left_sig
        ldx screen
        beq _nonum
        cpx #SC_GROOVE+1
        bcs _nonum
        pha
        jsr space
        jsr title_sel
        sta drev
        pla
        jsr puthex_e
        lda #0
        sta drev
_nonum  lda #12
        jsr pad_to
        jsr cursor_chan         ; channel under the cursor
        lda chan_col,x
        sta dcolor
        lda #3                  ; 'c'
        jsr putc
        txa
        clc
        adc #$31
        jsr putc
        lda #16
        jsr pad_to
        lda #COL_TEXT
        sta dcolor
        jsr tempo_byte
        jsr putbpm
        jsr prt
        .null "bpm"
        lda #23
        jsr pad_to
        jsr prt
        .null "p:"
        lda pl_playing
        jsr chan_flags
        lda #COL_TEXT
        sta dcolor
        jsr prt
        .null " m:"
        lda pl_mute
        jsr chan_flags
        lda pl_nch              ; 2SID: six flags each, no room for the name
        cmp #NCHAN2
        beq +
        lda #36
        jsr pad_to
        lda #COL_DIM
        sta dcolor
        jsr prt
        .null "sidj"
+       rts

; A = channel bits: digit in channel colour if set, else '-'
chan_flags
        sta tmp2
        ldx #0
-       lda chan_col,x
        sta dcolor
        lsr tmp2
        lda #$2d
        bcc +
        txa
        adc #$30                ; carry set: +$31
+       jsr putc
        inx
        cpx pl_nch
        bne -
        rts

; tempo shown: the player's while it plays (if set), else the project's
tempo_byte
        lda pl_playing
        beq +
        lda pl_tempo
        bne ++
+       lda HD_TEMPO
+       rts

; A = tempo byte ($00-$27 = 256-295) as 3 decimal digits
putbpm  ldx #0
        cmp #$28
        bcs +
        inx
+       sta tmp
        stx tmp2
        ldx #0
-       lda tmp                 ; hundreds by subtraction
        sec
        sbc #100
        tay
        lda tmp2
        sbc #0
        bcc +
        sta tmp2
        sty tmp
        inx
        bne -
+       txa
        ora #$30
        jsr putc
        ldx #0
-       lda tmp
        cmp #10
        bcc +
        sbc #10
        sta tmp
        inx
        bne -
+       txa
        ora #$30
        jsr putc
        lda tmp
        ora #$30
        jmp putc

; ---------------------------------------------------------------------------
; Song: row 1 channel numbers, rows 2-17 sixteen song rows "RR>CC>CC>CC"
song_full
        ldx #1
        jsr gotoxy0
        lda #0
        sta drev
        jsr space
        jsr space
        ldx #0
-       lda chan_col,x
        sta dcolor
        jsr head_mark
        jsr putc
        txa
        clc
        adc #$31
        jsr putc
        jsr space
        inx
        cpx pl_nch
        bne -
        lda #20
        jsr pad_to
        lda #0
        sta step
-       jsr song_row
        inc step
        lda step
        cmp #SONG_ROWS
        bne -
        rts

; A = song row: redraw it if visible
song_rowa
        sec
        sbc song_top
        cmp #SONG_ROWS
        bcs +
        sta step
        bcc song_row
+       rts

; song row song_top + step at screen row step + 2
song_row
        lda step
        clc
        adc #2
        tax
        jsr gotoxy0
        lda song_top
        clc
        adc step
        sta item
        ldx #0
        cmp srow
        bne +
        ldx #$80
+       stx rowsel
        jsr mark_msel
        lda #0
        sta drev
        lda item                ; every 4th row brighter
        and #3
        beq +
        lda #COL_DIM
        .byte $2c               ; skip the next lda #
+       lda #COL_TEXT
        sta dcolor
        lda item                ; bookmarked rows: number in yellow
        jsr bm_test
        beq +
        lda #COL_BOOK
        sta dcolor
+
        lda item
        jsr puthex
        lda item
        sta ptr2
        ldx #0
_ch     lda chan_col,x
        sta dcolor
        lda #0
        sta drev
        jsr song_mark
        jsr putc
        jsr sel_field
        jsr cell_col
        sta dcolor
        txa
        clc
        adc #>SONG
        sta ptr2+1
        ldy #0
        lda (ptr2),y
        jsr puthex_e
        inx
        cpx pl_nch
        bne _ch
        lda #20
        jmp pad_to

; A = '*' if channel X has song row item queued (blinking), '>' if it
; plays it, else space
song_mark
        lda blink
        beq _play
        lda pl_queue,x
        cmp #$fe
        bcs _play
        cmp item
        bne _play
        lda #$2a
        rts
_play   lda pl_playing
        and bitmask,x
        beq +
        lda pl_row,x
        cmp item
        bne +
        lda #MARK
        rts
+       lda #$20
        rts

; marker columns of the 16 song rows
song_marks
        lda #0
        sta drev
        ldx #1                  ; header: queued stops
        ldy #2
        jsr gotoxy
        ldx #0
-       lda chan_col,x
        sta dcolor
        jsr head_mark
        jsr putc
        inc dx
        inc dx
        inx
        cpx pl_nch
        bne -
        lda #0
        sta step
-       lda step
        clc
        adc #2
        tax
        ldy #2
        jsr gotoxy
        lda song_top
        clc
        adc step
        sta item
        ldx #0
_ch     lda chan_col,x
        sta dcolor
        jsr song_mark
        jsr putc
        jsr cell_col            ; live: playing cell colour
        ldy dx
        sta (cp),y
        iny
        sta (cp),y
        iny
        sty dx
        inx
        cpx pl_nch
        bne _ch
        inc step
        lda step
        cmp #SONG_ROWS
        bne -
        rts

; A = channel X header mark: 'X' while a stop is queued (blinking)
head_mark
        lda blink
        beq +
        lda pl_queue,x
        cmp #$fe
        bne +
        lda #$18
        rts
+       lda #$20
        rts

; A = colour of channel X's cell in song row item: white for the playing
; chain in live mode, else the channel colour
cell_col
        lda pl_live
        beq +
        lda pl_playing
        and bitmask,x
        beq +
        lda pl_row,x
        cmp item
        bne +
        lda #COL_HEAD
        rts
+       lda chan_col,x
        rts

; panel: the chain under the cursor (item = panel_sig)
song_panel
        lda #20
        sta xoff
        ldx scol
        lda chan_col,x
        sta accent
        jsr chain_head
        lda #$ff
        sta lrow
        jmp draw_chain_list

; row 1 at xoff: "CHAIN 03"
chain_head
        ldx #1
        jsr line_ph
        .null "chain "
        lda item
        jsr puthex_e
        jmp line_end

; row 1 at xoff: "PHRASE 0A"
phrase_head
        ldx #1
        jsr line_ph
        .null "phrase "
        lda item
        jsr puthex_e
        jmp line_end

; ---------------------------------------------------------------------------
; Chain screen: list left, phrase under the cursor in the panel
chain_full
        ldx #1
        jsr line_pd
        .null "  ph tr"
        jsr line_end
        jmp draw_chain_list

chain_panel
        lda #20
        sta xoff
        lda #$ff
        sta lrow
        jsr phrase_head
        jmp draw_phrase_list

; Phrase screen: list left, instrument under the cursor in the panel
phrase_full
        ldx #1
        jsr line_pd
        .text "  nte in cmd"
        .byte $84, $92, $95, $8d ; reversed "drum": drum view label (grid.asm)
        .null "grid"
        jsr line_end
        jmp draw_phrase_list

phrase_panel
        lda #20
        sta xoff
        jmp draw_instr

; A = step of a list (Chain/Phrase): redraw it
list_rowa
        sta step
        lda screen
        cmp #SC_CHAIN
        bne +
        jmp chain_row
+       jmp phrase_row

; marker columns of a list at xoff (item set)
chain_lmarks
        lda #<chain_mark
        ldy #>chain_mark
        bne list_marks
phrase_lmarks
        lda #<phrase_mark
        ldy #>phrase_mark
list_marks
        sta lm_v
        sty lm_v+1
        lda #0
        sta drev
        sta step
-       lda step
        clc
        adc #2
        tax
        ldy xoff
        iny
        jsr gotoxy
        jsr _call
        inc step
        lda step
        cmp #16
        bne -
        rts
_call   jmp (lm_v)

; panel list marks (item = panel item)
chain_pmarks                    ; Song panel: a chain
        lda #20
        sta xoff
        bne chain_lmarks
phrase_pmarks                   ; Chain panel: a phrase
        lda #20
        sta xoff
        bne phrase_lmarks

; rowsel for the current step of a list
list_rowsel
        ldx #0
        lda step
        cmp lrow
        bne +
        ldx #$80
+       stx rowsel
        lda step                ; rowv terms: Table row 0 is the title
        ldx screen
        cpx #SC_TABLE
        bne +
        clc
        adc #1
+       jmp mark_msel

; "S" step digit at (step+2, xoff)
list_start
        lda step
        clc
        adc #2
        tax
        ldy xoff
        jsr gotoxy
        jsr list_rowsel
        lda #0
        sta drev
        lda #COL_DIM
        sta dcolor
        ldx step
        lda hexdig,x
        jmp putc

; Chain item at xoff, 16 steps "S>PP TT"
draw_chain_list
        lda #0
        sta step
-       jsr chain_row
        inc step
        lda step
        cmp #16
        bne -
        rts

chain_row
        jsr list_start
        jsr chain_mark
        lda item
        bmi _empty
        jsr chain_addr
        lda step
        asl
        ora ptr
        sta ptr2
        lda ptr+1
        sta ptr2+1
        lda accent
        sta dcolor
        ldx #0
        jsr sel_field
        ldy #0
        lda (ptr2),y
        jsr puthex_e
        lda #0
        sta drev
        jsr space
        ldx #1
        jsr sel_field
        ldy #1
        lda (ptr2),y
        jsr puthex
        jmp _pad
_empty  jsr dash2
        jsr space
        jsr dash2
_pad    jmp line_end

; Phrase item at xoff, 16 steps "S>NNN II CVV"
draw_phrase_list
        lda #0
        sta step
-       jsr phrase_row
        inc step
        lda step
        cmp #16
        bne -
        rts

phrase_row
        jsr list_start
        jsr phrase_mark
        lda item
        cmp #EMPTY
        beq _empty
        jsr phrase_addr
        lda step
        asl
        asl
        ora ptr
        sta ptr2
        lda ptr+1
        sta ptr2+1
        lda accent
        sta dcolor
        ldx #0
        jsr sel_field
        ldy #PH_NOTE
        lda (ptr2),y
        jsr putnote
        lda #0
        sta drev
        jsr space
        ldx #1
        jsr sel_field
        ldy #PH_INSTR
        lda (ptr2),y
        jsr puthex_e
        lda #0
        sta drev
        jsr space
        ldx #2
        jsr sel_field
        ldy #PH_CMD
        lda (ptr2),y
        bne +
        lda #$2d
+       jsr putc                ; command 1-26 = screen code of A-Z
        ldx #3
        jsr sel_field
        ldy #PH_CMD
        lda (ptr2),y
        beq +
        iny                     ; PH_VAL
        .cerror PH_VAL != PH_CMD + 1
        lda (ptr2),y
        jsr puthex
        jmp _pad
+       jsr dash2
        jmp _pad
_empty  lda #$2d
        jsr putc
        jsr dash2
        jsr space
        jsr dash2
        jsr space
        lda #$2d
        jsr putc
        jsr dash2
_pad    jmp line_end

; marker column: '>' in the colour of a channel playing item at step
chain_mark
        ldx #0
-       lda pl_playing
        and bitmask,x
        beq +
        lda pl_chain,x
        cmp item
        bne +
        lda pl_chain_step,x
        cmp step
        beq put_mark
+       inx
        cpx pl_nch
        bne -
        jmp space
put_mark
        lda chan_col,x
        sta dcolor
        lda #MARK
        jmp putc

phrase_mark
        ldx #0
-       lda pl_playing
        and bitmask,x
        beq +
        lda pl_phrase,x
        cmp item
        bne +
        lda pl_phrase_step,x
        cmp step
        beq put_mark
+       inx
        cpx pl_nch
        bne -
        jmp space

; ---------------------------------------------------------------------------
; Table screen: row 1 labels, rows 2-17 steps "S CC +TT CVV CVV"
table_full
        ldx #1
        jsr line_pd
        .null "  ct tr  cmd cmd"
        jsr line_end
        lda #0
        sta step
-       jsr table_row
        inc step
        lda step
        cmp #16
        bne -
        rts

; A = cursor row (Table/Groove): row 0 is the title (status line)
step_rowa
        sec
        sbc #1
        bcc +
        sta step
        lda screen
        cmp #SC_TABLE
        beq table_row
        jmp groove_row
+       rts

table_row
        jsr list_start
        jsr table_mark
        lda accent
        sta dcolor
        jsr table_cells
        jmp line_end

; '>' in the channel colour if a playing channel runs table item at step
table_mark
        ldx #NCHAN2-1
-       lda pl_playing
        and bitmask,x
        beq +
        lda pl_tbl,x
        cmp item
        bne +
        lda pl_tblstep,x
        cmp step
        bne +
        lda chan_col,x
        sta dcolor
        lda #MARK
        jmp putc
+       dex
        bpl -
        jmp space

; marker column of the 16 table rows (RD_MARKS)
table_marks
        lda #0
        sta step
-       lda step
        clc
        adc #2
        tax
        ldy #1
        jsr gotoxy
        lda #0
        sta drev
        jsr table_mark
        inc step
        lda step
        cmp #16
        bne -
        rts

; cells of table item, step: "CC +TT CVV CVV" (14 chars) at dx
table_cells
        lda item
        jsr item16
        ora step
        sta ptr2
        txa
        clc
        adc #>TABLES
        sta ptr2+1
        ldx #0
        jsr sel_field
        ldy #0
        lda (ptr2),y
        jsr puthex_e
        lda #0
        sta drev
        jsr space
        jsr _nextc
        ldx #1
        jsr sel_field
        lda (ptr2),y
        jsr putshex
        lda #0
        sta drev
        lda #2
        sta tc_col
-       jsr space
        jsr _nextc
        ldx tc_col
        jsr sel_field
        lda (ptr2),y
        sta tc_cmd
        bne +
        lda #$2d
+       jsr putc
        jsr _nextc
        inc tc_col
        ldx tc_col
        jsr sel_field
        lda tc_cmd
        beq +
        lda (ptr2),y
        jsr puthex
        jmp ++
+       jsr dash2
+       lda #0
        sta drev
        inc tc_col
        lda tc_col
        cmp #6
        bne -
        rts
_nextc  inc ptr2+1              ; next column: +512
        inc ptr2+1
        ldy #0
        rts

; ---------------------------------------------------------------------------
; Groove screen: row 1 label, rows 2-17 ticks per step, 0 = end "--"
groove_full
        ldx #1
        jsr line_pd
        .null "  tk"
        jsr line_end
        lda #0
        sta step
-       jsr groove_row
        inc step
        lda step
        cmp #16
        bne -
        rts

groove_row
        jsr list_start
        jsr space
        lda accent
        sta dcolor
        jsr groove_ptr
        ldx #0
        jsr sel_field
        ldy step
        lda (ptr2),y
        bne +
        jsr dash2
        jmp line_end
+       jsr puthex
        jmp line_end

; ptr2 = GROOVES + item*16
groove_ptr
        lda item
        jsr item16
        sta ptr2
        txa
        adc #>GROOVES           ; carry clear from item16
        sta ptr2+1
        rts

; panel: length and ticks of the groove
groove_panel
        lda #20
        sta xoff
        ldx #1
        jsr line_ph
        .null "groove "
        lda item
        jsr puthex
        jsr line_end
        jsr groove_ptr
        ldy #0                  ; steps until the end mark, tick sum
        sty g_lo
        sty g_hi
_sum    lda (ptr2),y
        beq _end
        clc
        adc g_lo
        sta g_lo
        bcc +
        inc g_hi
+       iny
        cpy #16
        bne _sum
_end    sty step
        ldx #2
        jsr line_pt
        .null "steps "
        lda step
        jsr puthex
        jsr line_end
        ldx #3
        jsr line_pt
        .null "ticks "
        lda g_hi
        jsr putnib
        lda g_lo
        jsr puthex
        jsr line_end
        ldx #4
        jsr line_at
        jsr line_end
        ldx #5
        jsr line_pd
        .null "-- ends: loop to 0"
        jsr line_end
        ldx #6
        jsr line_pd
        .null "gxx in a phrase"
        jsr line_end
        ldx #7
        jsr line_pd
        .null "selects a groove"
        jsr line_end
        lda #8
        ; fall through

; rows A-17 at xoff: blank
blank_rows
        sta step
-       ldx step
        jsr line_at
        jsr line_end
        inc step
        lda step
        cmp #18
        bne -
        rts

; Table screen panel: the instrument summary of cur_instr
table_panel
        lda #20
        sta xoff
        jmp draw_instr

; Instrument screen panel (cols 26-39): the instrument's table
instr_panel
        lda #FORM_W
        sta xoff
        ldx #1
        jsr line_ph
        .null "table "
        lda item
        jsr puthex_e
        jsr line_end
        lda item
        cmp #NTABLES
        bcc +
        lda #2
        bne blank_rows
+       lda #0
        sta step
        sta rowsel
        lda #$ff
        sta curf
-       lda step
        clc
        adc #2
        tax
        jsr line_at
        lda accent
        sta dcolor
        jsr table_cells
        jsr line_end
        inc step
        lda step
        cmp #16
        bne -
        rts

; Project screen panel (cols 26-39): allocation counts
proj_panel
        lda #FORM_W
        sta xoff
        ldx #1
        jsr line_ph
        .null "in use"
        jsr line_end
        lda #0
        sta step
_item   lda step
        clc
        adc #2
        tax
        jsr line_at
        ldx step
        lda pj_lo,x
        ldy pj_hi,x
        jsr putstr
        ldx step                ; count set bits
        lda pj_off,x
        tay
        lda pj_len,x
        sta tmp3
        lda #0
        sta tmp2
_byte   lda ALLOC_CHAINS,y
        beq _nb
-       asl
        bcc +
        inc tmp2
+       ora #0
        bne -
_nb     iny
        dec tmp3
        bne _byte
        lda tmp2
        jsr puthex
        lda #$2f                ; '/'
        jsr putc
        ldx step
        lda pj_max,x
        jsr puthex
        jsr line_end
        inc step
        lda step
        cmp #4
        bne _item
        lda #6
        jmp blank_rows

pj_s0   .null "chains  "
pj_s1   .null "phrases "
pj_s2   .null "instrs  "
pj_s3   .null "tables  "
pj_lo   .byte <pj_s0, <pj_s1, <pj_s2, <pj_s3
pj_hi   .byte >pj_s0, >pj_s1, >pj_s2, >pj_s3
pj_off  .byte 0, ALLOC_PHRASES-ALLOC_CHAINS, ALLOC_INSTR-ALLOC_CHAINS, ALLOC_TABLES-ALLOC_CHAINS
pj_len  .byte 16, 32, 8, 4
pj_max  .byte NCHAINS, NPHRASES, NINSTR, NTABLES
; SID setup screen (sid_full): sid2.asm (EDHI)

; ---------------------------------------------------------------------------
; Instrument summary of item at xoff, rows 1-17
draw_instr
        ldx #1
        jsr line_ph
        .null "instr "
        lda item
        jsr puthex_e
        jsr line_end
        lda #2
        sta step
        lda item
        cmp #NINSTR
        bcc +
        jmp _blank
+       asl                     ; ptr2 = INSTR + item*16
        asl
        asl
        asl
        sta ptr2
        lda item
        lsr
        lsr
        lsr
        lsr
        clc
        adc #>INSTR
        sta ptr2+1
        ; WAVE TSPN RS
        ldx #2
        jsr line_pt
        .null "wave  "
        ldy #IN_WAVE
        lda (ptr2),y
        sta tmp2
        lsr
        lsr
        lsr
        lsr
        ldx #S_WAVE
        jsr bit_letters
        jsr space
        lda tmp2
        lsr
        and #3                  ; bit 1 sync, bit 2 ring
        ldx #S_RS
        jsr bit_letters2
        jsr line_end
        ; AD 0A  SR F8
        ldx #3
        jsr line_pt
        .null "ad "
        ldy #IN_AD
        jsr _hexy
        jsr prt
        .null "  sr "
        ldy #IN_SR
        jsr _hexy
        jsr line_end
        ; PW 0800 UP   10
        ldx #4
        jsr line_pt
        .null "pw "
        ldy #IN_PWHI
        lda (ptr2),y
        jsr putnib
        ldy #IN_PWLO
        jsr _hexy
        jsr space
        ldy #IN_PWHI
        lda (ptr2),y
        lsr
        lsr
        lsr
        lsr
        and #3
        jsr put_name
        jsr space
        ldy #IN_PWSPD
        jsr _hexy
        jsr line_end
        ; FILT OWN LB.. RES 8
        ldx #5
        jsr line_pt
        .null "filt "
        ldy #IN_FLAGS
        lda (ptr2),y
        lsr
        lsr
        and #3
        clc
        adc #4
        jsr put_name
        ldy #IN_RESMODE
        lda (ptr2),y
        ldx #S_LBH3
        jsr bit_letters
        jsr prt
        .null " res "
        ldy #IN_RESMODE
        lda (ptr2),y
        lsr
        lsr
        lsr
        lsr
        jsr putnib
        jsr line_end
        ; CUT 40 FSWEEP FE
        ldx #6
        jsr line_pt
        .null "cut "
        ldy #IN_CUTOFF
        jsr _hexy
        jsr prt
        .null " fsweep "
        ldy #IN_FSWEEP
        jsr _hexy
        jsr line_end
        ; HR 2 MODE 0 SR 00
        ldx #7
        jsr line_pt
        .null "hr "
        ldy #IN_HR
        lda (ptr2),y
        lsr
        lsr
        lsr
        lsr
        jsr putnib
        jsr prt
        .null " mode "
        ldy #IN_HR
        lda (ptr2),y
        jsr putnib
        jsr prt
        .null " sr "
        ldy #IN_HRSR
        jsr _hexy
        jsr line_end
        ; VIB 34 DELAY 0A
        ldx #8
        jsr line_pt
        .null "vib "
        ldy #IN_VIB
        jsr _hexy
        jsr prt
        .null " delay "
        ldy #IN_VIBDLY
        jsr _hexy
        jsr line_end
        ; TABLE -- SPD 00
        ldx #9
        jsr line_pt
        .null "table "
        ldy #IN_TABLE
        lda (ptr2),y
        jsr puthex_e
        jsr prt
        .null " spd "
        ldy #IN_TBLSPD
        jsr _hexy
        jsr line_end
        ; TRANSP ON  PITCH TICK
        ldx #10
        jsr line_pt
        .null "trsp "
        ldy #IN_FLAGS
        lda (ptr2),y
        and #INF_TRANSP
        eor #INF_TRANSP
        clc
        adc #8                  ; on/off
        jsr put_name
        jsr prt
        .null "pitch "
        ldy #IN_FLAGS
        lda (ptr2),y
        lsr
        and #1
        clc
        adc #10                 ; tick/fast
        jsr put_name
        jsr line_end
        lda #11
        sta step
_blank  ldx step                ; clear the rest of the area
        jsr line_at
        jsr line_end
        inc step
        lda step
        cmp #18
        bne _blank
        rts
_hexy   lda (ptr2),y
        jmp puthex

; A = bits, X = offset of the letters in s_bits (4, or 2 for bit_letters2):
; letter where the bit is set, '.' where not
bit_letters
        ldy #4
        .byte $2c
bit_letters2
        ldy #2
        sty tmp3
        sta tmp
        stx sidx
-       lsr tmp
        ldx sidx
        lda s_bits,x
        bcs +
        lda #$2e
+       jsr putc
        inc sidx
        dec tmp3
        bne -
        rts

; A = name index: 4 characters from s_names
put_name
        asl
        asl
        tax
        ldy #4
        sty tmp3
-       lda s_names,x
        jsr putc
        inx
        dec tmp3
        bne -
        rts

; Screen map at rows 19-21, cols 21-39, current screen reversed
draw_map
        ldx #0
-       stx sidx
        lda map_tab,x
        pha
        ldy map_tab+1,x
        lda map_tab+2,x
        sta tmp2
        pla
        tax
        jsr gotoxy
        lda #0
        ldy #COL_DIM
        ldx tmp2
        cpx screen
        bne +
        lda #$80
        ldy #COL_HEAD
+       sta drev
        sty dcolor
        ldx sidx
        lda map_tab+3,x
        jsr putc
        lda map_tab+4,x
        jsr putc
        lda map_tab+5,x
        jsr putc
        txa
        sbx #256-6              ; X += 6 (illegal: X = A & X - imm)
        cpx #map_end - map_tab
        bne -
        lda #0
        sta drev
        rts

MAP_X = 21                      ; right of the Live FX faders (cols 0-19)
map_tab .byte 19, MAP_X+8, SC_PROJECT
        .text "prj"
        .byte 19, MAP_X+12, SC_SID
        .text "sid"
        .byte 20, MAP_X+0, SC_SONG
        .text "sng"
        .byte 20, MAP_X+4, SC_CHAIN
        .text "chn"
        .byte 20, MAP_X+8, SC_PHRASE
        .text "phr"
        .byte 20, MAP_X+12, SC_INSTR
        .text "ins"
        .byte 20, MAP_X+16, SC_TABLE
        .text "tbl"
        .byte 21, MAP_X+12, SC_GROOVE
        .text "grv"
map_end

; Row 24: what the field under the cursor is and how to edit it
; X = help index of the field under the cursor
help_index
        ldx #H_MSG
        lda msg_on
        bne _r
        ldx #H_MARK
        lda mark_on
        bne _r
        jsr hover_help          ; the field under a moving mouse pointer
        bcs help_cursor
_r      rts
help_cursor                     ; X = help of the field under the cursor
        ldx #0
        lda screen
        beq _r
        cmp #SC_CHAIN
        bne +
        lda ccol
        clc
        adc #1
        tax
        rts
+       cmp #SC_PHRASE
        bne +
        ldx #H_PIANO
        lda pn_on
        bne _r
        ldx #H_GRID
        lda grid_on
        beq _lst
        lsr
        bcs _r
        ldx #H_DRUM
        rts
_lst    lda pcol
        clc
        adc #3
        tax
        rts
+       cmp #SC_INSTR
        beq _form
        cmp #SC_PROJECT
        beq _form
        cmp #SC_TABLE
        bne _gr
        ldx #H_NUM
        lda rowv+SC_TABLE
        beq _r
        ldy colv+SC_TABLE
        ldx tb_help,y
        rts
_gr     cmp #SC_GROOVE
        bne _fi
        ldx #H_NUM
        lda rowv+SC_GROOVE
        beq _r
        ldx #H_GROOVE
        rts
_fi     ldx #H_FILES
        cmp #SC_FILE
        beq _r
        ldx #H_MAP
_r      rts
_form   jsr cur_field
        ldx fl_help,y
        rts

tb_help .byte H_CTL, H_TTR, 5, 6, 5, 6

; X = help index: row 24
draw_help
        stx tmp2
        ldx #24
        lda #COL_HELP
        jsr line_0c
        ldx tmp2
        cpx #H_MSG
        bne +
        lda #COL_HEAD           ; message (msg_buf, 20 screen codes)
        sta dcolor
        ldx #0
-       lda msg_buf,x
        jsr putc
        inx
        cpx #20
        bne -
        beq _pad
+       php                     ; copy the string out of RAM under I/O
        sei
        lda #BANK_ALLRAM
        sta $01
        jsr help_copy           ; helptext.asm, under I/O
        lda #BANK_RAMIO
        sta $01
        plp
        lda #<HELPBUF
        ldy #>HELPBUF
        jsr putstr
_pad    lda #40
        jmp pad_to

; ---------------------------------------------------------------------------
row_lo  .byte <(SCREEN + range(0, 1000, 40))
row_hi  .byte >(SCREEN + range(0, 1000, 40))
chan_col .byte 10, 3, 13, 7, 4, 5   ; light red, cyan, light green (+2SID)
COL_BOOK = 7                        ; yellow: bookmarked song row number

; redraw snapshot: what the screen shows now
d_item  .byte $ff
d_top   .byte $ff
d_row   .byte 0
d_col   .byte 0
d_pitem .byte $ff
d_paux  .byte $ff
d_help  .byte $ff
d_stat  .fill NSTAT, $ff
s_stat  .fill NSTAT, 0
lm_v    .word 0
tc_col  .byte 0
tc_cmd  .byte 0
g_lo    .byte 0
g_hi    .byte 0
