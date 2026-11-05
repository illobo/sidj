; Strings and character tables. .enc "screen": lowercase letters become
; screen codes 1-26, which the ROM upper case charset shows as A-Z.
        .enc "screen"

hexdig  .text "0123456789abcdef"

; note names: letter and '-'/'#' per semitone
note_l  .text "ccddeffggaab"
note_s  .text "-#-#--#-#-#-"

; letters for bit_letters (bit 0 first)
s_bits
S_WAVE  = * - s_bits
        .text "tspn"            ; triangle saw pulse noise
S_LBH3  = * - s_bits
        .text "lbh3"            ; low band high, voice 3 off
S_RS    = * - s_bits
        .text "sr"              ; sync ring

; 4-character names for put_name
s_names .text "noneup  downping"      ; 0-3 PW sweep mode
        .text "off use own ??? "      ; 4-7 filter
        .text "on  off "              ; 8-9
        .text "tickfast"              ; 10-11
        .text "off on  "              ; 12-13 (bit clear/set)
        .text "gateadsrtest"          ; 14-16 hard restart mode
        .text "????"                  ; 17 out of range
        .text "deepslim"              ; 18-19 clone mode
        .text "off prt1prt2"          ; 20-22 mouse port
NM_SWEEP  = 0
NM_FILTER = 4
NM_TICK   = 10
NM_OFFON  = 12
NM_HRMODE = 14
NM_BAD    = 17
NM_CLONE  = 18
NM_PORT   = 20

; name characters for K_CHAR fields, in SPACE+direction order
name_chars
        .text " abcdefghijklmnopqrstuvwxyz0123456789-."
NAME_NCHARS = * - name_chars

scr_names
_song   .null "song"
_chain  .null "chain"
_phrase .null "phrase"
_instr  .null "instr"
_table  .null "table"
_groove .null "groove"
_proj   .null "project"
_sid    .null "sid setup"
_file   .null "file"
scr_name_lo .byte <_song, <_chain, <_phrase, <_instr, <_table, <_groove, <_proj, <_sid, <_file
scr_name_hi .byte >_song, >_chain, >_phrase, >_instr, >_table, >_groove, >_proj, >_sid, >_file

; Help line per field (max 40 characters). H_* = string index (help_copy).
; help strings and help_copy: helptext.asm, staged under I/O at HELPTEXT
H_MAP    = 7
H_NUM    = 8
H_PRESET = 9
H_WAVE   = 10
H_BYTE   = 11
H_NIB    = 12
H_PW     = 13
H_ENUM   = 14
H_FTYPE  = 15
H_SBYTE  = 16
H_TABLE  = 17
H_CTL    = 18
H_TTR    = 19
H_GROOVE = 20
H_TEMPO  = 21
H_GTR    = 22
H_NAME   = 23
H_FILE   = 24
H_CUT    = 25
H_MARK   = 26
H_FILES  = 27
H_CLONE  = 28
H_MOUSE  = 29
H_HEAD   = 30
H_LIVE   = 31
H_GRID   = 32                   ; grid view (M5, grid.asm)
H_GRIDT  = 33                   ; grid / list toggle label
H_FX     = 34                   ; 34-39: Live FX faders, one per row (fx.asm)
H_DRUM   = 40                   ; drum lane view (grid.asm, overlay 2)
H_PIANO  = 41                   ; piano mode (loop.asm, M9)
H_MSG    = $fe                  ; draw_help: msg_buf instead of a help text

        .enc "none"
