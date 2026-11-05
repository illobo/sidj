; Loop record, arming, part of overlay 4 (OVWIN, REU
; only; ov_drum_tog.asm, X = 3), called by ov_call from loop.asm (F6 while
; not armed). On the Phrase screen
; with the cursor channel playing the phrase on screen: lr_chan, lr_phr,
; lr_on = 15 (hold_frame holds the phrase), piano mode on. Otherwise
; "play this phrase" (Phrase screen) or nothing. Recording: overlay 6.

lr_arm  lda screen
        cmp #SC_PHRASE
        bne _r
        ldx cur_chan
        lda pl_playing
        and bitmask,x
        beq _np
        lda pl_phrase,x
        cmp cur_phrase
        bne _np
        sta lr_phr
        stx lr_chan
        lda pl_phrase_step,x
        sta lr_last
        lda #EMPTY
        sta lr_pend
        sta lr_note
        lda #1
        sta pn_on
        lda #15
        sta lr_on
        lda #<s_larm
        ldy #>s_larm
        bne _m
_np     lda #<s_lnp
        ldy #>s_lnp
_m      jsr msg_set
_r      clc
        rts

        .enc "screen"
s_larm  .null "rec c=:erase f6:stop"
s_lnp   .null "play this phrase"
        .enc "none"
