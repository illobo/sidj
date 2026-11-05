; REU (I/O in): detection and size, page stash for the tune loader.
; Banks 0 and 1 belong to SIDJ (undo, crash recovery): T.A.S.T.E only uses
; the top two banks, bswap = top, btune = top - 1, and only with 4 or more
; banks (256 KB+). The size test writes one byte at $ffff of bank k and puts
; it back, so no other bank's contents change.

reu_detect
        lda #0
        sta reu
        sta nbanks
        sta nbanks+1
        lda #$55                ; the address registers read back
        sta $df02
        cmp $df02
        bne _r
        lda #$aa
        sta $df02
        cmp $df02
        bne _r
        lda #$3c
        sta $df03
        cmp $df03
        bne _r
        lda #0
        sta $df09               ; no REU interrupts
        sta $df0a               ; both addresses count up
        ldx #2                  ; banks = the first k (2, 4 .. 128) that mirrors bank 0, else 256
_k      stx ab
        jsr alias
        ldx ab
        bcs _n
        txa
        asl
        tax
        bne _k
        inc nbanks+1            ; 256
        ldx #0
        beq +
_n      stx nbanks
+       dex
        cpx #3                  ; top bank >= 3: 4 or more banks
        bcc _r
        stx bswap
        dex
        stx btune
        lda #1
        sta reu
_r      rts

; C set if bank ab, $ffff is bank 0, $ffff
alias   ldx #0
        jsr rb_get
        sta a0
        ldx ab
        jsr rb_get
        sta ak
        lda a0
        eor #$ff
        sta u_t
        ldx ab
        lda #$90
        jsr rb_cmd
        ldx #0
        jsr rb_get
        pha
        lda ak                  ; put bank k back (when it mirrors bank 0, ak = a0)
        sta u_t
        ldx ab
        lda #$90
        jsr rb_cmd
        pla
        eor #$ff
        cmp a0
        beq +
        clc
        rts
+       sec
        rts

; A = byte at bank X, $ffff
rb_get  lda #$91
        jsr rb_cmd
        lda u_t
        rts
; command A for u_t <-> bank X, $ffff
rb_cmd  ldy #<u_t
        sty $df02
        ldy #>u_t
        sty $df03
        ldy #$ff
        sty $df04
        sty $df05
        stx $df06
        ldy #1
        sty $df07
        ldy #0
        sty $df08
        sta $df01
        rts

; pagebuf -> btune, page A
reu_put sta $df05
        lda #0
        sta $df04
        sta $df07
        lda #<pagebuf
        sta $df02
        lda #>pagebuf
        sta $df03
        lda btune
        sta $df06
        lda #1
        sta $df08
        lda #$90
        sta $df01
        rts
