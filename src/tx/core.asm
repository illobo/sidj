; Capture core: runs from the RAM under I/O ($01 = $34, IRQs off, NMIs held
; off), where no PSID can load. It calls the tune's init / play, reads the
; SID writes back from $d400-$d418 RAM, turns gate edges into steps
; (note, instrument, K) and keeps them in a 64-step ring; every CHUNK steps it
; hands the ring to T.A.S.T.E (status ST_CHUNK).
;
; Around each hand-over the tune's RAM and T.A.S.T.E's are exchanged:
;   REU:    DMA swap of $0002-$00ff, $0200-$cfff, $e000-$ffff with the REU
;           bank c_bswap (the stack page and $d000-$dfff stay). The first
;           entry stashes T.A.S.T.E there and fetches the pristine tune from
;           bank c_btune instead.
;   no REU: the tune shares RAM with T.A.S.T.E (load range checked); only
;           zero page and $0200-$03ff are exchanged with XBUF. A checksum of
;           T.A.S.T.E's code pages, checked after init, every 256 frames and
;           before each hand-over, catches a tune that writes into it.
; The REU registers need I/O, which hides this code: a small trampoline is
; copied into the stack page ($0100-) for each DMA / keyboard poll, and the
; bytes it covers are put back afterwards.
;
; Layout under I/O (the tune's I/O writes land in RAM too: $d000-$d03f VIC,
; $d400-$d4ff SID, $dc00-$dc0f and $dd00-$dd0f CIAs are left alone):
;   $d040-$d0ff  core variables
;   $d100-$d3ff  ring: voice v at $d100 + v*256, step s at (s & 63) * 4
;   $d500-$dbff  core code (copied from the program at each session)
;   $dd10-$dfff  results: hist, instruments, note boundaries, trampoline save

CORE    = $d500
CEND    = $dc00
CRING   = $d100
TRAMP   = $0100
ST_INIT = 1
ST_CHUNK = 2
ST_DONE = 3
ST_ABORT = 4
CHUNK   = 32                    ; steps per hand-over
CMARGIN = 4                     ; steps kept back (pending note / K up to 3 frames)

core_img
        .logical CORE
core_begin
        jsr c_ref
        jsr swap_first
        lda #0
        ldx #$18
-       sta SIDRAM,x
        dex
        bpl -
        lda #$25                ; CIA1 timer A default for CIA speed tunes (~60 Hz)
        sta $dc04
        lda #$40
        sta $dc05
        lda c_song
        ldx #0
        ldy #0
        jsr call_init
        lda #$34
        sta $01
        cld
        lda $dc04
        sta latch
        lda $dc05
        sta latch+1
        lda #ST_INIT
        bne c_ret

core_run
        jsr c_ref
        jsr swap
_frame  jsr call_play
        lda #$34
        sta $01
        cld
        jsr tick
        lda abort
        beq +
        lda #ST_ABORT
        bne c_ret
+       lda skip
        ora skip+1
        ora skip+2
        beq _work
        lda skip
        bne _d0
        lda skip+1
        bne _d1
        dec skip+2
_d1     dec skip+1
_d0     dec skip
        jsr track_gates
        jmp _frame
_work   lda mode
        beq _g
        jsr cap_frame
        beq _frame
        bne c_ret
_g      jsr guess_frame
        bcc _frame
        lda #ST_DONE
c_ret   pha
        jsr c_check
        jsr swap
        pla
        rts

call_init jmp $ffff
call_play jmp $ffff

; ---------------------------------------------------------------------------
; RAM exchange
; ---------------------------------------------------------------------------
swap_first
        lda c_reu
        bne +
        ldx #2                  ; no REU: the tune starts with our zero page / $0200-$03ff
-       lda $00,x
        sta XBUF,x
        inx
        bne -
-       lda $0200,x
        sta XBUF+$100,x
        lda $0300,x
        sta XBUF+$200,x
        inx
        bne -
        rts
+       ldy #0
        jmp tr_dmarun

swap    lda c_reu
        bne +
        ldx #2
-       lda $00,x
        ldy XBUF,x
        sta XBUF,x
        sty $00,x
        inx
        bne -
-       lda $0200,x
        pha
        lda XBUF+$100,x
        sta $0200,x
        pla
        sta XBUF+$100,x
        lda $0300,x
        pha
        lda XBUF+$200,x
        sta $0300,x
        pla
        sta XBUF+$200,x
        inx
        bne -
        rts
+       ldy #tab_swap-tab_first
        ; fall through
; Y = table offset: run its DMA list through the trampoline
tr_dmarun
        ldx #0
-       lda tab_first,y
        sta tr_tab-tr_dma+tr_img,x  ; (the image's table, copied below)
        iny
        inx
        cpx #TABLEN
        bne -
        jsr tr_in
        jsr tr_dma
        jmp tr_out

; trampoline in: save the stack page bytes it covers, copy it there
tr_in   ldx #TRLEN
-       lda @w TRAMP-1,x
        sta tsave-1,x
        lda tr_img-1,x
        sta @w TRAMP-1,x
        dex
        bne -
        rts
; trampoline out, A kept
tr_out  pha
        ldx #TRLEN
-       lda tsave-1,x
        sta @w TRAMP-1,x
        dex
        bne -
        pla
        rts

; DMA lists: command, C64 address, REU address, bank, length; 0 ends.
; Bank bytes and the tune range are patched by T.A.S.T.E (cs_setup).
tab_first
        .byte $90, $02, $00, $02, $00, 0, $fe, $00     ; stash: T.A.S.T.E -> c_bswap
        .byte $90, $00, $02, $00, $02, 0, $00, $ce
        .byte $90, $00, $e0, $00, $e0, 0, $00, $20
tf_tune .byte $91, 0, 0, 0, 0, 0, 0, 0                  ; fetch: tune range from c_btune
        .byte 0
TABLEN  = * - tab_first
tab_swap
        .byte $92, $02, $00, $02, $00, 0, $fe, $00
        .byte $92, $00, $02, $00, $02, 0, $00, $ce
        .byte $92, $00, $e0, $00, $e0, 0, $00, $20
        .byte 0
        .fill TABLEN - (* - tab_swap)

; the trampoline image (runs at TRAMP)
tr_img
        .logical TRAMP
tr_dma  lda #$35                ; I/O in, everything else RAM: what the DMA sees
        sta $01
        ldx #0
_op     lda tr_tab+1,x
        sta $df02
        lda tr_tab+2,x
        sta $df03
        lda tr_tab+3,x
        sta $df04
        lda tr_tab+4,x
        sta $df05
        lda tr_tab+5,x
        sta $df06
        lda tr_tab+6,x
        sta $df07
        lda tr_tab+7,x
        sta $df08
        lda tr_tab,x
        sta $df01               ; go (the CPU waits)
        txa
        clc
        adc #8
        tax
        lda tr_tab,x
        bne _op
        lda #$34
        sta $01
        rts
tr_key  lda #$35                ; A = keyboard column 7 (bit 7: RUN/STOP)
        sta $01
        lda #$7f
        sta $dc00
        lda $dc01
        ldx #$34
        stx $01
        rts
tr_fatal
        lda #$37
        sta $01
        lda #0
        sta $d418
        lda #C_ERR
        sta $d020
        ldx #39
-       sta COLORRAM+24*40,x
        dex
        bpl -
        lda #0
        sta $dc00
-       lda $dc01               ; wait for a key, then reset
        cmp #$ff
        beq -
        jmp ($fffc)
tr_tab  .fill TABLEN
tr_end
        .endlogical
TRLEN   = tr_end - tr_dma
        .cerror TRLEN > 255, "trampoline too long"

; ---------------------------------------------------------------------------
; No REU: checksum of T.A.S.T.E's code pages
; ---------------------------------------------------------------------------
c_ref   jsr c_sum
        stx ck_ref
        sty ck_ref+1
        rts
c_check jsr c_sum
        cpx ck_ref
        bne c_fatal
        cpy ck_ref+1
        bne c_fatal
        rts
; X/Y = sum (0 with an REU)
c_sum   ldx #0
        ldy #0
        lda c_reu
        bne _r
        lda #>CODE
        sta _l+2
        stx ck
_p      ldx #0
_l      lda $ff00,x
        clc
        adc ck
        sta ck
        bcc +
        iny
+       inx
        bne _l
        inc _l+2
        lda _l+2
        cmp #>VARS
        bne _p
        ldx ck
_r      rts

c_fatal ldx #39
-       lda s_fatal,x
        sta SCREEN+24*40,x
        dex
        bpl -
        jsr tr_in
        jmp tr_fatal
s_fatal .text "tune overwrites t.a.s.t.e. key: reset   "

; ---------------------------------------------------------------------------
; Frame bookkeeping
; ---------------------------------------------------------------------------
; frame counter, progress on the screen; every 256 frames RUN/STOP and the
; checksum
tick    inc fr
        bne +
        inc fr+1
        bne +
        inc fr+2
+       lda fr
        and #15
        bne _r
        jsr c_wiggle
        ldx #0
        lda fr+2
        jsr phx
        lda fr+1
        jsr phx
        lda fr
        jsr phx
        lda fr
        bne _r
        jsr c_check
        jsr tr_in
        jsr tr_key
        jsr tr_out
        and #$80
        bne _r
        lda #1
        sta abort
_r      rts

phx     pha
        lsr
        lsr
        lsr
        lsr
        tay
        lda c_hex,y
        sta SCREEN+PROGROW*40+7,x
        inx
        pla
        and #15
        tay
        lda c_hex,y
        sta SCREEN+PROGROW*40+7,x
        inx
        rts
c_hex   .text "0123456789abcdef"

; the title tildes flip (the sprite bytes are plain RAM)
c_wiggle
        lda TILDE+6
        cmp #$72
        bne +
        lda #$4e
        ldx #$39
        bne ++
+       lda #$72
        ldx #$9c
+       sta TILDE+6
        stx TILDE+9
        rts

track_gates
        ldy #2
-       ldx c_voff,y
        lda SIDRAM+4,x
        and #1
        sta prev,y
        dey
        bpl -
        rts
c_voff  .byte 0, 7, 14
c_vbit  .byte 1, 2, 4

; ---------------------------------------------------------------------------
; Guess pass: onset intervals (frames) per selected voice. C set: done.
; ---------------------------------------------------------------------------
guess_frame
        ldy #0
_v      ldx c_voff,y
        lda SIDRAM+4,x
        and #1
        sta gnow
        beq _st
        lda prev,y
        bne _st
        lda c_vbit,y
        and c_voices
        beq _st
        lda ghave,y
        beq _first
        lda gcount
        sec
        sbc glast,y
        sta s_x
        lda gcount+1
        sbc glast+3,y
        bne _first
        lda s_x
        cmp #64
        bcs _first
        tax
        inc hist,x
        bne _first
        dec hist,x
_first  lda #1
        sta ghave,y
        lda gcount
        sta glast,y
        lda gcount+1
        sta glast+3,y
_st     lda gnow
        sta prev,y
        iny
        cpy #3
        bne _v
        inc gcount
        bne +
        inc gcount+1
+       lda gcount+1
        cmp #>GUESSFR
        bne +
        lda gcount
        cmp #<GUESSFR
        bne +
        sec
        rts
+       clc
        rts

; ---------------------------------------------------------------------------
; Capture pass, one frame. A = 0 (Z set): go on, else a status.
; ---------------------------------------------------------------------------
cap_frame
        ldy #0
_v      lda c_vbit,y
        and c_voices
        bne +
        jmp _next
+       ldx c_voff,y
        lda pend,y
        beq +
        jsr resolve
        lda #0
        sta pend,y
+       lda SIDRAM+4,x
        and #1
        sta gnow
        beq _off
        lda prev,y
        bne _store
        lda #0                  ; gate on
        sta offpend,y
        lda grid
        bne +
        lda #1
        sta grid
        lda fr
        sec
        sbc #1
        sta gridfr
        lda fr+1
        sbc #0
        sta gridfr+1
+       jsr in_range
        bcs _store
        lda step
        sta sv
        lda step+1
        sta sv+1
        jsr slot_at
        jsr sl_r0
        cmp #$ff
        bne _store              ; the first note in a step stays
        lda #1
        sta pend,y
        lda step
        sta pstep,y
        lda step+1
        sta pstep+3,y
        lda SIDRAM+4,x
        sta wave0,y
        jmp _store
_off    lda prev,y
        beq _held
        lda c_offs              ; gate off
        beq _store
        lda grid
        beq _store
        jsr in_range
        bcs _store
        lda #HRWIN
        sta offpend,y
        lda step
        sta offstep,y
        lda step+1
        sta offstep+3,y
        lda sub
        sta offsub,y
        jmp _store
_held   lda offpend,y
        beq _store
        sec
        sbc #1
        sta offpend,y
        bne _store
        jsr commit_off
_store  lda gnow
        sta prev,y
_next   iny
        cpy #3
        beq +
        jmp _v
+       lda grid
        beq _wait
        jsr in_range
        bcc _adv
        inc tail
        lda tail
        cmp #HRWIN+2
        bcc _cont
_done   lda #ST_DONE
        rts
_adv    inc sub
        lda sub
        cmp c_fps
        bcc _cont
        lda #0
        sta sub
        inc step
        bne +
        inc step+1
+       lda step                ; CHUNK + CMARGIN steps past cstart: hand over
        sec
        sbc cstart
        tax
        lda step+1
        sbc cstart+1
        bne _cont
        cpx #CHUNK+CMARGIN
        bcc _cont
        lda #ST_CHUNK
        rts
_cont   lda #0
        rts
_wait   inc wcount
        bne +
        inc wcount+1
+       lda wcount+1
        cmp #>WAITMAX
        bcc _cont
        lda wcount
        cmp #<WAITMAX
        bcc _cont
        bcs _done               ; no note (grid = 0)

; C clear if step < length
in_range
        lda step
        cmp c_len
        lda step+1
        sbc c_len+1
        rts

; note at pstep of voice Y (X = its register offset): frequency and
; instrument from this frame (one after the gate edge)
resolve lda pstep,y
        sta sv
        lda pstep+3,y
        sta sv+1
        lda c_notes
        bne +
        lda #48                 ; notes off: C-4
        bne _n
+       lda SIDRAM,x
        sta f_lo
        lda SIDRAM+1,x
        sta f_hi
        jsr freq2note
_n      sta r_note
        lda #0
        sta r_ins
        lda c_instr
        beq _w
        lda wave0,y             ; waveform at the edge, unless test bit / none there
        and #$08
        bne _cur
        lda wave0,y
        and #$f0
        bne _w0
_cur    lda SIDRAM+4,x
        jmp +
_w0     lda wave0,y
+       and #$f6                ; no gate, no test; sync and ring kept
        sta k_w
        and #$f0
        bne +
        lda k_w
        ora #$40
        sta k_w
+       lda SIDRAM+5,x
        sta k_ad
        lda SIDRAM+6,x
        sta k_sr
        lda SIDRAM+3,x
        and #$0f
        sta k_ph
        lda SIDRAM+2,x
        sta k_pl
        jsr find_instr
        sta r_ins
_w      jsr slot_at
        lda r_note
        jsr sl_w0
        lda r_ins
        jsr sl_w1
        lda #0                  ; a K-only step taken over by the note: K gone
        jsr sl_w2
        jmp sl_w3

; K at offstep / offsub of voice Y unless the step has a command
commit_off
        lda offstep,y
        sta sv
        lda offstep+3,y
        sta sv+1
        jsr slot_at
        jsr sl_r2
        bne +
        lda #CMD_K
        jsr sl_w2
        lda offsub,y
        jmp sl_w3
+       rts

; ring slot of voice Y, step sv -> the operands of sl_r0..3 / sl_w0..3
slot_at lda sv
        and #63
        asl
        asl
        sta sl_r0+1
        sta sl_w0+1
        ora #1
        sta sl_w1+1
        eor #3
        sta sl_r2+1
        sta sl_w2+1
        ora #3
        sta sl_w3+1
        tya
        clc
        adc #>CRING
        sta sl_r0+2
        sta sl_r2+2
        sta sl_w0+2
        sta sl_w1+2
        sta sl_w2+2
        sta sl_w3+2
        rts
sl_r0   lda $ffff
        rts
sl_r2   lda $ffff
        rts
sl_w0   sta $ffff
        rts
sl_w1   sta $ffff
        rts
sl_w2   sta $ffff
        rts
sl_w3   sta $ffff
        rts

; f_lo/f_hi -> A = nearest note 0..95 (boundaries between notes); X, Y kept
freq2note
        stx s_x
        ldx #0
-       lda f_hi
        cmp mid_hi,x
        bcc _f
        bne _nx
        lda f_lo
        cmp mid_lo,x
        bcc _f
_nx     inx
        cpx #95
        bne -
_f      txa
        ldx s_x
        rts

; k_* -> A = instrument (equal one, a new one, or the nearest of 64); X, Y kept
find_instr
        stx s_x
        ldx #0
_l      cpx ninstr
        beq _add
        lda k_w
        cmp ins_w,x
        bne _nx
        lda k_ad
        cmp ins_ad,x
        bne _nx
        lda k_sr
        cmp ins_sr,x
        bne _nx
        lda k_ph
        cmp ins_ph,x
        beq _found
_nx     inx
        bne _l
_add    cpx #NINSTR
        beq _near
        lda k_w
        sta ins_w,x
        lda k_ad
        sta ins_ad,x
        lda k_sr
        sta ins_sr,x
        lda k_ph
        sta ins_ph,x
        lda k_pl
        sta ins_pl,x
        inc ninstr
_found  txa
        ldx s_x
        rts
_near   lda #255
        sta best
        ldx #0
_nl     lda #0
        sta score
        lda k_w
        cmp ins_w,x
        beq +
        lda #32
        sta score
+       lda ins_ad,x
        sta nb
        lda k_ad
        jsr nibs
        lda ins_sr,x
        sta nb
        lda k_sr
        jsr nibs
        lda ins_ph,x
        sta nl
        lda k_ph
        jsr adiff
        lda score
        cmp best
        bcs +
        sta best
        stx besti
+       inx
        cpx #NINSTR
        bne _nl
        lda besti
        ldx s_x
        rts

; score += nibble distances of A and nb
nibs    sta na
        lsr
        lsr
        lsr
        lsr
        sta nl
        lda nb
        lsr
        lsr
        lsr
        lsr
        jsr adiff
        lda na
        and #$0f
        sta nl
        lda nb
        and #$0f
; score += |A - nl|
adiff   sec
        sbc nl
        bcs +
        eor #$ff
        adc #1
+       clc
        adc score
        sta score
        rts
core_endc
        .endlogical
CORELEN = core_endc - CORE
        .cerror core_endc > CEND, "capture core too long"

; core variables (RAM under I/O)
        .virtual $d040
c_reu   .byte ?                 ; 1 = REU path
c_song  .byte ?                 ; subtune - 1
c_voices .byte ?
c_len   .word ?
c_fps   .byte ?
c_notes .byte ?
c_instr .byte ?
c_offs  .byte ?
cstart  .word ?                 ; first step not handed over yet
ck      .byte ?
ck_ref  .word ?
mode    .byte ?
; cleared at each session (abort .. cv_end)
abort   .byte ?
grid    .byte ?
gridfr  .word ?
step    .word ?
sub     .byte ?
tail    .byte ?
fr      .fill 3
skip    .fill 3
wcount  .word ?
gcount  .word ?
latch   .word ?
prev    .fill 3
pend    .fill 3
pstep   .fill 6                 ; lo x3, hi x3
wave0   .fill 3
offpend .fill 3
offstep .fill 6
offsub  .fill 3
glast   .fill 6
ghave   .fill 3
cv_end
gnow    .byte ?
sv      .word ?                 ; slot step
r_note  .byte ?
r_ins   .byte ?
k_w     .byte ?
k_ad    .byte ?
k_sr    .byte ?
k_ph    .byte ?
k_pl    .byte ?
f_lo    .byte ?
f_hi    .byte ?
s_x     .byte ?
best    .byte ?
besti   .byte ?
score   .byte ?
na      .byte ?
nb      .byte ?
nl      .byte ?
cv0_end
        .endv
        .cerror cv0_end > CRING, "core variables too long"

        .virtual $dd10
cres                            ; results copied out after a session
hist    .fill 64
ninstr  .byte ?
ins_w   .fill 64
ins_ad  .fill 64
ins_sr  .fill 64
ins_ph  .fill 64
ins_pl  .fill 64
cres_end
mid_lo  .fill 95
mid_hi  .fill 95
tsave   .fill TRLEN
cv1_end
        .endv
        .cerror cv1_end > $e000, "core tables too long"
CRESLEN = cres_end - cres
