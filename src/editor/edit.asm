; Grammar: turns btn/press/key into cursor moves, field
; edits, screen changes and player calls. Only press bits act; btn tells
; which modifiers are held (SPACE = A, C= = B, CTRL = SELECT, RETURN = START).

grammar
        lda mark_on             ; clone needs CTRL held since the mark began
        beq +
        lda btn
        and #BT_SELECT
        bne +
        sta mark_ctrl
+       lda key
        cmp #KC_NONE
        beq +
        jsr on_key
+       lda press
        bne +
        rts
+       ldx #0
        stx tdig                ; any button ends a typed tempo
        stx msg_on              ; and removes a message from the help line
        cmp #BT_A               ; only a lone SPACE keeps the double-tap window
        beq +
        stx dbl_timer
        stx confirm             ; and a pending confirmation
+       jsr tap_b               ; C=, C=, C= (bookmark)
        lda press
        and #BT_START
        beq _nostart
        lda btn
        and #BT_B
        beq +
        jsr do_solo             ; C= + RETURN
        jmp _nostart
+       lda btn
        and #BT_SELECT
        beq +
        jsr play_all            ; CTRL + RETURN
        jmp _nostart
+       jsr play_screen         ; RETURN
_nostart
        lda mark_on
        beq +
        jmp mark_input          ; marking: SPACE/C=/CRSR act on the block
+       lda screen
        cmp #SC_FILE
        bne +
        jsr file_input          ; File screen: SPACE/C= are file actions
        jmp _noa
+       lda press               ; C= held, CTRL pressed: mute
        and #BT_SELECT
        beq +
        lda btn
        and #BT_B
        beq +
        jsr do_mute
        jmp ++                  ; both pressed in one frame: mute only
+       lda press               ; CTRL held, C= pressed: mark block
        and #BT_B
        beq +
        lda btn
        and #BT_SELECT
        beq +
        jsr mark_start_g        ; (not in the grid view)
+       lda press
        and #BT_A
        beq _noa
        lda btn
        and #BT_B
        beq +
        jsr do_cut              ; C= + SPACE
        jmp _noa
+       lda btn
        and #BT_SELECT
        beq +
        jsr do_paste            ; CTRL + SPACE
        jmp _noa
+       jsr do_tap              ; SPACE
_noa    lda #0
        sta dir_i
_dir    ldx dir_i
        lda press
        and dir_bits,x
        beq _dnext
        lda btn
        and #BT_SELECT
        beq +
        jsr nav_screen          ; CTRL + CRSR
        jmp _dnext
+       lda btn
        and #BT_A
        beq +
        jsr edit_dir            ; SPACE + CRSR
        jmp _dnext
+       lda btn
        and #BT_B
        beq +
        jsr page_dir            ; C= + CRSR
        jmp _dnext
+       jsr move_dir            ; CRSR
_dnext  inc dir_i
        lda dir_i
        cmp #4
        bne _dir
        rts

dir_bits .byte BT_UP, BT_DOWN, BT_LEFT, BT_RIGHT

; ---------------------------------------------------------------------------
; Field under the cursor -> fp, ftype. Carry set = no editable field.
field_ptr
        lda screen
        bne _chain
        lda srow                ; Song: SONG + channel*256 + row
        sta fp
        lda scol
        clc
        adc #>SONG
        sta fp+1
        lda #FT_CHAIN
        sta ftype
        clc
        rts
_chain  cmp #SC_CHAIN
        bne _phrase
        lda cur_chain
        bmi _none
        jsr chain_addr
        lda crow
        asl
        ora ccol
        ora ptr                 ; chains are 32-byte aligned
        sta fp
        lda ptr+1
        sta fp+1
        lda ccol
        clc
        adc #FT_PHRASE
        sta ftype
        clc
        rts
_phrase cmp #SC_PHRASE
        bne field_ptr2
+       lda cur_phrase
        cmp #EMPTY
        beq _none
        jsr phrase_addr
        lda prow
        asl
        asl
        ora pcol
        ora ptr                 ; phrases are 64-byte aligned
        sta fp
        lda ptr+1
        sta fp+1
        lda pcol
        clc
        adc #FT_NOTE
        sta ftype
        clc
        rts
_none   lda #FT_NONE
        sta ftype
        sec
        rts

; Instrument/Project (forms), Table and Groove
field_ptr2
        cmp #SC_INSTR
        beq _form
        cmp #SC_PROJECT
        beq _form
        cmp #SC_TABLE
        beq _table
        cmp #SC_GROOVE
        bne field_none
        lda rowv+SC_GROOVE      ; row 0 = groove number
        beq field_item
        sbc #1                  ; GROOVES + g*16 + step (carry set: = SC_GROOVE)
        sta tmp
        lda cur_groove
        jsr item16
        ora tmp
        sta fp
        txa
        adc #>GROOVES           ; carry clear from item16
        sta fp+1
        lda #FT_GROOVE
        sta ftype
        clc
        rts
_form   jmp form_fptr
_table  lda rowv+SC_TABLE       ; row 0 = table number
        beq field_item
        sec                     ; TABLES + col*512 + t*16 + step
        sbc #1
        sta tmp
        lda cur_table
        jsr item16
        ora tmp
        sta fp
        lda colv+SC_TABLE
        tay
        asl
        stx tmp
        adc tmp
        adc #>TABLES
        sta fp+1
        lda tb_ft,y
        sta ftype
        clc
        rts
field_item
        lda #K_ITEM             ; the number in the title line
        sta fkind
        lda #FT_FORM
        sta ftype
        clc
        rts
field_none
        lda #FT_NONE
        sta ftype
        sec
        rts

tb_ft   .byte FT_CTL, FT_TRANSP, FT_CMD, FT_VAL, FT_CMD, FT_VAL

; A = item < 32 -> A = (item & 15) * 16, X = item >> 4, carry clear
item16  pha
        lsr
        lsr
        lsr
        lsr
        tax
        pla
        asl
        asl
        asl
        asl
        clc
        rts

; A = chain (< 128) -> ptr = CHAINS + chain*32
chain_addr
        pha
        lsr
        lsr
        lsr
        clc
        adc #>CHAINS
        sta ptr+1
        pla
        asl
        asl
        asl
        asl
        asl
        sta ptr
        rts

; A = phrase -> ptr = PHRASES + phrase*64
phrase_addr
        pha
        lsr
        lsr
        clc
        adc #>PHRASES
        sta ptr+1
        pla
        ror                     ; bits 0-1 -> 6-7
        ror
        ror
        and #$c0
        sta ptr
        rts

; A = chain under the Song cursor
song_cell
        lda srow
        sta ptr
        lda scol
        clc
        adc #>SONG
        sta ptr+1
        ldy #0
        lda (ptr),y
        rts

; A = phrase at the Chain cursor step
chain_cell
        lda cur_chain
        jsr chain_addr
        lda crow
        asl
        tay
        lda (ptr),y
        rts

; A = instrument of the Phrase cursor step, or the nearest one above it
phrase_instr
        lda cur_phrase
        cmp #EMPTY
        beq _r
        jsr phrase_addr
        lda prow
        asl
        asl
        tay
        iny
-       lda (ptr),y
        cmp #EMPTY
        bne _r
        dey
        dey
        dey
        dey
        bpl -
_r      rts

; X = channel under the cursor (Song: cursor column, else context channel)
cursor_chan
        ldx scol
        lda screen
        beq +
        ldx cur_chan
+       rts

; ---------------------------------------------------------------------------
; Field edits. Field types: see FT_* in editor.asm.
;                 CHN PHR TRN NOT INS CMD VAL TBL CTL GRV FORM
ft_hasempty .byte 1,  1,  0,  1,  1,  1,  0,  1,  1,  1,  0
ft_emptyv   .byte EMPTY, EMPTY, 0, EMPTY, EMPTY, 0, 0, EMPTY, EMPTY, 0, 0
ft_max      .byte $7f, NPHRASES-1, $ff, $5f, NINSTR-1, 26, $ff, NTABLES-1, $fe, $ff, 0
ft_min      .byte 0,  0,  0,  0,  0,  1,  0,  0,  0,  1,  0
ft_big      .byte $10, $10, 12, 12, $10, 4, $10, $10, $10, $10, 0
ft_alloc    .byte 0,  1, $ff, $ff, 2, $ff, $ff, 3, $ff, $ff, $ff ; bitmap marked on store
ft_new      .byte 1,  1,  0,  0,  0,  0,  0,  1,  0,  0,  0  ; SPACE,SPACE makes a new item
        .cerror * - ft_new != NFT, "ft_* out of sync"

; Z set if the field at fp holds its empty value
fld_empty
        ldy #0
        ldx ftype
        lda ft_hasempty,x
        beq +
        lda (fp),y
        cmp ft_emptyv,x
        rts
+       lda #1                  ; types without empty: never empty
        rts

; A = new value: store, remember as last value, mark the item used
fld_store
        ldy #0
        sta (fp),y
        ldx ftype
        sta tmp
        lda ft_hasempty,x
        beq +
        lda tmp
        cmp ft_emptyv,x
        beq fld_touch
+       lda tmp
        sta last,x
        lda ft_alloc,x
        bmi fld_touch
        tax
        lda tmp
        jsr alloc_set
        ; fall through

; the item being edited holds data now; request the row redraw
fld_touch
        lda #RD_ROW
        ora dirty
        sta dirty
        lda screen
        cmp #SC_INSTR
        bne +
        ldx #2                  ; instrument used
        lda cur_instr
        jsr alloc_test
        bne _r
        lda cur_instr
        jsr alloc_set
        jmp dirty_list          ; usage map changes
+       cmp #SC_TABLE
        bne +
        ldx #3
        lda cur_table
        jmp alloc_set
+       cmp #SC_GROOVE
        bne _r
        lsr a                   ; A = SC_GROOVE -> RD_PANEL: groove summary
        .cerror SC_GROOVE >> 1 != RD_PANEL
        ora dirty
        sta dirty
_r      rts

; SPACE alone: empty field -> last value (new chain/phrase if none yet);
; second tap within DBL_FRAMES on what the first tap inserted -> new item;
; filled field -> remember its value.
do_tap
        jsr field_ptr
        bcs _r
        lda ftype
        cmp #FT_FORM
        bne +
        lda fkind
        cmp #K_ACTION
        bne _lis
        jmp proj_action         ; LOAD SAVE CLEAN
_lis    jmp prelisten           ; other form fields: SPACE only listens
+       jsr fld_empty
        bne _filled
        lda ft_new,x
        beq _ins
        lda last,x
        cmp #EMPTY
        beq _new
_ins    lda last,x
        jsr fld_store
        lda #DBL_FRAMES
        sta dbl_timer
        jsr note_fill
        jmp prelisten
_filled lda dbl_timer
        beq _keep
        lda ft_new,x
        beq _keep
        lda (fp),y
        cmp last,x
        bne _keep
_new    lda ft_alloc,x
        tax
        jsr alloc_new
        bcs _r
        jsr fld_store
        lda #0
        sta dbl_timer
_r      rts
_keep   lda (fp),y
        sta last,x
        jmp prelisten

; A note entered on an empty step also gets the last instrument
note_fill
        lda ftype
        cmp #FT_NOTE
        bne +
        ldy #PH_INSTR
        lda (fp),y
        cmp #EMPTY
        bne +
        lda last+FT_INSTR
        sta (fp),y
+       rts

; C= + SPACE: field to the clipboard (a 1x1 block), then clear it
do_cut
        jsr field_ptr
        bcs _r
        ldx ftype
        cpx #FT_FORM
        bne +
        jmp form_cut
+       jsr mark_here
        jmp blk_cut
_r      rts

; clear the field at fp (ftype): empty value; a command clears its value
cell_clear
        ldx ftype
        ldy #0
        lda ft_emptyv,x
        sta (fp),y
        cpx #FT_CMD
        bne _t
        lda screen              ; value: next byte, or next column in tables
        cmp #SC_TABLE
        beq +
        iny                     ; (M10 fix: iny after lda #0 left Z clear,
        lda #0                  ; so a phrase command also cleared fp+$201)
        sta (fp),y
        beq _t
+       inc fp+1
        inc fp+1
        lda #0
        sta (fp),y
_t      jmp fld_touch

; SPACE + CRSR (X = direction 0 up 1 down 2 left 3 right):
; right/left = +-1, up/down = +-big step; empty fields stay empty.
edit_dir
        stx dir_t
        jsr field_ptr
        bcs _nf
        lda ftype
        cmp #FT_FORM
        bne +
        jsr form_dir
        jmp prelisten
+       jsr fld_empty
        beq _r
        lda ft_big,x
        ldy dir_t
        cpy #2
        bcc +
        lda #1
+       cpy #1                  ; down and left are negative
        beq _neg
        cpy #2
        bne +
_neg    eor #$ff
        clc
        adc #1
+       sta tmp
        ldy #0
        lda ft_hasempty,x
        bne _clamp
        lda (fp),y              ; full-range byte: wrap
        clc
        adc tmp
        jmp _st
_clamp  lda tmp
        bmi _down
        lda (fp),y
        clc
        adc tmp
        bcs _max
        cmp ft_max,x
        bcc _st
        beq _st
_max    lda ft_max,x
        jmp _st
_down   lda (fp),y
        clc
        adc tmp
        bcc _min
        cmp ft_min,x
        bcs _st
_min    lda ft_min,x
_st     jsr fld_store
        jmp prelisten
_nf     jmp sid_dir             ; no field: SID setup (high.asm)
_r      rts

; Typed char (A = KC_*): F1/F3/F5 mute, else hex/note/command entry
on_key
        cmp #KC_F1
        bcc _type
        sbc #KC_F1
        cmp #NCHAN
        bcc +
        jmp undo_key            ; F7 / F8 (high.asm)
+       tax
        jmp mute_x
_type   sta kcode
        jsr field_ptr
        bcs _r
        lda #0
        sta dbl_timer
        lda ftype
        cmp #FT_FORM
        bne +
        jmp form_key
+       cmp #FT_NOTE
        beq key_note
        cmp #FT_CMD
        beq key_cmd
        lda kcode               ; hex digit shifted in from the right
        cmp #16
        bcs _r
        jsr fld_empty
        bne +
        lda #0
        beq ++
+       lda (fp),y
+       asl
        asl
        asl
        asl
        ora kcode
        cmp ft_max,x
        bcc +
        beq +
        lda kcode               ; out of range: start again from the digit
+       jmp fld_store
_r      rts

key_cmd lda kcode               ; letter -> command 1..26
        sec
        sbc #10
        bcc +
        adc #0                  ; carry set: +1
        jmp fld_store
+       rts

; Note field: 0-7 = octave, A-G = natural note, keeping the other part
key_note
        ldy #0
        lda (fp),y
        cmp #EMPTY
        bne +
        lda last+FT_NOTE
+       jsr div12               ; tmp = octave, A = semitone
        sta tmp2
        lda kcode
        cmp #8
        bcs +
        sta tmp
        bcc _make
+       sec
        sbc #10
        bcc _r
        cmp #7
        bcs _r
        tax
        lda letter_semi,x
        sta tmp2
_make   lda tmp                 ; octave*12 + semitone
        asl
        adc tmp
        asl
        asl
        adc tmp2
        jsr fld_store
        jsr note_fill
        jmp prelisten
_r      rts

letter_semi .byte 9, 11, 0, 2, 4, 5, 7  ; A B C D E F G

; A = note -> A = semitone, tmp = octave
div12   ldx #0
-       cmp #12
        bcc +
        sbc #12
        inx
        bne -
+       stx tmp
        rts

; ---------------------------------------------------------------------------
; Allocation bitmaps (X = 0 chains, 1 phrases, 2 instruments, 3 tables;
; A = index)
alloc_clr
        jsr alloc_pos
        lda a_bit
        eor #$ff
        and ALLOC_CHAINS,y
        sta ALLOC_CHAINS,y
        rts

alloc_set
        jsr alloc_pos
        lda ALLOC_CHAINS,y
        ora a_bit
        sta ALLOC_CHAINS,y
        rts

; Z clear if used
alloc_test
        jsr alloc_pos
        lda ALLOC_CHAINS,y
        and a_bit
        rts

alloc_pos
        pha
        and #7
        tay
        lda bitmask,y
        sta a_bit
        pla
        lsr
        lsr
        lsr
        clc
        adc alloc_off,x
        tay
        rts

alloc_off   .byte 0, ALLOC_PHRASES - ALLOC_CHAINS, ALLOC_INSTR - ALLOC_CHAINS
            .byte ALLOC_TABLES - ALLOC_CHAINS
alloc_count .byte NCHAINS, NPHRASES, NINSTR, NTABLES

; X = bitmap 0/1/3 (chain/phrase/table): A = first unused, empty item,
; carry set if none
alloc_new
        stx a_type
        lda #0
        sta a_idx
-       lda a_idx
        ldx a_type
        jsr alloc_test
        bne +
        lda a_idx
        ldx a_type
        jsr item_empty
        bne +
        lda a_idx
        ldx a_type
        clc
        rts
+       inc a_idx
        lda a_idx
        ldx a_type
        cmp alloc_count,x
        bne -
        rts                     ; carry set: none free

; A = item, X = 0 chain / 1 phrase / 2 instrument / 3 table: Z set if it
; holds no data (an instrument: equal to the default, preset 0)
item_empty
        cpx #3
        bne +
        jmp table_empty
+       cpx #2
        bne +
        jsr instr_addr
        ldy #15
-       lda (ptr),y
        cmp pre_data,y
        bne _no
        dey
        bpl -
        lda #0
        rts
+       cpx #0
        bne _ph
        jsr chain_addr
        ldy #30
-       lda (ptr),y
        cmp #EMPTY
        bne _no
        dey
        dey
        bpl -
        lda #0
        rts
_ph     jsr phrase_addr
        ldy #60
-       lda (ptr),y             ; note
        cmp #EMPTY
        bne _no
        iny
        lda (ptr),y             ; instrument
        cmp #EMPTY
        bne _no
        iny
        lda (ptr),y             ; command
        bne _no
        tya
        sbc #6                  ; carry set (= EMPTY)
        tay
        bpl -
        lda #0
        rts
_no     lda #1
        rts

; Mark everything the song data already uses (main loads a demo without
; touching the bitmaps). Only sets bits, so a loader's bitmaps survive.
alloc_rebuild
        ldx #0
-       lda SONG,x
        jsr _chref
        lda SONG+$100,x
        jsr _chref
        lda SONG+$200,x
        jsr _chref
        inx
        bne -
        txa
        sta a_idx
_ch     lda a_idx
        jsr chain_addr
        ldy #30
-       lda (ptr),y
        cmp #EMPTY
        beq +
        sty a_y
        ldx #1
        jsr alloc_set           ; phrase used by this chain
        lda a_idx
        ldx #0
        jsr alloc_set           ; and the chain holds data
        ldy a_y
+       dey
        dey
        bpl -
        inc a_idx
        bpl _ch
        lda #0
        sta a_idx
-       lda a_idx
        ldx #1
        jsr item_empty
        beq _pnext
        lda a_idx
        ldx #1
        jsr alloc_set
        ldy #PH_INSTR + 60      ; and the instruments it uses (ptr = phrase)
_in     lda (ptr),y
        cmp #NINSTR
        bcs _nin
        sty a_y
        ldx #2
        jsr alloc_set
        ldy a_y
_nin    iny                     ; A command: table used
        lda (ptr),y
        dey
        cmp #1
        bne +
        iny
        iny
        lda (ptr),y
        dey
        dey
        cmp #NTABLES
        bcs +
        sty a_y
        ldx #3
        jsr alloc_set
        ldy a_y
+       tya
        sec
        sbc #4
        tay
        bpl _in
_pnext  inc a_idx
        lda a_idx
        cmp #NPHRASES
        bne -
        lda #0                  ; tables: holding data or set in an instrument
        sta a_idx
-       lda a_idx
        jsr table_empty
        beq +
        lda a_idx
        ldx #3
        jsr alloc_set
+       inc a_idx
        lda a_idx
        cmp #NTABLES
        bne -
        ldx #NINSTR-1
-       txa
        jsr instr_addr
        ldy #IN_TABLE
        lda (ptr),y
        cmp #NTABLES
        bcs +
        stx a_y
        ldx #3
        jsr alloc_set
        ldx a_y
+       dex
        bpl -
        rts
_chref  bmi +                   ; $80-$ff: clip or empty
        stx a_y
        ldx #0
        jsr alloc_set
        ldx a_y
+       rts

; ---------------------------------------------------------------------------
; Cursor movement (X = direction 0 up 1 down 2 left 3 right)
move_dir
        stx dir_t
        ldx screen
        cpx #SC_FILE
        bne +
        jmp file_move
+       jsr grid_act            ; grid view: between cells (grid.asm)
        beq +
        jmp grid_move
+       cpx #SC_INSTR
        beq _form
        cpx #SC_PROJECT
        beq _form
        cpx #SC_SID
        bcs _r
        lda dir_t
        beq _up
        cmp #1
        beq _dn
        cmp #2
        beq _lt
        lda colv,x
        cmp colmax,x
        bcs _r
        inc colv,x
_r      rts
_form   jmp form_move
_lt     lda colv,x
        beq _r
        dec colv,x
        rts
_up     lda rowv,x
        beq _r
        dec rowv,x
        jmp song_scroll
_dn     lda rowv,x
        cmp rowmax,x
        bcs _r
        inc rowv,x
        bcc song_scroll

;               SNG CHN PHR INS TBL GRV
rowmax  .byte 255, 15, 15, 0, 16, 16
colmax  .byte NCHAN-1, 1, 3, 0, 5, 0 ; Song: pl_nch - 1 (nch_sync, high.asm)

; keep the Song cursor inside the visible window
song_scroll
        lda srow
        cmp song_top
        bcs +
        sta song_top
        rts
+       sec
        sbc song_top
        cmp #SONG_ROWS
        bcc +
        lda srow
        sbc #SONG_ROWS-1
        sta song_top
+       rts

; C= + Up/Down: Song pages by 16 rows, lists jump to first/last step.
; C= + Left/Right on Instr/Table/Groove: previous/next item.
page_dir
        cpx #2
        bcs item_step
        lda screen
        bne _list
        jsr bm_any              ; bookmarks: jump between them
        beq +
        jmp bm_jump
+       cpx #0
        bne _pd
        lda srow
        sbc #SONG_ROWS          ; carry set (X = 0)
        bcs +
        txa
+       sta srow
        lda song_top
        sec
        sbc #SONG_ROWS
        bcs +
        lda #0
+       sta song_top
        jmp song_scroll
_pd     lda srow
        clc
        adc #SONG_ROWS
        bcc +
        lda #255
+       sta srow
        lda song_top
        clc
        adc #SONG_ROWS
        bcs _top
        cmp #256-SONG_ROWS+1
        bcc +
_top    lda #256-SONG_ROWS
+       sta song_top
        jmp song_scroll
_list   tay
        lda pg_first,y
        cpx #0
        beq +
        lda rowmax,y
+       cpy #SC_INSTR
        beq _r
        cpy #SC_GROOVE+1
        bcs _r
        sta rowv,y
_r      rts

pg_first .byte 0, 0, 0, 0, 1, 1

; X = 2 left / 3 right: previous/next instrument, table or groove
item_step
        jsr grid_act            ; grid view: C=+L/R picks the field (grid.asm)
        beq +
        jmp grid_field
+       lda screen
        sec
        sbc #SC_INSTR
        cmp #3
        bcs _r
        tay
        lda cur_instr,y
        cpx #2
        bne _nx
        cmp #0
        beq _r
        sbc #1                  ; carry set
        bcs _st
_nx     cmp item_max,y
        bcs _r
        adc #1                  ; carry clear
_st     sta cur_instr,y
_r      rts

item_max .byte NINSTR-1, NTABLES-1, NGROOVES-1

; CTRL + CRSR: move on the screen map, following the item under the cursor
nav_screen
        stx dir_t
        lda screen
        bne +
        cpx #2                  ; Song CTRL+Left: song/live mode
        bne +
        lda pl_live
        eor #1
        sta pl_live
nav_rts rts
+       cmp #SC_GROOVE          ; Groove up: back where it was entered from
        bne +
        cpx #0
        bne +
        lda groove_from
        sta nav_to
        jmp _go
+       asl
        asl
        ora dir_t
        tay
        lda nav_table,y
        bmi nav_rts
        sta nav_to
        cmp #SC_GROOVE
        bne +
        lda screen
        sta groove_from
+       lda screen
        bne _fc
        lda scol                ; Song -> Chain: chain, channel and row
        sta cur_chan
        lda srow
        sta cur_songrow
        jsr song_cell
        bmi _go
        sta cur_chain
        bpl _go
_fc     cmp #SC_CHAIN
        bne _fp
        lda nav_to
        cmp #SC_PHRASE
        bne _go
        jsr chain_cell
        cmp #EMPTY
        beq _go
        sta cur_phrase
        bne _go
_fp     cmp #SC_PHRASE
        bne _fi
        lda nav_to
        cmp #SC_GROOVE
        beq _fg
        cmp #SC_INSTR
        bne _go
        jsr phrase_instr
        cmp #NINSTR
        bcs _go
        sta cur_instr
        bne _go                 ; (Z clear: below NINSTR)
_fg     jsr phrase_cmd          ; G command under the cursor: its groove
        cmp #CMD_G
        bne _go
        tya
        cmp #NGROOVES
        bcs _go
        sta cur_groove
        bne _go                 ; (Z clear: below NGROOVES)
_fi     cmp #SC_INSTR
        bne _go
        lda nav_to
        cmp #SC_TABLE
        bne _go
        lda cur_instr           ; Instr -> Table: the instrument's table
        jsr instr_addr
        ldy #IN_TABLE
        lda (ptr),y
        cmp #NTABLES
        bcs _go
        sta cur_table
_go     lda #0
        sta mark_on
        lda nav_to
        sta screen
        lda #1
        sta need_clear
_r      rts

CMD_G = 7

; A = command, Y = value at the Phrase cursor step (A = 0 if none)
phrase_cmd
        lda cur_phrase
        cmp #EMPTY
        beq _none
        jsr phrase_addr
        lda prow
        asl
        asl
        ora #PH_VAL
        tay
        lda (ptr),y
        pha
        dey
        lax (ptr),y
        pla
        tay
        txa
        rts
_none   lda #0
        rts

; [screen][up, down, left, right]; Song left is live mode (above)
nav_table
        .byte $ff, $ff, $ff, SC_CHAIN           ; SONG
        .byte $ff, $ff, SC_SONG, SC_PHRASE      ; CHAIN
        .byte SC_PROJECT, SC_GROOVE, SC_CHAIN, SC_INSTR ; PHRASE
        .byte SC_SID, SC_GROOVE, SC_PHRASE, SC_TABLE ; INSTR
        .byte $ff, $ff, SC_INSTR, $ff           ; TABLE
        .byte SC_INSTR, $ff, $ff, $ff           ; GROOVE (up: groove_from)
        .byte $ff, SC_PHRASE, $ff, SC_SID       ; PROJECT
        .byte $ff, SC_INSTR, SC_PROJECT, $ff    ; SID SETUP
        .byte SC_PROJECT, $ff, $ff, $ff         ; FILE (hidden)

; ---------------------------------------------------------------------------
; Playback
play_screen
        lda screen
        cmp #SC_PROJECT         ; Project tempo field: RETURN taps the tempo
        bne +
        lda rowv+SC_PROJECT
        ora colv+SC_PROJECT
        bne _chan
        jmp tap_tempo
+       lda screen
        bne _chan
        lda pl_live
        beq +
        jmp live_start          ; live: queue the chain(s)
+       lda pl_playing          ; Song: play from the cursor row, or stop
        beq +
        jmp player_stop
+       lda srow
        jmp player_play_song
_chan   ldx cur_chan            ; elsewhere: the context channel only
        lda pl_playing
        and bitmask,x
        beq +
        jmp player_stop_channel
+       lda cur_songrow
        jmp player_play_channel

play_all
        lda screen
        bne +
        lda pl_live
        beq +
        jmp live_stop           ; live: queue a stop
+       lda pl_playing
        beq +
        jmp player_stop
+       lda srow
        ldx screen
        beq +
        lda cur_songrow
+       jmp player_play_song

do_mute jsr cursor_chan
mute_x  lda bitmask,x
        eor pl_mute
        sta pl_mute
        rts

; solo: mute all others; again (others already muted) unmutes all
do_solo jsr cursor_chan
solo_x  ldy pl_nch
        lda bitmask,y
        sec
        sbc #1
        eor bitmask,x
        cmp pl_mute
        bne +
        lda #0
+       sta pl_mute
        rts

; Pre-listen: after a note edit play it on the context channel unless that
; channel is playing; it stops when SPACE is released and a few frames passed.
prelisten
        lda no_listen           ; block edits stay silent
        bne _r
        lda screen
        cmp #SC_INSTR
        beq instr_listen
        cmp #SC_TABLE
        beq instr_listen
        lda ftype
        cmp #FT_NOTE
        bne _r
        ldy #0
        lda (fp),y
        cmp #EMPTY
        beq _r
        sta tmp
        ldx cur_chan
        lda pl_playing
        and bitmask,x
        bne _r
        iny
        lda (fp),y
        cmp #EMPTY
        bne +
        lda last+FT_INSTR
+       tay
        stx pre_chan
        lda tmp
        jsr player_note_on
        lda #12
        sta pre_timer
_r      rts

; Instrument and Table screens: play cur_instr at the last entered note
instr_listen
        ldx cur_chan
        lda pl_playing
        and bitmask,x
        bne _r
        stx pre_chan
        jsr instr_fix
        ldx pre_chan
        ldy cur_instr
        lda last+FT_NOTE
        jsr player_note_on
        lda #12
        sta pre_timer
_r      rts

prelisten_tick
        lda pre_timer
        beq _r
        lda btn
        and #BT_A
        bne _r
        lda pre_timer
        sec
        sbc elapsed
        sta pre_timer
        beq +
        bcs _r
+       lda #0
        sta pre_timer
        ldx pre_chan
        jmp player_note_off
_r      rts

bitmask .byte 1, 2, 4, 8, 16, 32, 64, 128

; grammar scratch (main context only)
ftype   = $9d                   ; zp, start value FT_NONE (editor_init)
kcode   = $d5                   ; zp
dir_i   .byte 0
dir_t   = $d1                   ; zp
nav_to  .byte 0
a_bit   .byte 0
a_idx   = $9f                   ; zp
a_type  .byte 0
a_y     = $dc                   ; zp
no_listen .byte 0
