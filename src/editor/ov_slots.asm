; Overlay 1 (OVWIN): REU project slots, the File screen's device REU. Y = 0 save (as HD_NAME), 1 load (X = slot), 2 directory, 3 delete
; (X = slot). Every call first fetches the slot directory (bank 0 pages
; REU_DIRPG..+1, 32 x 16 B) into FIO_DIR and lists all r_nslots slots, free
; ones as "-". A slot is the 106 song data pages ($80-$cf, $e0-$f9) in bank
; REU_SLOTBANK + slot/2 from page (slot & 1) * $80, one DMA per page.
; C clear = ok, C set = error; the message goes to fio_msg (fio_call shows it).
        sty os_op
        stx os_slot
        jsr os_rdir             ; directory -> FIO_DIR
        lda os_op
        beq os_save
        cmp #2
        beq os_list
        jsr os_ptr              ; load / delete: a used slot
        lda (ptr),y
        cmp #$ff
        bne +
        ldx #om_empty - os_m
        bcs os_end              ; carry set: an error
+       lda os_op
        cmp #1
        beq os_load
        lda #$ff                ; delete: free it
-       sta (ptr),y
        lda #$20
        iny
        cpy #16
        bne -
        ldx #om_del - os_m
        bne os_wdir

os_load jsr player_stop
        lda #$91
        jsr os_xfer
        lda pl_mute             ; as fio_load: player_init, mute and live kept
        pha
        lda pl_live
        pha
        jsr player_init
        pla
        sta pl_live
        pla
        sta pl_mute
        ldx #om_load - os_m
        bne os_ok

; save: the slot named HD_NAME, else the first free one
os_save ldx #$ff
        stx os_free
        inx
        stx os_slot
_slot   jsr os_ptr
        lda (ptr),y
        cmp #$ff
        bne +
        lda os_free
        bpl _next
        lda os_slot
        sta os_free
        bpl _next
+       ldy #15
-       lda (ptr),y
        cmp HD_NAME,y
        bne _next
        dey
        bpl -
        bmi _go
_next   inc os_slot
        lda os_slot
        cmp r_nslots
        bcc _slot
        ldx #om_full - os_m
        lda os_free             ; (carry set)
        bmi os_end
        sta os_slot
        jsr os_ptr
_go     ldy #15
-       lda HD_NAME,y
        sta (ptr),y
        dey
        bpl -
        lda #$90
        jsr os_xfer
        ldx #om_save - os_m
os_wdir txa                     ; directory back to the REU
        pha
        jsr os_wdir2
        pla
        tax
        .byte $2c
os_list ldx #om_list - os_m
os_ok   clc
        jmp os_end

; A = command: the song data <-> slot os_slot, page by page
os_xfer sta os_cmd
        lda os_slot
        lsr                     ; C = slot & 1
        tax
        lda #0
        ror                     ; first page $00 / $80, C clear
        sta os_base
        txa
        adc #REU_SLOTBANK
        sta u_bank
        lda #UPAGE0
        sta u_p
-       lax u_p
        sec
        sbc #UPAGE0
        cpx #UPAGE_A
        bcc +
        sbc #UPAGE_A - ((>CHAINS) + $10)
+       ora os_base
        tay
        lda os_cmd
        jsr reu_page
        jsr u_nextp
        bcc -
        lda #0
        sta u_bank
        rts

; variables (overlay calls only; helpers in high.asm use them too)
os_op   .byte 0
os_slot .byte 0
os_free .byte 0
os_cmd  .byte 0
os_base .byte 0
