; SIDJ main: BASIC stub, machine setup, empty project + demo song, then editor.
; Build: make (see Makefile). Memory map: src/defs.inc.

        .include "defs.inc"
        .cpu "6502i"            ; M10: the editor may use illegal opcodes (allowlist: make check-illegal)

        .weak
STUB    = 0                     ; make STUB=1: build against player_stub.asm
MEMREPORT = 0                   ; make mem: free bytes per area
        .endweak
MEMFREE .macro name, n
        .if MEMREPORT
        .warn format("free %-24s %5d", \name, \n)
        .fi
        .endm

        * = $0801
        .word (+), 2026
        .null $9e, format("%d", boot)
+       .word 0

; The start-up code runs once, from $0200: boot copies 3 pages there from
; the staging area, so EDLOW is free for editor code. The code stays below
; the screen; only the demo data may reach into it, and load_demo reads it
; before editor_init clears the screen. start copies the staged blocks
; (help text, EDHI, the RES2/OVWIN images + late to CLIPBUF, the REU
; start-up code to the screen at $0600), finds the REU (boot_reu.asm),
; loads the demo or recovers, then late (boot_late.asm, at $fc00) puts
; RES2 and OVWIN in place over the finished start-up code.
boot    sei
        ldx #0
-       lda init_stage,x
        sta INIT_RUN,x
        lda init_stage+$100,x
        sta INIT_RUN+$100,x
        lda init_stage+$200,x
        sta INIT_RUN+$200,x
        inx
        bne -
        jmp start
        .cerror * > EDLOW, "boot overflows into EDLOW"

; ---------------------------------------------------------------------------
        * = EDLOW
        .include "editor/low.asm"
        .include "editor/kits.asm"
        .dsection edlow_ext     ; lr_stamp (input.asm, M9)
        .cerror * > HELPBUF, "EDLOW overflows into HELPBUF"
        #MEMFREE "EDLOW", HELPBUF - *

        * = MS_SPRITE           ; pointer sprite, loaded in place (mouse.asm)
        .dsection sprite_img
        .cerror * != MS_SPRITE + 64, "pointer sprite is not 64 bytes"

        * = DBG_IDX + 3         ; $0c04-$0c0f: free beside the debug hooks
        .dsection lowtab1
        .cerror * > MDBG_SCRIPT, "lowtab1 overflows into MDBG_SCRIPT"


; ---------------------------------------------------------------------------
        * = PLAYER
        .cpu "6502"             ; the player: none (shared with standalone.asm, doc reader, player_test)
        .if STUB
        .include "player_stub.asm"
        .else
        .include "player.asm"
        #MEMFREE "player", pl.SQ_TABLES - pl.free_space
        #MEMFREE "PLAYER_EXT", pl_lapend - pl.ext_end
        .fi
        .cerror * > PLAYER_END, "player overflows PLAYER_END"
        .cpu "6502i"

        * = $2800
        .include "editor/editor.asm"
        .cerror * > FILEIO, "editor overflows into FILEIO"
        #MEMFREE "main editor", FILEIO - *

        * = FILEIO
        .include "fileio.asm"
        .dsection sid2_fio      ; SID SETUP screen (sid2.asm): rarely used editor code in the module's slack
        .cerror * > FIO_DIRCOUNT, "fileio overflows its buffers"
        #MEMFREE "fileio", FIO_DIRCOUNT - *

; ---------------------------------------------------------------------------
; Staged blocks, copied by copy_stage before fio_clean clears the phrases
        * = STAGE
; Code overlays first (page aligned at STAGE), stashed to bank 0 REU_OVPG + id at start-up (REU only)
        .cerror (* & $ff) != 0, "overlays must start on a page (STAGE)"
stage_ov
        .logical OVWIN
        .include "editor/ov_undo_reu.asm"
        .cerror * > OVWIN + $100, "overlay 0 (undo) over 256 bytes"
        #MEMFREE "overlay 0 undo", OVWIN + $100 - *
        .fill OVWIN + $100 - *, 0
        .here
        .logical OVWIN
        .include "editor/ov_slots.asm"
        .cerror * > OVWIN + $100, "overlay 1 (slots) over 256 bytes"
        #MEMFREE "overlay 1 slots", OVWIN + $100 - *
        .fill OVWIN + $100 - *, 0
        .here
        .logical OVWIN
        .include "editor/ov_drum_in.asm"
        .cerror * > OVWIN + $100, "overlay 2 (drum input) over 256 bytes"
        #MEMFREE "overlay 2 drum input", OVWIN + $100 - *
        .fill OVWIN + $100 - *, 0
        .here
        .logical OVWIN
        .include "editor/ov_drum_draw.asm"
        .cerror * > OVWIN + $100, "overlay 3 (drum draw) over 256 bytes"
        #MEMFREE "overlay 3 drum draw", OVWIN + $100 - *
        .fill OVWIN + $100 - *, 0
        .here
        .logical OVWIN
        .include "editor/ov_drum_tog.asm"
        .include "editor/ov_arm.asm"
        .cerror * > OVWIN + $100, "overlay 4 (drum toggle) over 256 bytes"
        #MEMFREE "overlay 4 drum toggle, arm", OVWIN + $100 - *
        .fill OVWIN + $100 - *, 0
        .here
        .logical OVWIN
        .include "editor/ov_help.asm"
        .cerror * > OVWIN + $100, "overlay 5 (help) over 256 bytes"
        #MEMFREE "overlay 5 help", OVWIN + $100 - *
        .fill OVWIN + $100 - *, 0
        .here
        .logical OVWIN
        .include "editor/ov_rec.asm"
        .cerror * > OVWIN + $100, "overlay 6 (loop record) over 256 bytes"
        #MEMFREE "overlay 6 loop record", OVWIN + $100 - *
        .here                   ; the last overlay is not padded: its page is stashed whole (the tail is whatever follows)
stage_ov_end
REU_NOV_USED = (stage_ov_end - stage_ov + $ff) / $100
        .cerror REU_NOV_USED > REU_NOV, "too many overlays"
        .cerror OV_SLOTS >= REU_NOV_USED, "overlay ids"
        .cerror OV_DRUMIN != 2 || OV_DRUMDR != 3 || OV_DRUMTG != 4 || OV_DRUMTG >= REU_NOV_USED, "drum overlay ids"
        .cerror OV_HELP != 5 || OV_HELP >= REU_NOV_USED, "help overlay id"
        .cerror OV_REC != 6 || OV_REC >= REU_NOV_USED, "loop record overlay id"
; Extended preset library, stashed to bank 0 REU_XPPG at start-up (REU only)
stage_xp
        .include "editor/xpresets.asm"
stage_xp_end
        #MEMFREE "REU presets ($7000-$7fff)", $1000 - 32 * (XP_N + XP_NT)
stage_io
        .logical HELPTEXT
        .include "editor/helptext.asm"
        .include "editor/presetdata.asm"
        .cerror * > IORAM_FREE, "help text overflows HELPTEXT"
        #MEMFREE "HELPTEXT", IORAM_FREE - *
        .here
stage_hi
        .logical EDHI
        .include "editor/high.asm"
        .cerror * > EDHI_END, "high editor code overflows into the vectors"
        #MEMFREE "EDHI", EDHI_END - *
        .here
; RES2 and OVWIN images plus the late start-up code: to CLIPBUF first,
; to $0200-$03ff by late (boot_reu.asm) once the start-up code there is done
stage_tmp
        .logical RES2
        .include "editor/res.asm"
        .cerror * > RES2 + $100, "res.asm overflows RES2"
        #MEMFREE "RES2", RES2 + $100 - *
        .fill RES2 + $100 - *, 0
        .here
        .logical OVWIN
        .include "editor/ov_undo_c.asm"
        .logical CLIPBUF + $100 + (* - OVWIN)   ; its unused tail: start-up code run in place at CLIPBUF
        .dsection late_pad      ; input_init (input.asm), called from editor_init (boot_late.asm)
        .here
        .cerror * > OVWIN + $100, "no-REU undo overflows OVWIN"
        #MEMFREE "OVWIN tier C undo", OVWIN + $100 - *
        .fill OVWIN + $100 - *, 0
        .here
        .logical CLIPBUF + $200
        .include "editor/boot_late.asm"
        .cerror * > CLIPBUF + $300, "late start-up code overflows CLIPBUF"
        #MEMFREE "late start-up", CLIPBUF + $300 - *
        .here
stage_boot
        .logical SCREEN + $200
        .include "editor/boot_reu.asm"
        .cerror * > SCREEN + 1000, "REU start-up code overflows the screen"
        #MEMFREE "REU start-up (screen)", SCREEN + 1000 - *
        .here
stage_end
init_stage
        .logical INIT_RUN
; zero page used during init only (editor owns $40-$ff afterwards)
zp_ptr   = $fb
zp_ptr2  = $fd
cs_src   = $f7                  ; copy_stage: source, dest, length (this order)
cs_dst   = $f9
cs_cnt   = $fb

start
        sei
        cld
        ldx #$ff
        txs
        lda #BANK_ALLRAM        ; staged code and text to their places
        sta $01
        inx                     ; 0 (from $ff)
        jsr copy_stage
        lda #BANK_RAMIO
        sta $01
        ldx #6
        jsr copy_stage
        ldx #12
        jsr copy_stage
        ldx #18
        jsr copy_stage
        lda #$7f                ; all CIA interrupts off, clear pending
        sta CIA1+$0d
        sta CIA2+$0d
        lda CIA1+$0d
        lda CIA2+$0d
        lda #0                  ; no raster IRQ until the editor installs one
        sta VIC+$1a
        lda #$ff
        sta VIC+$19
        lda #<default_irq
        sta $fffe
        lda #>default_irq
        sta $ffff
        lda #<default_irq       ; player_init replaces the NMI vector
        sta $fffa
        lda #>default_irq
        sta $fffb
        jsr sid_probe           ; SID model, second SID (boot_sid.asm)
        jsr reu_boot            ; REU: size, overlays, header (boot_reu.asm)
        jsr fio_clean
        lda rec_on
        beq +
        jsr reu_recover         ; crash/reset recovery: the undo mirror
        jmp ++
+       jsr load_demo
+       jsr player_init
        jmp late                ; RES2 + OVWIN, editor_init, editor_main

default_irq
        rti

; copy one staged block: X = 0 help text, 6 editor high code
copy_stage
        ldy #0
-       lda stage_tab,x
        sta cs_src,y
        inx
        iny
        cpy #6
        bne -
        ldy #0
_loop   lda cs_cnt
        ora cs_cnt+1
        beq _done
        lda (cs_src),y
        sta (cs_dst),y
        inc cs_src
        bne +
        inc cs_src+1
+       inc cs_dst
        bne +
        inc cs_dst+1
+       lda cs_cnt
        bne +
        dec cs_cnt+1
+       dec cs_cnt
        jmp _loop
_done   rts

stage_tab
        .word stage_io, HELPTEXT, stage_hi - stage_io
        .word stage_hi, EDHI, stage_tmp - stage_hi
        .word stage_tmp, CLIPBUF, stage_boot - stage_tmp
        .word stage_boot, SCREEN + $200, stage_end - stage_boot

; Demo song: 3 channels looping rows 0-1. demo_data holds records, 0 ends:
;   1, phrase, step, note, instr, cmd, val
;   2, chain, step, phrase, transpose
;   3, row, slot, chain
;   4, instrument, 16 bytes
load_demo
        lda #<demo_data
        sta zp_ptr2
        lda #>demo_data
        sta zp_ptr2+1
_next   jsr demo_byte
        beq _done
        cmp #1
        beq _phrase
        cmp #2
        beq _chain
        cmp #3
        beq _song
        jsr demo_byte           ; instrument: INSTR + i*16 (i < 16 in the demo)
        asl
        asl
        asl
        asl
        sta zp_ptr
        lda #>INSTR
        sta zp_ptr+1
        ldx #16
        bne _copy
_phrase jsr demo_byte           ; PHRASES + p*64 + step*4
        tax
        lsr
        lsr
        ora #>PHRASES
        sta zp_ptr+1
        txa
        and #3
        lsr
        ror
        ror
        sta zp_ptr
        jsr demo_byte
        asl
        asl
        ora zp_ptr
        sta zp_ptr
        ldx #4
        bne _copy
_chain  jsr demo_byte           ; CHAINS + c*32 + step*2
        tax
        lsr
        lsr
        lsr
        ora #>CHAINS
        sta zp_ptr+1
        txa
        asl
        asl
        asl
        asl
        asl
        sta zp_ptr
        jsr demo_byte
        asl
        ora zp_ptr
        sta zp_ptr
        ldx #2
        bne _copy
_song   jsr demo_byte           ; SONG + slot*256 + row
        sta zp_ptr
        jsr demo_byte
        clc
        adc #>SONG
        sta zp_ptr+1
        ldx #1
_copy   ldy #0                  ; copy X bytes from the stream to (zp_ptr)
-       jsr demo_byte
        sta (zp_ptr),y
        iny
        dex
        bne -
        beq _next
_done   rts

; next byte of demo_data in A (flags set), Y preserved
demo_byte
        sty _y+1
        ldy #0
        lda (zp_ptr2),y
        inc zp_ptr2
        bne _y
        inc zp_ptr2+1
_y      ldy #0
        ora #0
        rts

CMD_K = 11
CMD_C = 3
NOTE  .function n, oct
        .endf (n + oct*12)
C_ = 0
Ds = 3
F_ = 5
G_ = 7
As = 10

        .include "editor/boot_sid.asm"
        .cerror * > SCREEN, "start-up code runs into the screen"
demo_data
        ; instruments: flags wave AD SR pwlo pwhi pwspd cut resmode fsweep hr hrsr vib vibdly table tblspd
        .byte 4, 0, $09,$40,$09,$a6,$00,$06,$00,$30,$81,$fe,$20,$00,$00,$00,$ff,$00 ; bass, filter own LP
        .byte 4, 1, $01,$40,$09,$a9,$00,$14,$18,$00,$00,$00,$20,$00,$34,$0a,$ff,$00 ; lead, PW sweep up, vibrato
        .byte 4, 2, $00,$10,$06,$00,$00,$08,$00,$00,$00,$00,$00,$00,$00,$00,$ff,$00 ; kick (triangle, M2 adds tables)
        .byte 4, 3, $00,$80,$02,$00,$00,$08,$00,$00,$00,$00,$00,$00,$00,$00,$ff,$00 ; hat (noise)
        .byte 4, 4, $00,$80,$06,$00,$00,$08,$00,$00,$00,$00,$00,$00,$00,$00,$ff,$00 ; snare (noise)
        ; phrase 00: bass
        .byte 1, 0, 0, NOTE(C_,2), 0, 0, 0
        .byte 1, 0, 3, NOTE(C_,2), 0, CMD_K, 2
        .byte 1, 0, 4, NOTE(C_,3), 0, 0, 0
        .byte 1, 0, 6, NOTE(C_,2), 0, 0, 0
        .byte 1, 0, 8, NOTE(Ds,2), 0, 0, 0
        .byte 1, 0, 10, NOTE(F_,2), 0, 0, 0
        .byte 1, 0, 12, NOTE(G_,2), 0, 0, 0
        .byte 1, 0, 14, NOTE(As,1), 0, 0, 0
        ; phrase 01: lead
        .byte 1, 1, 0, NOTE(G_,4), 1, 0, 0
        .byte 1, 1, 6, NOTE(As,4), 1, 0, 0
        .byte 1, 1, 8, NOTE(C_,5), 1, CMD_C, $37
        .byte 1, 1, 14, NOTE(G_,4), 1, CMD_K, 3
        ; phrase 02: lead answer
        .byte 1, 2, 0, NOTE(F_,4), 1, 0, 0
        .byte 1, 2, 4, NOTE(Ds,4), 1, 0, 0
        .byte 1, 2, 8, NOTE(C_,4), 1, 0, 0
        ; phrase 03: drums
        .byte 1, 3, 0, NOTE(C_,1), 2, 0, 0
        .byte 1, 3, 2, NOTE(C_,6), 3, 0, 0
        .byte 1, 3, 4, NOTE(C_,4), 4, 0, 0
        .byte 1, 3, 6, NOTE(C_,6), 3, 0, 0
        .byte 1, 3, 8, NOTE(C_,1), 2, 0, 0
        .byte 1, 3, 10, NOTE(C_,6), 3, 0, 0
        .byte 1, 3, 12, NOTE(C_,4), 4, 0, 0
        .byte 1, 3, 14, NOTE(C_,6), 3, 0, 0
        ; chains: 00 bass (transpose 0, then +5), 01 lead, 02 drums
        .byte 2, 0, 0, 0, 0
        .byte 2, 0, 1, 0, 5
        .byte 2, 1, 0, 1, 0
        .byte 2, 1, 1, 2, 0
        .byte 2, 2, 0, 3, 0
        .byte 2, 2, 1, 3, 0
        ; song rows 0-1
        .byte 3, 0, 0, 0
        .byte 3, 0, 1, 1
        .byte 3, 0, 2, 2
        .byte 3, 1, 0, 0
        .byte 3, 1, 1, 1
        .byte 3, 1, 2, 2
        .byte 0
        .cerror * > INIT_RUN + $300, "start-up code overflows $0200-$04ff"
        #MEMFREE "INIT_RUN", INIT_RUN + $300 - *
        .cerror * > SCREEN + $200, "start-up data runs into the REU start-up code"
        .cerror INIT_RUN != RES2 || RES2 + $100 != OVWIN, "INIT_RUN layout: RES2, OVWIN"
        .here
        .cerror * > $a000, "staged blocks beyond BASIC LOAD range"
        #MEMFREE "staging (to $a000)", $a000 - *
