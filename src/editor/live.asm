; Live mode, help-line messages
; and the File screen on top of the FILEIO module.
;
; Live mode (pl_live = 1, CTRL+Left on Song toggles it). On the Song screen:
;   RETURN            queue the chain under the cursor on its channel
;   RETURN, RETURN    the same, switching at the end of the playing phrase
;   CTRL + RETURN     queue a stop of the cursor channel (twice: phrase end)
;   Left + RETURN     (SHIFT + CRSR RIGHT held) queue the whole row
; The player switches at the end of the playing chain; stopped channels
; start in step with the playing ones. Display: '>' and a white cell for the
; playing chain, a blinking '*' before a queued one, a blinking 'X' in the
; channel header for a queued stop.

live_start
        jsr ret_mode
        lda btn
        and #BT_LEFT
        beq _one
        ldx #0                  ; the whole row: every channel with a chain
-       stx q_x
        txa
        clc
        adc #>SONG
        sta ptr+1
        lda srow
        sta ptr
        ldy #0
        lda (ptr),y
        bmi +
        lda srow
        ldy q_mode
        jsr player_queue
+       ldx q_x
        inx
        cpx pl_nch
        bne -
        rts
_one    jsr song_cell
        bmi _r                  ; empty (or a clip, later)
        ldx scol
        lda srow
        ldy q_mode
        jmp player_queue
_r      rts

live_stop
        jsr ret_mode
        ldx scol
        ldy q_mode
        jmp player_queue_stop

; q_mode = 1 if this is the second press of the same RETURN combo on the same
; cell within DBL_FRAMES (switch at the phrase end), else 0
ret_mode
        lda btn
        and #BT_LEFT | BT_SELECT
        ora scol
        ldx #0
        ldy ret_timer
        beq +
        cmp ret_key
        bne +
        ldy srow
        cpy ret_row
        bne +
        inx
+       stx q_mode
        sta ret_key
        lda srow
        sta ret_row
        lda #DBL_FRAMES
        cpx #0
        beq +
        lda #0                  ; a third press starts over
+       sta ret_timer
        rts

; ---------------------------------------------------------------------------
; Help-line messages: msg_buf (20 screen codes) replaces the help text until
; the next button press.

; A/Y = 0-terminated screen-code string
msg_set sta ptr
        sty ptr+1
        ldy #0
-       lda (ptr),y
        beq +
        sta msg_buf,y
        iny
        cpy #20
        bne -
+       lda #$20
-       cpy #20
        beq msg_show
        sta msg_buf,y
        iny
        bne -
msg_show
        lda #1
        sta msg_on
        lda #$ff                ; redraw the help line even if one is shown
        sta d_help
        rts

; A = confirm id: Z set (go) if the previous press asked for this one, else
; ask ("press again") and return Z clear
confirm_q
        cmp confirm
        bne +
        lda #0
        sta confirm
        rts
+       sta confirm
        lda #<m_again
        ldy #>m_again
        jsr msg_set
        lda #1
        rts

CF_CLEAN = 1
CF_LOAD  = 2
CF_DEL   = 3

; Call a FILEIO routine (A/Y = address, X = argument). Its fio_msg goes to
; the help line. Carry as returned (set = error).
fio_call
        sta fjv
        sty fjv+1
        lda #0
        sta mark_on
        jsr _go
        php
        ldx #19
-       lda fio_msg,x
        sta msg_buf,x
        dex
        bpl -
        jsr msg_show
        plp
        rts
_go     jmp (fjv)

; ---------------------------------------------------------------------------
; Project screen actions (SPACE on LOAD SAVE CLEAN). Export: tools/sidj2sid.py
proj_action
        ldy ffield
        lda fl_arg,y
        beq _load
        cmp #2
        bcc _save
        bcs _clean
_load   lda #1                  ; File screen, cursor on the first file
        .byte $2c
_save   lda #0                  ; File screen, cursor on SAVE
        jmp file_enter
_clean  lda #CF_CLEAN
        jsr confirm_q
        bne _r
        lda #<fio_clean
        ldy #>fio_clean
        jsr fio_call
        bcs _r
        ldx #ALLOC_TABLES + 4 - ALLOC_CHAINS - 1
        lda #0                  ; nothing is used any more
-       sta ALLOC_CHAINS,x
        dex
        bpl -
        bmi new_song
_r      rts

; after a load or clean: allocation, cursors, bookmarks, full redraw
new_song
        jsr alloc_rebuild
        lda #0
        ldx #SC_GROOVE
-       sta colv,x
        dex
        bpl -
        sta srow
        sta crow
        sta prow
        sta song_top
        sta mark_on
        sta cur_chan
        sta cur_songrow
        ldx #cur_groove - cur_chain
-       sta cur_chain,x
        dex
        bpl -
        lda #1
        sta rowv+SC_INSTR
        sta rowv+SC_TABLE
        sta rowv+SC_GROOVE
        sta need_clear
        lda #$ff
        ldx #NSNAP-1
-       sta pl_snap,x
        dex
        bpl -
        jmp undo_reset          ; new project: no history

; ---------------------------------------------------------------------------
; File screen. Rows: 0 = SAVE (as the project name), 1.. = FIO_DIR entries
; (drive fio_device, or with device REU every REU slot, free ones "-").
;   SPACE           row 0: save; a file: load (press twice)
;   C= + SPACE      delete the file (press twice)
;   CRSR left/right device: drive / REU (only with REU slots)
;   CTRL + Up       back to the Project screen

; A = start row: read the directory, show the screen
file_enter
        pha
        lda #SC_FILE
        sta screen
        lda #1
        sta need_clear
        lda #0
        sta file_top
        jsr file_dir
        pla
        cmp fcount
        bcc +
        lda fcount
+       sta rowv+SC_FILE
        jmp file_scroll

; read the directory (message on the help line); fcount = entries (0 on error)
file_dir
        lda #2
        jsr file_op             ; drive or REU slots (high.asm)
        lda #0
        bcs +
        lda FIO_DIRCOUNT
        cmp #33
        bcc +
        lda #32
+       sta fcount
        lda rowv+SC_FILE
        cmp fcount
        bcc +
        beq +
        lda fcount
        sta rowv+SC_FILE
+       jmp dirty_lp

; directory again after a save/delete, keeping that call's message
file_refresh
        ldx #19
-       lda msg_buf,x
        sta msg_keep,x
        dex
        bpl -
        jsr file_dir
        ldx #19
-       lda msg_keep,x
        sta msg_buf,x
        dex
        bpl -
        jsr file_scroll
        jmp msg_show

; SPACE / C= + SPACE on the File screen
file_input
        lda press
        and #BT_A
        beq _r
        lda btn
        and #BT_SELECT
        bne _r
        lda btn
        and #BT_B
        bne _del
        lda rowv+SC_FILE
        bne _load
        jsr file_op             ; A = 0: save
        bcs _r
        bcc file_refresh
_load   lda #CF_LOAD
        jsr confirm_q
        bne _r
        ldx rowv+SC_FILE
        dex
        lda #1
        jsr file_op
        bcs _r
        jsr new_song
        lda #SC_SONG
        sta screen
        rts
_del    lda rowv+SC_FILE
        beq _r
        lda #CF_DEL
        jsr confirm_q
        bne _r
        ldx rowv+SC_FILE
        dex
        lda #3
        jsr file_op
        bcc file_refresh
_r      rts

; CRSR on the File screen (dir_t = direction)
file_move
        lda dir_t
        bne +
        lda rowv+SC_FILE
        beq file_rts
        dec rowv+SC_FILE
        jmp file_scroll
+       cmp #1
        beq +
        jmp file_dev            ; left / right: device (high.asm)
+       lda rowv+SC_FILE
        cmp fcount
        bcs file_rts
        inc rowv+SC_FILE
        ; fall through
file_scroll
        lda rowv+SC_FILE
        cmp file_top
        bcs +
        sta file_top
        rts
+       sec
        sbc file_top
        cmp #16
        bcc file_rts
        lda rowv+SC_FILE
        sbc #15
        sta file_top
file_rts
        rts

        .enc "screen"
; left part: row 1 labels, rows 2-17 the list from file_top
file_full
        ldx #1
        jsr line_pd
        .null "   name"
        jsr line_end
        lda #0
        sta step
-       jsr file_row
        inc step
        lda step
        cmp #16
        bne -
        rts

; A = list row: redraw it if visible
file_rowa
        sec
        sbc file_top
        cmp #16
        bcs +
        sta step
        bcc file_row
+       rts

; list row file_top + step at screen row step + 2: "SV name" / "NN name"
file_row
        lda step
        clc
        adc #2
        tax
        jsr line_at
        lda file_top
        clc
        adc step
        sta item
        ldx #0
        cmp rowv+SC_FILE
        bne +
        ldx #$80
+       stx rowsel
        lda item
        bne _file
        lda #COL_HEAD
        sta dcolor
        jsr prt
        .null "sv "
        lda #<HD_NAME
        ldy #>HD_NAME
        bne _name
_file   cmp fcount
        beq +
        bcs _end
+       lda #COL_DIM
        sta dcolor
        ldx item
        dex
        txa
        jsr puthex
        jsr space
        ldx item
        dex
        txa
        jsr item16
        clc
        adc #<FIO_DIR
        pha
        txa
        adc #>FIO_DIR
        tay
        pla
_name   sta ptr2
        sty ptr2+1
        lda rowsel
        sta drev
        lda accent
        sta dcolor
        ldy #0
-       sty tmp2
        lda (ptr2),y
        and #$7f
        bne +
        lda #$20                ; $00 padding shows as a space
+       jsr putc
        ldy tmp2
        iny
        cpy #16
        bne -
_end    jmp line_end

; panel: device, file count, keys
file_panel
        lda #20
        sta xoff
        ldx #1
        jsr line_ph
        .null "device "
        jsr dev_show
        jsr line_end
        ldx #2
        jsr line_pt
        .null "files  "
        lda fcount
        jsr puthex
        jsr line_end
        lda #0
        sta step
-       ldx step
        lda fp_lo,x
        ldy fp_hi,x
        sta ptr2
        sty ptr2+1
        txa
        sbx #256-4              ; X += 4
        lda #COL_DIM
        jsr line_atc
        lda ptr2
        ldy ptr2+1
        jsr putstr
        jsr line_end
        inc step
        lda step
        cmp #6
        bne -
        lda #10
        jmp blank_rows

_fp0    .null "spc    save, load"
_fp1    .null "       (load: x2)"
_fp2    .null "c=+spc delete (x2)"
_fp3    .null "ctrl+u project"
_fp4    .null "c=+spc on sv: kit"
fp_lo   .byte <_fp0, <_fp1, <_fp2, <_fp3, <_fp4, <s_fp5
fp_hi   .byte >_fp0, >_fp1, >_fp2, >_fp3, >_fp4, >s_fp5

m_again .null "spc again: confirm"
m_noch  .null "no free chain"
m_noph  .null "not enough phrases"
m_full  .null "none free"
        .enc "none"

; state
q_x      .byte 0
q_mode   .byte 0
ret_key  .byte $ff
ret_row  .byte 0
msg_on   .byte 0
msg_buf  .fill 20, $20
msg_keep .fill 20, $20
confirm  .byte 0
fjv      .word 0
fcount   .byte 0                ; directory entries shown
file_top .byte 0
