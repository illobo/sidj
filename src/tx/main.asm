; T.A.S.T.E, The Approximate SidJ Transverter-Encoder: a standalone program that loads
; a PSID tune from drive 8, runs it with the I/O area banked out so that its
; SID writes land in RAM ($d400-$d418 under I/O), turns gate edges into notes,
; K commands and instruments, and writes a slice of it as a SIDJ project file
; the editor loads like its own saves.
;
; Memory:
;   $0801-        BASIC stub + mover (dead after start-up)
;   $a000-$cfff   program code, tables and variables (BASIC ROM off: $01 = $36);
;                 CODE+3 = ui_state (tests)
;   $d040-$dfff   RAM under I/O: the capture core and its state (core.asm)
;   $9800-$9bff   directory list (before a tune is loaded)
;   phrase store  2 KB blocks of 32 phrases (vpage): with an REU 8 blocks at
;                 $1000-$4fff, without one the highest three free 2 KB blocks
;                 of $0800-$9fff outside the tune's load range
; REU (256 KB or more; never banks 0 and 1, SIDJ's): the top bank (bswap) is
;   the swap partner during a capture, the one below (btune) holds the tune as
;   loaded. The tune can use all RAM but $d000-$dfff and the top of the stack.
; No REU: the tune is loaded into RAM: inside $0800-$9fff or $e000-$ffff.
; Tunes: PSID only, play != 0.
;
; Zero page: $02-$0f (BASIC's, BASIC is never used) while the KERNAL runs.
; During a capture nothing of ours uses zero page (the tune owns all of it).

        .include "defs.inc"

CODE    = $a000
VSTRIDE = $0800                 ; bytes per voice in the step buffer
MAXLEN  = 512                   ; steps without an REU
MAXLENR = 256*64                ; with one: 256 song rows
DIRBUF  = $9800                 ; 64 x 16 bytes PETSCII names, 0 padded
NDIRMAX = 64
SIDRAM  = $d400
HRWIN   = 3                     ; gate off followed by gate on within 3 frames: hard restart, no K
GUESSFR = 500                   ; frames looked at for the frames-per-step guess
WAITMAX = 3000                  ; frames to wait for the first note after the start
CMD_K   = 11
ESC     = $e7
LISTH   = 19                    ; file list rows

; KERNAL
SECOND  = $ff93
UNLSN   = $ffae
LISTEN  = $ffb1
SETLFS  = $ffba
SETNAM  = $ffbd
OPEN    = $ffc0
CLOSE   = $ffc3
CHKIN   = $ffc6
CHKOUT  = $ffc9
CLRCHN  = $ffcc
CHRIN   = $ffcf
CHROUT  = $ffd2
GETIN   = $ffe4
STATUS  = $90
NDX     = $c6                   ; keyboard buffer count

; zero page
cur     = $02                   ; screen pointer
sp      = $04                   ; inline string pointer
zp_p    = $06
zp_q    = $08
zp_r    = $0a
errp    = $0c                   ; error message pointer

; colours: orange / green
C_BORDER = 8                    ; orange
C_BG    = 0                     ; black
C_TITLE = 13                    ; light green
C_TEXT  = 5                     ; green
C_SEL   = 8                     ; orange: cursor row
C_VAL   = 13                    ; light green: values
C_MSG   = 7                     ; yellow: status line
C_ERR   = 10                    ; light red: errors

; keys (PETSCII)
K_DOWN  = $11
K_UP    = $91
K_RIGHT = $1d
K_LEFT  = $9d
K_RET   = $0d
K_DEL   = $14
K_F1    = $85
K_PLUS  = $2b
K_MINUS = $2d

; ---------------------------------------------------------------------------
; BASIC stub and mover
; ---------------------------------------------------------------------------
        * = $0801
        .word _next, 2026
        .byte $9e
        .text format("%d", start)
        .byte 0
_next   .word 0
start   sei
        cld
        ldx #$ff
        txs
        lda #<payload
        sta zp_p
        lda #>payload
        sta zp_p+1
        lda #<CODE
        sta zp_q
        lda #>CODE
        sta zp_q+1
        ldx #NPAGES
        ldy #0
-       lda (zp_p),y            ; writes go to the RAM under the BASIC ROM
        sta (zp_q),y
        iny
        bne -
        inc zp_p+1
        inc zp_q+1
        dex
        bne -
        lda #$36                ; BASIC out, KERNAL + I/O in
        sta $01
        cli
        jmp main

payload
        .logical CODE
        .enc "screen"
        jmp main
ui_state .byte 0                ; CODE+3: screen waiting for a key (tests): 0 busy, 1 files, 2 options, 3 yes/no, 4 message
        .byte 0, 0, 0, 0

main    ldx #$ff
        txs
        sei                     ; the capture core under I/O (once: nothing else writes there)
        lda #$34
        sta $01
        ldx #>(CORELEN+255)
        ldy #0
-
_src    lda core_img,y
_dst    sta CORE,y
        iny
        bne -
        inc _src+2
        inc _dst+2
        dex
        bne -
        lda #$36
        sta $01
        cli
        lda #C_BORDER
        sta $d020
        lda #C_BG
        sta $d021
        lda #$15                ; upper case charset
        sta $d018
        lda #8
        sta device
        lda #0
        sta loaded
        jsr reu_detect
_files  jsr file_screen
        jsr options
        jmp _files

; ---------------------------------------------------------------------------
; File list
; ---------------------------------------------------------------------------
file_screen
        jsr cls
        jsr title
        ldx #2
        ldy #0
        jsr at
        jsr prt
        .null "drive 8: reading directory..."
        jsr read_dir
        bcc +
        jsr show_err
        jsr wait_msg
        jmp file_screen
+       lda ndir
        bne +
        ldx #2
        jsr clr_row
        jsr prt
        .null "no prg files on drive 8"
        jsr wait_msg
        jmp file_screen
+       ldx #2
        jsr clr_row
        jsr prt
        .null "pick a psid tune (drive 8):"
        ldx #23
        ldy #0
        jsr at
        jsr prt
        .null "crsr up/down, return: load, r: reread"
        ldx #22
        ldy #0
        jsr at
        jsr p_reu
        lda #0
        sta sel
        sta top
_draw   jsr draw_files
_key    lda #1
        jsr get_key
        cmp #K_DOWN
        bne _up
        ldx sel
        inx
        cpx ndir
        bcs _key
        stx sel
        txa
        sec
        sbc top
        cmp #LISTH
        bcc _draw
        inc top
        bne _draw
_up     cmp #K_UP
        bne _ret
        ldx sel
        beq _key
        dex
        stx sel
        cpx top
        bcs _draw
        stx top
        jmp _draw
_ret    cmp #$52                ; R: read the directory again
        bne +
        jmp file_screen
+       cmp #K_RET
        bne _key
        ldx #24
        jsr clr_row
        jsr prt
        .null "loading..."
        jsr load_psid
        bcc +
        jsr show_err
        jmp _key
+       lda #1
        sta loaded
        rts

draw_files
        ldx #3
-       jsr clr_row
        inx
        cpx #3+LISTH
        bne -
        lda #0
        sta t0
_row    lda top
        clc
        adc t0
        cmp ndir
        bcs _done
        sta t1
        lda t0
        clc
        adc #3
        tax
        lda t1
        cmp sel
        bne +
        lda #C_SEL
        .byte $2c
+       lda #C_TEXT
        ldy #0
        jsr setcol
        ldy #0
        jsr at
        lda t1
        cmp sel
        bne +
        lda #$3e                ; '>'
        .byte $2c
+       lda #$20
        jsr putc
        lda #$20
        jsr putc
        lda t1
        jsr dir_ptr             ; zp_q = entry
        ldy #0
-       lda (zp_q),y
        beq _next
        jsr pet2scr
        sty t2
        jsr putc
        ldy t2
        iny
        cpy #16
        bne -
_next   inc t0
        lda t0
        cmp #LISTH
        bne _row
_done   rts

; A = entry -> zp_q = DIRBUF + A*16
dir_ptr ldx #0
        stx zp_q+1
        asl
        rol zp_q+1
        asl
        rol zp_q+1
        asl
        rol zp_q+1
        asl
        rol zp_q+1
        sta zp_q
        lda zp_q+1
        clc
        adc #>DIRBUF
        sta zp_q+1
        rts

; ---------------------------------------------------------------------------
; Options
; ---------------------------------------------------------------------------
NROWS   = 9
R_SUB   = 0
R_VOICE = 1
R_START = 2
R_LEN   = 3
R_FPS   = 4
R_NOTES = 5
R_INSTR = 6
R_OFFS  = 7
R_NAME  = 8
OROW    = 8                     ; screen row of option 0

options
        jsr cls
        jsr title
        jsr draw_info
        lda last_ok
        beq +
        jsr draw_result
+
        ldx #23
        ldy #0
        jsr at
        jsr prt
        .null "crsr:select/change +/-:more f1:files"
        ldx #22
        ldy #0
        jsr at
        jsr prt
        .null "return: transcribe   1 2 3: voices"
_draw   jsr draw_opts
_key    lda #2
        jsr get_key
        cmp #K_F1
        bne +
        rts
+       cmp #K_RET
        bne +
        jsr transcribe
        jmp options
+       cmp #K_DOWN
        bne +
        ldx o_row
        cpx #NROWS-1
        beq _key
        inc o_row
        bne _draw
+       cmp #K_UP
        bne +
        ldx o_row
        beq _key
        dec o_row
        jmp _draw
+       ldx o_row
        cpx #R_NAME
        bne +
        jsr name_key
        jmp _draw
+       cmp #$31                ; 1 2 3 toggle voices on every row except the name
        bcc +
        cmp #$34
        bcs +
        sbc #$30                ; C clear: A - $31 = voice 0..2
        tax
        lda vbit,x
        eor o_voices
        sta o_voices
        jmp _draw
+       jsr val_key
        jmp _draw

; left/right/+/- on a numeric or on/off row
val_key cpx #R_VOICE
        beq _r
        ldy #0
        cmp #K_RIGHT
        beq _small
        cmp #K_LEFT
        beq _msmall
        cmp #K_PLUS
        beq _big
        cmp #K_MINUS
        beq _mbig
_r      rts
_small  lda d_small,x
        bne _add
_msmall lda d_small,x
        bne _neg
_big    lda d_big,x
        bne _add
_mbig   lda d_big,x
_neg    eor #$ff
        clc
        adc #1
        dey                     ; Y = $ff: high byte of the negative delta
_add    cpx #R_NOTES            ; on/off: any change flips
        bcc +
        lda o_lo,x
        eor #1
        sta o_lo,x
        rts
+       clc
        adc o_lo,x
        sta t0
        tya
        adc o_hi,x
        sta t1
        bmi _min                ; below 0
        cmp v_maxhi,x
        bcc +
        bne _max
        lda t0
        cmp v_maxlo,x
        bcc +
        beq +
_max    lda v_maxlo,x
        sta o_lo,x
        lda v_maxhi,x
        sta o_hi,x
        rts
+       lda t1                  ; >= min (min < 256)
        bne _st
        lda t0
        cmp v_min,x
        bcs _st
_min    lda v_min,x
        sta o_lo,x
        lda #0
        sta o_hi,x
        rts
_st     lda t0
        sta o_lo,x
        lda t1
        sta o_hi,x
        rts

;              sub voi sta len fps not ins off
d_small .byte  1,  0,  1,  16, 1,  1,  1,  1
d_big   .byte  1,  0,  10, 64, 4,  1,  1,  1
v_min   .byte  1,  0,  0,  16, 0,  0,  0,  0
v_maxlo .byte  1,  0,  <999, <MAXLEN, 32, 1, 1, 1
v_maxhi .byte  0,  0,  >999, >MAXLEN, 0,  0, 0, 0

; output name: letters, digits, space, '.', '-', DEL
name_key
        cmp #K_DEL
        bne +
        lda o_nlen
        beq _r
        dec o_nlen
        rts
+       ldx o_nlen
        cpx #16
        bcs _r
        cmp #$41
        bcc +
        cmp #$5b
        bcc _ok
+       cmp #$30
        bcc +
        cmp #$3a
        bcc _ok
+       cmp #$20
        beq _ok
        cmp #$2e
        beq _ok
        cmp #$2d
        bne _r
_ok     sta o_name,x
        inc o_nlen
_r      rts

draw_opts
        lda #0
        sta t0
_row    lda t0
        clc
        adc #OROW
        tax
        jsr clr_row
        ldy #15
        lda #C_VAL
        jsr setcol
        lda t0
        cmp o_row
        bne +
        lda #C_SEL
        .byte $2c
+       lda #C_TEXT
        jsr setcol_lab
        ldy #0
        jsr at
        lda t0
        cmp o_row
        bne +
        lda #$3e
        .byte $2c
+       lda #$20
        jsr putc
        lda #$20
        jsr putc
        lda t0
        asl
        tax
        lda labels,x
        sta sp
        lda labels+1,x
        sta sp+1
        jsr prt_sp
        lda t0
        clc
        adc #OROW
        tax
        ldy #15
        jsr at
        lda t0
        asl
        tax
        lda vdraw,x
        sta _jmp+1
        lda vdraw+1,x
        sta _jmp+2
_jmp    jsr $ffff
        inc t0
        lda t0
        cmp #NROWS
        bne _row
        rts

labels  .word l_sub, l_voi, l_sta, l_len, l_fps, l_not, l_ins, l_off, l_nam
l_sub   .null "subtune"
l_voi   .null "voices"
l_sta   .null "start (s)"
l_len   .null "length"
l_fps   .null "frames/step"
l_not   .null "notes"
l_ins   .null "instruments"
l_off   .null "note-offs"
l_nam   .null "output name"
vdraw   .word dv_sub, dv_voi, dv_sta, dv_len, dv_fps, dv_tog, dv_tog, dv_tog, dv_nam

dv_sub  lda o_lo+R_SUB
        jsr pdec8
        jsr prt
        .null " of "
        lda songs
        jsr pdec8
        ldx o_lo+R_SUB
        jsr is_cia
        beq +
        jsr prt
        .null "  cia"
        rts
+       jsr prt
        .null "  vbi"
        rts

dv_voi  ldx #0
-       lda vbit,x
        and o_voices
        beq +
        txa
        clc
        adc #$31                ; voice number 1-3 (ora would turn 1 into "1" again)
        .byte $2c
+       lda #$2d
        jsr putc
        lda #$20
        jsr putc
        inx
        cpx #3
        bne -
        rts

dv_sta  ldx #R_START
        jsr pdec_opt
        lda last_ok
        beq +
        jsr prt
        .null " (grid at frame "
        lda x_gridfr
        sta num
        lda x_gridfr+1
        sta num+1
        jsr pdec
        lda #$29
        jmp putc
+       rts

dv_len  ldx #R_LEN
        jsr pdec_opt
        jsr prt
        .null " steps = "
        lda o_lo+R_LEN
        clc
        adc #63
        sta num
        lda o_hi+R_LEN
        adc #0
        sta num+1
        ldx #6
-       lsr num+1
        ror num
        dex
        bne -
        jsr pdec
        jsr prt
        .null " rows"
        rts

dv_fps  lda o_lo+R_FPS
        bne +
        jsr prt
        .null "auto"
        lda g_fps
        beq _r
        jsr prt
        .null " (guess "
        lda g_fps
        jsr pdec8
        lda #$29
        jmp putc
+       jsr pdec8
_r      rts

dv_tog  lda t0
        tax
        lda o_lo,x
        beq +
        jsr prt
        .null "on"
        rts
+       jsr prt
        .null "off"
        rts

dv_nam  ldx #0
-       cpx o_nlen
        beq +
        lda o_name,x
        jsr pet2scr
        jsr putc
        inx
        bne -
+       lda o_row
        cmp #R_NAME
        bne +
        lda #$a0                ; reversed space: the typing position
        jsr putc
+       rts

; X = option row: print its 16-bit value
pdec_opt
        lda o_lo,x
        sta num
        lda o_hi,x
        sta num+1
        jmp pdec

; tune info, rows 1-6
draw_info
        ldx #2
-       ldy #9
        lda #C_VAL
        jsr setcol
        inx
        cpx #5
        bne -
-       ldy #0
        jsr setcol
        inx
        cpx #7
        bne -
        ldx #2
        ldy #0
        jsr at
        jsr prt
        .null "name     "
        lda #$16
        jsr p_ascii
        ldx #3
        ldy #0
        jsr at
        jsr prt
        .null "author   "
        lda #$36
        jsr p_ascii
        ldx #4
        ldy #0
        jsr at
        jsr prt
        .null "released "
        lda #$56
        jsr p_ascii
        ldx #5
        ldy #0
        jsr at
        jsr prt
        .null "load $"
        lda load+1
        jsr phex
        lda load
        jsr phex
        jsr prt
        .null "-$"
        lda lend+1
        jsr phex
        lda lend
        jsr phex
        jsr prt
        .null " init $"
        lda init+1
        jsr phex
        lda init
        jsr phex
        ldx #6
        ldy #0
        jsr at
        jsr prt
        .null "play $"
        lda play+1
        jsr phex
        lda play
        jsr phex
        jsr prt
        .null " songs "
        lda songs
        jsr pdec8
        lda ntsc
        beq +
        jsr prt
        .null " ntsc  "
        jmp p_reu
+       jsr prt
        .null " pal  "
        ; fall through
p_reu   jsr prt
        .null "reu: "
        lda reu
        bne +
        jsr prt
        .null "no"
        rts
+       jsr prt
        .null "yes"
        rts

; A = header offset: up to 31 ASCII chars
p_ascii tax
        ldy #31
-       lda hdr,x
        beq _r
        jsr a2s
        sty t2
        jsr putc
        ldy t2
        inx
        dey
        bne -
_r      rts

; ASCII -> screen code
a2s     cmp #$20
        bcc _q
        cmp #$40
        bcc _r
        cmp #$60
        bcc _40
        cmp #$7b
        bcs _q
        sbc #$5f                ; C clear: - $60
        rts
_40     sbc #$3f                ; C clear: - $40
        rts
_q      lda #$3f
_r      rts

; ---------------------------------------------------------------------------
; Transcribe: guess pass (if frames/step is auto), capture, build, write
; ---------------------------------------------------------------------------
transcribe
        lda #0
        sta last_ok
        lda o_voices
        bne +
        jsr set_err
        .null "no voices selected"
        jmp _err
+       lda o_lo+R_FPS
        bne _fixed
        jsr busy
        .null "running the tune: guessing frames/step"
        lda #0
        jsr session
        bcc +
        jmp _abort
+       jsr guess_f
        lda g_fps
_fixed  sta fps
        jsr busy
        .null "running the tune: capturing"
        lda #1
        jsr session
        bcc +
        jmp _abort
+       lda x_grid
        bne +
        jsr set_err
        .null "no notes after the start"
        jmp _err
+       lda srow
        bne +
        jsr set_err
        .null "out of phrases"
        jmp _err
+       jsr calc_tempo
        lda #1
        sta last_ok
        jsr draw_result
        jsr busy
        .null "writing..."
        lda #0
        jsr write_project
        bcc _saved
        cmp #63                 ; file exists
        bne _err
        ldx #24
        jsr clr_row
        jsr prt
        .null "file exists. replace it? (y/n)"
-       lda #3
        jsr get_key
        cmp #$4e                ; N
        beq _kept
        cmp #$59                ; Y
        bne -
        jsr busy
        .null "writing..."
        lda #1
        jsr write_project
        bcs _err
_saved  ldx #24
        jsr clr_row
        jsr prt
        .null "saved "
        ldx #0
-       cpx nlen
        beq +
        lda name,x
        jsr pet2scr
        jsr putc
        inx
        bne -
+       jmp wait_msg
_kept   ldx #24
        jsr clr_row
        jsr prt
        .null "not saved"
        jmp wait_msg
_abort  jsr set_err
        .null "stopped"
_err    jsr show_err
        jmp wait_msg

; inline message on row 24 while working
busy    pla
        sta sp
        pla
        sta sp+1
        ldx #24
        jsr clr_row
        jsr prt_inl
        lda sp+1
        pha
        lda sp
        pha
        rts

; result summary, rows 18-20
draw_result
        ldx #18
        ldy #0
        lda #C_VAL
        jsr setcol
        inx
        ldy #0
        jsr setcol
        ldx #18
        jsr clr_row
        jsr prt
        .null "phrases "
        lda nphr
        jsr pdec8
        jsr prt
        .null " chains "
        lda nch
        jsr pdec8
        jsr prt
        .null " instr "
        lda x_ninstr
        jsr pdec8
        ldx #19
        jsr clr_row
        jsr prt
        .null "tempo "
        lda bpm
        sta num
        lda bpm+1
        sta num+1
        jsr pdec
        jsr prt
        .null " bpm, "
        lda fps
        jsr pdec8
        jsr prt
        .null " frames/step, "
        lda rate
        sta num
        lda rate+1
        sta num+1
        jsr pdec
        jsr prt
        .null " hz"
        ldx #20
        jsr clr_row
        lda full
        beq _r
        jsr prt
        .null "cut at step "
        lda #0
        sta num
        lda srow
        lsr
        ror num
        lsr
        ror num
        sta num+1
        jsr pdec
        lda full
        cmp #2
        beq +
        jsr prt
        .null ": out of phrases"
        rts
+       jsr prt
        .null ": out of chains"
_r      rts

; ---------------------------------------------------------------------------
; Screen helpers (direct screen writes, screen codes)
; ---------------------------------------------------------------------------
cls     ldx #0
-       lda #$20
        sta SCREEN,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$2e8,x
        lda #C_TEXT
        sta COLORRAM,x
        sta COLORRAM+$100,x
        sta COLORRAM+$200,x
        sta COLORRAM+$2e8,x
        inx
        bne -
        ldx #79
        lda #C_TITLE            ; title rows
-       sta COLORRAM,x
        dex
        bpl -
        ldx #39
        lda #C_MSG              ; status line
-       sta COLORRAM+24*40,x
        dex
        bpl -
        rts

; colour A from column Y to the end of row X; A, X kept
setcol  pha
        lda rowlo,x
        sta zp_r
        lda rowhi,x
        clc
        adc #>(COLORRAM-SCREEN)
        sta zp_r+1
        pla
-       sta (zp_r),y
        iny
        cpy #40
        bne -
        rts

; Title ~<[T.A.S.T.E.]>~, reversed, columns 12-27: the ROM font has no
; tilde, so sprites 0 and 1 draw one in the first and last cell.
title   ldx #0
        ldy #12
        jsr at
        ldx #0
-       lda s_taste,x           ; reversed
        beq +
        ora #$80
        jsr putc
        inx
        bne -
+       ldx #63                 ; tilde sprite at TILDE (block TILDE/64)
-       lda #0
        cpx #3*8                ; rows 2-3 hold the glyph (top-left 8x8)
        bcs +
        lda tilde,x
+       sta TILDE,x
        dex
        bpl -
        lda #TILDE/64
        sta SCREEN+$3f8
        sta SCREEN+$3f9
        lda #24+12*8            ; columns 12 and 27, row 0
        sta VIC+0
        lda #24+27*8
        sta VIC+2
        lda #50
        sta VIC+1
        sta VIC+3
        lda #0                  ; black on the reversed title
        sta VIC+$27
        sta VIC+$28
        sta VIC+$10
        sta VIC+$17
        sta VIC+$1d
        sta VIC+$1b
        sta VIC+$1c
        lda #3
        sta VIC+$15
        ldx #1
        ldy #0
        jsr at
        jsr prt
        .null "the approximate sidj transverter-encoder"
        rts
s_taste .null " <[t.a.s.t.e.]> "
TILDE   = $0340                 ; cassette buffer (sprite block 13): no disk use

; flip both tildes horizontally (~ <-> its mirror): shows disk and capture
; activity. Only writes the sprite bytes, so any $01 setting will do.
wiggle  lda TILDE+6
        cmp #$72
        bne +
        lda #$4e                ; mirrored
        ldx #$39
        bne ++
+       lda #$72
        ldx #$9c
+       sta TILDE+6
        stx TILDE+9
        rts
tilde   .byte 0,0,0, 0,0,0, $72,0,0, $9c,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0

; X = row, Y = column -> cur
at      lda rowlo,x
        sta cur
        lda rowhi,x
        sta cur+1
        tya
        clc
        adc cur
        sta cur
        bcc +
        inc cur+1
+       rts

; clear row X, cur = its start
clr_row cpx #24
        bne +
        ldy #0
        lda #C_MSG
        jsr setcol
+       ldy #0
        jsr at
        lda #$20
        ldy #39
-       sta (cur),y
        dey
        bpl -
        rts

; colour A for columns 0-14 of row X
setcol_lab
        pha
        lda rowlo,x
        sta zp_r
        lda rowhi,x
        clc
        adc #>(COLORRAM-SCREEN)
        sta zp_r+1
        pla
        ldy #14
-       sta (zp_r),y
        dey
        bpl -
        rts

; A to the screen at cur, cur+1. X kept, Y = 0.
putc    ldy #0
        sta (cur),y
        inc cur
        bne +
        inc cur+1
+       rts

; inline null-terminated string after the jsr
prt     pla
        sta sp
        pla
        sta sp+1
        jsr prt_inl
        lda sp+1
        pha
        lda sp
        pha
        rts
prt_inl
-       inc sp
        bne +
        inc sp+1
+       ldy #0
        lda (sp),y
        beq +
        jsr putc
        jmp -
+       rts

; string at sp (not inline)
prt_sp  lda sp
        bne +
        dec sp+1
+       dec sp
        jmp prt_inl

phex    pha
        lsr
        lsr
        lsr
        lsr
        jsr _dig
        pla
        and #$0f
_dig    tay
        lda hexscr,y
        jmp putc
hexscr  .text "0123456789abcdef"

pdec8   sta num
        lda #0
        sta num+1
; num (16 bit) in decimal, no leading zeros
pdec    lda #0
        sta t3                  ; digit printed
        ldx #4
_digit  ldy #0
-       lda num
        sec
        sbc p10lo,x
        sta t2
        lda num+1
        sbc p10hi,x
        bcc +
        sta num+1
        lda t2
        sta num
        iny
        bne -
+       tya
        bne _pr
        lda t3
        bne _pr
        cpx #0
        bne _skip
_pr     tya
        ora #$30
        sta t3
        txa
        pha
        lda t3
        jsr putc
        pla
        tax
_skip   dex
        bpl _digit
        rts
p10lo   .byte <1, <10, <100, <1000, <10000
p10hi   .byte >1, >10, >100, >1000, >10000

; PETSCII <-> screen code (fileio's 32-byte group map)
pet2scr sty t4
        pha
        lsr
        lsr
        lsr
        lsr
        lsr
        tay
        pla
        and #$1f
        ora p2s,y
        ldy t4
        rts
p2s     .byte $80, $20, $00, $a0, $c0, $60, $40, $e0

; key from the keyboard buffer; A = ui_state while waiting
get_key sta ui_state
-       jsr GETIN
        beq -
        ldx #0
        stx ui_state
        rts

; error message (inline string after the jsr) -> errp
set_err pla
        sta errp
        pla
        sta errp+1
        inc errp
        bne +
        inc errp+1
+       ldy #0
-       lda (errp),y
        beq +
        iny
        bne -
+       tya
        clc
        adc errp
        tax
        lda errp+1
        adc #0
        pha
        txa
        pha
        lda #0
        sec
        rts

show_err
        ldx #24
        jsr clr_row
        ldy #0
        lda #C_ERR
        jsr setcol
        ldy #0
        jsr at
        lda errp
        sta sp
        lda errp+1
        sta sp+1
        jmp prt_sp

; wait for a key with the message on row 24
wait_msg
        lda #4
        jmp get_key

rowlo
        .for r := 0, r < 25, r += 1
        .byte <(SCREEN + 40 * r)
        .next
rowhi
        .for r := 0, r < 25, r += 1
        .byte >(SCREEN + 40 * r)
        .next
vbit    .byte 1, 2, 4

        .include "disk.asm"
        .include "capture.asm"
        .include "build.asm"
        .include "reu.asm"

code_end
        .include "core.asm"     ; copied under I/O at the start, then the variables' space
        .here
payload_end
NPAGES = (payload_end - payload + 255) / 256

; ---------------------------------------------------------------------------
; Variables (not in the file)
; ---------------------------------------------------------------------------
VARS    = (code_end + 255) & $ff00 ; page aligned: the checksum covers CODE..VARS
        .virtual VARS
pagebuf .fill 256               ; first: scratch, a stray tune write here does no harm
device  .byte ?
loaded  .byte ?
ndir    .byte ?
sel     .byte ?
top     .byte ?
t0      .byte ?
t1      .byte ?
t2      .byte ?
t3      .byte ?
t4      .byte ?
num     .word ?
o_row   .byte ?
o_lo    .fill NROWS             ; option values by row (16 bit)
o_hi    .fill NROWS
o_voices .byte ?
o_nlen  .byte ?
o_name  .fill 16
last_ok .byte ?
g_fps   .byte ?
fps     .byte ?
bpm     .word ?
tempo   .byte ?
rate    .word ?

; PSID
hdr     .fill 124
load    .word ?
lend    .word ?
init    .word ?
play    .word ?
songs   .byte ?
ntsc    .byte ?
; disk
linebuf .fill 40
fnbuf   .fill 24
fnlen   .byte ?
name    .fill 16
nlen    .byte ?
eof     .byte ?
t_x     .byte ?
t_y     .byte ?
t_a     .byte ?
wr      .byte ?
scnt    .word ?
e_blk   .byte ?
e_page  .byte ?
e_idx   .byte ?
e_rem   .word ?
e_n     .byte ?
e_val   .byte ?
e_sm1   .byte ?                 ; stride - 1
e_col   .byte ?
e_gen   .byte ?                 ; page e_page must be generated
; capture results (copied from the core)
res     .fill CRESLEN
x_hist  = res + (hist - cres)
x_ninstr = res + (ninstr - cres)
x_ins_w = res + (ins_w - cres)
x_ins_ad = res + (ins_ad - cres)
x_ins_sr = res + (ins_sr - cres)
x_ins_ph = res + (ins_ph - cres)
x_ins_pl = res + (ins_pl - cres)
x_grid  .byte ?
x_latch .word ?
x_gridfr .word ?
s_mode  .byte ?
s_stat  .byte ?
full    .byte ?                 ; slice cut: 1 out of phrases, 2 out of chains
srow    .byte ?                 ; song rows built
sv_nphr .byte ?
sv_nch  .byte ?
maxphr  .byte ?
nmisave .word ?
reu     .byte ?                 ; 1 = REU used
bswap   .byte ?                 ; REU banks
btune   .byte ?
nbanks  .word ?
u_t     .byte ?
ab      .byte ?
a0      .byte ?
ak      .byte ?
ldbad   .byte ?
t_pa    .byte ?
msgbuf  .fill 41
t_s     .word ?
; math
dd      .fill 3                 ; dividend / quotient
dv      .word ?
rem     .fill 3
ma      .word ?
mb      .word ?
prod    .fill 4
; build
nphr    .byte ?
nch     .byte ?
ch0     .fill 128
ch1     .fill 128
ch2     .fill 128
ch3     .fill 128
key4    .fill 4
g_page  .byte ?
ciaf    .byte ?
vpage   .fill 8                 ; phrase store blocks (32 phrases each)
        .align 256
rowbuf  .fill 3*256             ; one song row: voice v at +v*256, step s at s*4
songr   .fill 3*256             ; song rows: voice v at +v*256
XBUF    .fill 3*256             ; no REU: the other zero page / $0200-$03ff
vars_end
        .endv
        .cerror cv_end - abort > 127, "capture state too long for the clear loop"
        .cerror vars_end > $d000, "transcriber variables run into the I/O area"
