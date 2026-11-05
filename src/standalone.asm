; Standalone SIDJ images, assembled by make and completed by
; tools/sidj2sid.py, which appends a saved project's song data at DATA:
;   PSID=0 build/sidj-prg.bin: runnable .prg from $0801 (BASIC SYS stub, a
;          minimal display, the player at $1000); DATA = PLAYER_END
;   PSID=1 build/sidj-sid.bin: PSID image from $1000 (player, then init/play
;          at PLAYER_END); DATA = PLAYER_END + $100
; Song data in the file: phrases ($3fc0), chains ($1000), $e000-$f9ff
; ($1a00). Both copy it to its place before playing: the high block first,
; then chains, then phrases (whose destination overlaps the high block's
; source).

        .include "defs.inc"

        .weak
PSID    = 0
        .endweak

        .if PSID
DATA    = PLAYER_END + $100
        .else
DATA    = PLAYER_END
        .fi
X_CHAINS  = X_PHRASES + NPHRASES*64
X_HIGH    = X_CHAINS + NCHAINS*32
X_HIGH_LEN = ALLOC_CHAINS + $100 - SONG
; second SID base (word, 0 = none) that sidj2sid.py patches: right below
; DATA in the PSID image, right below PLAYER_EXT in the .prg
        .if PSID
X_SID2  = DATA - 2
        .else
X_SID2  = PLAYER_EXT - 2
        .fi
        .cerror X_HIGH + X_HIGH_LEN > $a000, "image too large for BASIC LOAD"

        .if !PSID


        * = $0801
        .word (+), 2026
        .null $9e, format("%d", x_start)
+       .word 0
x_start sei
        cld
        ldx #$ff
        txs
        lda #$7f                ; KERNAL timer IRQ off
        sta CIA1+$0d
        sta CIA2+$0d
        lda CIA1+$0d
        lda CIA2+$0d
        lda #BANK_RAMIO
        sta $01
        lda #0
        sta VIC+$1a
        sta VIC+$15
        lda #<x_rti
        sta $fffe
        sta $fffa
        lda #>x_rti
        sta $ffff
        sta $fffb
        ldx #2                  ; high block, chains, phrases (in this order)
_mv     lda x_src_lo,x
        sta $fb
        lda x_src_hi,x
        sta $fc
        lda #0
        sta $fd
        lda x_dst_hi,x
        sta $fe
        lda x_pages,x
        sta $02
        ldy #0
-       lda ($fb),y
        sta ($fd),y
        iny
        bne -
        inc $fc
        inc $fe
        dec $02
        bne -
        dex
        bpl _mv
        lda #$1b                ; text screen at $0400, ROM charset, bank 0
        sta VIC+$11
        lda #$c8
        sta VIC+$16
        lda #$15
        sta VIC+$18
        lda CIA2
        ora #3
        sta CIA2
        lda #0
        sta VIC+$20
        sta VIC+$21
        tax
-       lda #$20
        sta SCREEN,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$2e8,x
        lda #1
        sta COLORRAM,x
        sta COLORRAM+$100,x
        sta COLORRAM+$200,x
        sta COLORRAM+$2e8,x
        inx
        bne -
        ldx #x_title_end-x_title-1
-       lda x_title,x
        sta SCREEN+40*2+4,x
        dex
        bpl -
        ldx #15
-       lda HD_NAME,x
        bne +
        lda #$20                ; $00 padding
+       sta SCREEN+40*4+4,x
        dex
        bpl -
        lda x_sid2              ; second SID (sidj2sid --sid2), 0 = none
        sta pl_sid2
        lda x_sid2+1
        sta pl_sid2+1
        jsr player_init
        lda #0
        jsr player_play_song
_frame  lda VIC+$12             ; once per frame: song row of each channel
        cmp #$fb
        bne _frame
        ldx #2
-       ldy x_col,x
        lda pl_row,x
        lsr
        lsr
        lsr
        lsr
        jsr x_hex
        sta SCREEN+40*6+4,y
        lda pl_row,x
        and #15
        jsr x_hex
        sta SCREEN+40*6+5,y
        dex
        bpl -
-       lda VIC+$12
        cmp #$fb
        beq -
        bne _frame
x_hex   cmp #10
        bcc +
        sbc #9                  ; screen codes 1-6 = A-F
        rts
+       ora #$30
        rts
x_rti   rti                     ; (also the IRQ/NMI vectors until player_init)

x_src_lo .byte <X_PHRASES, <X_CHAINS, <X_HIGH
x_src_hi .byte >X_PHRASES, >X_CHAINS, >X_HIGH
x_dst_hi .byte >PHRASES, >CHAINS, >SONG
x_pages  .byte $40, NCHAINS*32/256, X_HIGH_LEN/256
x_col    .byte 0, 3, 6
        .enc "screen"
x_title .text "sidj player"
x_title_end
        .enc "none"
x_end
        .cerror * > X_SID2, "stub overlaps X_SID2"
        * = X_SID2
x_sid2  .word 0                 ; patched by tools/sidj2sid.py
        .fi

X_PHRASES = DATA

        * = PLAYER
        .include "player.asm"
        .cerror * > PLAYER_END, "player overflows PLAYER_END"
        .fill PLAYER_END - *, 0

        .if PSID
; PSID entry points (header: init = PLAYER_END, play = PLAYER_END + 3, CIA
; speed). The player runs without its CIA2 NMI clock: play is one tick,
; and the CIA1 timer A latch the driver calls play with follows the tempo.
        jmp sid_init
        jmp sid_play
sid_init
        lda $01
        pha
        lda #BANK_RAMIO
        sta $01
        ldx #2                  ; high block, chains, phrases (in this order)
_mv     lda s_src_lo,x
        sta $fb
        lda s_src_hi,x
        sta $fc
        lda #0
        sta $fd
        lda s_dst_hi,x
        sta $fe
        lda s_pages,x
        sta $02
        ldy #0
-       lda ($fb),y
        sta ($fd),y
        iny
        bne -
        inc $fc
        inc $fe
        dec $02
        bne -
        dex
        bpl _mv
        lda s_sid2              ; second SID (PSID v3 header), 0 = none
        sta pl_sid2
        lda s_sid2+1
        sta pl_sid2+1
        jsr player_init
        lda #$7f                ; no NMI clock: the driver calls play
        sta CIA2+$0d
        lda #0
        sta CIA2+$0e
        lda CIA2+$0d
        lda #0                  ; from song row 0
        jsr player_play_song
        jsr sid_rate
        pla
        sta $01
        rts
sid_play
        lda $01
        pha
        lda #BANK_RAMIO
        sta $01
        inc pl.lock             ; as the NMI handler does
        jsr pl.tick
        jsr pl.leave
        jsr sid_rate            ; tempo commands change the latch
        pla
        sta $01
        rts
sid_rate
        lda pl.latch_eff
        sta CIA1+4
        lda pl.latch_eff+1
        sta CIA1+5
        rts
s_src_lo .byte <X_PHRASES, <X_CHAINS, <X_HIGH
s_src_hi .byte >X_PHRASES, >X_CHAINS, >X_HIGH
s_dst_hi .byte >PHRASES, >CHAINS, >SONG
s_pages  .byte $40, NCHAINS*32/256, X_HIGH_LEN/256
        .cerror * > X_SID2, "PSID entry code overflows into X_SID2"
        .fill X_SID2 - *, 0
s_sid2  .word 0                 ; patched by tools/sidj2sid.py
        .fi
