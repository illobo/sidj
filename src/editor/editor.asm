; SIDJ editor: Song, Chain, Phrase, Instrument, Table, Groove,
; Project and File screens with the four-key grammar, live mode, block
; copy/paste, cloning and bookmarks.
; Entry: editor_init (from main, after player_init), then jmp editor_main.
; Files in src/editor/:
;   input.asm  raster IRQ, raw CIA1 matrix scan, buttons, debug script hook
;   edit.asm   grammar: cursor, field edits, allocation, navigation, playback
;   form.asm   form screens (Instrument, Project): field tables, presets
;   low.asm    factory presets: browse, apply, library access (EDLOW;
;              data in presetdata.asm under I/O)
;   draw.asm   screen output with partial redraw: status, screens, panels
;   clip.asm   block mark, clipboard, clone, bookmarks
;   live.asm   live mode (queue), messages, File screen (FILEIO calls)
;   mouse.asm  1351 driver (IRQ), pointer sprite, mouse grammar, hover
;              help, tap tempo, nudge
;   grid.asm   grid view of the Phrase screen (keys, mouse, drawing)
;   fx.asm     Live FX panel: faders on rows 18-23 (mouse, drawing)
;   text.asm   strings (screen codes via .enc "screen": lowercase = A-Z)

; ---------------------------------------------------------------------------
; Zero page ($40-$ff belong to the editor)
; ---------------------------------------------------------------------------
dp      = $40                   ; screen pointer of the current output row
cp      = $42                   ; colour RAM pointer of the same row
dx      = $44                   ; output column
dcolor  = $45                   ; output colour
drev    = $46                   ; $80 = reversed output
ptr     = $47                   ; general pointer
ptr2    = $49                   ; second pointer (data rows while drawing)
fp      = $4b                   ; pointer to the field under the cursor
tmp     = $4d
tmp2    = $4e
tmp3    = $4f
sidx    = $50                   ; string index for putstr
rowsel  = $51                   ; $80 while drawing the cursor row, else 0
curf    = $52                   ; field index under the cursor ($ff in the panel)
xoff    = $53                   ; left column of the list being drawn
item    = $54                   ; chain/phrase/instrument being drawn
step    = $55                   ; step/row being drawn
accent  = $56                   ; channel colour of the list being drawn
mchan   = $57                   ; scratch channel index
; $58-$59 fb (form.asm)
cbp     = $5a                   ; clipboard buffer pointer (clip.asm)
; $e0-$f2 undo / redo (high.asm)
; $60-$7f Live FX panel (fx.asm), $a0-$cb grid view variables (grid.asm)
; $80-$93 loop record, piano (loop.asm), $cc-$cd drum view (ov_drum_in.asm)
; M10: the most used editor variables live in the rest; editor_init sets
; their start values (the definitions stay in their files, marked "zp"):
ZPV_A   = $5c                   ; screen dirty btn press
ZPV_AN  = 4
ZPV_B   = $94                   ; rowv[9] ftype m_t a_idx
ZPV_BN  = 12
ZPV_C   = $cf                   ; song_top m_row dir_t m_col h_val m_btn kcode h_row
ZPV_CN  = 17                    ; h_col key cur_chan grid_on dr_base a_y k_i mark_on cl_new
        .cerror FT_NONE != $ff || KC_NONE != $ff || SC_SONG != 0, "editor_init start values"

; Debug hook (fixed addresses, documented in the report). A test writes up to
; 128 (buttons, char) pairs to DBG_SCRIPT, sets DBG_IDX = 0, then DBG_COUNT =
; number of pairs. Each main loop iteration (one per frame) consumes one pair
; instead of the keyboard. Buttons use the BT_* bits; char = KC_* code or $ff.
DBG_COUNT  = $0c00
DBG_IDX    = $0c01
DBG_SCRIPT = $0d00

; Mouse debug hook (same idea, runs alongside the one above, so a test can
; hold keys while it clicks). A test writes up to 74 frames of 3 bytes to
; MDBG_SCRIPT: x bits 0-7, y, flags (bit 0 left button, bit 1 right button,
; bit 7 = x bit 8), sets MDBG_IDX = 0, then MDBG_COUNT = number of frames.
; Each main loop iteration (one per frame) takes one frame instead of the
; driver: pointer hot spot at (x, y) in text-area pixels (0-319, 0-199;
; character column = x/8, row = y/8) with those buttons. The pointer sprite
; follows, and the driver continues from the last scripted position.
MDBG_COUNT  = $0c02
MDBG_IDX    = $0c03
MDBG_SCRIPT = $0c10             ; .. $0cdd

; Abstract buttons (bit order matches joystick port 2 for bits 0-4)
BT_UP     = $01
BT_DOWN   = $02
BT_LEFT   = $04
BT_RIGHT  = $08
BT_A      = $10                 ; SPACE / fire
BT_B      = $20                 ; C=
BT_SELECT = $40                 ; CTRL
BT_START  = $80                 ; RETURN
BT_DIRS   = $0f

; Char codes from the matrix: 0-9 digits, 10-35 letters A-Z, F1/F3/F5
KC_F1   = $40
KC_F7   = KC_F1+3               ; undo
KC_SHIFTF = 8                   ; SHIFT + F-key: code + 8 (F2 F4 F6 F8)
KC_F2   = KC_F1+KC_SHIFTF       ; SHIFT + F1: extended help (REU)
KC_F8   = KC_F7+KC_SHIFTF       ; SHIFT + F7: redo
KC_NONE = $ff

; Screens
SC_SONG    = 0
SC_CHAIN   = 1
SC_PHRASE  = 2
SC_INSTR   = 3
SC_TABLE   = 4
SC_GROOVE  = 5
SC_PROJECT = 6
SC_SID     = 7
SC_FILE    = 8                  ; hidden: reached from Project LOAD/SAVE
NSCREENS   = 9

; Field types (edit.asm tables ft_*)
FT_CHAIN  = 0
FT_PHRASE = 1
FT_TRANSP = 2
FT_NOTE   = 3
FT_INSTR  = 4
FT_CMD    = 5
FT_VAL    = 6
FT_TABLE  = 7                   ; table number, $ff none (instrument)
FT_CTL    = 8                   ; table control byte, $ff no write
FT_GROOVE = 9                   ; groove ticks, 0 = end
FT_FORM   = 10                  ; masked/special form field (form.asm)
NFT       = 11
FT_NONE   = $ff

; Redraw requests (dirty bits); see draw.asm update
RD_ROW    = $01                 ; cursor row content changed
RD_PANEL  = $02                 ; context panel content changed
RD_LIST   = $04                 ; whole left screen content changed
RD_MARKS  = $08                 ; player positions changed
RD_ALL    = $80                 ; everything (screen switch)

; Colours
COL_TEXT   = 15                 ; light grey
COL_DIM    = 11                 ; dark grey: step and row numbers
COL_HEAD   = 1                  ; white
COL_HELP   = 14                 ; light blue
COL_BG     = 0

REP_DELAY = 16                  ; frames before a held direction repeats
REP_RATE  = 3                   ; frames between repeats
DBL_FRAMES = 25                 ; window for SPACE, SPACE (new chain/phrase)
SONG_ROWS = 16                  ; visible song rows

; ---------------------------------------------------------------------------
        .section late_init      ; start-up only: boot_late.asm
editor_init
        sei
        jsr zpv_init            ; zero page variables
        lda #COL_BG
        sta VIC+$20
        sta VIC+$21
        lda #$1b                ; text mode, 25 rows, screen on
        sta VIC+$11
        lda #$c8                ; 40 columns, no multicolour
        sta VIC+$16
        lda #$15                ; screen $0400, ROM upper case charset
        sta VIC+$18
        lda CIA2                ; VIC bank 0
        ora #3
        sta CIA2
        lda #$ff                ; CIA1: port A drives columns, port B reads rows
        sta CIA1+2
        lda #0
        sta CIA1+3
        sta DBG_COUNT
        sta DBG_IDX
        jsr nch_sync            ; channel count from the player (sid2.asm)
        jsr alloc_rebuild
        jsr undo_reset          ; empty history (res.asm; REU found at start-up)
        jsr clear_screen
        jsr input_init          ; installs the raster IRQ
        cli
        rts
        .send late_init

; start values of the zero page variables: ZPV_A-C 0, then the rest.
; Main editor code: the staged start-up code has no room left.
zpv_init
        lda #0
        ldx #ZPV_CN-1
-       sta ZPV_C,x
        cpx #ZPV_BN
        bcs +
        sta ZPV_B,x
        cpx #ZPV_AN
        bcs +
        sta ZPV_A,x
+       dex
        bpl -
        stx ftype               ; FT_NONE
        stx key                 ; KC_NONE
        stx dr_base
        lda #RD_ALL
        sta dirty
        lda #1                  ; rowv: Instr, Table, Groove start on row 1
        sta rowv+SC_INSTR
        sta rowv+SC_TABLE
        sta rowv+SC_GROOVE
        rts

editor_main
        lda last_frame          ; at most one iteration per frame; a redraw
-       cmp in_frame            ; can span frames, so timers use elapsed
        beq -
        lax in_frame
        sec
        sbc last_frame
        sta elapsed
        stx last_frame
        jsr input_poll
        jsr loop_frame          ; F4/F6, piano keys, recording, holds (loop.asm)
        jsr undo_frame
        jsr hp_mouse            ; mouse_input, or the help viewer (high.asm)
        jsr drum_grammar        ; drum view (grid.asm), else grammar + kit gestures (kits.asm)
        jsr grid_key
        jsr nudge_watch
        jsr play_watch
        jsr border_fx
        jsr nmi_watch
        jsr prelisten_tick
        ldx #2                  ; dbl_timer, ret_timer, b_timer run down
-       lda dbl_timer,x
        sec
        sbc elapsed
        bcs +
        lda #0
+       sta dbl_timer,x
        dex
        bpl -
        jsr hp_update           ; update, unless the help viewer is open
        jmp editor_main

; Border shows the transport: black when stopped, dark grey while playing,
; blue in live mode, red while loop recording; on every beat (each 4th step)
; of the lowest playing channel it flashes for a few frames, white on step 0.
border_fx
        lda pl_playing
        bne +
        sta VIC+$20             ; stopped: black
        lda #$ff
        sta bf_step             ; next start flashes at once
        rts
+       ldx #$ff                ; lowest playing channel
-       inx
        lsr
        bcc -
        lda pl_phrase_step,x
        cmp bf_step
        beq _hold
        sta bf_step
        and #3
        bne _hold
        ldy #1                  ; white on step 0, light grey on other beats
        lda bf_step
        beq +
        ldy #15
+       sty bf_col
        lda #5
        sta bf_time
_hold   lda bf_time
        beq _base
        dec bf_time
        lda bf_col
        bne _set
_base   lda #11                 ; dark grey
        ldx pl_live
        beq +
        lda #6                  ; blue: live mode
+       ldx lr_on
        beq _set
        lda #2                  ; red: recording
_set    sta VIC+$20
        rts
bf_step .byte $ff
bf_time .byte 0
bf_col  .byte 0

; The player runs on the CIA2 timer NMI, which fires on a falling edge. If one
; NMI is missed (the C64 Ultimate or a freezer halting the CPU), CIA2 keeps
; the line low and no edge ever comes again: the player stands still. While a
; channel plays and pl_tick has not moved for 12 frames (the slowest tempo
; ticks every 3), read the ICR once: the line goes high, the next underflow fires.
nmi_watch
        lda pl_playing
        beq _clear
        lda pl_tick
        cmp nw_tick
        bne _moved
        lda nw_frames
        clc
        adc elapsed
        sta nw_frames
        cmp #12
        bcc _x
        lda CIA2+$0d
_clear  lda #0
        sta nw_frames
_x      rts
_moved  sta nw_tick
        lda #0
        sta nw_frames
        rts
nw_tick   .byte 0
nw_frames .byte 0

; Play markers follow the player's visible state (positions, play flags).
play_watch
        ldx #0
        lda pl_playing
        jsr _cmp
        lda pl_mute
        jsr _cmp
        lda pl_tempo
        jsr _cmp
        ldy #0
-       lda pl_row,y
        jsr _cmp
        lda pl_chain,y
        jsr _cmp
        lda pl_chain_step,y
        jsr _cmp
        lda pl_phrase,y
        jsr _cmp
        lda pl_phrase_step,y
        jsr _cmp
        lda pl_queue,y
        jsr _cmp
        iny
        cpy #NCHAN2
        bne -
        lda pl_live
        jsr _cmp
        ldy #0                  ; Table: table position per channel
-       lda #0
        sta tmp
        lda screen
        cmp #SC_TABLE
        bne +
        lda pl_tblstep,y
        sta tmp
        lda pl_tbl,y
+       jsr _cmp
        lda tmp
        jsr _cmp
        iny
        cpy #NCHAN2
        bne -
        dey                     ; Y = 5: blink phase while anything is queued
        lda #$ff
-       and pl_queue,y
        dey
        bpl -
        iny
        cmp #$ff
        beq +
        lda in_frame
        and #$10
        tay
+       sty blink
        tya
        ; fall through
_cmp    cmp pl_snap,x
        beq +
        sta pl_snap,x
        lda #RD_MARKS
        ora dirty
        sta dirty
+       inx
        rts

; ---------------------------------------------------------------------------
; Editor state. Start values come with the program file.
; ---------------------------------------------------------------------------
vars
screen      = $5c               ; zp, start value SC_SONG (editor_init)
        .virtual ZPV_B          ; zp, start values set in editor_init (a label, so srow & co. are addresses for the tests)
rowv        .fill 9             ; cursor row per screen
        .endv
colv        .byte 0, 0, 0, 0, 0, 0, 0, 0, 0 ; cursor field per screen
srow        = rowv + SC_SONG
crow        = rowv + SC_CHAIN
prow        = rowv + SC_PHRASE
scol        = colv + SC_SONG    ; Song: channel
ccol        = colv + SC_CHAIN   ; Chain: 0 phrase, 1 transpose
pcol        = colv + SC_PHRASE  ; Phrase: 0 note 1 instr 2 cmd 3 value
song_top    = $cf               ; zp; first visible song row
cur_chain   .byte 0             ; chain shown on the Chain screen
cur_phrase  .byte 0             ; phrase shown on the Phrase screen
cur_instr   .byte 0             ; instrument shown on the Instr screen
cur_table   .byte 0             ; table shown on the Table screen
cur_groove  .byte 0             ; groove shown on the Groove screen
cur_chan    = $d9               ; zp; channel context of Chain/Phrase (play, colour)
cur_songrow .byte 0             ; song row context of Chain/Phrase (play)
groove_from .byte SC_INSTR      ; screen CTRL+Up returns to from Groove
last        .byte $ff, $ff, 0, $30, 0, 11, 0, $ff, $41, 6, 0 ; last value per FT_*
            .cerror * - last != NFT, "last[] out of sync"
dbl_timer   .byte 0
ret_timer   .byte 0             ; RETURN, RETURN window (live: queue at phrase end)
b_timer     .byte 0             ; C=, C=, C= window (bookmark)
dirty       = $5d               ; zp, start value RD_ALL (editor_init)
need_clear  .byte 1
pre_timer   .byte 0             ; pre-listen note running, frames left
pre_chan    .byte 0
btn         = $5e               ; zp; buttons held this frame
btn_prev    .byte 0
press       = $5f               ; zp; newly pressed (+ repeats for directions)
key         = $d8               ; zp, start value KC_NONE (editor_init); char typed this frame
rep_timer   .byte REP_DELAY
lrow        .byte 0             ; cursor step of the list being drawn ($ff none)
tdig        .byte 0             ; tempo digits typed so far
tentry      .word 0             ; tempo being typed (decimal)
sid_model   .byte 0             ; 0 unknown, 1 = 6581, 2 = 8580
vars_end

last_frame .byte 0
elapsed .byte 1
NSNAP = 3 + 6*NCHAN2 + 2 + 2*NCHAN2
pl_snap .fill NSNAP, $ff         ; last seen player state
blink   .byte 0                 ; $10 = queued items shown, 0 = hidden

        .include "editor/input.asm"
        .include "editor/edit.asm"
        .include "editor/form.asm"
        .include "editor/draw.asm"
        .include "editor/clip.asm"
        .include "editor/live.asm"
        .include "editor/mouse.asm"
        .include "editor/grid.asm"
        .include "editor/fx.asm"
        .include "editor/loop.asm"
        .include "editor/text.asm"
        .dsection kits_main     ; kits.asm code that does not fit in EDLOW
        .include "editor/sid2.asm"
        .dsection sid2_main     ; sid2.asm: channel count, SID SETUP edits
