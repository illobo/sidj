; Grid view of the Phrase screen: the 16 steps as a 4x4
; grid of cells instead of the list. Nothing in the data changes; the cursor
; is still prow (step) / pcol (field), so every edit goes through the list's
; code paths (field_ptr, edit_dir, do_tap, cell_clear).
;
; Cell of step s: column (s & 3) * 5, rows 2 + (s >> 2) * 4 .. +2, 4 wide,
; drawn reversed in the colour of its octave (empty: dark grey, playing:
; white); the 5th column and the 4th row are gaps.
;   line 0  note "C-3"            field 0
;   line 1  instrument "01"       field 1 (shown when set = instrument change)
;   line 2  command "C" value "37" fields 2, 3
; The cursor field is drawn unreversed in white.
; Toggle: HOME (read from the matrix, not a key code) or a click on the
; "grid"/"list" label in row 1 (cols 16-19). Keys: CRSR moves between cells
; (up/down = 4 steps), C= + Left/Right picks the field, SPACE + CRSR edits
; it as in the list. Mouse: click toggles a step (on = last note and
; instrument), left drag up/down = pitch (semitones), left/right =
; instrument, right drag = command value (up/down 10, left/right 1).

; Drum lane view (grid_on = 2, REU only: overlays 2-4, ov_drum_*.asm):
; CLR (SHIFT + HOME) or a click on the reversed "drum" label toggles it.

KC_GRID = $4f                   ; debug script char: toggles the grid view
KC_DRUM = $4e                   ; debug script char: toggles the drum view (CLR)

        .enc "screen"

; A = grid_on on the Phrase screen, else 0 (flags set). Keeps X and Y.
grid_act
        lda screen
        cmp #SC_PHRASE
        bne +
        lda grid_on
        rts
+       lda #0
        rts

; main loop, in place of kit_grammar: the drum view takes CRSR / SPACE
; presses and left clicks (overlays 2 and 4), CTRL and RETURN go to the
; grammar
drum_grammar
        jsr grid_act
        cmp #OV_DRUMIN          ; grid_on = 2 = the overlay id
        bne +
        ldx #0
        jsr ov_call
        bcs +
        tax                     ; A = 2: overlay 4 toggles the hit
        beq g_r
        lda #OV_DRUMTG
        jmp ov_call
+       jmp kit_grammar

; main loop: HOME (matrix column 6, row 3) or KC_GRID toggles the view,
; CLR (SHIFT + HOME) or KC_DRUM the drum view
grid_key
        lda key
        cmp #KC_DRUM
        beq drum_view
        cmp #KC_GRID
        beq grid_view
        lda kb_mat+6
        and #$08
        tax
        eor g_home
        stx g_home
        and g_home              ; newly pressed
        beq g_r
        lda k_shift
        beq grid_view
drum_view
        ldx #1
        .byte $2c
grid_view
        ldx #0
        lda screen
        cmp #SC_PHRASE
        bne g_r
        lda mark_on             ; a marked block stays in the list
        bne g_r
        txa
        beq +
        lda #OV_DRUMTG          ; drum view on/off (no REU: "needs reu")
        jmp ov_call
+       lda grid_on             ; list -> grid, grid or drum -> list
        cmp #1
        txa
        rol
        eor #1
        sta grid_on
        jmp dirty_list
g_r     rts

; CTRL + C= on the Phrase screen: no block marking in the grid
mark_start_g
        jsr grid_act
        bne g_r
        jmp mark_start

; Phrase screen entries of the draw.asm screen tables
; (drum view: overlay 3 redraws the whole view for each of them)
phr_full
        ldx grid_on
        bne +
        jmp phrase_full
+       dex
        beq grid_full
drum_draw
        lda #OV_DRUMDR
        jmp ov_call
phr_row
        ldx grid_on
        bne +
        jmp list_rowa
+       dex
        beq grid_rowa
        bne drum_draw
phr_marks
        ldx grid_on
        bne +
        jmp phrase_lmarks
+       dex
        beq grid_marks
        bne drum_draw

grid_full
        ldx #1
        jsr line_pd
        .null "  grid (home)   list"
        jsr line_end
        jsr grid_play
        lda #0
        sta step
-       jsr grid_cell
        inc step
        lda step
        cmp #16
        bne -
        rts

; A = step: redraw its cell
grid_rowa
        sta step
        jsr grid_play
        jmp grid_cell

; play markers: redraw the cells whose playing state changed
grid_marks
        jsr grid_play
        lda #0
        sta step
-       ldx step
        lda g_pn,x
        cmp g_pd,x
        beq +
        jsr grid_cell
+       inc step
        lda step
        cmp #16
        bne -
        rts

; g_pn[step] = 1 where a playing channel is at that step of item
grid_play
        ldx #15
        lda #0
-       sta g_pn,x
        dex
        bpl -
        ldx #NCHAN2-1
-       lda pl_playing
        and bitmask,x
        beq +
        lda pl_phrase,x
        cmp item
        bne +
        lda pl_phrase_step,x
        and #15
        tay
        lda #1
        sta g_pn,y
+       dex
        bpl -
        rts

; cell of step (item = phrase, lrow/curf = cursor, g_pn = playing)
grid_cell
        ldx step
        lda g_pn,x
        sta g_pd,x
        txa
        and #3
        sta g_x
        asl
        asl
        adc g_x
        sta g_x                 ; column (step & 3) * 5
        txa
        and #$0c
        adc #2
        sta g_y                 ; row 2 + (step >> 2) * 4
        lda #EMPTY
        sta g_n
        sta g_i
        lda #0
        sta g_c
        lda item
        cmp #EMPTY
        beq _col
        jsr phrase_addr
        lda step
        asl
        asl
        ora ptr
        sta ptr2
        lda ptr+1
        sta ptr2+1
        ldy #3
-       lda (ptr2),y
        sta g_n,y               ; g_n, g_i, g_c, g_v
        dey
        bpl -
_col    ldx step
        lda #COL_HEAD           ; playing: white
        ldy g_pn,x
        bne +
        lda #COL_DIM            ; empty: dark grey
        ldy g_n
        cpy #EMPTY
        beq +
        tya
        jsr div12
        ldx tmp
        lda oct_col,x
+       sta g_col
        lda #$ff                ; cursor field in this cell
        ldx step
        cpx lrow
        bne +
        lda curf
+       sta g_cf
        ; line 0: note
        ldx g_y
        jsr g_line
        ldx #0
        jsr g_sel
        lda g_n
        bcs +                   ; cursor: "---" when empty
        cmp #EMPTY
        bne +
        lda #3
        jsr g_spc
        jmp _l1
+       jsr putnote
_l1     jsr g_end
        ; line 1: instrument
        ldx g_y
        inx
        jsr g_line
        ldx #1
        jsr g_sel
        lda g_i
        bcs +                   ; cursor: "--" when empty
        cmp #EMPTY
        bne +
        lda #2
        jsr g_spc
        jmp _l2
+       jsr puthex_e
_l2     jsr g_end
        ; line 2: command letter and value
        ldx g_y
        inx
        inx
        jsr g_line
        ldx #2
        jsr g_sel
        lda g_c
        bne _cl
        bcc +
        lda #$2d                ; cursor on an empty command: '-'
        .byte $2c
+       lda #$20
_cl     jsr putc
        ldx #3
        jsr g_sel
        lda g_c
        beq +
        lda g_v
        jsr puthex
        jmp _l3
+       bcc +
        jsr dash2
        jmp _l3
+       lda #2
        jsr g_spc
_l3     jsr g_end
        ; gap row
        ldx g_y
        inx
        inx
        inx
        jsr g_line
        lda #0
        sta drev
        lda #5
        ; fall through

; A = count: spaces (reversed if drev)
g_spc   sta g_t
-       jsr space
        dec g_t
        bne -
        rts

; X = row: output at (row, g_x)
g_line  ldy g_x
        jmp gotoxy

; X = field: cursor field -> unreversed white, carry set; else the cell
; (reversed, cell colour), carry clear
g_sel   cpx g_cf
        bne g_cell
        lda #0
        sta drev
        lda #COL_HEAD
        sta dcolor
        rts                     ; carry set (X = g_cf)
g_cell  lda #$80
        sta drev
        lda g_col
        sta dcolor
        clc
        rts

; rest of the cell line reversed up to its 4th column, then the gap column
g_end   jsr g_cell
-       lda dx
        sec
        sbc g_x
        cmp #4
        bcs +
        jsr space
        jmp -
+       lda #0
        sta drev
        jmp space

; ---------------------------------------------------------------------------
; Keyboard. CRSR (X = direction via dir_t): between cells
grid_move
        ldx prow
        lda dir_t
        cmp #1
        beq _dn
        bcs _lr
        txa                     ; up
        sec
        sbc #4
        bcc _r
        sta prow
        rts
_dn     txa
        clc
        adc #4
        cmp #16
        bcs _r
        sta prow
        rts
_lr     cmp #2
        bne _rt
        txa
        beq _r
        dec prow
        rts
_rt     cpx #15
        bcs _r
        inc prow
_r      rts

; C= + Left/Right (X = 2/3): the field edited in the cell
grid_field
        lda pcol
        cpx #2
        bne +
        cmp #0
        beq _r
        dec pcol
        rts
+       cmp #3
        bcs _r
        inc pcol
_r      rts

; ---------------------------------------------------------------------------
; Mouse. Phrase screen hit test: the toggle label, then grid cells or list
grid_hit
        lda m_row
        cmp #1
        bne _cells
        lda m_col
        cmp #12
        bcc _no
        cmp #20
        bcs _no
        and #$10                ; h_val 0: "drum" (cols 12-15), else grid/list
        sta h_val
        lda #HK_GRID
        rts                     ; carry clear
_cells  lda grid_on
        bne +
        jmp hit_phrase
+       lsr
        bcc _no                 ; drum view: overlay 2 takes the clicks
        lda m_row
        sbc #2                  ; carry set
        cmp #16
        bcs _no
        tay
        and #3
        cmp #3
        beq _no                 ; gap row
        sta g_t                 ; cell line
        lda m_col
        cmp #20
        bcs _no
        ldx #0
-       cmp #5
        bcc +
        sbc #5
        inx
        bne -
+       cmp #4
        beq _no                 ; gap column
        sta g_t2                ; column inside the cell
        stx h_row
        tya
        and #$0c
        ora h_row
        sta h_row               ; step
        ldx g_t                 ; line = field, line 2: value right of the letter
        cpx #2
        bne +
        lda g_t2
        beq +
        inx
+       stx h_col
        lda #HK_FIELD
        clc
        rts
_no     sec
        rts

; click on a cell (no drag, no modifier): toggle the step. Off: note and
; instrument cleared (remembered as last); on: SPACE on the empty note
; (last note + last instrument, as in the list).
grid_toggle
        lda #0
        sta pcol
        jsr field_ptr
        bcs _r
        ldy #PH_NOTE
        lda (fp),y
        cmp #EMPTY
        bne +
        jmp do_tap
+       sta last+FT_NOTE
        iny
        lda (fp),y
        cmp #EMPTY
        beq +
        sta last+FT_INSTR
+       jsr cell_clear
        inc pcol
        jsr field_ptr
        jsr cell_clear
        dec pcol
_r      rts

; left drag direction A (BT_*) -> A: up/down = note -/+ semitone,
; left/right = instrument; right drag = command value as in the list
grid_dir
        sta g_t
        jsr grid_act
        beq _a
        lda m_btn
        and #2
        beq +
        lda #3
        sta pcol
        bne _a
+       lda g_t
        and #BT_UP | BT_DOWN
        beq _x
        lda #0
        sta pcol
        lda #BT_RIGHT
        ldx g_t
        cpx #BT_UP
        beq +
        lda #BT_LEFT
+       rts
_x      lda #1
        sta pcol
_a      lda g_t
        rts

; main loop (m_buttons): right button held after a right press on a cell
grid_rdrag
        lda m_rgrid
        beq +
        lda m_btn
        and #2
        bne ++
        sta m_rgrid
+       rts
+       jmp m_ldrag

; right press (m_rpress): Live FX release, grid cell (right drag), else
; carry set = not handled
m5_rpress
        lda #0
        sta m_rgrid
        jsr hit_test
        bcs _no
        cmp #HK_FX
        bne +
        ldx h_val
        jsr fx_free
        jmp _done
+       cmp #HK_FIELD
        bne _no
        jsr grid_act
        beq _no
        jsr m_setcur
        lda #3
        sta pcol
        lda #0
        sta m_hit
        sta m_axis
        sta m_ax
        sta m_ax+1
        sta m_ay
        sta m_ay+1
        lda #1
        sta m_rgrid
_done   inc m_rspec
        clc
        rts
_no     sec
        rts

        .enc "none"
oct_col .byte 9, 2, 8, 7, 13, 3, 14, 4  ; octave 0-7: brown red orange yellow lgreen cyan lblue purple

grid_on = $da                   ; zp; 1 = Phrase screen shows the grid, 2 the drum lanes
dr_base = $db                   ; zp, start value $ff (editor_init); drum view: instrument of lane 0 ($ff: cur_instr on entry)
dr_lane .byte 0                 ; drum view: cursor lane 0-7

; zero page $a0-$cb (editor.asm list); no start values needed
g_home  = $a0
m_rgrid = $a1                   ; 1 = right drag on a grid cell
g_x     = $a2
g_y     = $a3
g_n     = $a4                   ; note, instrument, command, value (this order)
g_i     = $a5
g_c     = $a6
g_v     = $a7
g_col   = $a8
g_cf    = $a9
g_t     = $aa
g_t2    = $ab
g_pn    = $ac                   ; [16] playing steps now
g_pd    = $bc                   ; [16] playing steps as drawn
