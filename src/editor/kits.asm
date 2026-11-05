; Instrument kits, EDLOW after low.asm. Runs in place
; of grammar (editor_main), so it sees each gesture after the grammar:
;   Instrument screen, PRESET field:
;     CTRL + SPACE        factory kit: KIT_LEN presets into the instruments
;                         from this one (cut at 3F); with CTRL still held,
;                         every further SPACE puts the next kit there instead
;   File screen:
;     C= + SPACE on SV    save the kit file NAME.Kxx: the Instrument screen's
;                         instrument xx and the used ones after it (up to the
;                         first default one), with their tables
;     SPACE, SPACE on a kit file: load it into the instruments from the
;                         Instrument screen's instrument on (fio_load), its
;                         tables into free tables
; Kit files list on the File screen next to the projects (fio_dir).

KIT_LEN = 8
CF_KIT  = 4                     ; confirm id: the last gesture put a factory kit

kit_grammar
        lda cur_instr           ; where fio_load puts a kit
        sta fio_kdst
        lda screen
        cmp #SC_FILE
        bne +
        lda press
        and #BT_A
        beq +
        jsr kit_free            ; SPACE on the File screen: tables for a kit
+       jsr grammar
        lda fio_err
        cmp #FIO_KIT
        bne +
        lda #0                  ; a kit was loaded
        sta fio_err
        jsr alloc_rebuild
        lda cur_instr
        clc
        adc fio_kcnt
        sta k_i
        ldy #10                 ; "kit loaded xx-yy"
        jsr kit_rng
+       lda press
        and #BT_A
        beq _r
        lda btn
        and #BT_B | BT_SELECT
        ldx screen
        cpx #SC_FILE
        beq _file
        cpx #SC_INSTR
        bne _r
        cmp #BT_SELECT
        bne _r
        lda mark_on
        bne _r
        jsr cur_field
        lda fl_kind,y
        cmp #K_PRESET
        beq kit_factory
_r      rts
_file   cmp #BT_B
        bne _r
        lda rowv+SC_FILE
        ora f_reu               ; kits: drive only
        bne _r
        jsr kit_list
        ldx cur_instr
        lda #<fio_kit_save
        ldy #>fio_kit_save
        jsr fio_call
        bcs _r
        ldy #9                  ; "kit saved xx-yy"
        jsr kit_rng
        jmp file_refresh

; factory kit kit_sel (the next one while CTRL stays held)
kit_factory
        ldx kit_sel
        inx
        lda confirm
        cmp #CF_KIT
        beq +
        ldx #0
+       cpx k_nk                ; NKITS, + NXKITS with an REU
        bcc +
        ldx #0
+       stx kit_sel
        lda #CF_KIT
        sta confirm
        txa
        asl
        asl
        asl
        sta k_j
        adc #NKALL * KIT_LEN    ; (C clear) names after the ids
        tax
        ldy #0                  ; message: name, then the range
-       jsr kit_get             ; (high.asm: kit tables under I/O)
        sta msg_buf,y
        inx
        iny
        cpy #KIT_LEN
        bne -
        lda cur_instr
        sta k_i
-       lda k_i
        cmp #NINSTR
        bcs +
        jsr instr_addr
        lda ptr
        sta fb
        lda ptr+1
        sta fb+1
        ldx k_j
        jsr kit_get
        jsr apply_preset
        inc k_i
        inc k_j
        lda k_j
        and #KIT_LEN-1
        bne -
+       ldy #KIT_LEN
        ; fall through

; msg_buf from Y: " xx-yy" (cur_instr .. k_i-1), padded, shown
kit_rng lda #$20
        sta msg_buf,y
        iny
        lda cur_instr
        jsr k_hex
        lda #$2d                ; '-'
        sta msg_buf,y
        iny
        ldx k_i
        dex
        txa
        jsr k_hex
        lda #$20
-       sta msg_buf,y
        iny
        cpy #20
        bcc -
        jmp msg_show

; A -> two hex digits (screen codes) at msg_buf,y
k_hex   pha
        lsr
        lsr
        lsr
        lsr
        jsr _dig
        pla
        and #15
_dig    cmp #10
        bcc +
        sbc #9                  ; screen codes 1-6 = A-F
        .byte $2c
+       ora #$30
        sta msg_buf,y
        iny
        rts

; Factory kits: KIT_LEN preset ids each (library ids, presetdata.asm; update
; here if they change) and an 8-character name. The tables kit_ids and
; kit_names live in EDHI (high.asm), with the REU kits (xpresets.asm XKITS)
P_KICK   = $06
P_SNARE  = $07
P_CLHAT  = $08
P_OPHAT  = $09
P_TOM    = $0a
P_CLAP   = $0b
P_RIM    = $0c
P_CRASH  = $0d
P_PULSBS = $0e
P_ACID   = $10
P_SUBBAS = $11
P_PWMLD  = $13
P_SAWLD  = $14
P_SLOWPD = $17
P_PWMPAD = $18
P_MAJOR  = $1a
P_MINOR  = $1b
KITS := [("drums", [P_KICK, P_SNARE, P_CLHAT, P_OPHAT, P_TOM, P_CLAP, P_RIM, P_CRASH])]
KITS ..= [("band", [P_KICK, P_SNARE, P_CLHAT, P_PULSBS, P_ACID, P_PWMLD, P_SLOWPD, P_MAJOR])]
KITS ..= [("synth", [P_PULSBS, P_ACID, P_SUBBAS, P_PWMLD, P_SAWLD, P_PWMPAD, P_MAJOR, P_MINOR])]
NKITS = len(KITS)
KITS_BASE = KITS

; The rest lives in the main editor area (editor.asm: .dsection kits_main)
        .section kits_main
; FIO_KBUF = the tables of instruments cur_instr.. (it and the used ones
; after it), fio_kcnt = their count, k_i = the first one after them
kit_list
        jsr kb_clear
        lda cur_instr
        sta k_i
_in     lda k_i
        jsr instr_addr
        ldy #IN_TABLE
        lda (ptr),y
        cmp #NTABLES
        bcs _nx
        ldx k_n                 ; listed already?
-       dex
        bmi +
        cmp FIO_KBUF,x
        bne -
        beq _nx
+       jsr kb_add
_nx     inc k_i
        lda k_i
        cmp #NINSTR
        bcs +
        ldx #2
        jsr item_empty
        bne _in
+       lda k_i
        sec
        sbc cur_instr
        sta fio_kcnt
        rts

; FIO_KBUF = the free (unused and empty) tables
kit_free
        jsr kb_clear
        lda #0
        sta k_i
-       lda k_i
        ldx #3
        jsr alloc_test
        bne +
        lda k_i
        jsr table_empty
        bne +
        lda k_i
        jsr kb_add
+       inc k_i
        lda k_i
        cmp #NTABLES
        bne -
        rts

kb_clear
        ldx #NTABLES            ; (and a terminator after 32 tables)
        lda #$ff
-       sta FIO_KBUF,x
        dex
        bpl -
        inx
        stx k_n
        rts

kb_add  ldx k_n
        sta FIO_KBUF,x
        inc k_n
        rts

kit_sel .byte 0
k_i     = $dd                   ; zp
k_j     .byte 0
k_n     .byte 0
        .send kits_main
