; SIDJ file I/O: project and kit save/load, directory, scratch, clean
; project. (The .prg / .sid export is a host tool: tools/sidj2sid.py.) Included by main.asm at FILEIO.
;
; KERNAL session: every disk call runs between k_enter and k_leave. k_enter
; stops playback, masks the editor raster IRQ, stops and masks the player's
; CIA2 timer A NMI, turns sprites off (DMA breaks serial timing), saves zero
; page $02-$ff and $0200-$03ff (to RAM under I/O, $d000-$d2ff), clears them
; for the KERNAL, probes the drive with LISTEN (a TALK to a missing device
; hangs in the KERNAL), sets $0314/$0316
; (IRQ/BRK) and $0318 (NMI, RESTORE) to handlers that just return, and banks
; $36 (KERNAL + I/O, BASIC out). Data under the KERNAL is read one byte at a
; time with $01 = $35 (nothing can interrupt into the KERNAL meanwhile: every
; source is masked, RESTORE lands in the player NMI which sees no timer flag);
; writes go to RAM under the ROM anyway. k_leave puts everything back.
;
; Project file (PRG): "SIDJ", version 2, then blocks, then a 0 tag. Other
; versions are refused (not a sidj project).
;   block: tag, encoding, raw length (2), stored length (2), stored bytes.
;   Unknown tags or encodings are skipped by stored length.
;   encoding: high nibble = stride S - 1, low nibble 1 = RLE (the only one).
;   The block is RLE of its raw bytes in planar order: with P = raw length / S
;   records of S bytes, decoded byte i goes to raw[(i mod P) * S + i div P],
;   i.e. byte 0 of every record, then byte 1, ... (S = 1: plain order).
;   Phrases S = 4 ($31), chains S = 2 ($11), instruments S = 16 ($f1), all
;   other blocks S = 1 ($01). A planar block whose raw length differs from
;   ours is skipped.
;   RLE: ESC, count, value = count x value (count 1-255, 0 = nothing); any
;   other byte is a literal.
; Load clears the project first, so blocks missing from a file keep defaults.
;
; Export (.prg at $0801): BASIC SYS stub + mover + display, zero pad to
; $1000, player $1000-$1fff, phrases at $2000, chains at $5fc0, $e000-$f9ff
; at $6fc0 (file ends $89bf). The stub moves the high block first, then
; chains, then phrases (whose destination overlaps the high block's source).

VERSION = 2                     ; project file
KVERSION = 1                    ; kit file
ESC     = $e7                   ; RLE escape, rare in song data
; strings: 64tass -a turns lower case into PETSCII upper case ("sidj" = $53 $49 $44 $4a)
NDIR    = 32                    ; FIO_DIR entries
MSGLEN  = 20

; KERNAL
RESTOR_TAB = $fd30            ; KERNAL default vector table (RESTOR source)
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
STATUS  = $90
BANK_KERNAL = $36

; zero page: inside a session the KERNAL leaves $fb-$fe alone; fio_clean
; saves them for the editor
zp_p    = $fb                   ; 2 data pointer
zp_q    = $fd                   ; 2 second pointer

; saved machine state during a session: RAM under I/O ($01 = $34 to reach
; it), unused by everyone else and only borrowed while the KERNAL runs
zsave   = $d000                 ; $02-$ff (index = address)
p2save  = $d100                 ; $0200-$02ff
p3save  = $d200                 ; $0300-$03ff

; session-only buffers and variables: the cassette buffer ($033c-$03fb),
; which disk I/O never touches; k_enter clears it, k_leave restores it
TAPEBUF = $033c
linebuf = TAPEBUF               ; [40] drive status / directory line
LINEMAX = 39
fnbuf   = linebuf + 40          ; [24] file name / DOS command
sv      = fnbuf + 24            ; session variables (see the end of the file)
kbuf    = FIO_KBUF              ; kit tables (the editor fills it)
BUF_START = FIO_DIRCOUNT
t_a     = sv+0
t_x     = sv+1
t_y     = sv+2
t_tag   = sv+3
eof     = sv+4
enc     = sv+5
blk     = sv+6
wr      = sv+7
n       = sv+8
maxn    = sv+9
ebyte   = sv+10
rlen    = sv+11
scnt    = sv+13
blen    = sv+15
skip    = sv+17
seen    = sv+18
newc    = sv+19
more    = sv+20
src     = sv+21
srcend  = sv+22
fnlen   = sv+23
cv_y    = sv+24
nlen    = sv+25
k_first = sv+26
k_nt    = sv+27
k_t     = sv+28
name    = sv+29
stride  = sv+45                 ; planar block: stride S
endp    = sv+46                 ; 2 block end address
wrapd   = sv+48                 ; 2 raw length - 1 (back from end to next column)
rawl    = sv+50                 ; 2 raw length in the file
rl_pg   = sv+52                 ; fio_rload: next REU page
        .cerror sv+53 > $03fc, "session variables overflow the cassette buffer"


; ---------------------------------------------------------------------------
; Jump table and public variables (fixed offsets, defs.inc)
; ---------------------------------------------------------------------------
        jmp api_save
        jmp api_load
        jmp api_clean
        jmp api_dir
        jmp api_delete
        jmp api_rload           ; +$0f REU payload (was the export: tools/sidj2sid.py)
        jmp api_ksave
        .fill fio_kcnt - *, 0
        .byte 0                 ; fio_kcnt
        .byte 0                 ; fio_kdst
        .byte 8                 ; fio_device
        .byte 0                 ; fio_err
        .enc "screen"
        .text "file i/o ready      "
        .enc "none"
        .cerror * != fio_msg + MSGLEN, "fio_msg misplaced"

; ---------------------------------------------------------------------------
; API entries: Y = operation, X = argument
; ---------------------------------------------------------------------------
api_save
        ldy #0
        beq session
api_load
        ldy #1
        bne session
api_dir
        ldy #2
        bne session
api_delete
        ldy #3
        bne session
api_rload
        ldy #5
        bne session
api_ksave
        ldy #4

session
        stx arg
        lda op_lo,y
        sta sess_go+1
        lda op_hi,y
        sta sess_go+2
        lda #0
        sta touched
        jsr k_enter
        tsx
        stx sp_save
        jsr sess_go
        lda #0
        beq sess_end
; A = FIO_ERR_*: unwind to the session level, close everything, leave
fail    ldx sp_save
        txs
sess_end
        sta fio_err
        jsr CLRCHN
        lda #3
        jsr CLOSE
        lda #2
        jsr CLOSE
        lda #15                 ; last: closing 15 closes all drive channels
        jsr CLOSE
        jsr k_leave
        lda touched             ; song data changed: rebuild the player
        beq +
        jsr reinit_player
+       lda fio_err
        cmp #1                  ; C set = error
        rts
sess_go jmp $ffff

op_lo   .byte <do_save, <do_load, <do_dir, <do_delete, <do_ksave, <do_rload
op_hi   .byte >do_save, >do_load, >do_dir, >do_delete, >do_ksave, >do_rload

; player_init clears the editor's mute and live settings: keep them
reinit_player
        lda pl_mute
        pha
        lda pl_live
        pha
        jsr player_init
        pla
        sta pl_live
        pla
        sta pl_mute
        rts

; ---------------------------------------------------------------------------
; fio_clean: no KERNAL needed. The player is touched only once player_init
; has started its clock (main calls this before player_init).
; ---------------------------------------------------------------------------
api_clean
        lda #0
        sta touched
        lda $fffb               ; player_init done: NMI vector in the player
        and #$f0                ; and its timer A running
        cmp #>PLAYER
        bne _boot
        lda CIA2+$0e
        and #1
        sta touched
        beq _boot
        jsr player_stop
        jmp +
_boot   lda #0                  ; start-up: no directory read yet
        sta FIO_DIRCOUNT
+       ldx #3
-       lda zp_p,x
        sta zp4,x
        dex
        bpl -
        jsr clean_data
        ldx #3
-       lda zp4,x
        sta zp_p,x
        dex
        bpl -
        lda touched
        beq +
        jsr reinit_player
+       ldx #m_new-msgs
        jsr set_msg
        lda #0
        sta fio_err
        clc
        rts

; Empty project: $ff everywhere except command/transpose columns (0),
; grooves/header/allocation (0), default instruments, groove 0 = 6/6, 125 BPM.
clean_data
        lda #EMPTY
        ldx #$80
        ldy #$50                ; $8000-$cfff
        jsr fill
        ldx #$e0
        ldy #$1a                ; $e000-$f9ff
        jsr fill
        lda #0
        ldx #(>TABLES)+2
        ldy #10                 ; table columns 1-5
        jsr fill
        ldx #>GROOVES
        ldy #4                  ; grooves, header, allocation bitmaps
        jsr fill
        ; phrase command + value: 0 (every 4th pair from PH_CMD)
        ldx #>PHRASES
        stx zp_p+1
        ldx #PH_CMD
        stx zp_p
-       sta (zp_p),y            ; Y = 0 here: fill and every loop below end with it
        iny
        sta (zp_p),y
        iny
        iny
        iny
        bne -
        inc zp_p+1
        ldx zp_p+1
        cpx #>CHAINS
        bne -
        ; chain transposes: 0
        ldx #1
        stx zp_p
-       sta (zp_p),y
        iny
        iny
        bne -
        inc zp_p+1
        ldx zp_p+1
        cpx #$d0
        bne -
        ; instruments: plain pulse preset (preset id 0 = custom)
        lda #>INSTR
        sta zp_p+1
        tya
        sta zp_p
-       tya
        and #15
        tax
        lda def_instr,x
        sta (zp_p),y
        iny
        bne -
        inc zp_p+1
        lda zp_p+1
        cmp #(>INSTR)+4
        bne -
        lda #6                  ; groove 0 = 6/6
        sta GROOVES
        sta GROOVES+1
        lda #125
        sta HD_TEMPO
        rts

; A = value, X = first page, Y = page count
fill
        stx zp_p+1
        ldx #0
        stx zp_p
        sty zp_q
        ldy #0
-       sta (zp_p),y
        iny
        bne -
        inc zp_p+1
        dec zp_q
        bne -
        rts

        ; flags wave AD  SR  pwlo pwhi spd cut res fsw hr  hrsr vib vdly tbl tspd
def_instr
        .byte $01,$40,$09,$a0,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,$ff,$00

; ---------------------------------------------------------------------------
; KERNAL session
; ---------------------------------------------------------------------------
k_enter
        php
        pla
        sta s_p
        lda #BANK_RAMIO
        sta $01
        jsr player_stop
        sei
        lda VIC+$1a             ; editor raster IRQ off
        sta s_d01a
        lda #0
        sta VIC+$1a
        lda #$ff
        sta VIC+$19
        lda VIC+$15             ; sprite DMA would break KERNAL serial timing
        sta s_d015
        lda #0
        sta VIC+$15
        lda #$7f                ; player NMI off, its timer stopped
        sta CIA2+$0d
        lda CIA2+$0e
        sta s_dd0e
        and #$fe
        sta CIA2+$0e
        lda CIA2+$0d
        lda CIA2
        sta s_dd00
        lda CIA2+2
        sta s_dd02
        lda #$3f                ; KERNAL serial: ATN/CLK/DATA out, VIC bank bits
        sta CIA2+2
        lda #BANK_ALLRAM        ; (RESTORE: player NMI banks $35 itself)
        sta $01
        ldx #2
-       lda $00,x
        sta zsave,x
        lda #0
        sta $00,x
        inx
        bne -
-       lda $0200,x
        sta p2save,x
        lda $0300,x
        sta p3save,x
        lda #0
        sta $0200,x
        sta $0300,x
        inx
        bne -
        lda #BANK_KERNAL
        sta $01
        ldx #$1f                ; $0314-$0333 from the ROM table. Not RESTOR:
-       lda RESTOR_TAB,x        ; its VECTOR loop also stores the table into
        sta $0314,x             ; the RAM under it, which is editor code (EDHI)
        dex
        bpl -
        lda #<k_irq
        sta $0314
        sta $0316
        lda #>k_irq
        sta $0315
        sta $0317
        lda #<k_nmi
        sta $0318
        lda #>k_nmi
        sta $0319
        lda #3                  ; output: screen, input: keyboard, no messages
        sta $9a
        lda #$ff                ; no STOP key
        sta $91
        lda #>SCREEN
        sta $0288
        rts

; KERNAL IRQ entry pushed A, X, Y; ack whatever got through and return
k_irq   lda CIA1+$0d
        lda #$ff
        sta VIC+$19
        pla
        tay
        pla
        tax
        pla
k_nmi   bit CIA2+$0d          ; a CIA2 NMI here must still be acked, or the line stays low
        rti

k_leave
        sei
        lda #BANK_ALLRAM
        sta $01
        ldx #2
-       lda zsave,x
        sta $00,x
        inx
        bne -
-       lda p2save,x
        sta $0200,x
        lda p3save,x
        sta $0300,x
        inx
        bne -
        lda #BANK_RAMIO
        sta $01
        lda s_dd02
        sta CIA2+2
        lda s_dd00
        sta CIA2
        lda s_d015
        sta VIC+$15
        lda #$ff
        sta VIC+$19
        lda s_d01a
        sta VIC+$1a
        lda CIA2+$0d            ; drop the flag the stopped timer may hold
        lda s_dd0e
        sta CIA2+$0e
        lda #$81                ; timer A -> NMI (player_init's setting)
        sta CIA2+$0d
        lda s_p
        pha
        plp
        rts

; ---------------------------------------------------------------------------
; Byte I/O (session only)
; ---------------------------------------------------------------------------

; A = (zp_p),y even under the KERNAL; X clobbered, Y kept
rd      ldx #BANK_RAMIO
        stx $01
        lda (zp_p),y
        inx                     ; BANK_KERNAL
        stx $01
        rts

; A to the current output channel; A, X, Y kept
putb    sta t_a
        stx t_x
        sty t_y
        jsr CHROUT
        ldx t_x
        ldy t_y
        lda t_a
        rts

; next byte of the current input channel: C clear, A = byte; C set at end of
; file or on error. X, Y kept.
getc    lda eof
        bne _end
        stx t_x
        sty t_y
        jsr CHRIN
        sta t_a
        lda STATUS
        beq _ok
        and #$bf
        beq +
        lda #$ff                ; error: the byte is not valid
        sta eof
        bne _end
+       lda #$40                ; this was the last byte
        sta eof
_ok     ldx t_x
        ldy t_y
        lda t_a
        clc
        rts
_end    sec
        rts

; getc that must succeed
getb    jsr getc
        bcc +
        lda eof
        cmp #$40
        beq bad_format
        bne disk_error
+       rts

; byte of the current block: counts down blen, which must not run out
getbl   lda blen
        bne +
        ora blen+1
        beq bad_format
        dec blen+1
+       dec blen
        jmp getb

bad_format
        ldx #m_format-msgs
        jsr set_msg
        lda #FIO_ERR_FORMAT
        jmp fail

disk_error
        jsr read_status
        jsr status_msg
        lda #FIO_ERR_DISK
        jmp fail

; ---------------------------------------------------------------------------
; Drive channels
; ---------------------------------------------------------------------------

; command channel 15; fails with FIO_ERR_NODEV if nobody answers. A TALK to
; a missing device hangs in the KERNAL (TKSA waits for CLK): probe by LISTEN.
cmd_open
        lda #0
        sta STATUS
        lda fio_device
        jsr LISTEN
        lda #$6f                ; secondary address 15
        jsr SECOND
        jsr UNLSN
        lda STATUS
        bpl +
        jmp no_device
+       lda #0
        jsr SETNAM
        lda #15
        tay
        ldx fio_device
        jsr SETLFS
        jsr OPEN
        bcs open_err
        ; fall through: read the power-on message / last error

; drive status line into linebuf; A = code (0-99), C set if >= 20
read_status
        lda #0
        sta STATUS
        sta eof
        ldx #15
        jsr CHKIN
        bcs no_device
        ldy #0
-       jsr getc
        bcs +
        cmp #$0d
        beq +
        cpy #LINEMAX
        bcs -
        sta linebuf,y
        iny
        bne -
+       lda #0
        sta linebuf,y
        sta eof
        jsr CLRCHN
        lda linebuf             ; two decimal digits
        and #$0f
        asl
        sta t_a
        asl
        asl
        adc t_a
        sta t_a
        lda linebuf+1
        and #$0f
        adc t_a
        cmp #20
        rts

; read_status that fails on a drive error (62 = file not found)
check_status
        jsr read_status
        bcc _r
        pha
        jsr status_msg
        pla
        cmp #62
        bne +
        lda #FIO_ERR_NOFILE
        jmp fail
+       lda #FIO_ERR_DISK
        jmp fail
_r      rts

open_err
        cmp #5                  ; KERNAL "device not present"
        beq no_device
        ldx #m_io-msgs
        jsr set_msg
        lda #FIO_ERR_DISK
        jmp fail
no_device
        ldx #m_nodev-msgs
        jsr set_msg
        lda #FIO_ERR_NODEV
        jmp fail

; open fnbuf as logical file A = secondary address (open_dir: Y = sa)
open_fn
        tay
open_dir
        jsr open_raw
        jmp check_status

open_raw
        pha
        tya
        pha
        lda fnlen
        ldx #<fnbuf
        ldy #>fnbuf
        jsr SETNAM
        pla
        tay
        pla
        ldx fio_device
        jsr SETLFS
        lda #0
        sta STATUS
        sta eof
        jsr OPEN
        bcs open_err
        rts

; send fnbuf to the command channel (executes on UNLISTEN)
send_cmd
        ldx #15
        jsr CHKOUT
        bcs no_device
        ldy #0
-       lda fnbuf,y
        jsr putb
        iny
        cpy fnlen
        bne -
        jsr CLRCHN
        jmp read_status

; fnbuf = "S0:" name (A = 0) or "0:" name ",P," A
mk_fn   sta t_a
        ldy #0
        tax
        bne +
        lda #"s"
        sta fnbuf
        iny
+       lda #"0"
        sta fnbuf,y
        iny
        lda #":"
        sta fnbuf,y
        iny
        ldx #0
-       cpx nlen
        beq +
        lda name,x
        sta fnbuf,y
        iny
        inx
        bne -
+
        lda t_a
        beq +
        ldx #0
-       lda s_pmode,x
        sta fnbuf,y
        iny
        inx
        cpx #3
        bne -
        lda t_a
        sta fnbuf,y
        iny
+       sty fnlen
        rts
s_pmode .text ",p,"

; name/nlen = PETSCII of HD_NAME (screen codes, trailing $00/$20 dropped),
; "UNTITLED" if empty. A = max length.
name_from_header
        sta t_y
        ldx #15
-       ldy #BANK_RAMIO         ; HD_NAME is under the KERNAL
        sty $01
        lda HD_NAME,x
        iny                     ; BANK_KERNAL
        sty $01
        sta name,x
        dex
        bpl -
        ldx #16
-       lda name-1,x
        beq +
        cmp #$20
        bne _found
+       dex
        bne -
        ldx #7                  ; empty: default name
-       lda s_untitled,x
        sta name,x
        dex
        bpl -
        lda #8
        sta nlen
        rts
_found  cpx t_y
        bcc +
        ldx t_y
+       stx nlen
        dex
-       lda name,x              ; screen code -> PETSCII, DOS specials -> '-'
        jsr scr2pet
        ldy #s_bad_end-s_bad-1
-       cmp s_bad,y
        beq _bad
        dey
        bpl -
        bmi _st
_bad    lda #"-"
_st     sta name,x
        dex
        bpl --
        rts
s_untitled .text "untitled"
s_bad   .text "*?,:=", $22
s_bad_end

; X = FIO_DIR entry: name/nlen (PETSCII, trailing spaces dropped)
name_from_entry
        jsr dir_ptr
        ldy #15
-       lda (zp_q),y
        jsr scr2pet
        sta name,y
        dey
        bpl -
        ldx #16
-       lda name-1,x
        cmp #$20
        bne +
        dex
        bne -
+       stx nlen
        rts

; zp_q = FIO_DIR + X*16
dir_ptr txa
        asl
        asl
        asl
        asl
        sta zp_q
        txa
        lsr
        lsr
        lsr
        lsr
        clc
        adc #>FIO_DIR
        sta zp_q+1
        rts

; FIO_DIR entry X -> entry Y
move_entry
        jsr dir_ptr
        lda zp_q
        sta zp_p
        lda zp_q+1
        sta zp_p+1
        tya
        tax
        jsr dir_ptr
        ldy #15
-       lda (zp_p),y
        sta (zp_q),y
        dey
        bpl -
        rts

; name/nlen -> FIO_DIR entry X as screen codes, space padded
store_entry
        jsr dir_ptr
        ldy #15
-       lda #$20
        cpy nlen
        bcs +
        lda name,y
        jsr pet2scr
+       sta (zp_q),y
        dey
        bpl -
        rts

; ---------------------------------------------------------------------------
; Messages (fio_msg, screen codes, padded with spaces)
; ---------------------------------------------------------------------------

; X = message offset (msgs), Y = 0
set_msg ldy #0
set_msg_at
-       lda msgs,x
        beq +
        sta fio_msg,y
        inx
        iny
        bne -
+       lda #$20
-       cpy #MSGLEN
        bcs +
        sta fio_msg,y
        iny
        bne -
+       rts

; drive status line (PETSCII) -> fio_msg
status_msg
        ldx #0
-       lda linebuf,x
        beq +
        jsr pet2scr
        sta fio_msg,x
        inx
        cpx #MSGLEN
        bcc -
        rts
+       txa
        tay
        ldx #m_end-msgs
        bne set_msg_at

; PETSCII <-> screen code, a bijection by 32-byte groups (so FIO_DIR names
; convert back to the exact file name): $20-$5f and the shifted letters
; $c1-$da read as usual. Y kept; C = direction, table index = C * 8 + A / 32
scr2pet sec
        .byte $24               ; bit zp: skips the clc
pet2scr clc
        sty cv_y
        pha
        ror                     ; C -> bit 7
        lsr
        lsr
        lsr
        lsr
        tay
        pla
        and #$1f
        ora p2s,y
        ldy cv_y
        rts
p2s     .byte $80, $20, $00, $a0, $c0, $60, $40, $e0
s2p     .byte $40, $20, $c0, $a0, $00, $60, $80, $e0   ; = p2s + 8
        .cerror s2p != p2s + 8, "s2p must follow p2s"

        .enc "screen"
msgs
m_saved .null "saved"
m_loaded .null "loaded"
m_new   .null "new project"
m_deleted .null "deleted"
m_files .null " sidj files"
m_nodev .null "device not present"
m_format .null "not a sidj project"
m_noentry .null "no such entry"
m_io    .null "i/o error"
m_notbl .null "no free tables"
m_kit   .null "kit"
m_end   .byte 0
        .enc "none"
        .cerror * - msgs > 255, "messages too long"

; ---------------------------------------------------------------------------
; Save
; ---------------------------------------------------------------------------
do_save
        lda #16
        jsr name_from_header
        jsr open_write
        ldy #0
-       lda magic,y
        jsr putb
        iny
        cpy #5
        bne -
        ldx #0
_blk    stx blk
        jsr blk_setup
        lda #0                  ; pass 1: count the stored bytes
        sta wr
        jsr enc_region
        ldx blk
        lda blk_tag,x
        jsr putb
        lda blk_enc,x
        jsr putb
        lda blk_len_lo,x
        jsr putb
        lda blk_len_hi,x
        jsr putb
        lda scnt
        jsr putb
        lda scnt+1
        jsr putb
        jsr blk_setup           ; pass 2: write them
        lda #$80
        sta wr
        jsr enc_region
        ldx blk
        inx
        cpx #NBLK
        bne _blk
        lda #0                  ; end tag
        jsr putb
        jsr close_write
        ldx #m_saved-msgs
        jmp set_msg

; scratch name, open it as PRG for writing on channel 2, make it the output
open_write
        lda #0
        jsr mk_fn
        jsr cmd_open
        jsr send_cmd            ; "01, FILES SCRATCHED" or "62" are both fine
        lda #"w"
        jsr mk_fn
        lda #2
        jsr open_fn
        ldx #2
        jsr CHKOUT
        bcc +
        jmp no_device
+       rts

close_write
        jsr CLRCHN
        lda #2
        jsr CLOSE
        jmp check_status        ; e.g. 72 disk full

; zp_p / rlen = block X, stride / endp / wrapd from encoding A (blk_setup:
; our own)
blk_setup
        lda blk_enc,x
blk_setup_enc
        lsr
        lsr
        lsr
        lsr
        sta stride
        inc stride
        lda blk_addr_lo,x
        sta zp_p
        clc
        adc blk_len_lo,x
        sta endp
        lda blk_addr_hi,x
        sta zp_p+1
        adc blk_len_hi,x
        sta endp+1
        lda blk_len_lo,x
        sta rlen
        sec
        sbc #1
        sta wrapd
        lda blk_len_hi,x
        sta rlen+1
        sbc #0
        sta wrapd+1
        rts

; zp_p+X (X = 0: zp_p, 2: zp_q) += stride; at the block end: back to the
; start of the next column. A clobbered, X Y kept.
adv     lda zp_p,x
        clc
        adc stride
        sta zp_p,x
        bcc +
        inc zp_p+1,x
+       cmp endp
        lda zp_p+1,x
        sbc endp+1
        bcc _r
        lda zp_p,x
        sbc wrapd
        sta zp_p,x
        lda zp_p+1,x
        sbc wrapd+1
        sta zp_p+1,x
_r      rts

; RLE of the rlen bytes from zp_p in planar order (adv); scnt = stored
; bytes; written if wr != 0
enc_region
        lda #0
        sta scnt
        sta scnt+1
        sta n
_loop   lda rlen
        ora rlen+1
        beq flush
        lda rlen
        bne +
        dec rlen+1
+       dec rlen
        ldy #0
        jsr rd
        tay
        ldx #0
        jsr adv
        tya
        ldx n
        beq _new
        cmp ebyte
        bne _fl
        cpx #255
        beq _fl
        inc n
        bne _loop
_fl     pha
        jsr flush
        pla
_new    sta ebyte
        lda #1
        sta n
        bne _loop

; the pending run (n x ebyte): ESC triple, or literals if short
flush   lda n
        beq _r
        cmp #4
        bcs _esc
        lda ebyte
        cmp #ESC
        beq _esc
-       lda ebyte
        jsr emit
        dec n
        bne -
        rts
_esc    lda #ESC
        jsr emit
        lda n
        jsr emit
        lda ebyte
        jsr emit
        lda #0
        sta n
_r      rts

; count A as stored, write it in pass 2; A, X, Y kept
emit    inc scnt
        bne +
        inc scnt+1
+       bit wr
        bpl +
        jmp putb
+       rts

; ---------------------------------------------------------------------------
; Load (X = FIO_DIR entry)
; ---------------------------------------------------------------------------
do_load
        jsr open_entry
        jsr open_read
        ldy #0                  ; magic + version before touching anything
-       jsr getb
        cpy #3
        bne +
        cmp #"k"                ; "SIDK": a kit
        bne +
        jmp kit_load
+       cmp magic,y
        beq +
        jmp bad_format
+       iny
        cpy #5
        bne -
        lda #1
        sta touched
        jsr clean_data
_blk    jsr getb                ; tag
        beq _done
        sta t_tag
        jsr getb
        sta enc
        jsr getb                ; raw length
        sta rawl
        jsr getb
        sta rawl+1
        jsr getb
        sta blen
        jsr getb
        sta blen+1
        lda enc
        and #$0f
        cmp #1                  ; RLE only
        bne _skip
        ldx #NBLK-1
-       lda blk_tag,x
        cmp t_tag
        beq +
        dex
        bpl -
        bmi _skip
+       lda enc                 ; planar: the raw length must be ours
        cmp #$10
        bcc +
        lda rawl
        cmp blk_len_lo,x
        bne _skip
        lda rawl+1
        cmp blk_len_hi,x
        bne _skip
+       lda enc
        jsr blk_setup_enc
        lda zp_p                ; destination: zp_q
        sta zp_q
        lda zp_p+1
        sta zp_q+1
_byte   lda blen
        ora blen+1
        beq _blk
        jsr getbl
        ldx #1
        cmp #ESC
        bne _put
        jsr getbl
        tax
        jsr getbl
        cpx #0
        beq _byte
_put    jsr put
        dex
        bne _put
        beq _byte
_skip   lda blen
        ora blen+1
        beq _blk
        jsr getbl
        jmp _skip
_done   jsr CLRCHN
        ldx #m_loaded-msgs
        jmp set_msg

; A to (zp_q), next planar position (adv), while rlen lasts (longer blocks
; are cut). A, X kept.
put     ldy rlen
        bne +
        ldy rlen+1
        beq _r
        dec rlen+1
+       dec rlen
        ldy #0
        sta (zp_q),y
        pha
        stx t_x
        ldx #2
        jsr adv
        ldx t_x
        pla
_r      rts

; name of entry arg, else fail
open_entry
        ldx arg
        cpx FIO_DIRCOUNT
        bcs +
        jsr name_from_entry
        jmp cmd_open
+       ldx #m_noentry-msgs
        jsr set_msg
        lda #FIO_ERR_NOFILE
        jmp fail

; open name as PRG for reading on channel 2, make it the input
open_read
        lda #"r"
        jsr mk_fn
        lda #2
        jsr open_fn
        ldx #2
        jsr CHKIN
        bcc +
        jmp no_device
+       lda #0
        sta STATUS
        sta eof
        rts

; ---------------------------------------------------------------------------
; REU payload: SIDJ.HLP (PRG; after the load address an RLE
; stream as in project blocks) decoded into REU bank 0 from page REU_HLPPG,
; one 256-byte DMA per page through FIO_DIR; stops at REU_HLPEND. The editor
; checks the header (magic, page count) afterwards. The caller makes sure an
; REU is present. $01 = $36 here, so the REU registers are visible.
; ---------------------------------------------------------------------------
do_rload
        ldx #7
-       lda s_hlp,x
        sta name,x
        dex
        bpl -
        lda #8
        sta nlen
        jsr cmd_open            ; probe, command channel
        jsr open_read
        jsr getb                ; load address
        jsr getb
        lda #REU_HLPPG
        sta rl_pg
        ldy #0                  ; Y = position in the page buffer
_next   jsr getc
        bcs _eof
        ldx #1
        cmp #ESC
        bne _put
        jsr getb
        tax
        jsr getb
        cpx #0
        beq _next
_put    sta FIO_DIR,y
        iny
        bne +
        jsr rl_flush
        lda rl_pg
        cmp #REU_HLPEND
        bcs _done               ; the help area is full: the rest is ignored
        lda FIO_DIR+$ff
+       dex
        bne _put
        beq _next
_eof    lda eof
        cmp #$40
        beq +
        jmp disk_error
+       tya
        beq _done
        jsr rl_flush
_done   jsr CLRCHN
        ldx #m_loaded-msgs
        jmp set_msg

; FIO_DIR -> REU bank 0 page rl_pg (256 bytes), rl_pg + 1. X, Y kept.
rl_flush
        lda #0
        sta REU+2
        sta REU+4
        sta REU+6
        sta REU+7
        sta REU+9
        sta REU+$a
        lda #>FIO_DIR
        sta REU+3
        lda rl_pg
        sta REU+5
        lda #1
        sta REU+8
        lda #$90
        sta REU+1
        inc rl_pg
        rts
        .cerror (FIO_DIR & $ff) != 0, "rl_flush: FIO_DIR page aligned"

s_hlp   .text "sidj.hlp"

; ---------------------------------------------------------------------------
; Delete (X = FIO_DIR entry): scratch it and drop it from FIO_DIR
; ---------------------------------------------------------------------------
do_delete
        jsr open_entry
        lda #0
        jsr mk_fn
        jsr send_cmd            ; "01, FILES SCRATCHED,01,00"
        bcc +
        jsr status_msg
        lda #FIO_ERR_DISK
        jmp fail
+       ldx arg                 ; close the gap
-       inx
        cpx FIO_DIRCOUNT
        bcs +
        stx src
        txa
        tay
        dey
        jsr move_entry
        ldx src
        bne -
+       dec FIO_DIRCOUNT
        ldx #m_deleted-msgs
        jmp set_msg

; ---------------------------------------------------------------------------
; Directory: PRG files whose first bytes are the magic. The listing is read
; in rounds (FIO_DIR's free slots hold the candidates); each candidate is then opened and
; checked, the survivors are packed into FIO_DIR.
; ---------------------------------------------------------------------------
do_dir
        jsr cmd_open
        lda #0
        sta FIO_DIRCOUNT
        sta skip
_round  lda #"$"
        sta fnbuf
        lda #1
        sta fnlen
        lda #0
        sta seen
        sta newc
        sta more
        tay                     ; secondary address 0: BASIC style listing
        lda #2
        jsr open_dir
        ldx #2
        jsr CHKIN
        bcc +
        jmp no_device
+       jsr getc                ; load address
        jsr getc
        jsr dir_line            ; disk header
        bcs _end
_line   jsr dir_line
        bcs _end
        jsr parse_entry
        bcs _line
        lda seen
        inc seen
        cmp skip
        bcc _line               ; taken in an earlier round
        lda FIO_DIRCOUNT
        clc
        adc newc
        cmp #NDIR
        bcc +
        lda #1                  ; FIO_DIR full: another round after checking
        sta more
        dec seen
        bcs _end
+       tax
        jsr store_entry
        inc newc
        bne _line
_end    jsr CLRCHN
        lda #2
        jsr CLOSE
        lda seen
        sta skip
        ; check candidates FIO_DIRCOUNT .. +newc-1, pack the SIDJ ones
        lda FIO_DIRCOUNT
        sta src
        clc
        adc newc
        sta srcend
_chk    lda src
        cmp srcend
        bcs _next
        tax
        jsr name_from_entry
        jsr is_sidj
        bcs +
        ldx src                 ; keep it: pack into the next slot
        ldy FIO_DIRCOUNT
        jsr move_entry
        inc FIO_DIRCOUNT
+       inc src
        bne _chk
_next   lda more
        beq +
        lda FIO_DIRCOUNT
        cmp #NDIR
        bcc _round
+       lda FIO_DIRCOUNT        ; "nn sidj files" (digits: screen = PETSCII)
        ldx #"0"-1
-       inx
        sec
        sbc #10
        bcs -
        adc #"0"+10
        stx fio_msg
        sta fio_msg+1
        ldx #m_files-msgs
        ldy #2
        jmp set_msg_at

; is name a SIDJ project? C clear if so. Uses channel 3.
is_sidj
        lda #"r"
        jsr mk_fn
        lda #3
        tay
        jsr open_raw
        jsr read_status         ; e.g. a name DOS cannot open: not ours
        bcs _no
        ldx #3
        jsr CHKIN
        bcc +
        jmp no_device
+       lda #0
        sta STATUS
        sta eof
        tay
-       jsr getc
        bcs _no
        cpy #3
        bne +
        cmp #"k"                ; a kit
        beq _yes
+       cmp magic,y
        bne _no
        iny
        cpy #4
        bne -
_yes    clc
        .byte $24               ; bit zp: skip sec
_no     sec
        php
        jsr CLRCHN
        lda #3
        jsr CLOSE
        plp
        rts

; one listing line into linebuf (0 terminated). C set at the end.
dir_line
        jsr getc                ; link
        bcs _r
        sta t_tag
        jsr getc
        bcs _r
        ora t_tag
        beq _end
        jsr getc                ; blocks
        jsr getc
        ldy #0
-       jsr getc
        bcs _r
        cpy #LINEMAX
        bcs +
        sta linebuf,y
        iny
+       tax
        bne -
        sta linebuf,y
        clc
        rts
_end    sec
_r      rts

; linebuf = ' "NAME"   PRG': name/nlen, C clear if the type is PRG
parse_entry
        ldy #0
-       lda linebuf,y
        beq _no
        iny
        cmp #$22
        bne -
        ldx #0
-       lda linebuf,y
        beq _no
        iny
        cmp #$22
        beq +
        cpx #16
        bcs -
        sta name,x
        inx
        bne -
+       stx nlen
        txa
        beq _no
-       lda linebuf,y           ; padding, splat marker
        iny
        cmp #" "
        beq -
        cmp #"*"
        beq -
        cmp #"p"
        bne _no
        lda linebuf,y
        cmp #"r"
        bne _no
        lda linebuf+1,y
        cmp #"g"
        bne _no
        clc
        rts
_no     sec
        rts

s_kit   .text ".k00"            ; kit name suffix: digits = first instrument (hex)


; ---------------------------------------------------------------------------
; Instrument kits. Kit file (PRG): "SIDK", version 1, instrument
; count N (1-64), table count T (0-32), T tables (6 columns x 16 bytes,
; column order of TABLES), N instruments (16 bytes each). IN_TABLE holds the
; kit's own table number 0..T-1 ($ff none): a table shared in the kit stays
; shared. Name: HD_NAME (12 chars) + ".Kxx", xx = first instrument (hex).
; ---------------------------------------------------------------------------

; Save (X = first instrument, fio_kcnt = count, FIO_KBUF = their tables)
do_ksave
        lda arg
        sta k_first
        ldx #$ff                ; k_nt = tables listed
-       inx
        lda kbuf,x
        bpl -
        stx k_nt
        lda k_first             ; name + ".kxx" (first instrument, hex)
        lsr
        lsr
        lsr
        lsr
        jsr pdig
        sta s_kit+2
        lda k_first
        and #15
        jsr pdig
        sta s_kit+3
        lda #12
        jsr name_from_header
        ldx nlen                ; append s_kit
        ldy #0
-       lda s_kit,y
        sta name,x
        inx
        iny
        cpy #4
        bne -
        stx nlen
        jsr open_write
        ldy #5
-       lda magic,y
        jsr putb
        iny
        cpy #10
        bne -
        lda fio_kcnt
        jsr putb
        lda k_nt
        jsr putb
        lda #$80
        bne kit_body

; Load (from do_load after "SID" + "K"): instruments from fio_kdst on (cut at
; 63), tables into the free tables the caller listed in FIO_KBUF
kit_load
        jsr getb
        cmp #KVERSION
        bne _bad
        jsr getb
        sta fio_kcnt
        tax
        beq _bad
        jsr getb
        sta k_nt
        cmp #NTABLES+1
        bcs _bad
        tax                     ; enough free tables?
        beq +
        lda kbuf-1,x
        cmp #NTABLES
        bcc +
        ldx #m_notbl-msgs
        jsr set_msg
        lda #FIO_ERR_KIT
        jmp fail
_bad    jmp bad_format
+       lda fio_kdst
        sta k_first
        lda #NINSTR             ; cut at instrument 63
        sec
        sbc k_first
        cmp fio_kcnt
        bcs +
        sta fio_kcnt
+       lda #0

; wr = A; tables kbuf[0..k_nt-1], then instruments k_first.. (fio_kcnt),
; IN_TABLE mapped: save table -> kit table, load kit table -> kbuf
kit_body
        sta wr
        ldx #0
_tb     cpx k_nt
        beq _tdone
        stx k_t
        lda kbuf,x
        ldx #>TABLES
        jsr ptr16
        lda #6
        sta n
-       ldy #0
-       jsr kget
        jsr kput
        iny
        cpy #16
        bne -
        inc zp_p+1              ; next column: +512
        inc zp_p+1
        dec n
        bne --
        ldx k_t
        inx
        bne _tb
_tdone  lda k_first
        ldx #>INSTR
        jsr ptr16
        lda fio_kcnt
        sta n
_in     ldy #0
-       jsr kget
        cpy #IN_TABLE
        bne _put
        bit wr
        bpl _ld
        jsr k_find              ; save: its index in kbuf, else $ff
        txa
        jmp _put
_ld     cmp k_nt                ; load: kbuf[kit table], else $ff
        tax
        lda #$ff
        bcs _put
        lda kbuf,x
_put    jsr kput
        iny
        cpy #16
        bne -
        jsr p_add16
        dec n
        bne _in
        bit wr
        bpl +
        jsr close_write
        ldx #m_saved-msgs
        .byte $2c
+       ldx #m_loaded-msgs
        stx k_t
        ldx #m_kit-msgs         ; "kit saved" / "kit loaded"
        jsr set_msg
        ldy #4
        ldx k_t
        jsr set_msg_at
        bit wr
        bmi +
        lda #FIO_KIT            ; not an error: no project was loaded
        jmp fail
+       rts

; byte Y of (zp_p): from memory (save) or the file (load); X kept on load
kget    bit wr
        bpl +
        jmp rd
+       jmp getb
; ... to the file (save) or memory (load)
kput    bit wr
        bpl +
        jmp putb
+       sta (zp_p),y
        rts

; A = table: X = its index in kbuf[0..k_nt-1], $ff if absent; A kept
k_find  ldx k_nt
-       dex
        bmi +
        cmp kbuf,x
        bne -
+       rts

p_add16 lda zp_p
        clc
        adc #16
        sta zp_p
        bcc +
        inc zp_p+1
+       rts

; zp_p = X*256 + A*16 (A < 64)
ptr16   stx zp_p+1
        pha
        asl
        asl
        asl
        asl
        sta zp_p
        pla
        lsr
        lsr
        lsr
        lsr
        clc
        adc zp_p+1
        sta zp_p+1
        rts

; A = 0-15 -> PETSCII hex digit
pdig    cmp #10
        bcc +
        adc #6
+       adc #$30
        rts

magic   .text "sidj"
        .byte VERSION
        .text "sidk"            ; kit
        .byte KVERSION

; Project blocks: tag, address, length (header first)
NBLK = 8
B_ADDR = [HEADER, SONG, CHAINS, PHRASES, INSTR, TABLES, GROOVES, ALLOC_CHAINS]
B_LEN  = [$100, NSLOTS*256, NCHAINS*32, NPHRASES*64, NINSTR*16, NTABLES*16*6, NGROOVES*16, $100]
blk_tag     .byte 1, 2, 3, 4, 5, 6, 7, 8
blk_enc     .byte $01, $01, $11, $31, $f1, $01, $01, $01  ; RLE, stride - 1 in the high nibble
blk_addr_lo .byte <B_ADDR
blk_addr_hi .byte >B_ADDR
blk_len_lo  .byte <B_LEN
blk_len_hi  .byte >B_LEN

; ---------------------------------------------------------------------------
; Variables
; ---------------------------------------------------------------------------
arg     .byte 0
sp_save .byte 0
touched .byte 0
s_p     .byte 0
s_d01a  .byte 0
s_d015  .byte 0
s_dd00  .byte 0
s_dd02  .byte 0
s_dd0e  .byte 0
zp4     .fill 4
        .cerror * > BUF_START, "fileio code runs into its buffers"
