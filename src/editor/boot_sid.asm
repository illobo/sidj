; Start-up (INIT_RUN, runs once before player_init; no NMI, IRQs off):
; SID model (codebase64, SounDemon/Dag Lem: voice 3 sawtooth read right
; after the test bit is released) and a second SID: probe $de00 (the
; C64 Ultimate's UltiSID 2 default here), $d420 and $d500. A candidate at B counts if B's voice 3 sawtooth reads 0 with its
; test bit set and runs once it is released, while SID 1's voice 3 (test bit
; set) stays at 0: on a mono C64 B mirrors SID 1, so the release reaches it.
; Found: pl_sid2 = B (player_init then runs six channels).
sid_probe
        lda #$ff
-       cmp VIC+$12
        bne -
        lda #$ff
        sta SID+$12
        sta SID+$0e
        sta SID+$0f
        lda #$20
        sta SID+$12
        lda SID+$1b
        ldy #1                  ; reads 3 on a 6581, 2 on an 8580
        cmp #3
        beq +
        iny
        cmp #2
        beq +
        ldy #0                  ; anything else (no SID emulation): unknown
+       sty sid_model
        ldx #2
_cand   lda sp_hi,x             ; B: x = 2 $de00, 1 $d420, 0 $d500
        sta zp_ptr+1
        lda sp_lo,x
        sta zp_ptr
        lda #$28                ; both voice 3s: sawtooth, test bit (osc at 0);
        sta SID+$12             ; SID 1's frequency is still $ffff
        ldy #$12
        sta (zp_ptr),y
        lda #$ff
        ldy #$0e
        sta (zp_ptr),y
        iny
        sta (zp_ptr),y
        ldy #$1b
        lda (zp_ptr),y
        bne _no                 ; held: must read 0
        lda #$20                ; release B only
        ldy #$12
        sta (zp_ptr),y
        ldy #$1b
        lda (zp_ptr),y
        beq _no                 ; B runs
        lda SID+$1b
        bne _no                 ; SID 1 still held: B is not a mirror
        lda zp_ptr
        sta pl_sid2
        lda zp_ptr+1
        sta pl_sid2+1
_no     lda #0
        ldy #$12
        sta (zp_ptr),y
        sta SID+$12
        lda pl_sid2+1
        bne +
        dex
        bpl _cand
+       rts
sp_lo   .byte <$d500, <$d420, <$de00
sp_hi   .byte >$d500, >$d420, >$de00
