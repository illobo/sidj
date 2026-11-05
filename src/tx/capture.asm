; Capture session, T.A.S.T.E's side (src/tx/core.asm does the frames): IRQs
; off, NMIs held off by an unacknowledged CIA2 NMI, $01 = $34 from the core's
; init to the end. Each chunk the core hands over (ST_CHUNK) is copied from
; its ring into rowbuf; every 64 steps one song row is added: per selected
; voice 4 phrases (deduplicated against the phrase store) and one chain
; (deduplicated), song row srow. When phrases or chains run out the slice
; ends at the last complete row (full = 1 / 2).
;
; mode 0 (guess): skip to the start, then GUESSFR frames of note-onset
;   intervals per voice into hist.
; mode 1 (capture): skip to the start; the step grid starts at the first
;   gate-on edge of a selected voice; per voice and step the first note
;   start is kept (frequency and instrument read one frame after the edge);
;   gate off without a gate on within HRWIN frames -> K (ticks into the step).
; C set = stopped (RUN/STOP).

PROGROW = 21

session sta s_mode
        ldx #PROGROW
        jsr clr_row
        jsr prt
        .null "frame $000000  (run/stop: stop)"
        jsr nmi_block
        sei
        lda #$7f
        sta $dc0d
        lda $dc0d
        lda #$34
        sta $01
        jsr cs_setup
        jsr core_begin          ; init the tune
        jsr calc_rate           ; CIA latch -> rate, start -> skip
_run    jsr core_run
        sta s_stat
        cmp #ST_CHUNK
        bne _end
        jsr take_chunk
        lda full
        beq _run
        bne _out
_end    lda s_mode
        beq _out
        lda s_stat
        cmp #ST_DONE
        bne _out
        lda grid
        beq _out
_flush  lda full                ; the rest of the ring, up to a whole row
        bne _out
        lda cstart
        and #63
        bne +
        lda cstart
        cmp c_len
        lda cstart+1
        sbc c_len+1
        bcs _out
+       jsr take_chunk
        jmp _flush
_out    ldx #0                  ; results out from under I/O
-       lda cres,x
        sta res,x
        inx
        bne -
-       lda cres+256,x
        sta res+256,x
        inx
        cpx #CRESLEN-256
        bne -
        lda grid
        sta x_grid
        lda gridfr
        sta x_gridfr
        lda gridfr+1
        sta x_gridfr+1
        lda #$36
        sta $01
        lda #0                  ; silence the real SID
        ldx #$18
-       sta SID,x
        dex
        bpl -
        lda #$81
        sta $dc0d
        lda $dc0d
        jsr nmi_release
        cli
        lda s_stat
        cmp #ST_ABORT
        beq +
        clc
+       rts

; $01 = $34: the core's parameters and state
cs_setup
        lda init
        sta call_init+1
        lda init+1
        sta call_init+2
        lda play
        sta call_play+1
        lda play+1
        sta call_play+2
        lda reu
        sta c_reu
        ldx o_lo+R_SUB
        dex
        stx c_song
        lda o_voices
        sta c_voices
        lda o_lo+R_LEN
        sta c_len
        lda o_hi+R_LEN
        sta c_len+1
        lda fps
        sta c_fps
        lda o_lo+R_NOTES
        sta c_notes
        lda o_lo+R_INSTR
        sta c_instr
        lda o_lo+R_OFFS
        sta c_offs
        lda s_mode
        sta mode
        lda bswap               ; DMA lists
        sta tab_first+5
        sta tab_first+13
        sta tab_first+21
        sta tab_swap+5
        sta tab_swap+13
        sta tab_swap+21
        lda btune
        sta tf_tune+5
        lda load
        sta tf_tune+1
        sta tf_tune+3
        lda load+1
        sta tf_tune+2
        sta tf_tune+4
        lda lend                ; length = end - load + 1
        sec
        sbc load
        tax
        lda lend+1
        sbc load+1
        inx
        bne +
        clc
        adc #1
+       stx tf_tune+6
        sta tf_tune+7
        lda #0
        sta cstart
        sta cstart+1
        ldx #cv_end-abort-1
-       sta abort,x
        dex
        bpl -
        ldx #64
-       sta cres,x              ; hist, ninstr
        dex
        bpl -
        ldx #0                  ; ring: every step empty
-       txa
        and #2
        beq +
        lda #0
        .byte $2c
+       lda #$ff
        sta CRING,x
        sta CRING+$100,x
        sta CRING+$200,x
        inx
        bne -
        ldx #94                 ; note boundaries for the clock
        ldy #94+95
        lda ntsc
        bne _mid
        ldy #94
_mid    lda midt_lo,y
        sta mid_lo,x
        lda midt_hi,y
        sta mid_hi,x
        dey
        dex
        bpl _mid
        lda #0
        sta nphr
        sta nch
        sta srow
        sta full
        rts

; ring [cstart, cstart + 32) -> rowbuf (same offsets), ring slots emptied;
; a complete row -> add_row
take_chunk
        lda cstart
        and #32
        asl
        asl
        tax                     ; 0 or 128
        ldy #128
-       lda CRING,x
        sta rowbuf,x
        lda CRING+$100,x
        sta rowbuf+$100,x
        lda CRING+$200,x
        sta rowbuf+$200,x
        txa
        and #2
        beq +
        lda #0
        .byte $2c
+       lda #$ff
        sta CRING,x
        sta CRING+$100,x
        sta CRING+$200,x
        inx
        dey
        bne -
        lda cstart
        clc
        adc #CHUNK
        sta cstart
        bcc +
        inc cstart+1
+       and #63
        bne +
        jmp add_row
+       rts

; rowbuf -> song row srow of every selected voice
add_row lda nphr
        sta sv_nphr
        lda nch
        sta sv_nch
        lda #0
        sta t1                  ; voice
_voice  ldy t1
        lda vbit,y
        and o_voices
        bne +
        jmp _vnext
+       lda #0
        sta t2                  ; phrase of the row
_ph     lda srow                ; step srow * 64 + t2 * 16 past the length: none
        lsr
        lsr
        sta t_s+1
        lda srow
        and #3
        lsr
        ror
        ror
        sta t_s
        lda t2
        asl
        asl
        asl
        asl
        ora t_s
        cmp o_lo+R_LEN
        lda t_s+1
        sbc o_hi+R_LEN
        bcc +
        lda #EMPTY
        bne _key
+       lda t2                  ; zp_p = rowbuf + v * 256 + j * 64
        lsr
        ror
        ror
        sta zp_p
        lda t1
        clc
        adc #>rowbuf
        sta zp_p+1
        ldx #0                  ; same as a stored phrase?
_cmp    cpx nphr
        beq _new
        jsr ph_ptr
        ldy #63
-       lda (zp_p),y
        cmp (zp_q),y
        bne _diff
        dey
        bpl -
        bmi _have
_diff   inx
        bne _cmp
_new    cpx maxphr
        bne +
        lda #1
        jmp _full
+       jsr ph_ptr
        ldy #63
-       lda (zp_p),y
        sta (zp_q),y
        dey
        bpl -
        inc nphr
_have   txa
_key    ldx t2
        sta key4,x
        inc t2
        lda t2
        cmp #4
        bne _ph
        ldx #0                  ; chain: same as a stored one?
_ccmp   cpx nch
        beq _cnew
        lda key4
        cmp ch0,x
        bne _cdiff
        lda key4+1
        cmp ch1,x
        bne _cdiff
        lda key4+2
        cmp ch2,x
        bne _cdiff
        lda key4+3
        cmp ch3,x
        beq _chave
_cdiff  inx
        bne _ccmp
_cnew   cpx #NCHAINS
        bne +
        lda #2
        bne _full
+       lda key4
        sta ch0,x
        lda key4+1
        sta ch1,x
        lda key4+2
        sta ch2,x
        lda key4+3
        sta ch3,x
        inc nch
_chave  lda #0
        sta zp_q
        lda t1
        clc
        adc #>songr
        sta zp_q+1
        ldy srow
        txa
        sta (zp_q),y
_vnext  inc t1
        lda t1
        cmp #3
        beq +
        jmp _voice
+       inc srow
        rts
_full   sta full                ; this row does not fit: the slice ends before it
        lda sv_nphr
        sta nphr
        lda sv_nch
        sta nch
        rts

; X = phrase -> zp_q = its place in the store: block vpage[x / 32],
; (x & 31) * 64. X kept.
ph_ptr  txa
        lsr
        lsr
        lsr
        lsr
        lsr
        tay
        txa
        and #3
        lsr
        ror
        ror
        sta zp_q
        txa
        and #31
        lsr
        lsr
        clc
        adc vpage,y
        sta zp_q+1
        rts

; RESTORE off: a CIA2 timer NMI that is never acknowledged keeps the NMI
; line low, so no further NMI edge can come (I/O and KERNAL in)
nmi_block
        lda $0318
        sta nmisave
        lda $0319
        sta nmisave+1
        lda #<nmi_rti
        sta $0318
        lda #>nmi_rti
        sta $0319
        lda #$7f
        sta $dd0d
        lda $dd0d
        lda #0
        sta $dd0e
        sta $dd05
        lda #4
        sta $dd04
        lda #$81
        sta $dd0d
        lda #$19                ; force load, one shot, start
        sta $dd0e
        ldx #20
-       dex
        bne -
        rts
nmi_rti rti
nmi_release
        lda #$7f
        sta $dd0d
        lda $dd0d
        lda nmisave
        sta $0318
        lda nmisave+1
        sta $0319
        rts

; ---------------------------------------------------------------------------
; Guess
; ---------------------------------------------------------------------------
; frames per step = the smallest interval (2..63) seen at least a quarter as
; often as the most common one; 6 without notes; halved down to <= 32
guess_f lda #0
        sta t0
        ldx #2
-       lda x_hist,x
        cmp t0
        bcc +
        sta t0
+       inx
        cpx #64
        bne -
        lda t0
        bne +
        lda #6
        sta g_fps
        rts
+       lsr
        lsr
        cmp #2
        bcs +
        lda #2
+       cmp t0
        bcc +
        lda t0
+       sta t1
        ldx #2
-       lda x_hist,x
        cmp t1
        bcs +
        inx
        bne -
+
-       cpx #33
        bcc +
        txa
        lsr
        tax
        jmp -
+       stx g_fps
        rts

; ---------------------------------------------------------------------------
; Rates
; ---------------------------------------------------------------------------

; X = subtune (1-based): Z clear if it uses the CIA speed. X, Y clobbered.
is_cia  dex
        cpx #32
        bcc +
        ldx #31
+       txa
        and #7
        tay
        txa
        lsr
        lsr
        lsr
        eor #3
        tax
        lda hdr+$12,x
        and bitm,y
        rts
bitm    .byte 1, 2, 4, 8, 16, 32, 64, 128

; after init: rate (calls per second) and skip = start seconds * rate
calc_rate
        lda latch               ; (under I/O: kept for calc_tempo)
        sta x_latch
        lda latch+1
        sta x_latch+1
        ldx o_lo+R_SUB
        jsr is_cia
        beq _vbi
        lda #1
        sta ciaf
        ldx ntsc
        lda hz0,x
        sta dd
        lda hz1,x
        sta dd+1
        lda hz2,x
        sta dd+2
        jsr latch_dv
        jsr div24
        lda dd
        sta rate
        lda dd+1
        sta rate+1
        jmp _mul
_vbi    lda #0
        sta ciaf
        sta rate+1
        ldx ntsc
        lda vbirate,x
        sta rate
_mul    lda o_lo+R_START
        sta ma
        lda o_hi+R_START
        sta ma+1
        lda rate
        sta mb
        lda rate+1
        sta mb+1
        jsr mul16
        lda prod
        sta skip
        lda prod+1
        sta skip+1
        lda prod+2
        sta skip+2
        lda prod+3
        beq +
        lda #$ff
        sta skip
        sta skip+1
        sta skip+2
+       rts

; dv = CIA latch + 1 (at most $ffff)
latch_dv
        lda x_latch
        clc
        adc #1
        sta dv
        lda x_latch+1
        adc #0
        sta dv+1
        bcc +
        lda #$ff
        sta dv
        sta dv+1
+       rts

; one SIDJ tick per tune call: BPM = calls per second * 60 / 24, 40-295
calc_tempo
        lda ciaf
        bne _cia
        ldx ntsc
        lda vbibpm,x
        sta bpm
        lda #0
        sta bpm+1
        beq _enc
_cia    ldx ntsc
        lda ck0,x
        sta dd
        lda ck1,x
        sta dd+1
        lda ck2,x
        sta dd+2
        jsr latch_dv
        jsr div24
        lda dd+2
        bne _max
        lda dd+1
        cmp #>296
        bcc +
        bne _max
        lda dd
        cmp #<296
        bcs _max
+       lda dd+1
        bne _ok
        lda dd
        cmp #40
        bcs _ok
        lda #40
        sta dd
_ok     lda dd
        sta bpm
        lda dd+1
        sta bpm+1
        jmp _enc
_max    lda #<295
        sta bpm
        lda #>295
        sta bpm+1
_enc    lda bpm                 ; HD_TEMPO: 40-255, 256-295 as 0-39
        sta tempo
        rts

hz0     .byte <985248, <1022727
hz1     .byte >985248, >1022727
hz2     .byte `985248, `1022727
ck0     .byte <2463120, <2556818
ck1     .byte >2463120, >2556818
ck2     .byte `2463120, `2556818
vbirate .byte 50, 60
vbibpm  .byte 125, 150

; dd (24 bit) / dv (16 bit) -> dd, remainder in rem
div24   lda #0
        sta rem
        sta rem+1
        sta rem+2
        ldx #24
-       asl dd
        rol dd+1
        rol dd+2
        rol rem
        rol rem+1
        rol rem+2
        lda rem
        sec
        sbc dv
        tay
        lda rem+1
        sbc dv+1
        sta t_s
        lda rem+2
        sbc #0
        bcc +
        sta rem+2
        lda t_s
        sta rem+1
        sty rem
        inc dd
+       dex
        bne -
        rts

; ma * mb -> prod (32 bit); ma destroyed
mul16   lda #0
        sta prod+2
        sta prod+3
        ldx #16
-       lsr ma+1
        ror ma
        bcc +
        lda prod+2
        clc
        adc mb
        sta prod+2
        lda prod+3
        adc mb+1
        sta prod+3
+       ror prod+3
        ror prod+2
        ror prod+1
        ror prod
        dex
        bne -
        rts

; note boundaries: geometric middle between notes n and n+1, PAL then NTSC
MIDF    .function n, hz
        .endf int(round(440.0 * 2.0 ** ((n + 0.5 - 57) / 12.0) * 16777216.0 / hz))
MIDC    .function n, hz
        .endf MIDF(n, hz) > 65535 ? 65535 : MIDF(n, hz)
midt_lo .for n := 0, n < 95, n += 1
        .byte <MIDC(n, 985248.0)
        .next
        .for n := 0, n < 95, n += 1
        .byte <MIDC(n, 1022727.0)
        .next
midt_hi .for n := 0, n < 95, n += 1
        .byte >MIDC(n, 985248.0)
        .next
        .for n := 0, n < 95, n += 1
        .byte >MIDC(n, 1022727.0)
        .next
