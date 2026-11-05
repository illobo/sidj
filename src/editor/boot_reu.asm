; REU at start-up (main.asm): assembled for SCREEN + $200 and staged; runs
; before editor_init clears the screen (the display is off meanwhile).

; REU at start-up (once): u_reu = highest bank (0 = none), r_nslots, the
; overlays to bank 0, the header. rec_on = 1: recover the mirror (C= held
; at start-up skips it). Every bank's byte $fffe is overwritten (unused by
; the bank map; bank 1's is the undo ring, empty at start-up).
reu_boot
        jsr ms_init             ; pointer sprite (mouse.asm, start-up only)
        lda #$0b                ; display off until editor_init
        sta VIC+$11
        lda #0
        sta u_reu
        sta u_bank
        sta rec_on
        ldx #$55                ; the address registers read back
        stx REU+2
        cpx REU+2
        bne rb_r
        ldx #$aa
        stx REU+2
        cpx REU+2
        bne rb_r
        ldx #6                  ; size: bank number to bank:$fffe, 255..0,
-       lda rb_rx,x             ; then read back upwards: the first bank
        sta rx,x                ; that differs is past the end (mirrors)
        dex
        bpl -
-       lda rx+4
        sta u_t
        lda #$90
        jsr reu_xfer
        dec rx+4
        lda rx+4
        cmp #$ff
        bne -
        inc rx+4
-       lda #$91
        jsr reu_xfer
        lda u_t
        cmp rx+4
        bne +
        inc rx+4
        bne -
        lda #$ff                ; all 256: 16 MB
        bne ++
+       ldx rx+4                ; bank 0 wrong: no REU after all
        beq rb_r
        dex
        txa
+       sta u_reu
        sec                     ; slots: banks 2 .. u_reu - REU_TXBANKS
        sbc #REU_SLOTBANK + REU_TXBANKS - 1
        bcc +
        asl
        bcs _max
        cmp #REU_MAXSLOTS + 1
        bcc ++
_max    lda #REU_MAXSLOTS
        .byte $2c
+       lda #0
+       sta r_nslots
        ldx #(>stage_ov) + REU_NOV_USED - 1   ; overlays -> bank 0 REU_OVPG..
-       stx rb_n
        txa
        clc
        adc #REU_OVPG - (>stage_ov)
        tay
        lda #$90
        jsr reu_page
        ldx rb_n
        dex
        cpx #>stage_ov
        bcs -
        ldx #6                  ; extended presets -> bank 0 REU_XPPG:
-       lda xp_rx,x             ; XP_REC bytes into each 32-byte record,
        sta rx,x                ; then the templates in one go
        dex
        bpl -
        lda #XP_N
        sta rb_n
-       lda #$90
        jsr reu_xfer
        clc
        lda rx
        adc #XP_REC
        sta rx
        bcc +
        inc rx+1
+       clc
        lda rx+2
        adc #32
        sta rx+2
        bcc +
        inc rx+3
+       dec rb_n
        bne -
        lda #<(32 * XP_NT)
        sta rx+5
        lda #>(32 * XP_NT)
        sta rx+6
        lda #$90
        jsr reu_xfer
        lda #NPRESETS + XP_N - 1    ; browse, categories, templates, kits
        sta p_last
        lda #NCATS + NXCATS
        sta p_ncat
        lda #NTPL + XP_NT - 1
        sta p_ntl
        lda #NKITS + NXKITS
        sta k_nk
        ldx #6                  ; header
-       lda rh_rx0,x
        sta rx,x
        dex
        bpl -
        lda #$91
        jsr reu_xfer
        ldx #RH_MAP
-       lda rb_hdr,x
        cmp rh_tpl,x
        bne rb_new
        dex
        bpl -
        lda rb_hdr+RH_PFMT      ; same map: a whole project of this format?
        cmp #REU_PFORMAT
        bne rb_hd
        lda rb_hdr+RH_VALID
        cmp #1
        bne rb_hd
        lda #$ff                ; C= (column 7, row 5) held: no recovery
        sta CIA1+2
        lda #0
        sta CIA1+3
        lda #$7f
        sta CIA1
        lda CIA1+1
rec_cbm and #$20                ; (tests break here and set A)
        beq rb_hd
        inc rec_on
        bne rb_hd
rb_new    ldx #0                  ; new header: every slot free
-       lda #$20
        sta FIO_DIR,x
        sta FIO_DIR+$100,x
        txa
        and #15
        bne +
        lda #$ff
        sta FIO_DIR,x
        sta FIO_DIR+$100,x
+       inx
        bne -
        stx u_bank
        ldx #>FIO_DIR
        ldy #REU_DIRPG
        lda #$90
        jsr reu_page
        ldx #(>FIO_DIR) + 1
        ldy #REU_DIRPG + 1
        lda #$90
        jsr reu_page
rb_hd    lda u_reu               ; header: recovery off until undo_reset
        sta rh_tpl+RH_BANKS
        ldx #6
-       lda rh_rx1,x
        sta rx,x
        dex
        bpl -
        lda #$90
        jmp reu_xfer
rb_r      rts

; after fio_clean: the mirror (bank 0, same offsets) -> song data
reu_recover
        lda #UPAGE0
        sta u_p
-       lax u_p
        tay
        lda #$91
        jsr reu_page
        inc u_p
        lda u_p
        cmp #(>CHAINS) + $10
        bne +
        lda #UPAGE_A
        sta u_p
+       cmp #UPAGE_END
        bne -
        rts

rb_rx   .word u_t, $fffe
        .byte $ff
        .word 1
xp_rx   .word stage_xp, REU_XPPG * 256
        .byte 0
        .word XP_REC
        .cerror stage_xp_end - stage_xp != XP_N * XP_REC + 32 * XP_NT, "staged extended presets"
rh_rx0  .word rb_hdr, 0
        .byte 0
        .word RH_LEN
rh_rx1  .word rh_tpl, 0
        .byte 0
        .word RH_LEN
rh_tpl  .byte $53, $49, $44, $4a, $52, $45, $55   ; "SIDJREU" (ASCII)
        .byte REU_MAPVER, 0, REU_PFORMAT, 0
        .cerror * - rh_tpl != RH_LEN, "REU header template"
rb_hdr  .fill RH_LEN
rb_n    .byte 0

; pointer sprite set-up (moved out of mouse.asm, M9: start-up only; the
; shape is assembled at MS_SPRITE)
ms_init
        lda #1                  ; white, single colour, normal size
        sta VIC+$27
        lda #0
        sta VIC+$1c
        sta VIC+$17
        sta VIC+$1d
        sta VIC+$1b             ; in front of the text
        sta MDBG_COUNT
        sta MDBG_IDX
        rts

