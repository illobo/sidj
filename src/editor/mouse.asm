; Commodore 1351 mouse.
;
; Driver (IRQ, ms_irq, runs before kb_scan): proportional mode. The mouse
; sends its position modulo 64 to SID POTX/POTY every 512 us: bits 6-1 =
; position, bit 0 = noise, bit 7 = don't care. Delta = (new - old) & $7f,
; >= $40 negative, then >> 1 (noise bit out); a zero delta keeps the old
; value (manual's MOVCHK), so jitter never accumulates. Y is inverted.
; CIA1 port A bits 6/7 switch the POT lines (4066) to port 1 (%01) or port 2
; (%10). The keyboard scan drives those bits as columns 6/7, so kb_scan ends
; with the mouse port selected ($7f / $bf) and the POT values are read at the
; start of the next IRQ, ~19 ms later (the manual asks for > 1.6 ms).
; Detection: POTX = POTY = $ff (pull-up, nothing charging the line) for
; MS_GONE frames = no 1351 (nothing, joystick, or a 1351 in joystick mode):
; pointer hidden, the port lines count as joystick lines again. Any other
; value = 1351 found; the old values are synced first, so it never jumps.
; Speed (ms_speed 0-3): position in half pixels += delta * (speed + 1), so
; x0.5, x1, x1.5, x2; acceleration (ms_accel): deltas >= MS_ACC_MIN doubled.
; The pointer is sprite 0 (data assembled at MS_SPRITE and loaded in place,
; M9; ms_init in boot_reu.asm sets the VIC up), hot spot = top left pixel.
;
; Buttons (kb_scan in input.asm): left = fire line, right = up line of the
; port. Port 1 lines are keyboard rows 4/0 ($dc01), port 2 lines keyboard
; columns 4/0 ($dc00). See kb_scan for how the keyboard stays usable.
;
; Grammar (mouse_input, main loop, after input_poll): turns pointer and
; buttons into cursor moves and synthetic btn/press bits for grammar:
;   left click          cursor to the field under the pointer
;   click again (same field, within DBL_FRAMES)  SPACE (insert, new item ...)
;   left drag up/down   SPACE + Up/Down per MS_STEP pixels (axis locked
;   left drag l/r       SPACE + Left/Right    after MS_LOCK pixels)
;   right button        C= (held while held)
;   click + C=/CTRL     the SPACE combo (C= + click = cut, CTRL + click = paste)
;   click on the map    that screen
;   click Project tempo tap tempo
;   click instrument usage map (Instr)  that instrument
;   Song, live mode: click chain = queue (RETURN), twice = at phrase end,
;   right click chain = queue stop (CTRL + RETURN); every mode: click channel
;   header = mute, right click = solo.
;   Live FX panel (rows 18-23) and the Phrase grid view: fx.asm, grid.asm.
; Hover: while the pointer moves the help line explains the field under it;
; any key returns it to the cursor field.

MS_SPRITE  = $0bc0              ; 64 bytes, VIC bank 0: pointer $2f
MS_GONE    = 25                 ; frames of $ff/$ff until "no mouse"
MS_ACC_MIN = 4
MS_STEP    = 8                  ; drag pixels per edit step
MS_LOCK    = 4                  ; drag pixels before the axis is chosen
MS_XMAX    = 319
MS_YMAX    = 199

HK_FIELD = 0                    ; hit kinds
HK_MAP   = 1
HK_HEAD  = 2
HK_INSTR = 3

; ---------------------------------------------------------------------------
; IRQ: POT -> position, sprite. Uses only its own variables.
ms_irq
        lda ms_port
        cmp ms_lastport
        beq +
        sta ms_lastport         ; port changed: select settles first
        lda #0
        sta ms_found
        sta ms_gone
        jmp _sprite
+       cmp #0
        bne +
        sta ms_found
        jmp _sprite
+       lda SID+$19
        sta ms_potx
        and SID+$1a
        cmp #$ff
        bne _seen
        lda ms_gone
        cmp #MS_GONE
        bcc +
        lda #0
        sta ms_found
        jmp _sprite
+       inc ms_gone
        jmp _move
_seen   lda #0
        sta ms_gone
        lda ms_found
        bne _move
        lda #1                  ; newly found: sync, no movement yet
        sta ms_found
        lda ms_potx
        sta ms_oldx
        lda SID+$1a
        sta ms_oldy
        jmp _sprite
_move   lda ms_found
        beq _sprite
        lda ms_potx
        ldy ms_oldx
        jsr movchk
        sty ms_oldx
        jsr ms_scale
        clc
        adc ms_fx
        sta ms_fx
        txa
        adc ms_fx+1
        sta ms_fx+1
        ldx #<(MS_XMAX*2+1)
        ldy #>(MS_XMAX*2+1)
        lda #ms_fx - ms_fx
        jsr ms_clamp
        lda SID+$1a
        ldy ms_oldy
        jsr movchk
        sty ms_oldy
        jsr ms_scale
        sta ms_t                ; fy -= v (up = larger POT value)
        stx ms_t+1
        lda ms_fy
        sec
        sbc ms_t
        sta ms_fy
        lda ms_fy+1
        sbc ms_t+1
        sta ms_fy+1
        ldx #<(MS_YMAX*2+1)
        ldy #>(MS_YMAX*2+1)
        lda #ms_fy - ms_fx
        jsr ms_clamp
_sprite lda ms_found
        ora ms_dbg
        beq _hide
        lda ms_port
        beq _hide
        lda #MS_SPRITE / 64
        sta SCREEN + $3f8
        lda ms_fx+1             ; x = fx / 2 + 24 (9 bits)
        lsr
        sta ms_t+1
        lda ms_fx
        ror
        clc
        adc #24
        sta VIC+0
        lda ms_t+1
        adc #0
        and #1
        sta ms_t
        lda VIC+$10
        and #$fe
        ora ms_t
        sta VIC+$10
        lda ms_fy+1             ; y = fy / 2 + 50
        lsr
        lda ms_fy
        ror
        clc
        adc #50
        sta VIC+1
        lda VIC+$15
        ora #1
        sta VIC+$15
        rts
_hide   lda VIC+$15
        and #$fe
        sta VIC+$15
        rts

; 1351 manual MOVCHK: A = new POT, Y = old -> A/X = signed delta, Y = value
; to keep as old (unchanged when there was no movement)
movchk  sty ms_old
        sta ms_new
        ldx #0
        sec
        sbc ms_old
        and #$7f
        cmp #$40
        bcs _neg
        lsr
        beq _null
        ldy ms_new
        rts
_neg    ora #$c0
        cmp #$ff
        beq _null
        sec
        ror
        ldx #$ff
        ldy ms_new
        rts
_null   lda #0
        rts

; A/X = delta -> A/X = delta * (speed + 1), doubled when accelerated
ms_scale
        sta ms_d
        stx ms_d+1
        lda ms_accel
        beq _mul
        lda ms_d
        bpl _pos
        eor #$ff
        clc
        adc #1
_pos    cmp #MS_ACC_MIN
        bcc _mul
        asl ms_d
        rol ms_d+1
_mul    lda #0
        sta ms_t
        sta ms_t+1
        ldy ms_speed
-       lda ms_t
        clc
        adc ms_d
        sta ms_t
        lda ms_t+1
        adc ms_d+1
        sta ms_t+1
        dey
        bpl -
        lda ms_t
        ldx ms_t+1
        rts

; clamp the 16-bit value at ms_fx + A to 0 .. X/Y (lo/hi)
ms_clamp
        stx ms_d
        sty ms_d+1
        tax
        lda ms_fx+1,x
        bpl +
        lda #0                  ; negative -> 0
        sta ms_fx,x
        sta ms_fx+1,x
        rts
+       lda ms_fx,x
        cmp ms_d
        lda ms_fx+1,x
        sbc ms_d+1
        bcc +
        lda ms_d
        sta ms_fx,x
        lda ms_d+1
        sta ms_fx+1,x
+       rts

; IRQ-side mouse state
ms_port     .byte 1             ; Project setting: 0 off, 1 port 1, 2 port 2
ms_speed    .byte 1             ; Project setting: 0-3
ms_accel    .byte 1             ; Project setting: 0 off, 1 on
ms_lastport .byte $ff
ms_found    .byte 0             ; 1 = a 1351 answers on ms_port
ms_gone     .byte 0
ms_dbg      .byte 0             ; 1 once the debug hook drove the pointer
ms_potx     .byte 0
ms_oldx     .byte 0
ms_oldy     .byte 0
ms_old      .byte 0
ms_new      .byte 0
ms_fx       .word 320           ; position in half pixels
ms_fy       .word 200
ms_d        .word 0
ms_t        .word 0
in_mbtn     .byte 0             ; buttons from kb_scan: bit 0 left, bit 1 right

; port select ($dc00 idle value) per ms_port
ms_sel      .byte $ff, $7f, $bf

        .section sprite_img     ; assembled at MS_SPRITE (main.asm), no copy
ms_shape
        .byte %10000000, 0, 0
        .byte %11000000, 0, 0
        .byte %11100000, 0, 0
        .byte %11110000, 0, 0
        .byte %11111000, 0, 0
        .byte %11111100, 0, 0
        .byte %11111110, 0, 0
        .byte %11111111, 0, 0
        .byte %11111000, 0, 0
        .byte %11011000, 0, 0
        .byte %10001100, 0, 0
        .byte %00001100, 0, 0
        .byte %00000110, 0, 0
        .byte %00000110, 0, 0
        .fill 7*3 + 1, 0
        .send sprite_img

; ---------------------------------------------------------------------------
; Main loop: pointer state (debug hook or driver), then the grammar.
mouse_input
        lda MDBG_COUNT
        beq _hw
        dec MDBG_COUNT
        lda MDBG_IDX
        inc MDBG_IDX
        sta m_t
        asl
        adc m_t                 ; *3 (carry clear: index < 85)
        tax
        lda MDBG_SCRIPT+2,x
        and #3
        sta m_btn
        lda MDBG_SCRIPT+2,x
        asl                     ; bit 7 = x bit 8
        lda #0
        rol
        sta m_x+1
        lda MDBG_SCRIPT,x
        sta m_x
        lda MDBG_SCRIPT+1,x
        sta m_y
        sei                     ; the driver continues from here
        lda m_x
        asl
        sta ms_fx
        lda m_x+1
        rol
        sta ms_fx+1
        lda m_y
        asl
        sta ms_fy
        lda #0
        rol
        sta ms_fy+1
        lda #1
        sta ms_dbg
        cli
        bne m_go
_hw     lda ms_port
        beq _off
        lda ms_found
        bne +
        lda ms_dbg              ; driven by the hook, no 1351: stays put
        bne m_go
        beq _off
+       sei
        lda ms_fx+1
        lsr
        sta m_x+1
        lda ms_fx
        ror
        sta m_x
        lda ms_fy+1
        lsr
        lda ms_fy
        ror
        sta m_y
        lda in_mbtn
        sta m_btn
        cli
        jmp m_go
_off    lda #0                  ; no mouse: buttons up, no hover
        sta m_btn
        sta m_hover
        beq m_buttons

m_go    lda m_x+1               ; col = x / 8, row = y / 8
        lsr
        lda m_x
        ror
        lsr
        lsr
        sta m_col
        lda m_y
        lsr
        lsr
        lsr
        sta m_row
        lda m_x                 ; moved: hover help on
        cmp m_lx
        bne _mv
        lda m_x+1
        cmp m_lx+1
        bne _mv
        lda m_y
        cmp m_ly
        beq m_buttons
_mv     lda m_hover
        bne +
        lda #$ff                ; d_help recomputed
        sta d_help
+       lda #1
        sta m_hover
m_buttons
        lda press               ; keyboard use: help follows the cursor
        ora btn
        bne +
        lda key
        cmp #KC_NONE
        beq ++
+       lda #0
        sta m_hover
+       lda m_clk
        beq +
        sec
        sbc elapsed
        bcs +
        lda #0
+       sta m_clk
        lda m_prev
        eor #$ff
        and m_btn
        sta m_pr                ; newly pressed
        lda m_btn
        eor #$ff
        and m_prev
        sta m_rl                ; released
        lda m_btn
        sta m_prev
        lda m_pr
        and #1
        beq +
        jsr m_lpress
+       lda m_btn
        and #1
        beq +
        jsr m_ldrag
+       lda m_rl
        and #1
        beq +
        jsr m_lrelease
+       lda m_pr
        and #2
        beq +
        jsr m_rpress
+       jsr grid_rdrag          ; grid: right drag = command value (grid.asm)
        lda m_btn               ; right held = C= held (unless it was special)
        and #2
        beq +
        lda m_rspec
        bne +
        lda #BT_B
        ora btn
        sta btn
+       lda m_x
        sta m_lx
        lda m_x+1
        sta m_lx+1
        lda m_y
        sta m_ly
        rts

; left button pressed: act on what is under the pointer
m_lpress
        lda #0
        sta m_axis
        sta m_ax
        sta m_ax+1
        sta m_ay
        sta m_ay+1
        lda #$ff
        sta m_hit
        jsr hit_test
        bcs _r
        sta m_hit
        cmp #HK_FX              ; Live FX fader, grid toggle (fx.asm)
        bcc +
        jmp fx_lpress
+       cmp #HK_MAP
        beq m_map
        cmp #HK_HEAD
        bne +
        ldx h_val
        jmp mute_x
+       cmp #HK_INSTR
        bne m_setcur
        lda h_val
        sta cur_instr
        jmp dirty_lp
_r      rts

; cursor to the hit field (h_row, h_col)
m_setcur
        ldx screen
        lda h_row
        sta rowv,x
        lda h_col
        sta colv,x
        cpx #SC_SONG
        bne +
        jmp song_scroll
+       cpx #SC_FILE
        bne +
        jmp file_scroll
+       rts

; map click: jump to screen h_val
m_map   lda h_val
        cmp screen
        beq m_rts
        cmp #SC_GROOVE
        bne +
        ldx screen
        stx groove_from
+       sta screen
        lda #0
        sta mark_on
        lda #1
        sta need_clear
m_rts   rts

; left held: drag = SPACE + direction steps, one axis per drag
m_ldrag
        lda m_pr                ; not on the press frame
        and #1
        bne m_rts
        lda m_hit
        beq +                   ; drags on fields, or a Live FX fader (fx.asm)
        jmp fx_hdrag
+       lda m_x
        sec
        sbc m_lx
        sta m_t
        lda m_x+1
        sbc m_lx+1
        tay
        lda m_t
        ldx #m_ax - m_ax
        jsr _acc
        lda m_y
        sec
        sbc m_ly
        sta m_t
        lda #0
        sbc #0
        tay
        lda m_t
        ldx #m_ay - m_ax
        jsr _acc
        lda m_axis
        bne _step
        tax                     ; m_ax - m_ax: choose the axis
        jsr _abs
        cmp #MS_LOCK
        bcc +
        lda #1
        sta m_axis
        bne _step
+       ldx #m_ay - m_ax
        jsr _abs
        cmp #MS_LOCK
        bcc _r
        lda #2
        sta m_axis
_step   lda #BT_A               ; SPACE held for the whole drag
        ora btn
        sta btn
        ldx #m_ax - m_ax
        lda m_axis
        cmp #1
        beq +
        ldx #m_ay - m_ax
+       lda m_ax+1,x
        bmi _neg
        bne _pos
        lda m_ax,x
        cmp #MS_STEP
        bcc _r
_pos    lda m_ax,x
        sec
        sbc #MS_STEP
        sta m_ax,x
        bcs +
        dec m_ax+1,x
+       lda #BT_RIGHT
        ldy m_axis
        cpy #1
        beq _emit
        lda #BT_DOWN
        bne _emit
_neg    lda m_ax,x              ; word + STEP <= 0: a step back
        clc
        adc #MS_STEP
        sta m_t
        lda m_ax+1,x
        adc #0
        bmi +
        ora m_t
        bne _r
+       sta m_ax+1,x
        lda m_t
        sta m_ax,x
        lda #BT_LEFT
        ldy m_axis
        cpy #1
        beq _emit
        lda #BT_UP
_emit   jsr grid_dir            ; grid: drag axes to fields (grid.asm)
        pha
        ora btn
        sta btn
        pla
        ora press
        sta press
_r      rts
; add the word A (lo) / Y (hi) to the word at m_ax + X
_acc    clc
        adc m_ax,x
        sta m_ax,x
        tya
        adc m_ax+1,x
        sta m_ax+1,x
        rts
; A = |word at m_ax + X|, saturated to 255
_abs    lda m_ax+1,x
        bmi +
        bne _big
        lda m_ax,x
        rts
+       cmp #$ff
        bne _big
        lda m_ax,x
        eor #$ff
        clc
        adc #1
        bne +
_big    lda #255
+       rts

; left released: a click (no drag) on a field
m_lrelease
        lda m_hit
        bne _r                  ; not a field
        lda m_axis
        bne _r                  ; it was a drag
        jsr hit_test            ; still the same field?
        bcs _r
        cmp #HK_FIELD
        bne _r
        ldx screen
        lda h_row
        cmp rowv,x
        bne _r
        lda h_col
        cmp colv,x
        bne _r
        cpx #SC_SONG            ; live mode Song: queue (twice: phrase end)
        bne +
        lda pl_live
        beq +
        lda #BT_START
        ora press
        sta press
        rts
+       lda btn                 ; C= / CTRL (or right button) held: SPACE combo
        and #BT_B | BT_SELECT
        bne _space
        lda m_btn
        and #2
        bne _space
        cpx #SC_PROJECT         ; tempo field: tap
        bne +
        lda rowv,x
        ora colv,x
        bne +
        jmp tap_tempo
+       jsr grid_act            ; grid view: a click toggles the step (grid.asm)
        beq +
        jmp grid_toggle
+       lda m_clk               ; second click on the same field: SPACE
        beq +
        lda m_cscr
        cmp screen
        bne +
        lda m_crow
        cmp rowv,x
        bne +
        lda m_ccol
        cmp colv,x
        bne +
        lda #0
        sta m_clk
_space  lda #BT_A
        ora press
        sta press
_r      rts
+       stx m_cscr
        lda rowv,x
        sta m_crow
        lda colv,x
        sta m_ccol
        lda #DBL_FRAMES
        sta m_clk
        rts

; right button pressed: C=, or live/header specials
m_rpress
        lda #0
        sta m_rspec
        jsr m5_rpress           ; Live FX release, grid right drag (grid.asm)
        bcs +
        rts
+       jsr hit_test
        bcs _b
        cmp #HK_HEAD
        bne +
        inc m_rspec
        ldx h_val
        jmp solo_x
+       cmp #HK_FIELD
        bne _b
        lda screen
        bne _b
        lda pl_live
        beq _b
        inc m_rspec             ; live Song chain: queue stop
        jsr m_setcur
        lda #BT_SELECT
        ora btn
        sta btn
        lda #BT_START
        ora press
        sta press
        rts
_b      lda #BT_B
        ora press
        sta press
        rts

; ---------------------------------------------------------------------------
; What is at (m_col, m_row)? Carry clear: A = h_kind (HK_*), h_row/h_col =
; cursor values (HK_FIELD), h_val = screen (HK_MAP), channel (HK_HEAD) or
; instrument (HK_INSTR). Carry set: nothing.
hit_test
        lda m_row
        cmp #18
        bcc _scr
        jsr fx_hit              ; Live FX panel, rows 18-23 cols 0-19 (fx.asm)
        bcs +
        rts
+       ldx #0
-       lda map_tab,x
        cmp m_row
        bne _nx
        lda m_col
        sbc map_tab+1,x         ; carry set (= m_row)
        cmp #3
        bcs _nx
        lda map_tab+2,x
        sta h_val
        lda #HK_MAP
        rts                     ; carry clear
_nx     txa
        sbx #256-6              ; X += 6
        cpx #map_end - map_tab
        bne -
_no     sec
        rts
_scr    ldx screen
        lda hit_lo,x
        sta jv
        lda hit_hi,x
        sta jv+1
        jmp (jv)

HITS = [hit_song, hit_chain, grid_hit, hit_form, hit_table, hit_groove, hit_form, hit_sid, hit_file]
hit_lo  .byte <HITS
hit_hi  .byte >HITS

hit_none
        sec
        rts

; Song: row 1 headers, rows 2-17 cells "RR>CC>CC>CC"
hit_song
        lda m_col
        ldx scol                ; on the row number: keep the channel
        sec
        sbc #2
        bcc +
        jsr div3
        cpx pl_nch
        bcs hit_none
+       stx h_col
        lda m_row
        cmp #1
        bne +
        lda m_col               ; header (needs a real channel column)
        cmp #2
        bcc hit_none
        stx h_val
        lda #HK_HEAD
        clc
        rts
+       sec
        sbc #2
        cmp #SONG_ROWS
        bcs hit_none
        adc song_top
        sta h_row
        lda #HK_FIELD
        clc
        rts

; A = 0-17 -> X = A / 3
div3    ldx #0
-       cmp #3
        bcc +
        sbc #3
        inx
        bne -
+       rts

; list rows 2-17 -> h_row = row - 2 (+ A on entry), carry set if outside
list_row
        sta m_t
        lda m_row
        sec
        sbc #2
        cmp #16
        bcs +
        adc m_t
        sta h_row
        lda m_col
        cmp #20
+       rts

; X = column bound table offset: h_col = number of bounds <= m_col
col_by
        ldy #0
-       lda m_col
        cmp col_bounds,x
        bcc +
        iny
        inx
        lda col_bounds,x
        bne -
+       sty h_col
        rts

col_bounds
CB_CHAIN = * - col_bounds
        .byte 5, 0                      ; "S>PP TT"
CB_PHRASE = * - col_bounds
        .byte 5, 8, 10, 0               ; "S>NNN II CVV"
CB_TABLE = * - col_bounds
        .byte 5, 9, 10, 13, 14, 0       ; "S CC +TT CVV CVV"

hit_chain
        lda #0
        jsr list_row
        bcs hit_none
        ldx #CB_CHAIN
        bcc hit_cols
hit_phrase
        lda #0
        jsr list_row
        bcs hit_none2
        ldx #CB_PHRASE
hit_cols
        jsr col_by
        lda #HK_FIELD
        clc
        rts

; Table/Groove: row 0 (status) = title, list rows = cursor rows 1-16
hit_title
        lda m_col
        cmp #12
        bcs hit_none2
        lda #0                  ; HK_FIELD
        sta h_row
        sta h_col
        rts                     ; carry clear
        .cerror HK_FIELD != 0
hit_table
        lda m_row
        beq hit_title
        lda #1
        jsr list_row
        bcs hit_none2
        ldx #CB_TABLE
        bcc hit_cols
hit_groove
        lda m_row
        beq hit_title
        lda #1
        jsr list_row
        bcs hit_none2
        lda #0                  ; HK_FIELD
        sta h_col
        rts                     ; carry clear
hit_none2
        sec
        rts

; File: rows 2-17 = list from file_top (up to fcount)
hit_file
        lda file_top
        jsr list_row
        bcs hit_none2
        lda fcount
        cmp h_row
        bcc hit_none2
        lda #0                  ; HK_FIELD
        sta h_col
        clc
        rts

; Forms: the line on this row, the last field starting at or left of the
; pointer (or the first); Instr rows 14-17 = usage map
hit_form
        lda m_col
        cmp #FORM_W
        bcs hit_none2
        lda screen
        cmp #SC_INSTR
        bne _lines
        lda m_row
        sbc #14                 ; carry set (= SC_INSTR)
        cmp #4
        bcs _lines
        asl
        asl
        asl
        asl
        sta h_val
        lda m_col
        sec
        sbc #3
        cmp #16
        bcs hit_none2
        ora h_val
        sta h_val
        lda #HK_INSTR
        rts                     ; carry clear
_lines  ldx screen
        lda form_l0,x
        sta m_t                 ; global line
        lda #0
        sta h_row               ; line within the screen
-       ldy m_t
        lda ln_row,y
        cmp m_row
        bne _nl
        lda ln_n,y
        bne _found
_nl     inc m_t
        inc h_row
        lda h_row
        cmp form_nl,x
        bne -
        rts                     ; carry set
_found  sta m_t2                ; fields on the line
        lda ln_first,y
        tay
        ldx #0
        stx h_col
-       lda fl_col,y
        cmp m_col
        beq +
        bcs _done
+       stx h_col
        iny
        inx
        cpx m_t2
        bne -
_done   lda #HK_FIELD
        clc
        rts

; ---------------------------------------------------------------------------
; Hover help: X = help index for what is under the pointer, carry set if
; nothing (use the cursor field)
hover_help
        lda m_hover
        beq _no
        jsr hit_test
        bcs _r
        cmp #HK_FX              ; Live FX fader, grid toggle (fx.asm)
        bcc +
        jmp fx_hover
+       ldx #H_MAP
        cmp #HK_MAP
        beq _ok
        ldx #H_HEAD
        cmp #HK_HEAD
        beq _ok
        ldx #H_NUM
        cmp #HK_INSTR
        beq _ok
        ldx screen              ; a field: the help of that field
        lda screen
        bne +
        ldx #H_LIVE
        lda pl_live
        bne _ok
        tax                     ; 0
        beq _ok
+       lda rowv,x              ; swap the cursor with the hit field
        pha
        lda colv,x
        pha
        lda h_row
        sta rowv,x
        lda h_col
        sta colv,x
        jsr help_cursor
        stx m_t
        ldx screen
        pla
        sta colv,x
        pla
        sta rowv,x
        ldx m_t
_ok     clc
_r      rts
_no     sec
        rts

; ---------------------------------------------------------------------------
; Tap tempo (Project tempo field: RETURN or click): BPM from the average of
; the last taps (up to 4 intervals), measured in frames (PAL 50.125 Hz,
; NTSC 59.826 Hz: pl_ntsc picks the frames per minute).
TAP_MAX = 100                   ; frames: a longer gap starts over (< 30 BPM)
TAP_N   = 4
tap_tempo
        lda last_frame
        sec
        sbc tap_last
        sta m_t                 ; interval in frames
        lda last_frame
        sta tap_last
        lda tap_on
        beq _first
        lda m_t
        cmp #TAP_MAX
        bcc +
_first  lda #0                  ; the first tap only starts the count
        sta tap_n
        lda #1
        sta tap_on
_r      rts
+       cmp #8                  ; > 375 BPM: a bounce, ignore
        bcc _r
        ldx #TAP_N-2            ; shift the interval history
-       lda tap_iv,x
        sta tap_iv+1,x
        dex
        bpl -
        lda m_t
        sta tap_iv
        lda tap_n
        cmp #TAP_N
        bcs +
        inc tap_n
+       lda #0                  ; sum of the intervals
        sta tap_sum
        sta tap_sum+1
        ldx tap_n
        dex
-       lda tap_iv,x
        clc
        adc tap_sum
        sta tap_sum
        bcc +
        inc tap_sum+1
+       dex
        bpl -
        lda #0                  ; num = frames/min * n + sum / 2
        sta tap_num
        sta tap_num+1
        ldy pl_ntsc
        ldx tap_n
-       lda tap_num
        clc
        adc tap_fpm_lo,y
        sta tap_num
        lda tap_num+1
        adc tap_fpm_hi,y
        sta tap_num+1
        dex
        bne -
        lda tap_sum+1
        lsr
        lda tap_sum
        ror
        clc
        adc tap_num
        sta tap_num
        bcc +
        inc tap_num+1
+       jsr div16               ; f_bpm = num / sum
        jmp tempo_put

tap_fpm_lo .byte <3008, <3590   ; frames per minute: PAL, NTSC
tap_fpm_hi .byte >3008, >3590

; f_bpm = tap_num / tap_sum (16 bit, restoring division)
div16   lda #0
        sta m_t
        sta m_t2
        ldx #16
-       asl tap_num
        rol tap_num+1
        rol m_t
        rol m_t2
        lda m_t
        sec
        sbc tap_sum
        tay
        lda m_t2
        sbc tap_sum+1
        bcc +
        sta m_t2
        sty m_t
        inc tap_num
+       dex
        bne -
        lda tap_num
        sta f_bpm
        lda tap_num+1
        sta f_bpm+1
        rts

; Nudge: C= + Left/Right held on the Project tempo field -> pl_nudge -8/+8
; (player: latch - latch*nudge/256, i.e. about -3/+3 %), 0 otherwise
nudge_watch
        ldx #0
        lda screen
        cmp #SC_PROJECT
        bne _set
        lda rowv+SC_PROJECT
        ora colv+SC_PROJECT
        bne _set
        lda btn
        and #BT_B | BT_LEFT | BT_RIGHT
        cmp #BT_B | BT_RIGHT
        bne +
        ldx #8
+       cmp #BT_B | BT_LEFT
        bne _set
        ldx #256-8
_set    jsr fx_nudge_x          ; or the Live FX '<' '>' held (fx.asm)
        cpx m_nudge
        beq +
        stx m_nudge
        stx pl_nudge
+       rts

; main-side mouse state
m_x     .word 0                 ; pointer (hot spot) in text-area pixels
m_y     .byte 0
m_lx    .word 0
m_ly    .byte 0
m_col   = $d2                   ; zp
m_row   = $d0                   ; zp
m_btn   = $d4                   ; zp; bit 0 left, bit 1 right
m_prev  .byte 0
m_pr    .byte 0
m_rl    .byte 0
m_hover .byte 0                 ; 1 = help line follows the pointer
m_hit   .byte $ff               ; kind hit by the left press ($ff none)
m_axis  .byte 0                 ; drag axis: 0 none yet, 1 x, 2 y
m_ax    .word 0                 ; drag distance not yet turned into steps
m_ay    .word 0
m_rspec .byte 0                 ; right press was a live/header action
m_clk   .byte 0                 ; double-click window
m_cscr  .byte 0
m_crow  .byte 0
m_ccol  .byte 0
m_t     = $9e                   ; zp
m_t2    .byte 0
m_nudge .byte 0
h_row   = $d6                   ; zp
h_col   = $d7                   ; zp
h_val   = $d3                   ; zp
tap_last .byte 0
tap_on  .byte 0                 ; 1 = a tap sequence is running
tap_n   .byte 0                 ; intervals known
tap_iv  .fill TAP_N, 0
tap_sum .word 0
tap_num .word 0
