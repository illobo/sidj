; Input layer: raw CIA1 matrix -> abstract buttons (BT_*) and a typed char.
; The raster IRQ scans once per frame; the grammar only sees btn/press/key,
; so the debug script (editor.asm DBG_*) can stand in for the keyboard.
;
; Matrix: CIA1 port A ($dc00) selects a column (bit low), port B ($dc01)
; reads the rows (bit low = pressed). Keys used by the grammar:
;   col 0: b1 RETURN, b2 CRSR RIGHT, b4 F1, b5 F3, b6 F5, b7 CRSR DOWN
;   col 1: b7 LEFT SHIFT          col 6: b4 RIGHT SHIFT
;   col 7: b2 CTRL, b4 SPACE, b5 C=
; SPACE, C= and CTRL share column 7, so any mix of them never ghosts. A
; ghost needs three keys on two columns and two rows; with one of SPACE/C=/
; CTRL plus RETURN, or plus SHIFT + one CRSR key, no two keys share a row
; and a column with a third. Known ghosts (all harmless): SHIFT+CRSR DOWN+
; CRSR RIGHT adds A, SHIFT+CRSR DOWN+RETURN adds W (letters are ignored
; while SHIFT is held); RIGHT SHIFT+SPACE+C= adds '=', +CTRL adds ';'.
; Control ports. Port 1 lines pull port B (rows) low, port 2 lines pull
; port A (columns) low. Mouse buttons are fire (left) and up (right).
;   Port 1 (mouse or joystick 1): the rows held low with no column driven
;   (k_j1) are masked out of the scan. The keys on those rows are recovered
;   in reverse: a pressed key joins its column to the low row, so that
;   column reads low on port A with all columns high (k_pa). One column
;   low = every masked row on it (SPACE, C=, CTRL share column 7, so any
;   mix of them with a button is exact); several = the button row on each.
;   Both buttons held: row 4 (SPACE, RSHIFT, F1 ...) wins over row 0 (digits).
;   With the 1351 found, only rows 4/0 are its lines (the buttons, in_mbtn);
;   other low rows come from key chains. Port 1 lines never count as a
;   joystick 2.
;   Port 2 (joystick): a frame with port 2 active skips the matrix and uses
;   the stick as D-pad + A. Port 2 mouse: its buttons drive columns 4/0 low,
;   whose keys then show on every column: masked like port 1, and when one
;   button is held the masked rows are given to its column.
; The 1351 POT lines follow $dc00 bits 6/7, so the scan ends with the mouse
; port selected (ms_sel) and mouse.asm reads POTX/POTY first in the next IRQ.

        .section late_pad       ; start-up only: in the tier C undo image's tail, run at CLIPBUF (main.asm, M9)
input_init
        lda #0                  ; loop.asm zero page
        ldx #k_sl-pn_on
-       sta pn_on,x
        dex
        bpl -
        dec jam_pos             ; $ff: none
        dec lr_note
        lda #3                  ; piano: lower row from C-3
        sta pn_oct
        lda #<irq
        sta $fffe
        lda #>irq
        sta $ffff
        lda #$fa                ; bottom border, after the visible area
        sta VIC+$12
        lda VIC+$11
        and #$7f
        sta VIC+$11
        lda #KC_NONE            ; = $ff
        sta in_char
        sta VIC+$19
        lda #1
        sta VIC+$1a
        rts
        .send late_pad

irq     pha
        txa
        pha
        tya
        pha
        lda #$ff                ; ack raster
        sta VIC+$19
        jsr ms_irq              ; POT lines selected since the last scan
        jsr kb_scan
        inc in_frame
        pla
        tay
        pla
        tax
        pla
        rti

; Scan the matrix into kb_mat (bit set = pressed), derive in_btn and in_char.
; IRQ context: uses only its own variables, never the editor zero page.
kb_scan
        ldx #7
-       lda kb_mat,x
        sta kb_old,x
        dex
        bpl -
        lda #$ff                ; no column driven: port lines only
        sta CIA1
        lda CIA1+1
        eor #$ff
        sta k_j1                ; rows held low (masked in the scan)
        lda CIA1
        eor #$ff
        sta k_pa                ; columns held low
        lda #0
        sta k_joy2
        sta k_src
        sta k_mb
        sta k_force
        lda ms_found
        beq _nom
        lda ms_port
        cmp #2
        beq _m2
        cmp #1
        bne _nom
        lda k_j1                ; 1351 in port 1: rows 4/0 are its buttons
        and #$11
        sta k_src
        jsr kb_mbits
        jmp _scan
_m2     lda k_pa                ; 1351 in port 2: columns 4/0
        and #$11
        sta k_force
        jsr kb_mbits
        jmp _scan
_nom    lda k_j1                ; joystick 1 (or nothing)
        and #$1f
        sta k_src
        bne _scan               ; port 1 active: port A lows are keys
        lda k_pa
        and #$1f
        sta k_joy2
        beq _scan
        lda #0                  ; port 2 active: the scan would ghost
        ldx #7
-       sta kb_mat,x
        dex
        bpl -
        bmi _rest
_scan   ldx #7
-       lda kb_colsel,x
        sta CIA1
        lda CIA1+1
        ora k_j1
        eor #$ff
        sta kb_mat,x
        dex
        bpl -
        lda #$ff
        sta CIA1
        jsr kb_recover
_rest   ldx ms_port
        lda ms_sel,x
        sta CIA1                ; POT lines to the mouse port until next IRQ
        lda k_mb
        sta in_mbtn
_keys   lda kb_mat+1            ; either SHIFT
        and #$80
        sta k_shift
        lda kb_mat+6
        and #$10
        ora k_shift
        sta k_shift
        lda #0
        sta k_btn
        bit kb_mat              ; b7 CRSR DOWN, SHIFT = up
        bpl _noud
        lda #BT_DOWN
        ldx k_shift
        beq +
        lda #BT_UP
+       sta k_btn
_noud   lda kb_mat              ; b2 CRSR RIGHT, SHIFT = left
        and #$04
        beq _nolr
        lda #BT_RIGHT
        ldx k_shift
        beq +
        lda #BT_LEFT
+       ora k_btn
        sta k_btn
_nolr   lda kb_mat              ; b1 RETURN
        and #$02
        beq +
        lda #BT_START
        ora k_btn
        sta k_btn
+       lda kb_mat+7            ; CTRL b2 -> BT_SELECT b6
        and #$04
        asl
        asl
        asl
        asl
        ora k_btn
        sta k_btn
        lda kb_mat+7            ; SPACE b4 and C= b5 are BT_A and BT_B
        and #BT_A | BT_B
        ora k_btn
        ora k_joy2              ; stick + fire use the same bit order
        sta in_btn
        ; typed char: first newly pressed key with a code, held until polled
        lda in_char
        cmp #KC_NONE
        bne _done
        ldx #7
_col    lda kb_old,x
        eor #$ff
        and kb_mat,x
        beq _next
        sta k_new
        txa
        asl
        asl
        asl
        tay
-       lsr k_new
        bcs _hit
        iny
        bne -
_hit    sty k_pos
        lda kb_codes,y
        bmi _next
        cmp #KC_F1
        bcs _take
        ldy k_shift             ; letters only without modifiers (ghosts)
        bne _next
        tay
        lda in_btn
        and #BT_A | BT_B | BT_SELECT
        bne _next
        tya
_take   ldy k_shift             ; SHIFT + F1/F3/F5/F7 = F2/F4/F6/F8 (KC + 8)
        beq +
        ora #KC_SHIFTF
+       sta in_char
        jmp lr_stamp
_done   rts
_next   dex
        bpl _col
        rts

; Stamp of a typed key for loop record (loop.asm): the recorded channel's
; phrase step, pl_wait and pl_steplen, read again if a tick came between.
; IRQ (or input_poll for a script key); X and Y clobbered. Lives in EDLOW.
        .section edlow_ext
lr_stamp
        ldx lr_chan
-       ldy pl_tick
        lda pl_phrase_step,x
        sta k_st
        lda pl_wait,x
        sta k_sw
        lda pl_steplen,x
        sta k_sl
        cpy pl_tick
        bne -
        rts
        .send edlow_ext

; Main context: take this frame's buttons (keyboard or debug script) and
; compute press = new buttons + auto-repeat of held directions.
input_poll
        lda DBG_COUNT
        beq _kb
        dec DBG_COUNT
        lda DBG_IDX
        inc DBG_IDX
        asl
        tax
        lda DBG_SCRIPT,x
        sta btn
        lda DBG_SCRIPT+1,x
        sta key
        jsr lr_stamp            ; a script key is stamped now
        lda #$ff                ; (no matrix key to release)
        sta k_pos
        bne _cp
_kb     sei
        lda in_btn
        sta btn
        lda in_char
        sta key
        lda #KC_NONE
        sta in_char
_cp     ldx #3                  ; the key's stamps (loop.asm)
-       lda k_pos,x
        sta r_pos,x
        dex
        bpl -
        cli
_edges  lda btn_prev
        eor #$ff
        and btn
        sta press
        lda btn
        sta btn_prev
        and #BT_DIRS
        beq _rearm
        lda press
        and #BT_DIRS
        bne _rearm
        lda rep_timer
        sec
        sbc elapsed
        sta rep_timer
        beq _fire
        bcs +
_fire   lda #REP_RATE
        sta rep_timer
        lda btn
        and #BT_DIRS
        ora press
        sta press
+       rts
_rearm  lda #REP_DELAY
        sta rep_timer
        rts

; A = button lines (bit 4 left, bit 0 right) -> k_mb (bit 0 left, bit 1 right)
kb_mbits
        lsr
        bcc +
        ldx #2
        stx k_mb
+       and #8
        beq +
        lda #1
        ora k_mb
        sta k_mb
+       rts

; Keys hidden behind control-port lines (see the top of this file)
kb_recover
        lda k_force             ; port 2 mouse: one button column?
        beq _p1
        ldx #4
        cmp #$10
        beq +
        ldx #0
        cmp #$01
        bne _r
+       lda k_j1
        ora kb_mat,x
        sta kb_mat,x
_r      rts
_p1     lda k_src
        beq _r
        lda k_pa
        beq _r
        lda k_src               ; s = the button row (row 4 first)
        and #$10
        bne +
        lda k_src               ; lowest line (x & -x)
        and #$0f
        sta k_s
        eor #$ff
        clc
        adc #1
        and k_s
+       sta k_s
        lda k_src               ; rows joined by key chains
        eor #$ff
        and k_j1
        sta k_e
        lda k_pa                ; single column? (x & (x-1) = 0)
        sec
        sbc #1
        and k_pa
        bne _many
        tax                     ; X = 0
        lda k_pa
-       lsr
        bcs +
        inx
        bne -
+       lda k_s
        ora k_e
        ora kb_mat,x
        sta kb_mat,x
        rts
_many   ldx #0
        lda k_pa
-       lsr
        bcc +
        pha
        lda k_s
        ora kb_mat,x
        sta kb_mat,x
        pla
+       inx
        cpx #8
        bne -
        rts

kb_colsel .byte $fe, $fd, $fb, $f7, $ef, $df, $bf, $7f

; Matrix position (column*8 + row bit) -> 0-9 digit, 10-35 letter A-Z,
; KC_F1+0/1/2 for F1/F3/F5, KC_F7 (SHIFT: + KC_SHIFTF), $ff = no code.
kb_codes
        .byte $ff, $ff, $ff, KC_F7, KC_F1, KC_F1+1, KC_F1+2, $ff ; DEL RET RT F7 F1 F3 F5 DN
        .byte 3, 32, 10, 4, 35, 28, 14, $ff     ; 3 W A 4 Z S E LSHIFT
        .byte 5, 27, 13, 6, 12, 15, 29, 33      ; 5 R D 6 C F T X
        .byte 7, 34, 16, 8, 11, 17, 30, 31      ; 7 Y G 8 B H U V
        .byte 9, 18, 19, 0, 22, 20, 24, 23      ; 9 I J 0 M K O N
        .byte KC_PLUS, 25, 21, KC_MINUS, $ff, $ff, $ff, $ff ; + P L - . : @ ,
        .byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff ; pound * ; HOME RSHIFT = ^ /
        .byte 1, $ff, $ff, 2, $ff, $ff, 26, $ff ; 1 <- CTRL 2 SPACE C= Q STOP

; IRQ-side state
in_btn  .byte 0
in_char .byte KC_NONE
in_frame .byte 0
kb_mat  .fill 8, 0
kb_old  .fill 8, 0
k_j1    .byte 0
k_pa    .byte 0
k_src   .byte 0                 ; port 1 lines held low by the device
k_force .byte 0                 ; port 2 mouse: button columns held low
k_mb    .byte 0
k_s     .byte 0
k_e     .byte 0
k_joy2  .byte 0
k_shift .byte 0
k_btn   .byte 0
k_new   .byte 0
