; OVWIN without an REU (tier C), for good: the no-REU half of undo
; (high.asm). Copied at start-up; never replaced (ov_call needs an REU).
        jmp fc_snap             ; OV_SNAP
        jmp fb_cmp              ; OV_STEP (X ignored: one comparison)
        jmp fc_key              ; OV_KEY
        .cerror * != OV_KEY + 3, "undo entry points"

; a gesture starts: snapshot the cursor's page and the allocation page
fc_snap jsr field_ptr
        lda fp+1
        bcs _no
        cmp #UPAGE0
        bcc _no
        cmp #UPAGE_END - 1      ; not the allocation page itself
        bcs _no
        cmp #(>CHAINS) + $10
        bcc +
        cmp #UPAGE_A
        bcs +
_no     lda #0
+       sta fb_sp
        sta fb_pg
        lda #0
        ldx fb_pair
        jmp fb_xfer

; end of a gesture: changed? then the snapshot pair is the record
fb_cmp  lda #0
        sta u_state
        lda fb_sp
        sta fb_pg
        lda #1
        ldx fb_pair
        jsr fb_xfer
        lda fb_diff
        beq _r
        lda fb_sp
        sta fb_rp
        lda fb_pair
        eor #1
        sta fb_pair
        lda #1
        sta fb_rs
_r      rts

; u_t = 0 undo, 1 redo: A = 0 nothing to do, else done
fc_key  lda fb_rs               ; 1 = undo there, 2 = redo
        sec
        sbc #1
        cmp u_t
        bne _none
        eor #1
        clc
        adc #1
        sta fb_rs
        lda fb_rp
        sta fb_pg
        lda fb_pair
        eor #1
        tax
        lda #2
        jsr fb_xfer
        lda #1
        rts
_none   lda #0
        rts

; A = 0 copy live -> pair, 1 compare (fb_diff), 2 swap; X = pair;
; fb_pg = first page (0 = none), then the allocation page
fb_xfer sta fb_op
        txa
        asl
        adc #>FB
        sta ptr2+1
        lda #0
        sta ptr
        sta ptr2
        sta fb_diff
        lda fb_pg
        jsr _one
        inc ptr2+1
        lda #>ALLOC_CHAINS
_one    beq _r
        sta ptr+1
        php
        sei
        lda #BANK_ALLRAM
        sta $01
        ldy #0
        ldx fb_op
        beq _copy
        dex
        beq _cmp
_swap   lax (ptr),y
        lda (ptr2),y
        sta (ptr),y
        txa
        sta (ptr2),y
        iny
        bne _swap
        beq _end
_cmp    lda (ptr),y
        eor (ptr2),y
        ora fb_diff
        sta fb_diff
        iny
        bne _cmp
        beq _end
_copy   lda (ptr),y
        sta (ptr2),y
        iny
        bne _copy
_end    lda #BANK_RAMIO
        sta $01
        plp
_r      rts
