; Block mark, clipboard, cloning and bookmarks.
;
; Mark: CTRL held + C= pressed on Song/Chain/Phrase/Table starts a block at
; the cursor; CRSR then extends it (CTRL may stay held). In mark mode:
;   C=              copy the block to the clipboard, end marking
;   CTRL/C= + SPACE cut the block (copy, then clear), end marking
;   SPACE + CRSR    change every value in the block (transpose notes ...)
;   CTRL+(C=,SPACE) with the cursor not moved and CTRL held throughout, on a
;                   chain (Song) or phrase (Chain) number: clone it into a
;                   new item, deep or slim as set on the Project screen
; Outside mark mode C= + SPACE cuts the field under the cursor (a 1x1 block)
; and CTRL + SPACE pastes the clipboard at the cursor.
; Clipboard: clip_scr, width, height-1, field type per column, cells row by
; row in clip_buf. A 1x1 clip pastes on any field of the same type; a larger
; block only on its own screen, its first column on a field of the same type.
;
; Bookmarks (Song): C=, C=, C= toggles one on the cursor row; C= + Up/Down
; jumps to the previous/next one (wrapping) when any exist, else pages.

; ---------------------------------------------------------------------------
; mark the field under the cursor as a 1x1 block (anchor = cursor)
mark_here
        ldx screen
        lda rowv,x
        sta mark_row
        lda colv,x
        sta mark_col
        rts

; CTRL held, C= pressed
mark_start
        lda screen
        cmp #SC_GROOVE
        bcs _r
        jsr field_ptr           ; no list shown, or the Table title
        bcs _r
        lda ftype
        cmp #FT_FORM
        beq _r
        ldx screen              ; Instrument: only TABLE (clone it)
        cpx #SC_INSTR
        bne +
        cmp #FT_TABLE
        bne _r
+       jsr mark_here
        lda #1
        sta mark_on
        sta mark_ctrl
        lda #0
        sta mark_moved
        sta mark_quick
        beq dirty_list
_r      rts

dirty_lp                        ; RD_LIST | RD_PANEL
        lda #RD_LIST | RD_PANEL
        .byte $2c
dirty_list
        lda #RD_LIST
        ora dirty
        sta dirty
dl_rts  rts

; button presses while marking (START was handled by the grammar)
mark_input
        lda screen              ; Instrument TABLE: CTRL+(C=,SPACE) clones,
        cmp #SC_INSTR           ; any other press ends the mark
        bne +
        lda press
        beq dl_rts
        and #BT_A
        beq _end
        lda mark_ctrl           ; CTRL held throughout (grammar clears it)
        beq _end
        jsr clone
        jmp _end
+       lda press
        and #BT_A
        beq _noa
        lda btn
        and #BT_SELECT | BT_B
        beq _dirs               ; SPACE alone: nothing (SPACE + CRSR below)
        and #BT_SELECT
        beq _cut
        lda mark_ctrl
        beq _cut
        lda mark_moved
        bne _cut
        jsr clone
        bcc _end
_cut    jsr blk_cut
        jmp _end
_noa    lda press
        and #BT_B
        beq _dirs
        lda mark_ctrl           ; CTRL held since the mark began and the
        beq _copy               ; cursor not moved (or moved by quick-mark):
        lda mark_moved          ; C= again marks the column, then the screen
        beq +
        lda mark_quick
        cmp #1
        bne _copy
+       jmp quick_mark
_copy   jsr blk_copy
_end    lda #0
        sta mark_on
        beq dirty_list
_dirs   lda #0
        sta dir_i
_dir    ldx dir_i
        lda press
        and dir_bits,x
        beq _next
        lda btn
        and #BT_A
        beq +
        stx b_dir
        jsr mark_rect
        lda #<cb_edit
        ldy #>cb_edit
        jsr blk_each
        jsr dirty_list
        jmp _next
+       jsr move_dir
        lda screen              ; the Table title is no block row
        cmp #SC_TABLE
        bne +
        lda rowv+SC_TABLE
        bne +
        inc rowv+SC_TABLE
+       lda #1
        sta mark_moved
        jsr dirty_list
_next   inc dir_i
        lda dir_i
        cmp #4
        bne _dir
_r      rts

; Quick-mark (SELECT+B, B, B): the first extra C= marks the cursor's
; whole column (Song: rows 0 to the last row holding a chain), the second
; the whole screen.
quick_mark
        ldx screen
        lda mark_quick
        bne _all
        inc mark_quick
        sta mark_row            ; first row 0 (Table: 1, below the title)
        cpx #SC_TABLE
        bne +
        inc mark_row
+       lda rowmax,x
        cpx #SC_SONG
        bne _set
        ldy #255                ; Song: last row with a chain in any channel
-       lda SONG,y
        and SONG+$100,y
        and SONG+$200,y
        cmp #EMPTY
        bne +
        dey
        bne -
+       tya
_set    sta rowv,x
        lda #1
        sta mark_moved
        jsr song_scroll
        jmp dirty_list
_all    inc mark_quick
        lda #0
        sta mark_col
        lda colmax,x
        sta colv,x
        jmp dirty_list

cb_edit inc no_listen
        ldx b_dir
        jsr edit_dir
        dec no_listen
        rts

; block between anchor and cursor -> mr0..mr1, mc0..mc1 (rowv/colv terms)
mark_rect
        ldx screen
        lda rowv,x
        ldy mark_row
        cmp mark_row
        bcc +
        sty mr0
        sta mr1
        bcs ++
+       sta mr0
        sty mr1
+       lda colv,x
        ldy mark_col
        cmp mark_col
        bcc +
        sty mc0
        sta mc1
        rts
+       sta mc0
        sty mc1
        rts

; A = row being drawn (rowv terms): msel = $80 if it is in the marked block
; on the left part of the screen
mark_msel
        ldy #0
        sty msel
        ldy mark_on
        beq _r
        ldy xoff
        bne _r
        pha
        jsr mark_rect
        pla
        cmp mr0
        bcc _r
        cmp mr1
        beq +
        bcs _r
+       lda #$80
        sta msel
_r      rts

; ---------------------------------------------------------------------------
; Call the routine A/Y for each cell of the block mr0..mr1 x mc0..mc1, row
; by row, with the cursor on the cell, fp/ftype set (cells without a field
; are skipped) and cbp at the cell's clipboard byte. b_skip = clipboard
; bytes to skip after each row. The cursor is restored afterwards.
blk_each
        sta bjv
        sty bjv+1
        ldx screen
        lda rowv,x
        sta b_srow
        lda colv,x
        sta b_scol
        lda #<clip_buf
        sta cbp
        lda #>clip_buf
        sta cbp+1
        lda mr0
        sta b_r
_row    lda mc0
        sta b_c
_col    ldx screen
        lda b_r
        sta rowv,x
        lda b_c
        sta colv,x
        jsr field_ptr
        bcs +
        jsr _call
+       inc cbp
        bne +
        inc cbp+1
+       lda b_c
        cmp mc1
        bcs +
        inc b_c
        bne _col
+       lda cbp
        clc
        adc b_skip
        sta cbp
        bcc +
        inc cbp+1
+       lda b_r
        cmp mr1
        bcs +
        inc b_r
        bne _row
+       ldx screen
        lda b_srow
        sta rowv,x
        lda b_scol
        sta colv,x
        rts
_call   jmp (bjv)

; copy the marked block to the clipboard
blk_copy
        jsr mark_rect
        lda screen
        sta clip_scr
        lda mc1
        sec
        sbc mc0
        sta clip_w              ; width - 1 for now
        lda mr1
        sec
        sbc mr0
        sta clip_h1
        ldx #5
        lda #FT_NONE
-       sta clip_ft,x
        dex
        bpl -
        lda #0
        sta b_skip
        inc clip_w
        lda #<cb_copy
        ldy #>cb_copy
        jmp blk_each

cb_copy ldy #0
        lda (fp),y
        sta (cbp),y
        lda b_r                 ; first row: the column's field type
        cmp mr0
        bne +
        lda b_c
        sbc mc0                 ; carry set (b_r = mr0)
        tax
        lda ftype
        sta clip_ft,x
+       rts

; cut the marked block: copy it, then clear every field
blk_cut
        jsr blk_copy
        lda #<cb_cut
        ldy #>cb_cut
        jsr blk_each
        jmp dirty_list

cb_cut  jmp cell_clear

; CTRL + SPACE: paste the clipboard with its top left cell at the cursor
do_paste
        jsr field_ptr
        bcs _r
        lda ftype
        cmp #FT_FORM
        beq _r
        cmp clip_ft
        bne _r
        lda clip_w              ; 1x1: any field of the same type
        cmp #1
        bne _blk
        lda clip_h1
        bne _blk
        lda clip_buf
        jmp fld_store
_blk    lda clip_scr
        cmp screen
        bne _r
        jsr mark_here           ; target block: cursor + clip size, clipped
        lda mark_row
        sta mr0
        clc
        adc clip_h1
        bcc +
        lda #$ff
+       ldx screen
        cmp blk_rmax,x
        bcc +
        lda blk_rmax,x
+       sta mr1
        lda mark_col
        sta mc0
        clc
        adc clip_w
        sec
        sbc #1
        cmp colmax,x
        bcc +
        lda colmax,x
+       sta mc1
        sec                     ; clipboard bytes beyond the target width
        sbc mc0
        sta tmp
        lda clip_w
        clc
        sbc tmp                 ; clip_w - (mc1 - mc0) - 1
        sta b_skip
        lda #<cb_paste
        ldy #>cb_paste
        jsr blk_each
        jsr fld_touch
        jmp dirty_list
_r      rts

;               SNG CHN PHR INS TBL
blk_rmax .byte 255, 15, 15, 0, 16

cb_paste
        lda b_c                 ; same field type as the clipboard column
        sec
        sbc mc0
        tax
        lda clip_ft,x
        cmp ftype
        bne _r
        ldy #0
        lda (cbp),y
        sta (fp),y
        sta tmp
        ldx ftype               ; used items get their allocation bit
        lda ft_hasempty,x
        beq +
        lda tmp
        cmp ft_emptyv,x
        beq _r
+       lda ft_alloc,x
        bmi _r
        tax
        lda tmp
        jmp alloc_set
_r      rts

; ---------------------------------------------------------------------------
; Clone the chain (Song) or phrase (Chain) number under the cursor into a
; new unused item and put the new number in its place. Deep (clone_mode 0):
; a chain's phrases are cloned too (a phrase used twice gets one copy).
; Carry set: no chain/phrase number under the cursor (nothing done).
clone
        jsr field_ptr
        bcs _no
        ldy #0
        lda (fp),y
        sta cl_src
        lda ftype
        cmp #FT_PHRASE
        beq _ph
        cmp #FT_INSTR
        beq _in
        cmp #FT_TABLE
        beq _tb
        cmp #FT_CHAIN
        bne _no
        lda cl_src
        bpl _ch
_no     sec
        rts
_tb     lda cl_src              ; table: copy into a new table
        cmp #NTABLES
        bcs _no
        jsr tbl_clone
        bcc _st
_full   lda #<m_full
        ldy #>m_full
        jmp msg_set_c
_in     lda cl_src              ; instrument: copy, deep also its table
        cmp #NINSTR
        bcs _no
        ldx #2
        jsr alloc_new
        bcs _full
        sta cl_new
        jsr instr_addr
        jsr ptr_ptr2
        lda cl_src
        jsr instr_addr
        ldy #15
-       lda (ptr),y
        sta (ptr2),y
        dey
        bpl -
        lda cl_new
        ldx #2
        jsr alloc_set
        ldy #IN_TABLE
        lda (ptr),y
        ldx clone_mode          ; slim: shares the table
        bne _inok
        cmp #NTABLES
        bcs _inok
        jsr tbl_clone
        bcs _inok               ; no free table: shares it
        pha
        lda cl_new
        jsr instr_addr
        pla
        ldy #IN_TABLE
        sta (ptr),y
_inok   lda cl_new
_st     jmp _store
_ph     lda cl_src
        cmp #EMPTY
        beq _no
        ldx #1
        jsr alloc_new
        bcs _noph
        sta cl_new
        tax
        lda cl_src
        jsr phrase_copy
        jmp _inok
_noph   lda #<m_noph
        ldy #>m_noph
        jmp msg_set_c
_ch     ldx #0
        jsr alloc_new
        bcc +
        lda #<m_noch
        ldy #>m_noch
        jmp msg_set_c
+       sta cl_new
        lda cl_src              ; source chain -> cl_tmp
        jsr chain_addr
        ldy #31
-       lda (ptr),y
        sta cl_tmp,y
        dey
        bpl -
        lda clone_mode
        bne _write              ; slim: same phrases
        sta cl_need             ; deep: count distinct phrases (A = 0)
        tay
-       jsr cl_first
        bcs +
        inc cl_need
+       iny
        iny
        cpy #32
        bne -
        jsr cl_free             ; enough free phrases?
        bcc +
        lda #<m_noph
        ldy #>m_noph
        jmp msg_set_c
+       ldy #0                  ; copy each distinct phrase
_deep   sty cl_y
        jsr cl_first
        bcs _same
        ldx #1
        jsr alloc_new           ; cannot fail: counted above
        sta cl_ph
        tax
        ldy cl_y
        lda cl_tmp,y
        jsr phrase_copy
        ldy cl_y
        lda cl_ph
        sta cl_new2,y
        jmp _dnext
_same   lda cl_new2,x           ; X = earlier step with the same phrase
        sta cl_new2,y
_dnext  iny
        iny
        cpy #32
        bne _deep
        ldy #0
-       lda cl_tmp,y
        cmp #EMPTY
        beq +
        lda cl_new2,y
        sta cl_tmp,y
+       iny
        iny
        cpy #32
        bne -
_write  lda cl_new
        jsr chain_addr
        ldy #31
-       lda cl_tmp,y
        sta (ptr),y
        dey
        bpl -
        lda cl_new
        ldx #0
        jsr alloc_set
        lda cl_new
_store  pha
        jsr field_ptr
        pla
        jsr fld_store
        jsr dirty_list
        clc
        rts

; A = table: copy its 6 columns into a new table. A = new table, carry
; clear; carry set if none is free.
tbl_clone
        sta cl_ph
        ldx #3
        jsr alloc_new
        bcs _r
        sta cl_t
        jsr tbl_ptr
        jsr ptr_ptr2
        lda cl_ph
        jsr tbl_ptr
        ldx #6
-       ldy #15
-       lda (ptr),y
        sta (ptr2),y
        dey
        bpl -
        inc ptr+1               ; next column: +512
        inc ptr+1
        inc ptr2+1
        inc ptr2+1
        dex
        bne --
        lda cl_t
        ldx #3
        jsr alloc_set
        lda cl_t
        clc
_r      rts

; A = table: ptr = its first column (TABLES + t*16)
tbl_ptr pha
        asl
        asl
        asl
        asl
        sta ptr
        pla
        lsr
        lsr
        lsr
        lsr
        clc
        adc #>TABLES
        sta ptr+1
        rts

ptr_ptr2
        lda ptr
        sta ptr2
        lda ptr+1
        sta ptr2+1
        rts

; Y = step*2 in cl_tmp: carry clear if its phrase is the first occurrence
; (not empty); carry set if empty, or an earlier step X has the same phrase
cl_first
        lda cl_tmp,y
        cmp #EMPTY
        beq _set
        ldx #0
-       stx tmp
        cpy tmp
        beq _clr
        cmp cl_tmp,x
        beq _set
        inx
        inx
        bne -
_clr    clc
        rts
_set    sec
        rts

; carry clear if at least cl_need phrases are free
cl_free lda cl_need
        beq _ok
        lda #0
        sta cl_y
-       lda cl_y
        ldx #1
        jsr alloc_test
        bne +
        lda cl_y
        ldx #1
        jsr item_empty
        bne +
        dec cl_need
        beq _ok
+       inc cl_y
        lda cl_y
        cmp #NPHRASES
        bne -
        rts                     ; carry set
_ok     clc
        rts

; A = source phrase, X = new phrase: copy the 64 bytes, mark it used
phrase_copy
        pha
        txa
        pha
        jsr phrase_addr
        jsr ptr_ptr2
        pla
        sta cl_ph
        pla
        jsr phrase_addr
        ldy #63
-       lda (ptr),y
        sta (ptr2),y
        dey
        bpl -
        lda cl_ph
        ldx #1
        jmp alloc_set

; message and carry clear (the clone was attempted)
msg_set_c
        jsr msg_set
        clc
        rts

; ---------------------------------------------------------------------------
; Bookmarks: bit per song row in bm_bits

; C= taps on the Song screen: the third within the window toggles
tap_b   lda press
        cmp #BT_B
        bne _reset
        cmp btn
        bne _reset
        lda screen
        bne _reset
        lda mark_on
        bne _reset
        lda b_timer
        bne +
        sta b_count
+       inc b_count
        lda #DBL_FRAMES
        sta b_timer
        lda b_count
        cmp #3
        bcc _r
        lda #0
        sta b_count
        sta b_timer
        lda srow
        jsr bm_pos
        eor bm_bits,y
        sta bm_bits,y
        lda #RD_ROW
        ora dirty
        sta dirty
_r      rts
_reset  lda #0
        sta b_count
        rts

; A = row -> Y = byte index, A = bit
bm_pos  pha
        lsr
        lsr
        lsr
        tay
        pla
        and #7
        tax
        lda bitmask,x
        rts

; A = row: Z clear if bookmarked (X, Y clobbered: callers keep them)
bm_test stx bm_x
        sty bm_y
        jsr bm_pos
        and bm_bits,y
        ldx bm_x
        ldy bm_y
        ora #0
        rts

; Z clear if any bookmark exists
bm_any  lda #0
        ldy #31
-       ora bm_bits,y
        dey
        bpl -
        ora #0
        rts

; X = 0 up / 1 down: cursor to the previous/next bookmark (wrapping)
bm_jump stx dir_t
        lda srow
        sta bm_r
        ldx #255
-       lda dir_t
        bne +
        dec bm_r
        jmp ++
+       inc bm_r
+       lda bm_r
        jsr bm_test
        bne _found
        dex
        bne -
        rts
_found  lda bm_r
        sta srow
        jmp song_scroll

; ---------------------------------------------------------------------------
; state
mark_on    = $de                ; zp; block marking active
mark_ctrl  .byte 0              ; CTRL held since the mark began
mark_moved .byte 0              ; cursor moved since the mark began
mark_row   .byte 0              ; anchor (rowv/colv terms)
mark_col   .byte 0
mr0        .byte 0              ; block rectangle (mark_rect)
mr1        .byte 0
mc0        .byte 0
mc1        .byte 0
msel       .byte 0              ; $80: the row being drawn is in the block
clone_mode = HD_CLONE           ; 0 deep, 1 slim (Project screen; saved with the project)
b_count    .byte 0
b_dir      .byte 0
b_r        .byte 0
b_c        .byte 0
b_srow     .byte 0
b_scol     .byte 0
b_skip     .byte 0
bjv        .word 0
cl_src     .byte 0
cl_new     = $df                ; zp
cl_need    .byte 0
cl_y       .byte 0
cl_ph      .byte 0
cl_t       .byte 0
mark_quick .byte 0              ; quick-mark level: 0 none, 1 column, 2 screen
bm_x       .byte 0
bm_y       .byte 0
bm_r       .byte 0
clip_scr   .byte 0
clip_w     .byte 0              ; block width (1-6)
clip_h1    .byte 0              ; block height - 1 (0-255)
clip_ft    .fill 6, FT_NONE     ; field type per column, FT_NONE = empty clipboard
        .virtual $0801          ; M10: the BASIC stub and boot (main.asm), dead after start-up
cl_tmp     .fill 32             ; chain being cloned
        .cerror * > EDLOW
        .endv
cl_new2    .fill 32, 0          ; new phrase per chain step (deep clone)
bm_bits    = HD_BOOKMARKS       ; bookmarked song rows (saved with the project)
clip_buf   = CLIPBUF            ; 3 x 256: up to a whole song column block
