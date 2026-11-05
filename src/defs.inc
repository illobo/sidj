; SIDJ shared definitions: memory map, data layout, player API.
; This file is the contract between main, player and editor. Change it only
; together with every user.

; ---------------------------------------------------------------------------
; Machine
; ---------------------------------------------------------------------------
SID        = $d400
VIC        = $d000
CIA1       = $dc00
CIA2       = $dd00
SCREEN     = $0400
COLORRAM   = $d800
BANK_RAMIO = $35            ; $01 value: RAM everywhere except I/O (normal mode)

; ---------------------------------------------------------------------------
; Zero page split
; ---------------------------------------------------------------------------
ZP_PLAYER  = $02            ; $02-$3f belong to the player (NMI context)
ZP_PLAYER_END = $3f
ZP_EDITOR  = $40            ; $40-$ff belong to main + editor

; ---------------------------------------------------------------------------
; Song data (26 560 bytes). Empty = $ff unless noted.
; All blocks below $d000 or under the KERNAL; $01 must be BANK_RAMIO to read.
; ---------------------------------------------------------------------------
EMPTY      = $ff
NCHAN      = 3              ; voices of one SID (mono machine; the editor runs pl_nch channels)
NCHAN2     = 6              ; with a second SID: channels 4-6 on SID2
NSLOTS     = 6              ; song slots per row: channels 1-6 (4-6 play with a second SID, M7a)

; Phrases: 255 x 64 bytes. phrase p at PHRASES + p*64, step s at +s*4:
;   +0 note  ($00-$5f = C-0..B-7, $ff empty)
;   +1 instrument ($00-$3f, $ff empty)
;   +2 command (0 = none, 1..26 = letter A..Z)
;   +3 command value
PHRASES    = $8000          ; .. $bfbf
NPHRASES   = 255
PH_NOTE    = 0
PH_INSTR   = 1
PH_CMD     = 2
PH_VAL     = 3

; Chains: 128 x 32 bytes. chain c at CHAINS + c*32, step s at +s*2:
;   +0 phrase ($ff = end of chain), +1 transpose (signed semitones)
CHAINS     = $c000          ; .. $cfff
NCHAINS    = 128

; Song: planar, one 256-byte page per slot. SONG + slot*256 + row.
;   $00-$7f chain, $80-$fe clip (later), $ff empty
SONG       = $e000          ; .. $e5ff

; Instruments: 64 x 16 bytes, INSTR + i*16. Field offsets:
INSTR      = $e600          ; .. $e9ff
NINSTR     = 64
IN_FLAGS   = $0             ; b0 transpose on, b1 pitch fast, b2-3 filter 0 off/1 use/2 own, b4-7 preset id (editor only)
IN_WAVE    = $1             ; SID control byte without gate
IN_AD      = $2
IN_SR      = $3
IN_PWLO    = $4
IN_PWHI    = $5             ; lo nibble PW bits 8-11, hi nibble sweep mode 0 none/1 up/2 down/3 pingpong
IN_PWSPD   = $6
IN_CUTOFF  = $7             ; cutoff bits 3-10
IN_RESMODE = $8             ; hi nibble resonance, lo nibble mode bits LP=1 BP=2 HP=4 3OFF=8
IN_FSWEEP  = $9             ; signed cutoff change per tick
IN_HR      = $a             ; hi nibble HR ticks (0 off), lo nibble HR mode
IN_HRSR    = $b
IN_VIB     = $c             ; hi speed, lo depth
IN_VIBDLY  = $d
IN_TABLE   = $e             ; $ff none
IN_TBLSPD  = $f
INF_TRANSP = $01
INF_FAST   = $02
INF_FILTER_MASK = $0c
INF_FILTER_USE  = $04
INF_FILTER_OWN  = $08

; Tables: 32 x 16 steps, planar per column: TABLES + col*512 + t*16 + step
TABLES     = $ea00          ; .. $f5ff
NTABLES    = 32
TB_CTL     = 0              ; SID control byte, $ff = no write
TB_TRANSP  = 1
TB_CMD1    = 2
TB_VAL1    = 3
TB_CMD2    = 4
TB_VAL2    = 5

; Grooves: 32 x 16 tick counts, GROOVES + g*16 + step. 0 = end, loop to step 0.
GROOVES    = $f600          ; .. $f7ff
NGROOVES   = 32

; Project header
HEADER     = $f800
HD_TEMPO   = HEADER+0       ; encoding: $28-$ff = 40-255 BPM, $00-$27 = 256-295 BPM
HD_TRANSP  = HEADER+1
HD_CLONE   = HEADER+2       ; clone mode: 0 deep, 1 slim (editor)
HD_NAME    = HEADER+$10     ; 16 bytes, screen codes
HD_BOOKMARKS = HEADER+$20   ; 32 bytes: bit per song row (editor)

; Allocation bitmaps (1 bit per item, set = used)
ALLOC_CHAINS  = $f900       ; 16 bytes
ALLOC_PHRASES = $f910       ; 32 bytes
ALLOC_INSTR   = $f930       ; 8 bytes
ALLOC_TABLES  = $f938       ; 4 bytes

; ---------------------------------------------------------------------------
; Player API (src/player.asm, assembled at PLAYER). Fixed jump table and
; state block so the editor and exports never depend on internal labels.
; All calls: from main context, $01 = BANK_RAMIO, may clobber A/X/Y.
; ---------------------------------------------------------------------------
PLAYER          = $1000
player_init     = PLAYER+$00  ; SID reset, CIA2 timer A -> NMI, sets $fffa vector, tempo from HD_TEMPO
player_play_song = PLAYER+$03 ; A = song row: all channels play from that row
player_stop     = PLAYER+$06  ; stop all channels (gates off)
player_play_channel = PLAYER+$09 ; X = channel, A = song row: start that channel only
player_stop_channel = PLAYER+$0c ; X = channel
player_set_tempo = PLAYER+$0f ; A = tempo byte (HD_TEMPO encoding)
player_note_on  = PLAYER+$12  ; X = channel, A = note, Y = instrument (preview / jam)
player_note_off = PLAYER+$15  ; X = channel
player_queue    = PLAYER+$18  ; X = channel, A = song row $00-$fd (A = $ff cancels), Y = 0 at chain end / 1 at phrase end.
                              ; Stopped channel: starts on the next step of the lowest playing channel (Y ignored).
player_queue_stop = PLAYER+$1b ; live mode: X = channel, Y = 0 at chain end / 1 at phrase end

; State block (read by the editor; only pl_mute is written by the editor)
pl_playing      = PLAYER+$20  ; bit n = channel n playing
pl_mute         = PLAYER+$21  ; bit n = channel n muted (editor writes)
pl_tempo        = PLAYER+$22  ; current tempo byte
pl_tick         = PLAYER+$23  ; free-running tick counter
pl_nudge        = PLAYER+$25  ; signed, editor writes: temporary tempo nudge, effective latch = latch - latch*pl_nudge/256,
                              ; applied within one tick of a change; 0 = none (live sync by ear).
                              ; Keep within +-32. player_init (also load/clean) resets it to 0.
pl_ntsc         = PLAYER+$26  ; set by player_init: 0 = PAL, 1 = NTSC (read-only)
pl_nch          = PLAYER+$27  ; set by player_init: channels that play, 3 (mono) or 6 (pl_sid2 set) (read-only)
pl_live         = PLAYER+$24  ; 0 = song mode, 1 = live mode (editor writes): a chain loops until a queue entry replaces it;
                              ; a change takes effect at the next chain end
pl_row          = PLAYER+$28  ; [6] current song row per channel
pl_chain        = PLAYER+$30  ; [6] chain number playing per channel
pl_chain_step   = PLAYER+$38  ; [6]
pl_phrase       = PLAYER+$40  ; [6] phrase number playing per channel
pl_phrase_step  = PLAYER+$48  ; [6]
pl_shadow       = PLAYER+$50  ; [25] SID register shadow, written to SID each tick
; Live FX overrides. The editor writes the value first, then sets its pl_fxmask bit (latch);
; clearing the bit releases it. While latched the value replaces whatever instruments, tables and commands
; produce, applied to the shadow every tick (within one tick of a change). player_init clears pl_fxmask.
pl_fxmask       = PLAYER+$69  ; b0 cutoff, b1 resonance, b2 filter mode, b3 volume, b4 transpose
FX_CUT = $01
FX_RES = $02
FX_MODE = $04
FX_VOL = $08
FX_TRANSP = $10
pl_fxcut        = PLAYER+$6a  ; cutoff bits 3-10 (as IN_CUTOFF)
pl_fxres        = PLAYER+$6b  ; resonance 0-15
pl_fxmode       = PLAYER+$6c  ; filter mode bits LP=1 BP=2 HP=4 3OFF=8 (as IN_RESMODE low nibble)
pl_fxvol        = PLAYER+$6d  ; master volume 0-15
pl_fxtransp     = PLAYER+$6e  ; signed semitones added to every note of every channel (on top of HD_TRANSP)
pl_queue        = PLAYER+$70  ; [6] live mode: queued song row, $fe = queued stop, $ff = none
pl_qmode        = PLAYER+$78  ; [6] live mode: 0 = switch at chain end, 1 = at phrase end
pl_sid2         = PLAYER+$7e  ; word: second SID base ($d420, $d500, $de00, ...), hi 0 = none. Written before
                              ; player_init (which keeps it, sets pl_nch and points the SID2 writes at it)
pl_shadow2      = PLAYER+$80  ; [25] SID2 register shadow (channels 4-6, own filter), = pl_shadow+$30
PLAYER_CODE     = PLAYER+$a0  ; first byte of player code
PLAYER_END      = $2800       ; player must end below this ($2000-$27ff was a charset reserve, given to the player in M4)
PLAYER_EXT      = $0e00       ; $0e00-$0fff: player variables, rebuilt by player_init; nobody else may use it
pl_hold         = PLAYER+$99  ; [6] editor writes: hold mask per channel, 0 = off. Bits 0-3 = m: the step after s is
                              ; (s & ~m) | ((s + 1) & m), so 15 loops the phrase, 7/3/1 repeat 8/4/2 steps, $10 repeats one
                              ; step; phrase hops (H) and queue switches wait. player_init clears it. Takes effect at the
                              ; step after next, or at the next one if the editor also sets pl_lapend.
pl_lapend       = $0fde       ; [6] editor may set it to 1 on a playing channel: re-runs lookahead (next step) on the next tick
pl_wait         = $0fe4       ; [6] ticks left in the current step, read-only (counts down to 0, then the next step)
pl_steplen      = $0fea       ; [6] ticks of the current step, read-only
pl_tbl          = $0ff0       ; [6] table number running per channel ($ff none), read-only; keeps running through the release
pl_tblstep      = $0ff6       ; [6] current table row per channel
; Editor-owned low memory. Debug hooks (see src/editor/editor.asm):
;   keys:  $0c00 count, $0c01 index, $0d00 (buttons, char) pairs
;   mouse: $0c02 count, $0c03 index, $0c10 frames of (x lo, y, flags: b0 left, b1 right, b7 x bit 8)
; Pointer sprite data at $0bc0-$0bff (main's init area, dead after start-up).
EDITOR_LOW      = $0c00       ; $0c00-$0dff: editor variables (debug hook at $0c00/$0d00)
EDLOW           = $0830       ; $0830-$0b7f: editor code (low.asm), loaded in place; the start-up code moved out (main.asm)
INIT_RUN        = $0200       ; $0200-$04ff: start-up code runs here once (main.asm boot; its demo data may reach into the screen);
                              ; then $0200-$03ff become RES2 and OVWIN (below)
HELPBUF         = $0b80       ; [64] editor: help string copied out of HELPTEXT (main's init area, dead after start-up)

; Editor memory outside $2800-$6fff. main.asm stages HELPTEXT and EDHI in
; the .prg at STAGE (phrase area, cleared afterwards) and copies them at start-up.
STAGE           = $8000
HELPTEXT        = $d300       ; $d300-$dbff RAM under I/O: help strings ($01 = BANK_ALLRAM to read, with IRQs off)
IORAM_FREE      = $dc00       ; $dc00-$dfff RAM under I/O: free (M5: undo store without REU)
BANK_ALLRAM     = $34
CLIPBUF         = $fa00       ; $fa00-$fcff under the KERNAL: clipboard (3 x 256, editor); at start-up the RES2/OVWIN images + last start-up step
EDHI            = $fd00       ; $fd00-$fff9 under the KERNAL: editor code (high.asm); never called during file I/O
EDHI_END        = $fffa
RES2            = $0200       ; $0200-$02ff: resident editor code (res.asm), copied as the last start-up step
OVWIN           = $0300       ; $0300-$03ff: code overlay window (reu.asm); without an REU the no-REU undo code
                              ; lives here for good. fileio saves, clears and restores $0200-$03ff around KERNAL
                              ; sessions (its session variables use the cassette buffer $033c-$03fb meanwhile)

; ---------------------------------------------------------------------------
; REU bank map. The editor's u_reu = highest bank (0 = no REU,
; 1 = 128 KB, 3, 7 .. 255 = 16 MB), found once at start-up. T.A.S.T.E uses
; banks from the top down (REU_TXBANKS of them) and never banks 0-1.
; ---------------------------------------------------------------------------
REU_MAPVER      = 1           ; bank map version (header)
REU_PFORMAT     = 2           ; project format version (header; = fileio VERSION)
; bank 0 page $00: header
RH_MAGIC        = 0           ; 7 bytes "SIDJREU"
RH_MAP          = 7           ; REU_MAPVER
RH_BANKS        = 8           ; u_reu when written
RH_PFMT         = 9           ; REU_PFORMAT
RH_VALID        = 10          ; 1 = the undo mirror is a whole project (recovery at start-up), 0 = not
RH_LEN          = 11
REU_DIRPG       = $01         ; bank 0 pages $01-$02: slot directory, 32 x 16 B names (screen codes), $ff first = free
REU_CLIPPG      = $03         ; bank 0 pages $03-$1a: clipboard ring (later)
REU_PAYPG       = $20         ; bank 0 pages $20-$7f: payload: help pages and preset library
REU_HLPPG       = $20         ;   $20: help header (HLP_MAGIC, version, page count); pages from $2100 + n * HLP_STRIDE:
HLP_STRIDE      = $0580       ;   680 screen codes (rows 1-17), then 680 colours; SIDJ.HLP fills $20-$6f at start-up
HLP_TEXT        = 680
HLP_MAXPG       = 14
REU_HLPEND      = $70         ;   first page after the help area (fio_rload stops here)
REU_XPPG        = $70         ;   $70-$7f: extended presets, 32-byte records (staged in the .prg, stashed at start-up)
                              ; bank 0 pages $80-$cf, $e0-$f9: undo mirror of the song data (same offsets)
REU_OVPG        = $d0         ; bank 0 pages $d0-$df: code overlays, 256 B each (stashed at start-up)
REU_NOV         = 16
REU_UNDOBANK    = 1           ; bank 1: undo ring, 256 page slots
REU_SLOTBANK    = 2           ; project slots from bank 2 up, 2 per bank (pages $00-$69 / $80-$e9)
REU_SLOTPAGES   = 106         ; song data pages per slot: $80-$cf, $e0-$f9
REU_MAXSLOTS    = 32
REU_TXBANKS     = 2           ; top banks kept free for T.A.S.T.E
OV_UNDO         = 0           ; overlay ids: 0 = undo with an REU (lives in the window between other calls)
OV_SLOTS        = 1           ;              1 = REU project slots (File screen device REU)
OV_DRUMIN       = 2           ;              2 = drum lane view: keys, mouse, toggle (ov_drum_in.asm)
OV_DRUMDR       = 3           ;              3 = drum lane view: drawing (ov_drum_draw.asm)
OV_DRUMTG       = 4           ;              4 = drum lane view: on/off (ov_drum_tog.asm)
OV_HELP         = 5           ;              5 = extended help viewer (ov_help.asm, R2)
OV_REC          = 6           ;              6 = loop record while armed (ov_rec.asm, M9; arming: overlay 4, X = 3)

; ---------------------------------------------------------------------------
; File I/O module (src/fileio.asm at FILEIO). Called from the editor (main
; context, $01 = BANK_RAMIO). Each call stops playback, banks the KERNAL in as
; needed, protects zero page / $0200-$03ff / IRQ+NMI setup, and returns with the
; machine as it found it (editor raster IRQ running, player NMI clock running).
; Result: C clear = ok; C set = error, A = error code (FIO_ERR_*), fio_msg set.
; ---------------------------------------------------------------------------
FILEIO          = $7000         ; module occupies $7000-$7fff (code, buffers, directory)
fio_save        = FILEIO+$00    ; save project as HD_NAME (16 screen codes, $00/$20 padded) to fio_device
fio_load        = FILEIO+$03    ; X = directory entry index (from fio_dir): load it, then player_init state.
                                ; A kit file instead goes into instruments fio_kdst.. (cut at 63) and new tables taken
                                ; from FIO_KBUF; returns C set, A = FIO_KIT (not an error, project and player untouched)
fio_clean       = FILEIO+$06    ; empty project: everything empty, default instruments, groove 0 = 6/6, 125 BPM
fio_dir         = FILEIO+$09    ; read SIDJ project and kit files on fio_device into FIO_DIR
fio_delete      = FILEIO+$0c    ; X = directory entry index: scratch that file and remove it from FIO_DIR
fio_rload       = FILEIO+$0f    ; REU payload: read SIDJ.HLP (RLE, as project blocks) from fio_device into REU bank 0
                                ; from page REU_HLPPG on (stops before REU_HLPEND); uses FIO_DIR as its page buffer.
                                ; Needs an REU (the caller checks). (Was the .prg export; now tools/sidj2sid.py.)
fio_kit_save    = FILEIO+$12    ; X = first instrument, fio_kcnt = instrument count, FIO_KBUF = their tables ($ff after
                                ; the last): save them as a kit file named HD_NAME (12 chars) + ".Kxx" (xx = X, hex)
fio_kcnt        = FILEIO+$1e    ; kit instrument count: fio_kit_save input, fio_load (kit) output (after the cut at 63)
fio_kdst        = FILEIO+$1f    ; first instrument a kit file is loaded into (editor writes; see fio_load)
fio_device      = FILEIO+$20    ; drive number, default 8
fio_err         = FILEIO+$21    ; last error code (0 = ok)
fio_msg         = FILEIO+$22    ; 20 screen codes: human readable status for the help line
FIO_DIRCOUNT    = $7dff         ; number of entries in FIO_DIR (max 32)
FIO_KBUF        = HELPBUF         ; [32] tables, $ff after the last. fio_load: the tables a kit may use (free and empty);
                                ; fio_kit_save: the kit's tables (distinct IN_TABLE values). The editor fills it (kits.asm)
                                ; right before the call: it shares HELPBUF, a buffer used only while the help line is drawn.
FIO_DIR         = $7e00         ; 32 x 16 bytes: entry names as screen codes
FIO_SAVEAREA    = $d000         ; $d000-$d2ff RAM under I/O: zero page + $0200-$03ff saved here during disk calls
; After fio_load / fio_clean: player_init has run (pl_tick reset), playback stopped; pl_mute and pl_live kept.
FIO_ERR_NODEV   = 1
FIO_ERR_NOFILE  = 2
FIO_ERR_FORMAT  = 3             ; not a SIDJ project / unknown version
FIO_ERR_DISK    = 4             ; drive reported an error (fio_msg holds it)
FIO_ERR_KIT     = 5             ; kit load: not enough free tables
FIO_KIT         = 6             ; fio_load result: a kit was loaded (C set, fio_msg "KIT LOADED", fio_kcnt instruments)
