; SIDJ loader menu: the first file on the disk, "SIDJ".
;
; Raster bars, a small tune and a scroller from the author's raster demo
; (rasterbars/: stable bars with CIA1 timer A at 63 cycles per line,
; calibrated against $d012, clockslides; tables from tools/mkloader.py),
; the SIDJ logo in ROM quadrant characters, a menu with a raster bar behind
; the selected row, and an info line (REU size, second SID, SID model).
;
; The menu chains to SIDJ.EDITOR, TASTE, README or MANUAL (all on the one
; disk) through
; a stub in the tape buffer ($033c-$03fb), which no target loads over:
; machine reset (SIDs, VIC IRQ and sprites off, $01 = $37, $0314-$0333 from
; the copy saved at start, CINT, which also restores the jiffy timer), LOAD
; from the device in $ba (8 if not 8-30), then RUN ($a659 + $a7ae).
;
; Memory: program $0801-~$1300, buffers $2000-$22ff, screen $0400 with the
; ROM charset. Debug hook: $0810 state (0 menu, 1 unused, 2 loading,
; 3 load error), $0811 selected entry (0-3), $0812 video (1 PAL, 0 NTSC),
; $0813 KERNAL load error code. Keys also come from the keyboard buffer
; ($c6/$0277) for tests and remote control.
;
; NTSC: no calibrated bars (63-cycle lines only); simple polled bars.

SID      = $d400
VIC      = $d000
FIRST    = 56                   ; first bar line (multiple of 8), must match mkloader.py
ENDLINE  = 240                  ; first line after the bars
BARLEN   = 13
NBARS    = 5
SLIDE    = 40
ADJ      = 0
MSPEED   = 6
SPEED    = 1                    ; scroller pixels per frame
MROW     = 13                   ; first menu row (rows 13, 15, 17, 19)
IROW     = 21                   ; info line
HROW     = 22                   ; key help
SROW     = 24                   ; scroller
MCOL     = 11
HL_LO    = 50 + 8 * MROW        ; highlight band (lines)
HL_HI    = 60 + 8 * (MROW + 6)
SCREEN   = $0400
COLRAM   = $d800
buf      = $2000                ; colour per raster line
slidetab = $2100
seen     = $2200
pagebuf  = $2200                ; reu.asm (reu_put, unused here)
STUB     = $033c

zp_ptr   = $fb                  ; boot_sid.asm
bar      = $fd
cidx     = $fe
cnt      = $02

CINT     = $ff81
SETLFS   = $ffba
SETNAM   = $ffbd
LOAD     = $ffd5
CHROUT   = $ffd2

; action codes
A_E1 = 1                        ; 1-4: entry
A_UP = 5
A_DN = 6
A_GO = 7
A_STOP = 8

        .enc "sj"               ; screen codes, upper case / graphics set
        .cdef " ?", $20
        .cdef "@Z", $00
        .cdef "az", $01
        .enc "none"

        * = $0801
        .word basend, 10                ; 10 SYS 2061
        .byte $9e
        .text "2061"
        .byte 0
basend  .word 0
        jmp init
state   .byte 0                         ; $0810
sel     .byte 0                         ; $0811
ispal   .byte 0                         ; $0812
lderr   .byte 0                         ; $0813
        .cerror state != $0810, "debug hook moved"
        .fill $0900 - *, 0
        .include "gen.asm"              ; rblock ($0900), sine, freq tables, logo, scroll text, byline

; ---------------------------------------------------------------------
init    sei
        cld
        ldx #$ff                        ; own stack
        txs
        ldx #stub_end-stub_src-1        ; chain stub -> tape buffer
-       lda stub_src,x
        sta STUB,x
        dex
        cpx #$ff
        bne -
        ldx #$1f                        ; the vectors as we found them
-       lda $0314,x
        sta vecs,x
        dex
        bpl -
        lda $ba                         ; device: $ba if 8-30, else 8
        cmp #8
        bcc +
        cmp #31
        bcc ++
+       lda #8
+       sta dev
        lda #0
        sta $c6                         ; keyboard buffer empty
        sta state
        sta sel
        sta lderr
        lda #$7f
        sta $dc0d
        sta $dd0d
        lda $dc0d
        lda $dd0d
        lda #0
        sta $d015
        sta $d01a
        lda #$ff
        sta $d019
        lda #$0b                        ; blank: no DMA while probing / calibrating
        sta $d011

        lda #0                          ; probes
        sta pl_sid2
        sta pl_sid2+1
        jsr sid_probe
        jsr reu_detect
        lda pl_sid2                     ; stub silences the second SID too
        ldx pl_sid2+1
        bne +
        lda #<SID
        ldx #>SID
+       sta s2clr+1
        stx s2clr+2

        jsr paldet
        lda ispal
        beq +
        jsr calib
        jsr mkslide
+       jsr sidinit
        jsr drawscreen
        ldx #NBARS-1
        lda #FIRST
-       sta oldtop,x
        dex
        bpl -

; ---------------------------------------------------------------------
frame   bit $d011                       ; the frame's work may end before line
        bmi _top                        ; 256, after it, or in lines 0..FIRST-2 of
        lda $d012                       ; the next frame: get to line 0..FIRST-2
        cmp #FIRST-1
        bcc _go
-       bit $d011
        bpl -
_top    bit $d011
        bmi _top
_go
        lda #$1b
        sta $d011
        lda #$08                        ; 40 columns, no scroll above the scroller
        sta $d016
        lda #FIRST-1
-       cmp $d012
        bne -
        ldx #FIRST
        lda ispal
        beq +
        jsr rblock
        jmp ++
+       jsr simple
+       lda #0                          ; below the bars: black
        sta $d020
        sta $d021
        lda xs                          ; scroller row: 38 columns, fine scroll
        sta $d016

        jsr music
        jsr drawbars
        jsr colours
        jsr input
        jsr scroll
        jmp frame

; NTSC: polled bars, one colour per line (not stable), down to the menu band
; only, so the frame's work still fits in the 263-line frame
simple
-       lda buf,x
-       cpx $d012                       ; wait for line X (or later: a bad line
        bcc +                           ; may have eaten it)
        bne -
+       sta $d021
        sta $d020
        inx
        cpx #HL_HI+1                    ; NTSC frames are shorter: stop after the menu
        bne --
        rts

; PAL if the last line before the wrap is $137 (NTSC: $106 / $105)
paldet
-       lda $d012
-       cmp $d012
        beq -
        bmi --
        ldx #0
        cmp #$20
        bcc +
        inx
+       stx ispal
        rts

; ---------------------------------------------------------------------
; Bars: five sine bars in the logo band, the highlight behind the menu row
drawbars
        ldx #NBARS-1                    ; erase last frame's bars
_er     ldy oldtop,x
        lda #BARLEN
        sta cnt
        lda #0
-       sta buf,y
        iny
        dec cnt
        bne -
        dex
        bpl _er
        ldx #0
_bar    stx bar
        lda phase
        clc
        adc offsets,x
        tay
        lda sine,y
        sta oldtop,x
        tay
        lda coloff,x
        sta cidx
        lda #BARLEN
        sta cnt
-       ldx cidx
        lda colors,x
        sta buf,y
        inc cidx
        iny
        dec cnt
        bne -
        ldx bar
        inx
        cpx #NBARS
        bne _bar
        inc phase
        inc phase

        lda #0                          ; highlight band
        ldx #HL_HI-HL_LO
-       sta buf+HL_LO,x
        dex
        bpl -
        lda state
        cmp #2
        bcs _hx
        lda sel                         ; lines 50 + 8 * row .. +9
        asl
        asl
        asl
        asl
        adc #50+8*MROW
        tay
        lda sel                         ; gradient: sel * 10
        asl
        sta cnt
        asl
        asl
        adc cnt
        tax
        lda #10
        sta cnt
_hd     lda hlcol,x
        sta buf,y
        inx
        iny
        dec cnt
        bne _hd
_hx     rts

; menu rows: black on the highlight, grey otherwise
colours lda sel                         ; rows only when the selection changes
        cmp lastsel
        bne +
        rts
+       sta lastsel
        ldy #0
_row    lda #15
        cpy sel
        bne +
        lda #0
+       ldx mrowl,y
        stx _st+1
        ldx mrowh,y
        stx _st+2
        ldx #MLEN-1
_st     sta $ffff,x
        dex
        bpl _st
        iny
        cpy #4
        bne _row
        rts

; ---------------------------------------------------------------------
; Input: keyboard buffer (tests, remote control), joystick 2, key matrix
input   ldx $c6
        beq _mx
        lda $0277
        ldx #0
        stx $c6
        ldx #npet-1
-       cmp petkeys,x
        beq +
        dex
        bpl -
        rts
+       lda petact,x
        jmp act

_mx     lda #$ff                        ; joystick 2
        sta $dc00
        lda $dc00
        and #$1f
        eor #$1f
        beq _kb
        ldx #A_UP
        lsr
        bcs _new
        ldx #A_DN
        lsr
        bcs _new
        ldx #0
        and #4
        beq _new
        ldx #A_GO
        bne _new
_kb     ldy #nmat-1                     ; matrix: first key in the table
-       lda matcol,y
        sta $dc00
        lda $dc01
        and matbit,y
        beq +
        dey
        bpl -
        ldx #0
        beq _new
+       ldx matact,y
        cpx #A_DN                       ; CRSR down + SHIFT = up
        bne _new
        lda #$fd
        sta $dc00
        lda $dc01
        and #$80
        beq +
        lda #$bf
        sta $dc00
        lda $dc01
        and #$10
        bne _new
+       ldx #A_UP
_new    lda #$ff
        sta $dc00
        cpx lastkey
        stx lastkey
        bne +
        rts
+       txa
        bne act
        rts

; A = action
act     cmp #A_UP
        bne +
        lda sel
        sbc #1
        and #3
        sta sel
        rts
+       cmp #A_DN
        bne +
        lda sel
        clc
        adc #1
        and #3
        sta sel
        rts
+       cmp #A_GO
        bne +
        lda sel
        jmp chain
+       cmp #A_STOP
        bcs +
        sbc #0                          ; C clear: A - 1
        sta sel
        jmp chain
+       rts

; A = entry: name into the stub, go
chain   sta sel
        tax
        lda #2
        sta state
        lda nameoff,x
        tay
        ldx #0
-       lda names,y
        beq +
        sta name,x
        iny
        inx
        bne -
+       stx namelen
        jmp STUB

; ---------------------------------------------------------------------
drawscreen
        lda #$15                        ; screen $0400, ROM upper case / graphics
        sta $d018
        lda #0
        sta $d020
        sta $d021
        ldx #0
-       lda #$20
        sta SCREEN,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$2e8,x
        lda #15
        sta COLRAM,x
        sta COLRAM+$100,x
        sta COLRAM+$200,x
        sta COLRAM+$2e8,x
        lda #0
        sta buf,x
        inx
        bne -
        lda #<logo                      ; logo, rows 1-8, white
        sta zp_ptr
        lda #>logo
        sta zp_ptr+1
        ldx #0
_lr     ldy #LOGO_W-1
_lc     lda (zp_ptr),y
        sta SCREEN+40+LOGO_COL,y        ; operand moves down a row each time
        dey
        bpl _lc
        lda zp_ptr
        clc
        adc #LOGO_W
        sta zp_ptr
        bcc +
        inc zp_ptr+1
+       lda _lc+3                       ; next screen row
        clc
        adc #40
        sta _lc+3
        bcc +
        inc _lc+4
+       inx
        cpx #8
        bne _lr
        ldx #39                         ; static text rows
-       lda subtitle,x
        sta SCREEN+10*40,x
        lda #13
        sta COLRAM+10*40,x
        lda byline,x
        sta SCREEN+11*40,x
        lda #12
        sta COLRAM+11*40,x
        lda help,x
        sta SCREEN+HROW*40,x
        lda #11
        sta COLRAM+HROW*40,x
        lda #7
        sta COLRAM+IROW*40,x
        dex
        bpl -
        lda #1                          ; logo rows white
        ldx #0
-       sta COLRAM+40,x
        sta COLRAM+40+64,x
        inx
        bne -
        ldy #3                          ; menu entries
_me     lda mrowl,y
        sta zp_ptr
        lda mrowh,y
        and #3
        ora #>SCREEN
        sta zp_ptr+1
        ldx mtoff,y
        tya
        pha
        ldy #0
-       lda mtext,x
        sta (zp_ptr),y
        inx
        iny
        cpy #MLEN
        bne -
        pla
        tay
        dey
        bpl _me
        jmp infoline

; info line: REU size, second SID, SID model
infoline
        ldx #0
        lda nbanks+1
        bne _reu16
        lda nbanks
        bne _reu
        ldy #s_noreu-strs
        jsr put
        jmp _sid
_reu16  ldy #s_reu-strs
        jsr put
        ldy #s_16m-strs
        jsr put
        jmp _sid
_reu    ldy #s_reu-strs                 ; banks 2, 4 .. 128 -> 128K .. 8M
        jsr put
        lda nbanks
        ldy #s_128-strs-5
-       iny
        iny
        iny
        iny
        iny
        lsr
        cmp #1
        bne -
        jsr put
_sid    inx
        inx
        lda pl_sid2+1
        beq _mono
        ldy #s_2sid-strs
        jsr put
        lda pl_sid2+1
        jsr hex
        lda pl_sid2
        jsr hex
        jmp _mod
_mono   ldy #s_1sid-strs
        jsr put
_mod    inx
        inx
        lda sid_model
        asl
        asl
        asl
        adc #s_mod-strs
        tay
        jsr put
        rts                             ; X = length: centre is cosmetic

; string strs+Y (0 ends) to the info line at X
put     lda strs,y
        beq +
        sta SCREEN+IROW*40+6,x
        inx
        iny
        bne put
+       rts
hex     pha
        lsr
        lsr
        lsr
        lsr
        jsr +
        pla
        and #15
+       tay
        lda hexd,y
        sta SCREEN+IROW*40+6,x
        inx
        rts

; ---------------------------------------------------------------------
scroll  lda xs
        sec
        sbc #SPEED
        bcs _set
        and #7
        sta xs
        ldx #0
-       lda SCREEN+SROW*40+1,x
        sta SCREEN+SROW*40,x
        inx
        cpx #39
        bne -
        ldy tpos
        lda scrolltext,y
        bne +
        ldy #0
        lda scrolltext
+       sta SCREEN+SROW*40+39
        iny
        sty tpos
        jmp _sc
_set    sta xs
_sc     lda phase                       ; colour cycle: 40 bytes of cyc2 from phase/4
        lsr
        lsr
        and #15
        clc
        adc #<cyc2
        sta _cc+1
        lda #>cyc2
        adc #0
        sta _cc+2
        ldx #39
_cc     lda cyc2,x
        sta COLRAM+SROW*40,x
        dex
        bpl _cc
        rts

; ---------------------------------------------------------------------
; Music from the raster demo: bass, per-frame chord arpeggio, lead.
sidinit ldx #$18
-       lda #0
        sta SID,x
        dex
        bpl -
        sta mtick
        sta mstep
        sta arpi
        lda #$0a
        sta SID+5
        lda #$00
        sta SID+6
        lda #$00
        sta SID+12
        lda #$50
        sta SID+13
        lda #$04
        sta SID+10
        lda #$41
        sta SID+11
        lda #$0a
        sta SID+19
        lda #$a5
        sta SID+20
        lda #$0f
        sta SID+24
        rts

music   lda mstep
        lsr
        lsr
        lsr
        lsr
        sta cnt
        asl
        adc cnt
        adc arpi
        tay
        ldx chords,y
        lda freqlo,x
        sta SID+7
        lda freqhi,x
        sta SID+8
        ldy arpi
        iny
        cpy #3
        bne +
        ldy #0
+       sty arpi
        clc
        lda pwl
        adc #$18
        sta pwl
        sta SID+16
        lda pwh
        adc #0
        and #$0f
        sta pwh
        sta SID+17
        ldy mstep
        lda mtick
        bne _t1
        lda bass,y
        beq +
        lda #$20
        sta SID+4
+       lda lead,y
        beq _nx
        lda #$40
        sta SID+18
        jmp _nx
_t1     cmp #1
        bne _nx
        lda bass,y
        beq +
        tax
        lda freqlo,x
        sta SID+0
        lda freqhi,x
        sta SID+1
        lda #$21
        sta SID+4
+       lda lead,y
        beq _nx
        cmp #$ff
        beq _nx
        tax
        lda freqlo,x
        sta SID+14
        lda freqhi,x
        sta SID+15
        lda #$41
        sta SID+18
_nx     inc mtick
        lda mtick
        cmp #MSPEED
        bne +
        lda #0
        sta mtick
        lda mstep
        clc
        adc #1
        and #63
        sta mstep
+       rts

; ---------------------------------------------------------------------
; CIA1 timer A at 63 cycles, phase against the raster (see rasterbars)
calib   lda #62
        sta $dc04
        lda #0
        sta $dc05
        lda #$11
        sta $dc0e
        lda #0
        tay
-       sta seen,y
        iny
        bne -
        lda #80
-       cmp $d012
        bne -
        lda #1
        sta kd
_pass   ldx #13
_try    lda $d012
-       cmp $d012
        beq -
        ldy kd
-       dey
        bpl -
        lda $d012
-       cmp $d012
        beq -
        ldy $dc04
        lda #1
        sta seen,y
        dex
        bpl _try
        inc kd
        lda kd
        cmp #3
        bne _pass
        ldy #62
_find   lda seen,y
        beq _nxt
        tya
        tax
        inx
        cpx #63
        bne +
        ldx #0
+       lda seen,x
        beq _fnd
_nxt    dey
        bpl _find
        ldy #0
_fnd    sty t0
        rts

mkslide ldy #0
_m1     lda #SLIDE+1
        cpy #63
        bcs _m2
        sty cnt
        lda t0
        sec
        sbc cnt
        bcs +
        adc #63
+       clc
        adc #SLIDE-28+ADJ
        cmp #63
        bcc +
        sbc #63
+       cmp #SLIDE+2
        bcc _m2
        lda #SLIDE+1
_m2     sta slidetab,y
        iny
        bne _m1
        rts

        .include "reu.asm"              ; reu_detect (src/tx)
        .include "boot_sid.asm"         ; sid_probe (src/editor)

; ---------------------------------------------------------------------
; variables
xs      .byte 7
tpos    .byte 0
phase   .byte 0
t0      .byte 0
kd      .byte 0
mtick   .byte 0
mstep   .byte 0
arpi    .byte 0
pwl     .byte 0
pwh     .byte 8
lastkey .byte 0
lastsel .byte $ff
oldtop  .fill NBARS, 0
sid_model .byte 0
pl_sid2 .word 0
reu     .byte 0                         ; reu.asm
nbanks  .word 0
bswap   .byte 0
btune   .byte 0
ab      .byte 0
a0      .byte 0
ak      .byte 0
u_t     .byte 0
vecs    .fill 32, 0                     ; $0314-$0333 at start (read by the stub before LOAD)

offsets .byte 0, 22, 44, 66, 88
coloff  .byte 0, 13, 26, 39, 52
colors  .byte 9,2,8,10,15,7,7,7,15,10,8,2,9             ; yellow (7)
        .byte 11,9,9,2,2,8,8,8,2,2,9,9,11               ; orange (8)
        .byte 9,2,4,8,10,10,10,10,10,8,4,2,9            ; light red (10)
        .byte 11,5,5,3,13,13,13,13,13,3,5,5,11          ; light green (13)
        .byte 6,6,4,4,14,14,14,14,14,4,4,6,6            ; light blue (14)
hlcol   .byte 8,7,7,7,7,7,7,7,7,8
        .byte 9,8,8,8,8,8,8,8,8,9
        .byte 2,10,10,10,10,10,10,10,10,2
        .byte 5,13,13,13,13,13,13,13,13,5
cyc2    .byte 1,7,15,10,8,10,15,7,1,13,3,14,4,14,3,13   ; the cycle 4 times (16 + 40 bytes)
        .byte 1,7,15,10,8,10,15,7,1,13,3,14,4,14,3,13
        .byte 1,7,15,10,8,10,15,7,1,13,3,14,4,14,3,13
        .byte 1,7,15,10,8,10,15,7,1,13,3,14,4,14,3,13

chords  .byte 69,72,76, 65,69,72, 67,72,76, 67,71,74
bass    .byte 33,0,45,0,33,0,45,0,33,0,45,0,33,0,45,0
        .byte 29,0,41,0,29,0,41,0,29,0,41,0,29,0,41,0
        .byte 36,0,48,0,36,0,48,0,36,0,48,0,36,0,48,0
        .byte 31,0,43,0,31,0,43,0,31,0,43,0,31,0,43,0
lead    .byte 76,0,0,0,81,0,79,0,76,0,$ff,0,74,0,72,0
        .byte 72,0,0,0,77,0,76,0,72,0,$ff,0,69,0,72,0
        .byte 79,0,0,0,76,0,79,0,84,0,$ff,0,83,0,79,0
        .byte 74,0,0,0,79,0,77,0,74,0,$ff,0,71,0,74,0

; keyboard buffer (PETSCII) -> action
petkeys .byte $31,$32,$33,$34,$85,$86,$87,$88,$0d,$20,$11,$91,$03
npet    = * - petkeys
petact  .byte 1,2,3,4,1,2,3,4,A_GO,A_GO,A_DN,A_UP,A_STOP
; key matrix: column select, row bit, action
matcol  .byte $fe,$fe,$fe,$fe,$fe,$fe,$7f,$7f,$fd,$fd,$7f,$7f
matbit  .byte $02,$80,$10,$20,$40,$08,$01,$08,$01,$08,$10,$80
matact  .byte A_GO,A_DN,1,2,3,4,1,2,3,4,A_GO,A_STOP
nmat    = * - matact

mrowl   .for r := 0, r < 4, r += 1
        .byte <(COLRAM + (MROW + 2 * r) * 40 + MCOL)
        .next
mrowh   .for r := 0, r < 4, r += 1
        .byte >(COLRAM + (MROW + 2 * r) * 40 + MCOL)
        .next

; target file names (PETSCII: 64tass -a maps lower case ASCII to unshifted), 0 ends
names
n_ed    .text "sidj.editor"
        .byte 0
n_tx    .text "taste"
        .byte 0
n_rd    .text "readme"
        .byte 0
n_mn    .text "manual"
        .byte 0
mtoff   .byte 0, MLEN, 2 * MLEN, 3 * MLEN
nameoff .byte n_ed-names, n_tx-names, n_rd-names, n_mn-names

        .enc "sj"
MLEN    = 20
mtext   .text "1  SIDJ EDITOR      "
        .text "2  T.A.S.T.E.       "
        .text "3  README           "
        .text "4  MANUAL           "
        .cerror * - mtext != 4 * MLEN, "menu text"
subtitle .text "      DJ-STYLE TRACKER FOR THE C64      "
help    .text "  CRSR/JOY + RETURN, 1-4 OR F1/F3/F5/F7 "
strs
s_noreu .text "NO REU"
        .byte 0
s_reu   .text "REU "
        .byte 0
s_128   .text "128K"
        .byte 0
        .text "256K"
        .byte 0
        .text "512K"
        .byte 0
        .text "1M  "
        .byte 0
        .text "2M  "
        .byte 0
        .text "4M  "
        .byte 0
        .text "8M  "
        .byte 0
s_16m   .text "16M"
        .byte 0
s_2sid  .text "2SID $"
        .byte 0
s_1sid  .text "1 SID"
        .byte 0
s_mod   .text "SID ?  "
        .byte 0
        .text "6581   "
        .byte 0
        .text "8580   "
        .byte 0
hexd    .text "0123456789ABCDEF"
        .enc "none"

; ---------------------------------------------------------------------
; chain stub, copied to the tape buffer at start
stub_src
        .logical STUB
stub    sei
        lda #0
        ldx #$18
-       sta SID,x
s2clr   sta SID,x                       ; second SID (patched at start)
        dex
        bpl -
        sta $d015                       ; sprites, raster IRQ off
        sta $d01a
        lda #$ff
        sta $d019
        lda #$7f
        sta $dc0d
        sta $dc00
        lda $dc0d
        lda #$2f
        sta $00
        lda #$37
        sta $01
        ldx #$1f                        ; vectors as found at start (no RESTOR)
-       lda vecs,x
        sta $0314,x
        dex
        bpl -
        jsr CINT                        ; VIC, screen, PAL/NTSC jiffy timer
        cli
        lda namelen
        ldx #<name
        ldy #>name
        jsr SETNAM
        lda #1
        ldx dev
        ldy #1
        jsr SETLFS
        lda #0
        jsr LOAD
        bcs _err
        stx $2d                         ; end of program
        sty $2e
        lda #0                          ; RUN needs the 0 before the program: an
        sta $0800                       ; Exomizer sfx (the loader's own) can leave it set
        ldx #$fa
        txs
        jsr $a659                       ; RUN: CLR, text pointer to start
        jmp $a7ae                       ; next statement
_err    sta lderr
        lda #3
        sta state
        ldx #0
-       lda errmsg,x
        jsr CHROUT
        inx
        cpx #errlen
        bne -
        ldx #0
-       lda name,x
        jsr CHROUT
        inx
        cpx namelen
        bne -
        jmp ($a002)                     ; BASIC warm start: READY.
errmsg  .byte $0d
        .text "load error: "
errlen  = * - errmsg
dev     .byte 8
namelen .byte 0
name    .fill 16, 0
        .cerror * > $03fc, "stub too long"
        .here
stub_end
        .cerror * > $2000, "loader too long"
