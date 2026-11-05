; Transcriber disk I/O through the KERNAL ($01 = $36, IRQs on): directory,
; PSID load with range check, project file writer (SIDJ format, RLE like
; src/fileio.asm). Errors: C set, errp = message (screen codes).

; ---------------------------------------------------------------------------
; Channels
; ---------------------------------------------------------------------------

; is the device there? A TALK to a missing device hangs: probe with LISTEN
probe   lda #0
        sta STATUS
        lda device
        jsr LISTEN
        lda #$6f
        jsr SECOND
        jsr UNLSN
        lda STATUS
        bmi +
        clc
        rts
+       jsr set_err
        .null "device 8 not present"
        rts

; open the command channel (15)
cmd_open
        lda #0
        jsr SETNAM
        lda #15
        tay
        ldx device
        jsr SETLFS
        jsr OPEN
        rts

; open fnbuf as file 2, secondary address Y; C set + errp on a drive error
open2   lda fnlen
        ldx #<fnbuf
        sty t_y
        ldy #>fnbuf
        jsr SETNAM
        lda #2
        ldx device
        ldy t_y
        jsr SETLFS
        jsr OPEN
        bcc read_status
        jsr set_err
        .null "i/o error"
        rts

; drive status into linebuf; A = code; C set (errp = the line) if >= 20
read_status
        lda #0
        sta STATUS
        sta eof
        ldx #15
        jsr CHKIN
        ldy #0
-       jsr getc
        bcs +
        cmp #$0d
        beq +
        cpy #39
        bcs -
        sta linebuf,y
        iny
        bne -
+       lda #0
        sta linebuf,y
        sta eof
        jsr CLRCHN
        lda linebuf
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
        bcc +
        pha
        ldx #0                  ; linebuf -> screen codes for the message
-       lda linebuf,x
        beq ++
        jsr pet2scr
        sta linebuf,x
        inx
        bne -
+       rts
+       lda #<linebuf
        sta errp
        lda #>linebuf
        sta errp+1
        pla
        sec
        rts

; next byte of the input channel: C clear, A = byte; C set at end / error
getc    lda eof
        bne _end
        stx t_x
        sty t_y
        jsr io_busy
        jsr CHRIN
        sta t_a
        lda STATUS
        beq _ok
        and #$bf
        beq +
        lda #$ff
        sta eof
        bne _end
+       lda #$40                ; the last byte
        sta eof
_ok     ldx t_x
        ldy t_y
        lda t_a
        clc
        rts
_end    sec
        rts

; activity on the disk: wiggle the title tildes every 256 bytes
io_busy inc io_n
        bne +
        jmp wiggle
+       rts
io_n    .byte 0

close_all
        jsr CLRCHN
        lda #2
        jsr CLOSE
        lda #15
        jmp CLOSE

; fnbuf = "0:" name ",p," A, or "s0:" name for A = 0
mk_fn   sta t_a
        ldy #0
        tax
        bne +
        lda #$53                ; S
        sta fnbuf
        iny
+       lda #$30
        sta fnbuf,y
        iny
        lda #$3a
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
+       lda t_a
        beq +
        lda #$2c
        sta fnbuf,y
        lda #$50                ; P
        sta fnbuf+1,y
        lda #$2c
        sta fnbuf+2,y
        lda t_a
        sta fnbuf+3,y
        iny
        iny
        iny
        iny
+       sty fnlen
        rts

; ---------------------------------------------------------------------------
; Directory: PRG names into DIRBUF
; ---------------------------------------------------------------------------
read_dir
        lda #0
        sta ndir
        jsr probe
        bcs _r
        jsr cmd_open
        lda #$24                ; "$"
        sta fnbuf
        lda #1
        sta fnlen
        ldy #0
        jsr open2
        bcs _fail
        lda #0
        sta eof
        ldx #2
        jsr CHKIN
        jsr getc                ; load address
        jsr getc
        jsr dir_line            ; disk name
        bcs _end
_line   jsr dir_line
        bcs _end
        jsr parse_entry
        bcs _line
        lda ndir
        cmp #NDIRMAX
        bcs _end
        jsr dir_ptr
        ldy #15
-       lda name,y
        cpy nlen
        bcc +
        lda #0
+       sta (zp_q),y
        dey
        bpl -
        inc ndir
        jmp _line
_end    jsr close_all
        clc
_r      rts
_fail   jsr close_all
        sec
        rts

; one listing line into linebuf (0 terminated); C set at the end
dir_line
        jsr getc                ; link
        bcs _r
        sta t_a
        jsr getc
        bcs _r
        ora t_a
        beq _end
        jsr getc                ; blocks
        jsr getc
        ldy #0
-       jsr getc
        bcs _r
        cpy #39
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

; linebuf = ' "NAME"   PRG': name/nlen, C clear if PRG
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
-       lda linebuf,y
        iny
        cmp #$20
        beq -
        cmp #$2a                ; splat
        beq -
        cmp #$50                ; P
        bne _no
        lda linebuf,y
        cmp #$52
        bne _no
        lda linebuf+1,y
        cmp #$47
        bne _no
        clc
        rts
_no     sec
        rts

; ---------------------------------------------------------------------------
; PSID load (entry sel)
; ---------------------------------------------------------------------------
load_psid
        lda sel
        jsr dir_ptr
        ldy #0
-       lda (zp_q),y
        beq +
        sta name,y
        iny
        cpy #16
        bne -
+       sty nlen
        jsr probe
        bcc +
        rts
+       jsr cmd_open
        lda #$52                ; R
        jsr mk_fn
        ldy #2
        jsr open2
        bcc +
        jmp _fail
+       lda #0
        sta eof
        ldx #2
        jsr CHKIN
        ldy #123
        lda #0
-       sta hdr,y
        dey
        bpl -
        ldy #0
-       jsr getc
        bcs _short
        sta hdr,y
        iny
        cpy #8
        bne -
        lda hdr+1               ; "PSID" / "RSID"
        cmp #$53
        bne _notsid
        lda hdr+2
        cmp #$49
        bne _notsid
        lda hdr+3
        cmp #$44
        bne _notsid
        lda hdr
        cmp #$52
        bne +
        jsr set_err
        .null "rsid not supported"
        jmp _fail
+       cmp #$50
        beq +
_notsid jsr set_err
        .null "not a psid file"
        jmp _fail
_short  jsr set_err
        .null "file too short"
        jmp _fail
+       lda hdr+6               ; data offset (big endian), $76 or $7c
        bne _notsid
        lda hdr+7
        cmp #$76
        bcc _notsid
        sta t0
-       jsr getc                ; rest of the header (beyond 124 bytes: skipped)
        bcs _short
        cpy #124
        bcs +
        sta hdr,y
+       iny
        cpy t0
        bne -
        lda hdr+9               ; load address, big endian; 0 = in the data
        sta load
        lda hdr+8
        sta load+1
        ora load
        bne +
        jsr getc
        bcs _short
        sta load
        jsr getc
        bcs _short
        sta load+1
+       lda hdr+$0b
        sta init
        lda hdr+$0a
        sta init+1
        ora init
        bne +
        lda load
        sta init
        lda load+1
        sta init+1
+       lda hdr+$0d
        sta play
        lda hdr+$0c
        sta play+1
        ora play
        bne +
        jsr set_err
        .null "play address 0 (irq tune) unsupported"
        jmp _fail
+       lda hdr+$0f             ; songs (1-255)
        ldx hdr+$0e
        beq +
        lda #255
+       cmp #1
        bcs +
        lda #1
+       sta songs
        lda hdr+$77             ; clock bits 2-3: 2 = NTSC only
        and #$0c
        ldx #0
        cmp #$08
        bne +
        inx
+       stx ntsc
        ; data -> memory (no REU) or the REU bank btune, page by page;
        ; pages the tune may not use are counted but not stored
        lda #0
        sta ldbad
        lda load
        sta zp_p
        lda load+1
        sta zp_p+1
        ldy #0
_byte   jsr getc
        bcs _done
        ldx zp_p+1
        jsr page_ok
        bcc +
        ldx #1
        stx ldbad
        bne _nxt
+       ldx reu
        bne +
        sta (zp_p),y            ; under the KERNAL: RAM gets it
        jmp _nxt
+       ldx zp_p
        sta pagebuf,x
        inx
        bne _nxt
        lda zp_p+1
        jsr reu_put
_nxt    inc zp_p
        bne _byte
        inc zp_p+1
        bne _byte
        jsr getc                ; past $ffff: only the end may follow
        bcs _done
        jsr set_err
        .null "tune runs past $ffff"
        jmp _fail
_done   lda zp_p                ; end = pointer - 1
        sec
        sbc #1
        sta lend
        lda zp_p+1
        sbc #0
        sta lend+1
        lda reu
        beq +
        lda zp_p
        beq +
        lda zp_p+1              ; the last part page
        jsr reu_put
+       lda eof
        cmp #$40
        beq +
        jsr set_err
        .null "read error"
        jmp _fail
+       jsr close_all
        lda ldbad
        beq _okr
        jsr m_new
        lda reu
        bne +
        jsr prt
        .null "no reu: tune "
        jsr m_range
        jsr prt
        .null " won't fit"
        jmp m_end
+       jsr prt
        .null "tune "
        jsr m_range
        lda load+1
        cmp #2
        bcc +
        jsr prt
        .null " overlaps $d000-$dfff"
        jmp m_end
+       jsr prt
        .null " loads below $0200"
        jmp m_end
_okr    lda reu
        beq _blk0
        ldx #7                  ; REU: the phrase store at $1000-$4fff, 255 phrases
        lda #$48
-       sta vpage,x
        sec
        sbc #8
        dex
        bpl -
        lda #255
        sta maxphr
        jmp tune_loaded
        ; no REU: the highest three 2 KB blocks of $0800-$9fff that miss the tune
_blk0   lda #96
        sta maxphr
        ldx #0
        lda #$98
_blk    sta t0
        cmp lend+1              ; overlap if block <= lend_hi and load_hi <= block + 7
        beq +
        bcs _free
+       clc
        adc #7
        cmp load+1
        bcc _free
        bcs _taken
_free   lda t0
        sta vpage,x
        inx
        cpx #3
        beq tune_loaded
_taken  lda t0
        sec
        sbc #8
        bcc +
        cmp #8
        bcs _blk
+       jsr m_new
        jsr prt
        .null "tune too big: needs "
        jsr m_range
        jmp m_end
_fail   jsr close_all
        sec
        rts

; X = page: C set if the tune may not load there. A kept.
page_ok sta t_pa
        lda reu
        bne _reu
        cpx #$08
        bcc _no
        cpx #$a0
        bcc _ok
        cpx #$e0
        bcs _ok
_no     lda t_pa
        sec
        rts
_reu    cpx #$02
        bcc _no
        cpx #$d0
        bcc _ok
        cpx #$e0
        bcc _no
_ok     lda t_pa
        clc
        rts

; message under construction in msgbuf (screen codes, via prt / phex)
m_new   lda #<msgbuf
        sta cur
        lda #>msgbuf
        sta cur+1
        rts
m_range lda #$24
        jsr putc
        lda load+1
        jsr phex
        lda load
        jsr phex
        jsr prt
        .null "-$"
        lda lend+1
        jsr phex
        lda lend
        jmp phex
m_end   lda #0
        tay
        sta (cur),y
        lda #<msgbuf
        sta errp
        lda #>msgbuf
        sta errp+1
        sec
        rts

; defaults for a new tune, note boundaries for its clock
tune_loaded
        lda hdr+$11             ; start song
        ldx hdr+$10
        beq +
        lda #1
+       cmp songs
        beq +
        bcc +
        lda #1
+       cmp #1
        bcs +
        lda #1
+       sta o_lo+R_SUB
        lda songs
        sta v_maxlo+R_SUB
        lda #7
        sta o_voices
        lda #0
        sta o_hi+R_SUB
        sta o_lo+R_START
        sta o_hi+R_START
        sta o_lo+R_FPS
        sta o_hi+R_FPS
        sta o_hi+R_LEN
        sta o_hi+R_NOTES
        sta o_hi+R_INSTR
        sta o_hi+R_OFFS
        sta o_row
        sta g_fps
        sta last_ok
        lda #<256
        sta o_lo+R_LEN
        lda #>256
        sta o_hi+R_LEN
        lda #1
        sta o_lo+R_NOTES
        sta o_lo+R_INSTR
        sta o_lo+R_OFFS
        sta full
        sta srow
        ldx #>MAXLEN
        ldy #<MAXLEN
        lda reu
        beq +
        ldx #>MAXLENR
        ldy #<MAXLENR
+       stx v_maxhi+R_LEN
        sty v_maxlo+R_LEN
        ; output name from the tune name: ASCII -> PETSCII upper case,
        ; DOS specials -> '-', 16 chars, trailing spaces dropped
_name   ldx #0
        ldy #0
_nc     lda hdr+$16,x
        beq _trim
        cmp #$61
        bcc +
        cmp #$7b
        bcs _dash
        sbc #$1f                ; C clear: - $20
        bne _put
+       cmp #$41
        bcc +
        cmp #$5b
        bcc _put
        bcs _dash
+       cmp #$20
        bcc _dash
        cmp #$40
        bcs _dash
        stx t0
        ldx #5
-       cmp bad,x
        beq +
        dex
        bpl -
        ldx t0
        jmp _put
+       ldx t0
_dash   lda #$2d
_put    sta o_name,y
        iny
        inx
        cpy #16
        bcs _trim
        cpx #32
        bcc _nc
_trim   cpy #0
        beq +
        lda o_name-1,y
        cmp #$20
        bne +
        dey
        bne _trim
+       sty o_nlen
        clc
        rts
bad     .byte $2a, $3f, $2c, $3a, $3d, $22    ; * ? , : = "

; ---------------------------------------------------------------------------
; Project file writer. A = 1: scratch first. C set + A = 63 if the file
; exists (A = 0), else errp.
; ---------------------------------------------------------------------------
write_project
        sta t0
        ldx #0                  ; name/nlen = output name, "UNTITLED" if empty
-       cpx o_nlen
        beq +
        lda o_name,x
        sta name,x
        inx
        bne -
+       stx nlen
        cpx #0
        bne +
        ldx #7
-       lda s_untitled,x
        sta name,x
        dex
        bpl -
        lda #8
        sta nlen
+       jsr probe
        bcc +
        rts
+       jsr cmd_open
        lda t0
        beq +
        lda #0                  ; "S0:name" on the command channel
        jsr mk_fn
        ldx #15
        jsr CHKOUT
        ldy #0
-       lda fnbuf,y
        jsr CHROUT
        iny
        cpy fnlen
        bne -
        jsr CLRCHN
        jsr read_status         ; 01 files scratched
+       lda #$57                ; W
        jsr mk_fn
        ldy #2
        jsr open2
        bcc +
        pha
        jsr close_all
        pla
        sec
        rts
+       ldx #2
        jsr CHKOUT
        ldx #0
-       lda magic,x
        jsr putb
        inx
        cpx #5
        bne -
        ldx #0
_blk    stx e_blk
        lda #0                  ; pass 1: count
        sta wr
        jsr enc_block
        ldx e_blk
        txa
        clc
        adc #1
        jsr putb                ; tag
        lda benc,x              ; RLE, stride - 1 in the high nibble
        jsr putb
        lda blen_lo,x
        jsr putb
        lda blen_hi,x
        jsr putb
        lda scnt
        jsr putb
        lda scnt+1
        jsr putb
        lda #$80                ; pass 2: write
        sta wr
        jsr enc_block
        ldx e_blk
        inx
        cpx #8
        bne _blk
        lda #0
        jsr putb
        jsr CLRCHN
        lda #2
        jsr CLOSE
        jsr read_status         ; e.g. 72 disk full
        php
        jsr close_all
        plp
        rts

s_untitled .byte $55, $4e, $54, $49, $54, $4c, $45, $44
magic   .byte $53, $49, $44, $4a, 2  ; "SIDJ", version 2 (src/fileio.asm)

; byte to the output channel, A X Y kept
putb    sta t_a
        stx t_x
        sty t_y
        jsr io_busy             ; (changes A and X)
        lda t_a
        jsr CHROUT
        ldx t_x
        ldy t_y
        lda t_a
        rts

; block lengths: header, song, chains, phrases, instruments, tables, grooves, allocation
BLEN    = [$100, NSLOTS*256, NCHAINS*32, NPHRASES*64, NINSTR*16, NTABLES*16*6, NGROOVES*16, $100]
blen_lo .byte <BLEN
blen_hi .byte >BLEN
benc    .byte $01, $01, $11, $31, $f1, $01, $01, $01

; RLE of block e_blk in planar order (src/fileio.asm): column e_col (byte
; e_col of every S-byte record), then the next. Pages are generated as the
; columns pass through them (each S times). scnt = stored bytes, written if wr.
enc_block
        ldx e_blk
        lda blen_lo,x
        sta e_rem
        lda blen_hi,x
        sta e_rem+1
        lda benc,x
        lsr
        lsr
        lsr
        lsr
        sta e_sm1
        lda #0
        sta e_page
        sta e_idx
        sta e_col
        sta e_n
        sta scnt
        sta scnt+1
        lda #1
        sta e_gen
_loop   lda e_rem
        ora e_rem+1
        beq _end
        lda e_rem
        bne +
        dec e_rem+1
+       dec e_rem
        lda e_gen
        beq +
        ldx e_blk
        ldy e_page
        jsr gen_page
        lda #0
        sta e_gen
+       ldx e_idx
        lda pagebuf,x
        pha
        txa                     ; next: + S
        sec
        adc e_sm1
        sta e_idx
        bcc +
        inc e_page
        inc e_gen
+       ldx e_blk               ; past the block end: next column
        lda e_idx
        cmp blen_lo,x
        lda e_page
        sbc blen_hi,x
        bcc +
        inc e_col
        lda e_col
        sta e_idx
        lda #0
        sta e_page
        lda #1
        sta e_gen
+       pla
        ldy e_n
        beq _new
        cmp e_val
        bne _fl
        cpy #255
        beq _fl
        inc e_n
        bne _loop
_fl     pha
        jsr flush
        pla
_new    sta e_val
        lda #1
        sta e_n
        bne _loop
_end    jmp flush

flush   lda e_n
        beq _r
        cmp #4
        bcs _esc
        lda e_val
        cmp #ESC
        beq _esc
-       lda e_val
        jsr emit
        dec e_n
        bne -
        rts
_esc    lda #ESC
        jsr emit
        lda e_n
        jsr emit
        lda e_val
        jsr emit
        lda #0
        sta e_n
_r      rts

emit    inc scnt
        bne +
        inc scnt+1
+       bit wr
        bpl +
        jmp putb
+       rts
