; Project blocks, generated a page at a time (gen_page) from the tables the
; capture session fills (capture.asm add_row: phrase store, ch0-ch3, songr,
; srow rows; instruments from the core). Nothing is laid out at the editor's
; addresses.

; ---------------------------------------------------------------------------
; Page Y of block X -> pagebuf
; ---------------------------------------------------------------------------
gen_page
        sty g_page
        lda gen_lo,x
        sta _jmp+1
        lda gen_hi,x
        sta _jmp+2
_jmp    jmp $ffff
gen_lo  .byte <g_hdr, <g_song, <g_chain, <g_phr, <g_ins, <g_tbl, <g_grv, <g_alloc
gen_hi  .byte >g_hdr, >g_song, >g_chain, >g_phr, >g_ins, >g_tbl, >g_grv, >g_alloc

; A -> all of pagebuf
pfill   ldx #0
-       sta pagebuf,x
        inx
        bne -
        rts

g_hdr   lda #0
        jsr pfill
        lda tempo
        sta pagebuf+(HD_TEMPO-HEADER)
        ldx #15
-       lda #$20
        cpx nlen
        bcs +
        lda name,x
        jsr pet2scr
+       sta pagebuf+(HD_NAME-HEADER),x
        dex
        bpl -
        rts

g_song  lda #EMPTY
        jsr pfill
        ldy g_page              ; slot
        cpy #3
        bcs _r
        lda vbit,y
        and o_voices
        beq _r
        tya
        clc
        adc #>songr
        sta _ld+2
        ldx #0
-       cpx srow
        beq _r
_ld     lda songr,x
        sta pagebuf,x
        inx
        bne -
_r      rts

g_chain lda g_page              ; chains 8 * page ..
        asl
        asl
        asl
        sta t0
        ldx #0                  ; byte in the page
-       txa                     ; chain step s = (x / 2) & 15, chain = t0 + x / 32
        and #1
        bne _tr
        lda #EMPTY
        sta pagebuf,x
        txa
        and #31
        cmp #8                  ; steps 0-3: the phrases
        bcs _n
        lsr
        tay                     ; step 0..3
        txa
        lsr
        lsr
        lsr
        lsr
        lsr
        clc
        adc t0
        cmp nch
        bcs _n
        sta t1
        stx t2
        ldx t1
        lda ch_tab_lo,y
        sta _ld+1
        lda ch_tab_hi,y
        sta _ld+2
_ld     lda $ffff,x
        ldx t2
        sta pagebuf,x
        jmp _n
_tr     lda #0
        sta pagebuf,x
_n      inx
        bne -
        rts
ch_tab_lo .byte <ch0, <ch1, <ch2, <ch3
ch_tab_hi .byte >ch0, >ch1, >ch2, >ch3

g_phr   lda #0
        sta t1                  ; phrase in the page
_p      lda g_page
        asl
        asl
        ora t1
        sta t0                  ; phrase number
        lda t1                  ; zp_q = pagebuf + t1 * 64
        asl
        asl
        asl
        asl
        asl
        asl
        sta zp_q
        lda #>pagebuf
        sta zp_q+1
        lda zp_q
        clc
        adc #<pagebuf
        sta zp_q
        bcc +
        inc zp_q+1
+       lda t0
        cmp nphr
        bcs _empty
        tax
        lda zp_q
        pha
        lda zp_q+1
        pha
        jsr ph_ptr
        lda zp_q
        sta zp_p
        lda zp_q+1
        sta zp_p+1
        pla
        sta zp_q+1
        pla
        sta zp_q
        ldy #63
-       lda (zp_p),y
        sta (zp_q),y
        dey
        bpl -
        bmi _pn
_empty  ldy #63
-       lda #0
        sta (zp_q),y
        dey
        sta (zp_q),y
        dey
        lda #EMPTY
        sta (zp_q),y
        dey
        sta (zp_q),y
        dey
        bpl -
_pn     inc t1
        lda t1
        cmp #4
        bne _p
        rts

g_ins   lda #0
        sta t1
_i      lda t1                  ; instrument t0 = page * 16 + t1 at pagebuf + t1 * 16
        asl
        asl
        asl
        asl
        tay
        ldx #0
-       lda def_instr,x
        sta pagebuf,y
        iny
        inx
        cpx #16
        bne -
        lda g_page
        asl
        asl
        asl
        asl
        ora t1
        cmp x_ninstr
        bcs _in
        tax
        lda t1
        asl
        asl
        asl
        asl
        tay
        lda x_ins_w,x
        sta pagebuf+IN_WAVE,y
        lda x_ins_ad,x
        sta pagebuf+IN_AD,y
        lda x_ins_sr,x
        sta pagebuf+IN_SR,y
        lda x_ins_pl,x
        sta pagebuf+IN_PWLO,y
        lda x_ins_ph,x
        sta pagebuf+IN_PWHI,y
_in     inc t1
        lda t1
        cmp #16
        bne _i
        rts

        ; flags wave AD  SR  pwlo pwhi spd cut res fsw hr  hrsr vib vdly tbl tspd (fileio.asm)
def_instr
        .byte $01,$40,$09,$a0,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,$ff,$00

g_tbl   lda #EMPTY              ; column 0 (control) $ff, columns 1-5 zero
        ldx g_page
        cpx #2
        bcc +
        lda #0
+       jmp pfill

g_grv   lda #0
        jsr pfill
        lda g_page
        bne +
        lda fps                 ; groove 0 = fps, fps
        sta pagebuf
        sta pagebuf+1
+       rts

g_alloc lda #0
        jsr pfill
        lda #ALLOC_CHAINS-ALLOC_CHAINS
        ldx nch
        jsr setbits
        lda #ALLOC_PHRASES-ALLOC_CHAINS
        ldx nphr
        jsr setbits
        ldx x_ninstr
        bne +
        inx                     ; instrument 0 is used even without imported instruments
+       lda #ALLOC_INSTR-ALLOC_CHAINS
        ; fall through
; X bits from bit 0 of pagebuf + A, LSB first
setbits sta t0
        stx t1
        ldx #0
-       cpx t1
        beq _r
        txa
        lsr
        lsr
        lsr
        clc
        adc t0
        tay
        txa
        and #7
        sta t2
        stx t3
        tax
        lda bitm,x
        ora pagebuf,y
        sta pagebuf,y
        ldx t3
        inx
        bne -
_r      rts
