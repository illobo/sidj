; SIDJ doc reader: a noter for the README and the manual (SIDE = the name shown top right).
; One source, two builds (Makefile): DOCSRC names the text that
; tools/mkdocs.py made (dictionary, chapter names, packed chapters, song).
;
; Memory (KERNAL and I/O in, BASIC out: $01 = $36):
;   $0801-$0dff  BASIC stub, reader code and tables
;   $0e00-$0fff  player variables (PLAYER_EXT)
;   $1000-$27ff  SIDJ player (src/player.asm)
;   $2800-$7fff  doc data: glyphs, dictionary, names, song (RLE), chapters
;   $8000-...    phrases the song uses (SONG_PH_END), decoded at start
;   DOC_B-...    chapters that did not fit below $8000, then the text buffer
;   $c000-...    chains the song uses (SONG_CH_END)
;   $c100-$c2ff  line table (lo, hi; 255 lines per chapter at most)
;   $c400-$c7e7  screen (VIC bank 3)
;   $c800-$cfff  charset: ROM mixed case + doc glyphs (copied at start)
;   $e000-$f9ff  song, instruments, tables, grooves, header (under the KERNAL)
; Music: the player's tick from the raster IRQ, paced by its tempo latch
; (cycles per tick) against the cycles per frame, so tempos are right.
; Keys via KERNAL GETIN (the raster IRQ ends in the KERNAL's $ea31).

        .include "defs.inc"

SCR     = $c400
CHARSET = $c800
LINELO  = $c100
LINEHI  = $c200
DOC_AEND = $8000
DOC_B   = (SONG_PH_END + $ff) & $ff00

TOP_ROW = 3                     ; first text row
NROWS   = 21                    ; text rows 3-23
STATUS  = 24
MENU_ROW = 4                    ; first menu row
MENU_N  = 19                    ; menu rows 4-22
ESC     = $e7

GETIN   = $ffe4

; colours
C_TITLE = 7
C_DOC   = 13
C_MENU  = 15
C_SEL   = 7
C_STAT  = 14

; zero page ($50-$6f, BASIC's, unused here)
src     = $50
dst     = $52
cnt     = $54
p       = $56
sp      = $58                   ; screen pointer
cp      = $5a                   ; colour pointer
done    = $5c
top     = $5d                   ; first line shown
nlines  = $5e
maxtop  = $5f
sel     = $60                   ; menu: chapter under the bar
mtop    = $61                   ; menu: first chapter shown
mode    = $62                   ; 0 menu, 1 text
music   = $63                   ; 0 off
acc     = $64                   ; 3 bytes: cycles not yet spent on ticks
row     = $67
chap    = $68                   ; open chapter

        * = $0801
        .word (+), 2026
        .null $9e, format("%d", start)
+       .word 0

start   sei
        cld
        ldx #$ff
        txs
        lda #$36                ; BASIC out
        sta $01
        jsr song_load
        jsr charset
        jsr screen_init
        jsr music_init
        lda #<irq
        sta $0314
        lda #>irq
        sta $0315
        lda #$7f                ; CIA1 timer IRQ off: the raster IRQ scans the keys
        sta CIA1+$0d
        lda CIA1+$0d
        lda #56
        sta VIC+$12
        lda #$1b
        sta VIC+$11
        lda #1
        sta VIC+$1a
        sta VIC+$19
        lda #$80                ; no SHIFT + C= charset switch
        sta $0291
        lda #1                  ; no cursor blink
        sta $cc
        lda #0
        sta $c6                 ; empty keyboard buffer
        sta sel
        sta mtop
        cli
        jmp menu

; ---------------------------------------------------------------------------
; Menu
; ---------------------------------------------------------------------------
menu    lda #0
        sta mode
        jsr clear_text
        lda #<s_menu
        ldy #>s_menu
        jsr status
_draw   jsr draw_menu
_key    jsr GETIN
        beq _key
        cmp #$11                ; CRSR down
        bne +
        ldx sel
        inx
        cpx #DOC_NCH
        bcs _key
        stx sel
        txa
        sec
        sbc mtop
        cmp #MENU_N
        bcc _draw
        inc mtop
        bcs _draw
+       cmp #$91                ; CRSR up
        bne +
        ldx sel
        beq _key
        dex
        stx sel
        cpx mtop
        bcs _draw
        stx mtop
        bcc _draw
+       cmp #$0d                ; RETURN
        bne +
        lda sel
        jmp open
+       jsr common
        jmp _key

; keys for both views: M music on/off
common  cmp #$4d                ; M
        bne +
        lda music
        eor #1
        sta music
        bne +
        sta SID+$18             ; off: silent (the next tick writes it again)
+       rts

draw_menu
        ldx #0
_row    stx row
        txa
        clc
        adc #MENU_ROW
        tay
        jsr rowptr
        txa
        clc
        adc mtop
        cmp #DOC_NCH
        bcs _blank
        tax
        lda namelo,x
        sta p
        lda namehi,x
        sta p+1
        lda #0                  ; reverse for the bar
        cpx sel
        bne +
        lda #$80
+       sta done
        ldy #0
        lda #$20
        ora done
        sta (sp),y
        iny
        sta (sp),y
        iny
-       lda (p),y               ; columns 2-35: the name (p = name - 2)
        ora done
        sta (sp),y
        iny
        cpy #36
        bne -
        lda #$20
        ora done
        sta (sp),y
        iny
        lda #$20
-       sta (sp),y
        iny
        cpy #40
        bne -
        lda #C_MENU
        ldx done
        beq +
        lda #C_SEL
+       ldy #39
-       sta (cp),y
        dey
        bpl -
        jmp _nx
_blank  jsr blank_row
_nx     ldx row
        inx
        cpx #MENU_N
        bne _row
        rts

; ---------------------------------------------------------------------------
; Text view
; ---------------------------------------------------------------------------
open    sta chap
        lda #1
        sta mode
        lda chap
        jsr unpack
        jsr index
        lda #0
        sta top
        lda nlines
        sec
        sbc #NROWS
        bcs +
        lda #0
+       sta maxtop
        lda #<s_text
        ldy #>s_text
        jsr status
_draw   jsr page
_key    jsr GETIN
        beq _key
        cmp #$11                ; CRSR down: one line
        bne +
        lda top
        cmp maxtop
        bcs _key
        inc top
        bcc _draw
+       cmp #$91                ; CRSR up
        bne +
        lda top
        beq _key
        dec top
        jmp _draw
+       cmp #$20                ; SPACE: next page
        bne +
        lda top
        clc
        adc #NROWS-1
        bcs _end
        cmp maxtop
        bcc _set
_end    lda maxtop
_set    sta top
        jmp _draw
+       cmp #$a0                ; SHIFT + SPACE: previous page
        bne +
        lda top
        sec
        sbc #NROWS-1
        bcs _set
        lda #0
        beq _set
+       cmp #$13                ; CLR/HOME: start of the chapter
        bne +
        lda #0
        beq _set
+       cmp #$03                ; RUN/STOP
        beq _back
        cmp #$85                ; F1
        beq _back
        jsr common
        jmp _key
_back   jmp menu

; draw NROWS lines from top
page    ldx #0
_row    stx row
        txa
        clc
        adc #TOP_ROW
        tay
        jsr rowptr
        lda row
        clc
        adc top
        cmp nlines
        bcs _blank
        tax
        lda LINELO,x
        sta p
        lda LINEHI,x
        sta p+1
        ldy #0
        lda (p),y               ; $80 + colour
        and #15
        tax
-       txa
        sta (cp),y
        iny
        lda (p),y
        bmi _pad
        dey
        sta (sp),y
        iny
        cpy #40
        bne -
        beq _nx
_pad    dey
        lda #$20
-       sta (sp),y
        iny
        cpy #40
        bne -
        jmp _nx
_blank  jsr blank_row
_nx     ldx row
        inx
        cpx #NROWS
        bne _row
        rts

; line table: LINELO/HI = start ($80 + colour) of each line in BUF
index   lda #<BUF
        sta p
        lda #>BUF
        sta p+1
        ldx #0
        ldy #0
-       lda (p),y
        cmp #$ff
        beq _end
        cmp #$80
        bcc +
        lda p
        sta LINELO,x
        lda p+1
        sta LINEHI,x
        inx
+       inc p
        bne -
        inc p+1
        bne -
_end    stx nlines
        rts

; ---------------------------------------------------------------------------
; Byte-pair decoder: chapter A -> BUF (ends with $ff)
; ---------------------------------------------------------------------------
unpack  tax
        lda doc_chlo,x
        sta src
        lda doc_chhi,x
        sta src+1
        lda #<BUF
        sta dst
        lda #>BUF
        sta dst+1
        lda #0
        sta done
-       ldy #0
        lda (src),y
        inc src
        bne +
        inc src+1
+       jsr expand
        lda done
        beq -
        rts

expand  cmp #DOC_NLIT
        bcc _lit
        tax
        lda doc_right-DOC_NLIT,x
        pha
        lda doc_left-DOC_NLIT,x
        jsr expand
        pla
        jmp expand
_lit    tax
        lda doc_lit,x
        ldy #0
        sta (dst),y
        inc dst
        bne +
        inc dst+1
+       cmp #$ff
        bne +
        sta done
+       rts

; ---------------------------------------------------------------------------
; Screen
; ---------------------------------------------------------------------------
; Y = screen row -> sp, cp
rowptr  lda rowlo,y
        sta sp
        sta cp
        lda rowhi,y
        sta sp+1
        and #3
        ora #>COLORRAM
        sta cp+1
        rts

blank_row
        ldy #39
        lda #$20
-       sta (sp),y
        dey
        bpl -
        rts

clear_text
        ldx #0
-       stx row
        txa
        clc
        adc #TOP_ROW
        tay
        jsr rowptr
        jsr blank_row
        ldx row
        inx
        cpx #NROWS
        bne -
        rts

; status line (reversed): A/Y = 40 screen codes
status  sta p
        sty p+1
        ldy #39
-       lda (p),y
        ora #$80
        sta SCR+STATUS*40,y
        lda #C_STAT
        sta COLORRAM+STATUS*40,y
        dey
        bpl -
        rts

screen_init
        lda CIA2+2              ; VIC bank 3 ($c000-$ffff)
        ora #3
        sta CIA2+2
        lda CIA2
        and #$fc
        sta CIA2
        lda #$12                ; screen $c400 (1 x $400), charset $c800 (1 x $800)
        sta VIC+$18
        lda #>SCR               ; KERNAL screen editor (unused) agrees
        sta $0288
        lda #0
        sta VIC+$20
        sta VIC+$21
        ldx #0
-       lda #$20
        sta SCR,x
        sta SCR+$100,x
        sta SCR+$200,x
        sta SCR+$2e8,x
        lda #C_MENU
        sta COLORRAM,x
        sta COLORRAM+$100,x
        sta COLORRAM+$200,x
        sta COLORRAM+$2e8,x
        inx
        bne -
        ldx #3                  ; title row: SIDJ, the doc name
-       lda s_sidj,x
        sta SCR+1,x
        lda #C_TITLE
        sta COLORRAM+1,x
        dex
        bpl -
        ldx #15
-       lda doc_title,x
        sta SCR+8,x
        lda #C_DOC
        sta COLORRAM+8,x
        dex
        bpl -
        ldx #s_side_end-s_side-1
-       lda s_side,x
        sta SCR+40-(s_side_end-s_side)-1,x
        lda #C_STAT
        sta COLORRAM+40-(s_side_end-s_side)-1,x
        dex
        bpl -
        rts

; ROM mixed-case charset to CHARSET, then the doc glyphs
charset lda #$33                ; character ROM at $d000 (IRQs are off)
        sta $01
        ldx #0
_cp
        .for _p := 0, _p < 8, _p += 1
        lda $d800+_p*256,x
        sta CHARSET+_p*256,x
        .endfor
        inx
        bne _cp
        lda #$36
        sta $01
        ldx #0                  ; glyph n: doc_gdata + 8n -> CHARSET + 8 * code
_g      lda doc_gcode,x
        sta p
        lda #0
        asl p
        rol
        asl p
        rol
        asl p
        rol
        adc #>CHARSET
        sta p+1
        txa
        asl
        asl
        asl
        tay
        sty done
        ldy #0
-       sty row
        ldy done
        lda doc_gdata,y
        inc done
        ldy row
        sta (p),y
        iny
        cpy #8
        bne -
        inx
        cpx #DOC_NGLYPH
        bne _g
        rts

; ---------------------------------------------------------------------------
; Music
; ---------------------------------------------------------------------------
; song_data: segments (address, RLE length, RLE body: ESC, count, value or a
; literal byte), address 0 ends
song_load
        lda #<song_data
        sta src
        lda #>song_data
        sta src+1
_seg    jsr getb
        sta dst
        jsr getb
        sta dst+1
        ora dst
        beq _r
        jsr getb
        sta cnt
        jsr getb
        sta cnt+1
_loop   lda cnt
        ora cnt+1
        beq _seg
        jsr getc
        cmp #ESC
        bne _lit
        jsr getc
        tax
        jsr getc
-       jsr put
        dex
        bne -
        beq _loop
_lit    jsr put
        jmp _loop
_r      rts
getc    lda cnt                 ; getb, one less to read
        bne +
        dec cnt+1
+       dec cnt
getb    ldy #0
        lda (src),y
        inc src
        bne +
        inc src+1
+       rts
put     ldy #0
        sta (dst),y
        inc dst
        bne +
        inc dst+1
+       rts

music_init
        lda #BANK_RAMIO         ; the player reads the song under the KERNAL
        sta $01
        lda #0
        sta pl_sid2
        sta pl_sid2+1
        jsr player_init
        lda #$7f                ; no NMI clock: the raster IRQ runs the ticks
        sta CIA2+$0d
        lda #0
        sta CIA2+$0e
        lda CIA2+$0d
        lda #0
        jsr player_play_song
        lda #$36
        sta $01
        lda #0
        sta acc
        sta acc+1
        sta acc+2
        lda #1
        sta music
        rts

; Raster IRQ (line 56) through the KERNAL: colour bars, music, then the
; KERNAL's keyboard scan
irq     lda #$ff
        sta VIC+$19
        ldx #0
-       lda bar_line,x
-       cmp VIC+$12
        bne -
        lda bar_col,x
        sta VIC+$21
        inx
        cpx #NBARS
        bne --
        lda music
        beq _k
        ldx pl_ntsc             ; cycles per frame
        clc
        lda acc
        adc frlo,x
        sta acc
        lda acc+1
        adc frhi,x
        sta acc+1
        bcc +
        inc acc+2
+       lda $01
        pha
        lda #BANK_RAMIO
        sta $01
_tick   lda acc                 ; a tick per latch_eff cycles
        sec
        sbc pl.latch_eff
        tax
        lda acc+1
        sbc pl.latch_eff+1
        tay
        lda acc+2
        sbc #0
        bcc _done
        sta acc+2
        stx acc
        sty acc+1
        inc pl.lock
        jsr pl.tick
        jsr pl.leave
        jmp _tick
_done   pla
        sta $01
_k      jmp $ea31

frlo    .byte <19656, <17095    ; PAL 312 x 63, NTSC 263 x 65
frhi    .byte >19656, >17095

; five bars of two raster lines in rows 1-2 (51 + 8 per row)
NBARS   = 10
bar_line .byte 60, 62, 63, 65, 66, 68, 69, 71, 72, 74
bar_col  .byte 7, 0, 8, 0, 10, 0, 13, 0, 14, 0

rowlo   .for _r := 0, _r < 25, _r += 1
        .byte <(SCR + 40 * _r)
        .endfor
rowhi   .for _r := 0, _r < 25, _r += 1
        .byte >(SCR + 40 * _r)
        .endfor
namelo  .for _r := 0, _r < DOC_NCH, _r += 1     ; name - 2 (draw_menu)
        .byte <(doc_names + 34 * _r - 2)
        .endfor
namehi  .for _r := 0, _r < DOC_NCH, _r += 1
        .byte >(doc_names + 34 * _r - 2)
        .endfor

        .enc "mixed"            ; mixed-case charset screen codes
        .cdef " ?", $20
        .cdef "@@", $00
        .cdef "az", $01
        .cdef "AZ", $41
s_sidj  .text "SIDJ"
s_side  .text SIDE
s_side_end
s_menu  .text " CRSR: CHOOSE    RETURN: READ   M: MUSIC"
s_text  .text " CRSR/SPACE: SCROLL STOP: MENU  M: MUSIC"
s_end
        .enc "none"
        .cerror s_end - s_menu != 80, "status lines: 40 characters each"
        .cerror * > PLAYER_EXT, "reader code runs into PLAYER_EXT"

        * = PLAYER
        .include "player.asm"
        .cerror * > PLAYER_END, "player overflows PLAYER_END"

        * = PLAYER_END
        .include DOCSRC
        .cerror DOC_MAXLINES > 255, "chapter too long for the 8-bit line table"
BUF     = (* > DOC_AEND) ? * : DOC_B
        .cerror * > DOC_AEND && * < DOC_B, "doc data overlaps the song's phrases"
        .cerror BUF + DOC_MAXRAW > $c000, "text buffer beyond $c000"
        .cerror SONG_CH_END > LINELO, "song chains overlap the line table"
