; Stand-in for player.asm with the same API, so the editor builds and runs
; before the engine exists. It only records play state; nothing advances.

        jmp _rts                ; player_init
        jmp _play_song
        jmp _stop
        jmp _play_channel
        jmp _stop_channel
        jmp _rts                ; player_set_tempo
        jmp _rts                ; player_note_on
        jmp _rts                ; player_note_off
        jmp _rts                ; player_queue
        jmp _rts                ; player_queue_stop
        .fill pl_playing - *, 0
        .fill PLAYER_CODE - *, 0
_play_song
        ldx #NCHAN-1
-       sta pl_row,x
        dex
        bpl -
        lda #(1 << NCHAN) - 1
        sta pl_playing
_rts    rts
_stop   lda #0
        sta pl_playing
        rts
_play_channel
        sta pl_row,x
        lda _bit,x
        ora pl_playing
        sta pl_playing
        rts
_stop_channel
        lda _bit,x
        eor #$ff
        and pl_playing
        sta pl_playing
        rts
_bit    .byte 1, 2, 4, 8, 16, 32
