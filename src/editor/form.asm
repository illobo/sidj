; Form screens (Instrument, Project): a screen is a list of lines, a line is
; a template string plus fields. Each field is one byte (or masked bits of
; one) at an offset from fb (the instrument, or the project header).
; Fields of type FT_VAL/FT_TRANSP/FT_TABLE use the generic grammar in
; edit.asm; the others (FT_FORM) are edited here by kind (K_*).
; Cursor: rowv = line within the screen, colv = field within the line.

fb      = $58                   ; zp: base of the form data (2 bytes)
FORM_W  = 26                    ; form columns; the panel starts here

; field kinds (display + FT_FORM edit)
K_HEX    = 0                    ; byte as 2 hex digits
K_SHEX   = 1                    ; signed byte +xx/-xx
K_NIB    = 2                    ; masked nibble, 1 hex digit
K_ENUM   = 3                    ; masked value 0..max as a 4-char name
K_BIT    = 4                    ; masked bit: arg char when set, '.' when not
K_PW     = 5                    ; 12-bit pulse width (PW lo + PW hi nibble)
K_TABLE  = 6                    ; table number, $ff "--"
K_ITEM   = 7                    ; screen title number (instr/table/groove)
K_PRESET = 8                    ; preset id (low.asm pre_id), applies the preset
K_TEMPO  = 9                    ; HD_TEMPO in BPM
K_CHAR   = 10                   ; one character of the project name
K_ACTION = 11                   ; action: SPACE runs it (load save clean)
OFF_ED    = $fc                 ; field offsets $fc-$ff: editor settings (ed_lo/hi), not fb
OFF_MPORT = $fc
OFF_MSPD  = $fd
OFF_MACC  = $fe
OFF_CLONE = $ff

C_X = 24                        ; screen codes for K_BIT
C_L = 12
C_B = 2
C_H = 8
C_3 = $33

;  (col, offset, mask, kind, arg, max, ftype, help)
FIELDS := [(0, 0, 0, K_ITEM, 0, 0, FT_FORM, H_NUM)]                              ; 0 title
FIELDS ..= [(10, IN_FLAGS, $f0, K_PRESET, 0, NPRESETS-1, FT_FORM, H_PRESET)]      ; 1
FIELDS ..= [(10, IN_WAVE, $10, K_BIT, C_X, 1, FT_FORM, H_WAVE)]                  ; 2 tri
FIELDS ..= [(12, IN_WAVE, $20, K_BIT, C_X, 1, FT_FORM, H_WAVE)]                  ; saw
FIELDS ..= [(14, IN_WAVE, $40, K_BIT, C_X, 1, FT_FORM, H_WAVE)]                  ; pulse
FIELDS ..= [(16, IN_WAVE, $80, K_BIT, C_X, 1, FT_FORM, H_WAVE)]                  ; noise
FIELDS ..= [(19, IN_WAVE, $04, K_BIT, C_X, 1, FT_FORM, H_WAVE)]                  ; ring
FIELDS ..= [(23, IN_WAVE, $02, K_BIT, C_X, 1, FT_FORM, H_WAVE)]                  ; sync
FIELDS ..= [(3, IN_AD, $ff, K_HEX, 0, 0, FT_VAL, H_BYTE)]                        ; 8
FIELDS ..= [(13, IN_SR, $ff, K_HEX, 0, 0, FT_VAL, H_BYTE)]
FIELDS ..= [(3, IN_PWLO, $ff, K_PW, 0, 0, FT_FORM, H_PW)]                        ; 10
FIELDS ..= [(16, IN_PWHI, $f0, K_ENUM, NM_SWEEP, 3, FT_FORM, H_ENUM)]
FIELDS ..= [(21, IN_PWSPD, $ff, K_HEX, 0, 0, FT_VAL, H_BYTE)]
FIELDS ..= [(7, IN_FLAGS, $0c, K_ENUM, NM_FILTER, 2, FT_FORM, H_ENUM)]           ; 13
FIELDS ..= [(12, IN_RESMODE, $01, K_BIT, C_L, 1, FT_FORM, H_FTYPE)]
FIELDS ..= [(14, IN_RESMODE, $02, K_BIT, C_B, 1, FT_FORM, H_FTYPE)]
FIELDS ..= [(16, IN_RESMODE, $04, K_BIT, C_H, 1, FT_FORM, H_FTYPE)]
FIELDS ..= [(18, IN_RESMODE, $08, K_BIT, C_3, 1, FT_FORM, H_FTYPE)]
FIELDS ..= [(24, IN_RESMODE, $f0, K_NIB, 0, 15, FT_FORM, H_NIB)]
FIELDS ..= [(7, IN_CUTOFF, $ff, K_HEX, 0, 0, FT_VAL, H_CUT)]                     ; 19
FIELDS ..= [(17, IN_FSWEEP, $ff, K_SHEX, 0, 0, FT_VAL, H_SBYTE)]
FIELDS ..= [(9, IN_HR, $f0, K_NIB, 0, 15, FT_FORM, H_NIB)]                       ; 21
FIELDS ..= [(11, IN_HR, $0f, K_ENUM, NM_HRMODE, 2, FT_FORM, H_ENUM)]
FIELDS ..= [(21, IN_HRSR, $ff, K_HEX, 0, 0, FT_VAL, H_BYTE)]
FIELDS ..= [(8, IN_VIB, $f0, K_NIB, 0, 15, FT_FORM, H_NIB)]                      ; 24
FIELDS ..= [(10, IN_VIB, $0f, K_NIB, 0, 15, FT_FORM, H_NIB)]
FIELDS ..= [(18, IN_VIBDLY, $ff, K_HEX, 0, 0, FT_VAL, H_BYTE)]
FIELDS ..= [(6, IN_TABLE, $ff, K_TABLE, 0, 0, FT_TABLE, H_TABLE)]                ; 27
FIELDS ..= [(15, IN_TBLSPD, $0f, K_NIB, 0, 15, FT_FORM, H_NIB)]
FIELDS ..= [(22, IN_TBLSPD, $80, K_ENUM, NM_OFFON, 1, FT_FORM, H_ENUM)]
FIELDS ..= [(7, IN_FLAGS, INF_TRANSP, K_ENUM, NM_OFFON, 1, FT_FORM, H_ENUM)]     ; 30
FIELDS ..= [(18, IN_FLAGS, INF_FAST, K_ENUM, NM_TICK, 1, FT_FORM, H_ENUM)]
NF_INSTR = len(FIELDS)
FIELDS ..= [(6, 0, $ff, K_TEMPO, 0, 0, FT_FORM, H_TEMPO)]                        ; 32
FIELDS ..= [(18, HD_TRANSP - HEADER, $ff, K_SHEX, 0, 0, FT_TRANSP, H_GTR)]
NAMEF = len(FIELDS)
        .for _i in range(16)
FIELDS ..= [(6 + _i, HD_NAME - HEADER + _i, $ff, K_CHAR, 0, 0, FT_FORM, H_NAME)] ; 34-49
        .endfor
ACTF = len(FIELDS)
FIELDS ..= [(0, 0, 0, K_ACTION, 0, 0, FT_FORM, H_FILE)]                          ; 50
FIELDS ..= [(5, 0, 0, K_ACTION, 1, 0, FT_FORM, H_FILE)]
FIELDS ..= [(10, 0, 0, K_ACTION, 2, 0, FT_FORM, H_FILE)]
CLONEF = len(FIELDS)
FIELDS ..= [(8, OFF_CLONE, $01, K_ENUM, NM_CLONE, 1, FT_FORM, H_CLONE)]          ; 54
MOUSEF = len(FIELDS)
FIELDS ..= [(6, OFF_MPORT, $03, K_ENUM, NM_PORT, 2, FT_FORM, H_MOUSE)]          ; 55
FIELDS ..= [(16, OFF_MSPD, $03, K_NIB, 0, 3, FT_FORM, H_MOUSE)]
FIELDS ..= [(22, OFF_MACC, $01, K_ENUM, NM_OFFON, 1, FT_FORM, H_MOUSE)]
        .cerror NF_INSTR != 32 || NAMEF != 34 || ACTF != 50, "field numbering"

;  (screen row, first field, field count, template)
LINES := [(0, 0, 1, t_none)]                     ; instrument: title number
LINES ..= [(1, 1, 1, t_preset)]
LINES ..= [(2, 2, 0, t_wave)]
LINES ..= [(3, 2, 6, t_none)]
LINES ..= [(4, 8, 2, t_adsr)]
LINES ..= [(5, 10, 3, t_pw)]
LINES ..= [(6, 13, 6, t_filter)]
LINES ..= [(7, 19, 2, t_cutoff)]
LINES ..= [(8, 21, 3, t_hr)]
LINES ..= [(9, 24, 3, t_vib)]
LINES ..= [(10, 27, 3, t_table)]
LINES ..= [(11, 30, 2, t_transp)]
NL_INSTR = len(LINES)
LINES ..= [(2, 32, 2, t_tempo)]                 ; project
LINES ..= [(3, NAMEF, 16, t_name)]
LINES ..= [(5, ACTF, 0, t_sync)]
LINES ..= [(6, CLONEF, 1, t_keys)]
LINES ..= [(8, ACTF, 3, t_none)]
LINES ..= [(10, CLONEF, 0, t_fileio)]
LINES ..= [(12, MOUSEF, 3, t_mouse)]
NL_PROJ = len(LINES) - NL_INSTR

fl_col  .byte FIELDS[:, 0]
fl_off  .byte FIELDS[:, 1]
fl_mask .byte FIELDS[:, 2]
fl_kind .byte FIELDS[:, 3]
fl_arg  .byte FIELDS[:, 4]
fl_max  .byte FIELDS[:, 5]
fl_ft   .byte FIELDS[:, 6]
fl_help .byte FIELDS[:, 7]
ln_row  .byte LINES[:, 0]
ln_first .byte LINES[:, 1]
ln_n    .byte LINES[:, 2]
ln_tlo  .byte <LINES[:, 3]
ln_thi  .byte >LINES[:, 3]

; per screen: first line and line count (forms only)
form_l0 .byte 0, 0, 0, 0, 0, 0, NL_INSTR, 0, 0
form_nl .byte 0, 0, 0, NL_INSTR, 0, 0, NL_PROJ, 0, 0

        .enc "screen"
t_none   .null ""
t_preset .null "preset"
t_wave   .null "wave      t s p n rng syn"
t_adsr   .null "ad        sr"
t_pw     .null "pw        sweep"
t_filter .null "filter              res"
t_cutoff .null "cutoff    fsweep"
t_hr     .null "hrestart        hrsr"
t_vib    .null "vibrato     delay"
t_table  .null "table    speed   step"
t_transp .null "transp      pitch"
t_tempo  .null "tempo      transp"
t_name   .null "name"
t_sync   .null "sync  off   pal"
t_keys   .null "clone         keys sidj"
t_fileio .null "spc on load/save: file scr"
t_mouse  .null "mouse       spd   acc"
a_load   .null "load"
a_save   .null "save"
a_clean  .null "clean"
        .enc "none"
act_lo  .byte <a_load, <a_save, <a_clean
act_hi  .byte >a_load, >a_save, >a_clean

; ---------------------------------------------------------------------------
; A = instrument -> ptr = INSTR + A*16 (X, Y kept)
instr_addr
        pha
        asl
        asl
        asl
        asl
        sta ptr
        pla
        pha
        lsr
        lsr
        lsr
        lsr
        clc
        adc #>INSTR
        sta ptr+1
        pla
        rts

; An instrument never edited holds $ff everywhere (flags $ff is no valid
; value): give cur_instr the default preset before showing/playing it.
instr_fix
        lda cur_instr
        jsr instr_addr
        ldy #IN_FLAGS
        lda (ptr),y
        cmp #$ff
        bne +
        ldy #15
-       lda pre_data,y
        sta (ptr),y
        dey
        bpl -
+       rts

; fb = data of the form on this screen
form_setup
        lda screen
        cmp #SC_INSTR
        bne +
        jsr instr_fix
        lda ptr
        sta fb
        lda ptr+1
        sta fb+1
        rts
+       lda #<HEADER
        sta fb
        lda #>HEADER
        sta fb+1
        rts

; Field under the cursor (field_ptr for forms): ffield, fkind, fmask, fmax,
; ftype, fp = fb + offset. Carry clear.
form_fptr
        jsr form_setup
        jsr cur_field
        sty ffield
        lda fl_kind,y
        sta fkind
        lda fl_mask,y
        sta fmask
        lda fl_max,y
        sta fmax
        lda fl_ft,y
        sta ftype
        lda fl_off,y
        cmp #OFF_ED
        bcs _ed
        adc fb                  ; carry clear
        sta fp
        lda fb+1
        adc #0
        sta fp+1
        clc
        rts
_ed     tax                     ; an editor setting, not project data
        lda ed_lo-OFF_ED,x
        sta fp
        lda ed_hi-OFF_ED,x
        sta fp+1
        clc
        rts

ED_VARS = [ms_port, ms_speed, ms_accel, clone_mode]
ed_lo   .byte <ED_VARS
ed_hi   .byte >ED_VARS

; Y = field under the cursor, X = its global line
cur_field
        ldx screen
        lda rowv,x
        clc
        adc form_l0,x
        tay
        lda colv,x
        clc
        adc ln_first,y
        pha
        tya
        tax
        pla
        tay
        rts

; ---------------------------------------------------------------------------
; Form cursor: Left/Right within the line, Up/Down to the next line with
; fields, landing on the field closest in column.
form_move
        lda dir_t
        cmp #2
        bcs _lr
        jsr cur_field
        lda fl_col,y
        sta f_tcol
        ldx screen
        lda rowv,x
        sta f_line
-       lda dir_t               ; next line in the direction with fields
        bne _dn
        lda f_line
        beq _r
        dec f_line
        jmp _chk
_dn     lda f_line
        clc
        adc #1
        cmp form_nl,x
        bcs _r
        sta f_line
_chk    lda f_line
        clc
        adc form_l0,x
        tay
        lda ln_n,y
        beq -
        sta f_n                 ; nearest field in column
        lda ln_first,y
        sta f_f
        lda #$ff
        sta f_best
        ldy #0
_near   tya
        clc
        adc f_f
        tax
        lda fl_col,x
        sec
        sbc f_tcol
        bcs +
        eor #$ff
        adc #1
+       cmp f_best
        bcs +
        sta f_best
        sty f_bi
+       iny
        cpy f_n
        bne _near
        ldx screen
        lda f_line
        sta rowv,x
        lda f_bi
        sta colv,x
_r      rts
_lr     ldx screen
        lda rowv,x
        clc
        adc form_l0,x
        tay
        lda dir_t
        cmp #2
        bne _rt
        lda colv,x
        beq _r
        dec colv,x
        rts
_rt     lda colv,x
        clc
        adc #1
        cmp ln_n,y
        bcs _r
        sta colv,x
        rts

; ---------------------------------------------------------------------------
; Masked field value: A = (byte & fmask) >> shift
fget    jsr fshift
        ldy #0
        lda (fp),y
        and fmask
        ldx f_sh
        beq +
-       lsr
        dex
        bne -
+       rts

; A = value -> byte bits under fmask, then touch (row redraw, alloc)
fput    ldx f_sh
        beq +
-       asl
        dex
        bne -
+       and fmask
        sta tmp
        ldy #0
        lda fmask
        eor #$ff
        and (fp),y
        ora tmp
        sta (fp),y
        jmp fld_touch

; f_sh = position of the lowest set bit of fmask
fshift  lda fmask
        ldx #0
        lsr
        bcs +
-       inx
        lsr
        bcc -
+       stx f_sh
        rts

; signed step for the direction in dir_t: up +A, down -A, left -1, right +1
dir_delta
        ldy dir_t
        cpy #2
        bcc +
        lda #1
+       cpy #1
        beq _neg
        cpy #2
        bne +
_neg    eor #$ff
        clc
        adc #1
+       sta f_d
        rts

; A = value + f_d clamped to 0..fmax
add_clamp
        ldx f_d
        bmi _dn
        clc
        adc f_d
        bcs _max
        cmp fmax
        bcc +
_max    lda fmax
+       rts
_dn     clc
        adc f_d
        bcs +
        lda #0
+       rts

; SPACE + CRSR on an FT_FORM field
form_dir
        lda fkind
        cmp #K_ITEM
        bne +
        lda #16
        jsr dir_delta
        jsr item_ptr
        lda cur_instr,y
        jsr add_clamp
        sta cur_instr,y
        rts
+       cmp #K_PW
        bne +
        lda #16                 ; in units of $10: l/r $10, u/d $100
        jsr dir_delta
        lda #$ff
        sta fmax
        jsr pw_get
        jsr add_clamp
        jmp pw_set
+       cmp #K_TEMPO
        bne +
        lda #10
        jsr dir_delta
        jmp tempo_add
+       cmp #K_CHAR
        bne +
        lda #10
        jsr dir_delta
        jmp char_add
+       cmp #K_ACTION
        beq _r
        cmp #K_PRESET
        bne +
        jmp pre_dir
+       cmp #K_BIT
        bne +
        jsr fget
        eor #1
        jmp fput
+       ldx #1                  ; NIB: u/d 4, ENUM: 1
        cmp #K_NIB
        bne +
        ldx #4
+       txa
        jsr dir_delta
        jsr fget
        jsr add_clamp
        jmp fput
_r      rts

; Y = index of the item variable (cur_instr + Y), fmax = its maximum
item_ptr
        lda screen
        sec
        sbc #SC_INSTR
        tay
        lda item_max,y
        sta fmax
        rts

; typed character (kcode) on an FT_FORM field
form_key
        lda fkind
        cmp #K_CHAR
        beq _char
        cmp #K_TEMPO
        bne +
        jmp tempo_key
+       ldx kcode               ; the rest takes hex digits only
        cpx #16
        bcs _r
        cmp #K_ITEM
        bne +
        jsr item_ptr
        lda cur_instr,y
        jsr shift_digit
        sta cur_instr,y
        rts
+       cmp #K_PW
        bne +
        jmp pw_key
+       cmp #K_ACTION
        beq _r
        cmp #K_PRESET
        bne +
        jmp pre_key
+       lda kcode               ; masked: the digit is the value
        cmp fmax
        beq +
        bcs _r
+       pha
        jsr fshift
        pla
        jmp fput
_r      rts
_char   lda kcode               ; 0-9 -> '0'-'9', 10-35 -> A-Z
        cmp #10
        bcs +
        ora #$30
        bne _put
+       sbc #9                  ; carry set
_put    ldy #0
        sta (fp),y
        jsr fld_touch
        ldx screen              ; and move on to the next character
        lda colv,x
        cmp #15
        bcs +
        inc colv,x
+       rts

; A = value: (A << 4 | kcode), or kcode alone if that exceeds fmax
shift_digit
        asl
        asl
        asl
        asl
        ora kcode
        cmp fmax
        bcc +
        beq +
        lda kcode
+       rts

; C= + SPACE on an FT_FORM field: a name character becomes a space
form_cut
        lda fkind
        cmp #K_CHAR
        bne +
        lda #$20
        ldy #0
        sta (fp),y
        jmp fld_touch
+       rts

; name character +f_d through name_chars (wraps)
char_add
        ldy #0
        lda (fp),y
        ldx #NAME_NCHARS-1
-       cmp name_chars,x
        beq +
        dex
        bpl -
        ldx #0
+       txa
        clc
        adc f_d
        bpl +
        clc
        adc #NAME_NCHARS
+       cmp #NAME_NCHARS
        bcc +
        sbc #NAME_NCHARS
+       tax
        lda name_chars,x
        sta (fp),y
        jmp fld_touch

; pulse width: A = PW >> 4 (fp = PW lo, fp+1 = PW hi/sweep)
pw_get  ldy #0
        lda (fp),y
        lsr
        lsr
        lsr
        lsr
        sta tmp
        iny
        lda (fp),y
        asl
        asl
        asl
        asl
        ora tmp
        rts

; A = PW >> 4: store, keeping PW bits 0-3 and the sweep mode
pw_set  pha
        ldy #0
        asl
        asl
        asl
        asl
        sta tmp
        lda (fp),y
        and #$0f
        ora tmp
        sta (fp),y
        pla
        lsr
        lsr
        lsr
        lsr
        sta tmp
        iny
        lda (fp),y
        and #$f0
        ora tmp
        sta (fp),y
        jmp fld_touch

; hex digit shifted into the 12-bit pulse width
pw_key  ldy #1
        lda (fp),y
        asl
        asl
        asl
        asl
        sta tmp                 ; old PW bits 4-7 -> 8-11
        dey
        lda (fp),y
        lsr
        lsr
        lsr
        lsr
        ora tmp
        sta tmp
        lda (fp),y
        asl
        asl
        asl
        asl
        ora kcode
        sta (fp),y
        iny
        lda (fp),y
        and #$f0
        sta tmp2
        lda tmp
        and #$0f
        ora tmp2
        sta (fp),y
        jmp fld_touch

; ---------------------------------------------------------------------------
; Tempo: HD_TEMPO holds BPM 40-255 as is and 256-295 as $00-$27, so the
; byte is always the low byte of the BPM.
; f_bpm = BPM of HD_TEMPO
tempo_get
        lda HD_TEMPO
        sta f_bpm
        ldx #0
        cmp #$28
        bcs +
        inx
+       stx f_bpm+1
        rts

; f_bpm + f_d (signed), clamped to 40-295, stored
tempo_add
        jsr tempo_get
        lda f_d
        ldx #0
        ora #0
        bpl +
        dex
+       clc
        adc f_bpm
        sta f_bpm
        txa
        adc f_bpm+1
        sta f_bpm+1
        ; fall through

; store f_bpm (clamped) into HD_TEMPO and the player
tempo_put
        lda f_bpm+1
        bmi _lo
        bne _hi
        lda f_bpm
        cmp #40
        bcs _st
_lo     lda #40
        bne _st
_hi     cmp #2
        bcs _max
        lda f_bpm
        cmp #<296
        bcc _st
_max    lda #<295
_st     sta HD_TEMPO
        jsr player_set_tempo
        jmp fld_touch

; decimal digits typed into the tempo; a value in range is taken at once
tempo_key
        lda kcode
        cmp #10
        bcs _r
        ldx tdig
        bne +
        sta tentry
        txa                     ; 0
        sta tentry+1
        beq _chk
+       lda tentry+1            ; tentry = (tentry*4 + tentry)*2 + digit
        sta tmp2                ; (tentry < 100 here: no carries out)
        lda tentry
        asl
        rol tmp2
        asl
        rol tmp2                ; carry clear
        adc tentry
        sta tentry
        lda tmp2
        adc tentry+1
        asl tentry
        rol a                   ; carry clear
        sta tentry+1
        lda tentry
        adc kcode
        sta tentry
        bcc _chk
        inc tentry+1
_chk    inc tdig
        lda tdig
        cmp #3
        bcc +
        lda #0
        sta tdig
+       lda tentry+1            ; 40 <= tentry <= 295 ?
        bne +
        lda tentry
        cmp #40
        bcc _r
        bcs _ok
+       cmp #1
        bne _r
        lda tentry
        cmp #<296
        bcs _r
_ok     lda tentry
        sta f_bpm
        lda tentry+1
        sta f_bpm+1
        jmp tempo_put
_r      rts

; ---------------------------------------------------------------------------
; Preset 0 = the default instrument (instr_fix, item_empty, low.asm
; pre_fetch base); the factory library is in presetdata.asm.
PRESET_DEF = [$01,$40,$09,$a0,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,$ff,$00]
pre_data .byte PRESET_DEF

; Preset tables (apply_preset, low.asm)
; A = table: carry clear if no instrument but p_self uses it and it is
; empty or equal to a preset template
tbl_reusable
        sta p_t
        ldx #NINSTR-1
-       cpx p_self
        beq +
        txa
        jsr instr_addr
        ldy #IN_TABLE
        lda (ptr),y
        cmp p_t
        beq _no
+       dex
        bpl -
        ldx p_ntl               ; last template (high.asm; more with an REU)
-       lda p_t
        stx p_x
        jsr tbl_match
        beq _yes
        ldx p_x
        dex
        bpl -
_no     sec
        rts
_yes    clc
        rts

; A = table: Z set if it holds no data
table_empty
        ldx #TPL_EMPTY
        ; fall through

; A = table, X = template: Z set if the table equals the template
tbl_match
        jsr tbl_begin
-       jsr tbl_cell
        ldy t_step
        cmp (ptr),y
        bne _no
        jsr tbl_next
        bcc -
        lda #0
        rts
_no     lda #1
        rts

; A = table, X = template: write the template into the table
tbl_write
        jsr tbl_begin
-       jsr tbl_cell
        ldy t_step
        sta (ptr),y
        jsr tbl_next
        bcc -
        rts

; walk all cells of a table: tbl_begin, then tbl_cell (A = template value,
; ptr = column) and tbl_next (carry set at the end)
tbl_begin
        pha
        jsr tpl_load
        pla
        jsr item16
        sta t_lo
        txa
        clc
        adc #>TABLES
        sta t_hi
        lda #0
        sta t_col
        sta t_step
        ; fall through
tbl_colptr
        lda t_lo
        sta ptr
        lda t_col
        asl
        adc t_hi
        sta ptr+1
        rts

tbl_cell
        lda t_step
        cmp #8
        bcs _def
        lda t_col
        cmp #4
        bcs _zero
        asl
        asl
        asl
        ora t_step
        tax
        lda tplbuf,x
        rts
_def    lda t_col
        beq +
_zero   lda #0
        rts
+       lda #$ff
        rts

tbl_next
        inc t_step
        lda t_step
        cmp #16
        bcc _r
        lda #0
        sta t_step
        inc t_col
        jsr tbl_colptr
        lda t_col
        cmp #6
        rts
_r      clc
        rts

; ---------------------------------------------------------------------------
; Draw form line A (within this screen) at its row, cols 0-25
form_line
        sta f_line
        ldx screen
        clc
        adc form_l0,x
        tax
        lda ln_row,x
        bne +
        rts                     ; title line: the status line shows it
+       stx f_gl
        tax
        lda #COL_TEXT
        jsr line_0c
        ldx f_gl
        lda ln_tlo,x
        ldy ln_thi,x
        jsr putstr
        lda #FORM_W
        jsr pad_to
        ldx f_gl
        lda ln_n,x
        beq _r
        sta f_n
        lda ln_first,x
        sta f_f
        ldx screen
        lda f_line
        cmp rowv,x
        bne +
        lda colv,x
        clc
        adc f_f
        .byte $2c
+       lda #$ff
        sta f_sel               ; field shown reversed
        lda accent
        sta dcolor
_fld    lda f_f
        ldx #0
        cmp f_sel
        bne +
        ldx #$80
+       stx drev
        tay
        lda fl_col,y
        sta dx
        jsr draw_fval
        inc f_f
        dec f_n
        bne _fld
        lda #0
        sta drev
_r      rts

; Y = field: its value at dx (fb set)
draw_fval
        sty f_y
        lda fl_mask,y
        sta fmask
        lda fl_off,y
        tay
        lda (fb),y
        cpy #OFF_ED
        bcc +
        lda ed_lo-OFF_ED,y
        sta ptr
        lda ed_hi-OFF_ED,y
        sta ptr+1
        ldy #0
        lda (ptr),y
+       sta f_v                 ; the whole byte
        ldy f_y
        ldx fl_kind,y
        lda fv_lo,x
        sta jv
        lda fv_hi,x
        sta jv+1
        lda f_v
        jmp (jv)

fv_lo   .byte <puthex, <putshex, <_nib, <_enum, <_bit, <_pw, <puthex_e, <_r
        .byte <_preset, <_tempo, <_char, <_action
fv_hi   .byte >puthex, >putshex, >_nib, >_enum, >_bit, >_pw, >puthex_e, >_r
        .byte >_preset, >_tempo, >_char, >_action

_nib    jsr _masked
        jmp putnib
_enum   jsr _masked
        ldy f_y
        cmp fl_max,y
        beq +
        bcc +
        lda #NM_BAD
        jmp put_name
+       clc
        adc fl_arg,y
        jmp put_name
_bit    and fmask
        beq +
        ldy f_y
        lda fl_arg,y
        jmp putc
+       lda #$2e
        jmp putc
_pw     ldy f_y
        lda fl_off,y
        tay
        iny
        lda (fb),y
        jsr putnib
        lda f_v
        jmp puthex
_preset jsr pre_id              ; "1d laser"
        pha
        jsr puthex
        jsr space
        pla
        jsr pre_name
        jmp putstr
_tempo  lda HD_TEMPO
        jmp putbpm
_char   and #$7f
        bne +
        lda #$20
+       jmp putc
_action ldy f_y
        ldx fl_arg,y
        lda act_lo,x
        ldy act_hi,x
        jmp putstr
_r      rts
_masked lda f_v
        and fmask
        pha
        jsr fshift
        pla
        ldx f_sh
        beq +
-       lsr
        dex
        bne -
+       rts

; A = signed byte as +xx / -xx
putshex pha
        cmp #$80
        lda #$2b                ; '+'
        bcc +
        lda #$2d                ; '-'
+       jsr putc
        pla
        bpl +
        eor #$ff
        clc
        adc #1
+       jmp puthex

; whole form: all lines (+ instrument usage map)
form_full
        jsr form_setup
        lda #0
        sta f_ln
-       lda f_ln
        jsr form_line
        inc f_ln
        lda f_ln
        ldx screen
        cmp form_nl,x
        bne -
        lda screen
        cmp #SC_INSTR
        beq usage_map
        rts

; rows 13-17: which instruments are used (+), the current one reversed
usage_map
        ldx #13
        lda #COL_DIM
        jsr line_0c
        jsr prt
        .enc "screen"
        .null "instruments  + = used"
        .enc "none"
        lda #FORM_W
        jsr pad_to
        lda #0
        sta f_ln
_row    lda f_ln
        clc
        adc #14
        tax
        jsr gotoxy0
        lda #COL_DIM
        sta dcolor
        lda f_ln
        jsr putnib
        lda #$2d                ; '-'
        jsr putc
        jsr space
        lda accent
        sta dcolor
        lda f_ln
        asl
        asl
        asl
        asl
        sta f_i
_col    ldx #0
        lda f_i
        cmp cur_instr
        bne +
        ldx #$80
+       stx drev
        ldx #2
        jsr alloc_test
        beq +
        lda #$2b                ; '+'
        bne ++
+       lda #$2e                ; '.'
+       jsr putc
        inc f_i
        lda f_i
        and #15
        bne _col
        lda #FORM_W
        jsr pad_to
        inc f_ln
        lda f_ln
        cmp #4
        bne _row
        rts

; form scratch
ffield  .byte 0
fkind   .byte 0
fmask   .byte 0
fmax    .byte 0
f_sh    .byte 0
f_d     .byte 0
f_bpm   .word 0
f_tcol  .byte 0
f_line  .byte 0
f_gl    .byte 0
f_n     .byte 0
f_f     .byte 0
f_best  .byte 0
f_bi    .byte 0
f_sel   .byte 0
f_y     .byte 0
f_v     .byte 0
f_ln    .byte 0
f_i     .byte 0
jv      .word 0
p_v     .byte 0
p_old   .byte 0
p_tpl   .byte 0
p_t     .byte 0
p_x     .byte 0
t_lo    .byte 0
t_hi    .byte 0
t_col   .byte 0
t_step  .byte 0
; presets (low.asm)
p_idt   .byte 0
p_mlo   .byte 0
p_mhi   .byte 0
p_self  .byte 0
        .virtual $07e8          ; M10: between the screen and the sprite pointers
pbuf    .fill 16
        .cerror * > $07f8
        .endv
tplbuf  .fill 32
pnbuf   .fill PRE_NAMELEN
        .byte 0
