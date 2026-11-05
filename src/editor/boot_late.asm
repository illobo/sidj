; Last start-up step (main.asm): assembled for CLIPBUF + $200 and staged
; with the RES2 and OVWIN images (CLIPBUF, CLIPBUF + $100). copy_stage puts
; all three pages there first; the clipboard is empty until editor_main, and
; nothing here is needed afterwards.

; last start-up step (main.asm start jumps here): RES2 and OVWIN in place
; (the start-up code at $0200-$03ff is done), the undo code for this tier
; in the window, editor_init, "recovered" if so, the editor
late    ldx #0
-       lda CLIPBUF,x
        sta RES2,x
        lda CLIPBUF+$100,x
        sta OVWIN,x
        inx
        bne -
        lda u_reu
        beq +
        txa                     ; OV_UNDO: REU: the undo overlay replaces tier C's code
        .cerror OV_UNDO != 0
        jsr ov_load
+       jsr editor_init
        lda u_reu               ; REU: help pages from SIDJ.HLP
        beq +
        jsr help_load
+       lda rec_on
        beq +
        lda #<s_rec
        ldy #>s_rec
        jsr msg_set
+       jmp editor_main


; SIDJ.HLP from fio_device into bank 0 (fio_rload), hp_n = its page count
; if the header is right (else 0: F2 says "no help file")
help_load
        ldx #s_lhend - s_lhlp - 1   ; "loading sidj.hlp" on the help row
-       lda s_lhlp,x
        sta SCREEN + 24*40,x
        dex
        bpl -
        jsr fio_rload
        bcs _r
        ldx #6                  ; header -> HELPBUF
-       lda hh_rx,x
        sta rx,x
        dex
        bpl -
        lda #$91
        jsr reu_xfer
        ldx #7
-       lda HELPBUF,x
        cmp hh_magic,x
        bne _r
        dex
        bpl -
        lda HELPBUF+8
        cmp #HLP_MAXPG + 1
        bcs _r
        sta hp_n
_r      rts
hh_rx   .word HELPBUF, REU_HLPPG * 256
        .byte 0
        .word 9
hh_magic .byte $53, $49, $44, $4a, $48, $4c, $50, 1  ; "SIDJHLP" (ASCII), version 1

        .dsection late_init     ; editor_init, input_init (M9: start-up only)

rec_on  .byte 0                 ; 1 = reu_boot found a project to recover
        .enc "screen"
s_rec   .null "recovered"
s_lhlp  .text "loading sidj.hlp"
s_lhend
        .enc "none"
