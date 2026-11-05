; Editor code at EDLOW ($0830-$0b7f), loaded in place with the program
; (main.asm). Runs like the rest of the editor.

; ---------------------------------------------------------------------------
; Factory presets. Data in RAM under I/O (presetdata.asm),
; read with IRQs off; each access copies a small piece into RAM here.
; Preset id: 5 bits, flags bits 4-7 = id bits 0-3, table speed bit 4 = id
; bit 4 (the player ignores both).
NPRESETS    = 32
NTPL        = 14                ; table templates
TPL_EMPTY   = 2
PRE_NAMELEN = 6
NCATS       = len(PRESET_CATS)
CMD_HOP     = 8                 ; H
CMD_BEND    = 16                ; P

IO_ON   .macro
        php
        sei
        lda #BANK_ALLRAM
        sta $01
        .endm
IO_OFF  .macro
        lda #BANK_RAMIO
        sta $01
        plp
        .endm

; A = preset id of the instrument at fb
pre_id  ldy #IN_TBLSPD
        lda (fb),y
        and #$10
        sta p_idt
        ldy #IN_FLAGS
        lda (fb),y
        lsr
        lsr
        lsr
        lsr
        ora p_idt
        jmp xp_id               ; 0: an extended preset? (high.asm)

; A = preset id: A/Y = its name (PRE_NAMELEN screen codes, 0-terminated)
pre_name
        cmp #NPRESETS
        bcc +
        jsr xp_name             ; extended (REU)
        jmp pn_ret
+       asl
        sta p_idt
        asl
        adc p_idt               ; *6, carry clear (id < 32)
        tay
        #IO_ON
        ldx #0
-       lda pd_names,y
        sta pnbuf,x
        iny
        inx
        cpx #PRE_NAMELEN
        bne -
        #IO_OFF
pn_ret  lda #<pnbuf
        ldy #>pnbuf
        rts

; A = preset id -> pbuf: its 16 instrument bytes (byte $E = template)
pre_fetch
        cmp #NPRESETS
        bcc +
        jmp xp_inst             ; extended (REU)
+       tax
        ldy #15
-       lda pre_data,y
        sta pbuf,y
        dey
        bpl -
        #IO_ON
        lda pd_ofs,x
        clc
        adc #<pd_inst
        sta ptr
        lda #>pd_inst
        adc #0
        sta ptr+1
        ldy #0
        lda (ptr),y
        sta p_mlo
        iny
        lda (ptr),y
        sta p_mhi
        ldx #0
-       lsr p_mhi
        ror p_mlo
        bcc +
        iny
        lda (ptr),y
        sta pbuf,x
+       inx
        cpx #16
        bne -
        #IO_OFF
        rts

; X = template -> tplbuf (rows 0-7 of columns 0-3, col*8 + row)
tpl_load
        cpx #NTPL
        bcc +
        jmp xp_tpl              ; extended (REU)
+       ldy #31
-       lda #0
        cpy #8
        bcs +
        lda #$ff
+       sta tplbuf,y
        dey
        bpl -
        #IO_ON
        lda pd_tofs+1,x
        sta p_idt
        lda pd_tofs,x
        tay
        ldx #0
_row    cpy p_idt
        bcs _done
        lda pd_tpl,y
        sta tplbuf,x            ; ctl
        lda pd_tpl+1,y
        sta tplbuf+8,x          ; transpose
        lda pd_tpl+2,y
        beq _nx
        cmp #$20
        bcs _bend
        and #$0f
        sta tplbuf+24,x
        lda #CMD_HOP
        bne _cmd
_bend   sta tplbuf+24,x
        lda #CMD_BEND
_cmd    sta tplbuf+16,x
_nx     iny
        iny
        iny
        inx
        bne _row
_done   #IO_OFF
        rts

; SPACE + CRSR on the PRESET field: left/right -1/+1, up/down next /
; previous category; the preset is applied (fp field: fld_touch)
pre_dir jsr pre_id
        ldx dir_t
        cpx #2
        bcs _lr
        cpx #1
        beq _dn
        ldy #0                  ; up: first category start above
-       cmp pre_cat,y
        bcc _take
        iny
        cpy p_ncat
        bne -
        rts
_dn     ldy p_ncat              ; down: last category start below
        dey
-       cmp pre_cat,y
        beq +
        bcs _take
+       dey
        bpl -
        rts
_take   lda pre_cat,y
        jmp pre_set
_lr     bne _rt
        cmp #0                  ; left
        beq _r
        sbc #1                  ; carry set
        bcs pre_set
_rt     cmp p_last
        bcs _r
        adc #1                  ; carry clear
        bcc pre_set
_r      rts
pre_set jsr apply_preset
        jmp fld_touch

; hex digit typed on the PRESET field
pre_key jsr pre_id
        jsr shift_digit
        jsr pre_set
        jmp prelisten

; A = preset: fill the instrument at fb (any instrument, not only
; cur_instr) and give it its table. A table is reused only if it is empty or
; an unchanged preset table that no other instrument uses; else a new one is
; allocated (none free: no table). Presets without a table free such a
; table again. Clobbers ptr; sets RD_LIST and RD_PANEL.
apply_preset
        sta p_v
        lda fb+1                ; p_self = instrument at fb
        sec
        sbc #>INSTR
        asl
        asl
        asl
        asl
        sta p_self
        lda fb
        lsr
        lsr
        lsr
        lsr
        ora p_self
        sta p_self
        ldy #IN_TABLE
        lda (fb),y
        sta p_old
        lda p_v
        jsr pre_fetch
        lda pbuf+IN_TABLE
        sta p_tpl
        lda #$ff
        sta pbuf+IN_TABLE
        jsr xp_mark             ; A = p_v = the id (0 for an extended one)
                                ; the id: flags bits 4-7, table speed bit 4
        asl
        asl
        asl
        asl
        ora pbuf+IN_FLAGS
        sta pbuf+IN_FLAGS
        lda p_v
        and #$10
        ora pbuf+IN_TBLSPD
        sta pbuf+IN_TBLSPD
        ldy #15
-       lda pbuf,y
        sta (fb),y
        dey
        bpl -
        lda #RD_LIST|RD_PANEL   ; the panel shows the table
        ora dirty
        sta dirty
        lda p_tpl
        bmi _notbl
        lda p_old
        cmp #NTABLES
        bcs _new
        jsr tbl_reusable
        bcs _new
        lda p_old
        bcc _have
_new    ldx #3
        jsr alloc_new
        bcs _r                  ; none free: no table
_have   sta p_t
        ldx p_tpl
        jsr tbl_write
        lda p_t
        ldx #3
        jsr alloc_set
        lda p_t
        ldy #IN_TABLE
        sta (fb),y
_r      rts
_notbl  lda p_old
        cmp #NTABLES
        bcs _r
        jsr tbl_reusable
        bcs _r
        lda p_old
        ldx #TPL_EMPTY
        jsr tbl_write
        lda p_old
        ldx #3
        jmp alloc_clr

pre_cat .byte PRESET_CATS, XP_CATS     ; (the extended ones count with an REU: p_ncat)
