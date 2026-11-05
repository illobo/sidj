; Editor code under the KERNAL at EDHI ($fd00-$fff9), staged by main.asm.
; Runs with $01 = BANK_RAMIO like the rest of the editor; never called while
; fileio has the KERNAL banked in.
;
; REU support: the DMA helper, undo keys, the File
; screen device (drive or REU slots). The undo code itself is split by tier:
;   res.asm          RES2 ($0200): every tier (gesture tracking, reset)
;   ov_undo_reu.asm  overlay 0 in OVWIN ($0300) when an REU is present
;   ov_undo_c.asm    OVWIN for good without an REU (tier C)
; OVWIN entry points, the same in both undo images:
OV_SNAP = OVWIN+0               ; a gesture starts (tier C: snapshot)
OV_STEP = OVWIN+3               ; X pages of the scan (0 = all), u_state 0 when done
OV_KEY  = OVWIN+6               ; u_t = 0 undo, 1 redo: A = 0 (Z) nothing to do

; ---------------------------------------------------------------------------
; Undo / redo. F7 undo, SHIFT+F7 (F8) redo.
; Unit: one gesture = everything done from the first frame with input (key,
; button, mouse button) until all input is released. Song data = pages
; $80-$cf and $e0-$f9 (phrases, chains, song, instruments, tables, grooves,
; header, allocation); the clipboard and editor state are not undone.
;
; REU (tiers A/B): bank 0 mirrors the song data at the same offsets (the
; state after the last recorded gesture). When a gesture ends, a scan
; compares each page with its mirror (REU verify, 16 pages a frame while
; idle; finished at once when new input comes) and logs every changed page:
; 256 old bytes in a slot of bank 1 (256 slots, a ring; the oldest gesture
; is dropped when full). META (RAM under I/O) holds per slot page - $80 and
; bit 7 = first page of a gesture. Undo swaps a gesture's slots with the
; live pages (the slots then hold the redo data), redo swaps them back; a
; new gesture drops the redo part. The mirror doubles as the crash/reset
; recovery image (header RH_VALID, cleared while undo_reset rewrites it).
;
; No REU (tier C): one step. At the start of a gesture the page holding the
; object under the cursor (field_ptr) and the allocation page are copied
; into a pair of 512-byte buffers under I/O; if the gesture changed them,
; that pair becomes the record and undo/redo swap it with the live pages.
; Changes outside these two pages are not undone without an REU.
; ---------------------------------------------------------------------------
REU     = $df00
META    = IORAM_FREE            ; REU mode: 256 bytes, see above
FB      = IORAM_FREE            ; no REU: pairs at $dc00 / $de00
UPAGE0  = >PHRASES              ; data pages: $80-$cf, $e0-$f9
UPAGE_A = >SONG
UPAGE_END = (>ALLOC_CHAINS) + 1
SCANSTEP = 16                   ; pages verified per idle frame
        .cerror (UPAGE_END - UPAGE_A) + ((>CHAINS) + $10 - UPAGE0) != REU_SLOTPAGES, "REU_SLOTPAGES"

; A = command ($90 stash, $91 fetch, $92 swap, $93 verify) with the rx
; block (REU register order: C64 address, REU address, bank, length).
; Returns the status (b5 = verify found a difference). X, Y clobbered.
; Main context only (never from an interrupt); at most 256 bytes while the
; song can play (the DMA halts the CPU and delays the player NMI).
reu_xfer
        tay
        ldx #6
-       lda rx,x
        sta REU+2,x
        dex
        bpl -
        inx
        stx REU+9               ; no REU interrupts
        stx REU+$a              ; both addresses count up
        sty REU+1
        lda REU
        rts

; A = command, X = C64 page, Y = REU page in bank u_bank: 256 bytes
reu_page
        stx rx+1
        sty rx+3
        ldx u_bank
        stx rx+4
        ldx #0
        stx rx
        stx rx+2
        stx rx+5
        inx
        stx rx+6
        bne reu_xfer

; --- keys ------------------------------------------------------------------
; on_key: A = F-key index (KC - KC_F1) from 3: F7 undo, F8 redo, F2 help
undo_key
        cmp #KC_F2-KC_F1
        beq help_open
        sec                     ; (the compare above may clear C)
        sbc #KC_F7-KC_F1
        beq +
        cmp #KC_F8-KC_F7
        bne _r
        lda #1
+       sta u_t                 ; 0 undo, 1 redo
        jsr u_settle
        lda HD_TEMPO
        sta u_tempo
        jsr OV_KEY
        beq _none
        lda #RD_ALL
        ora dirty
        sta dirty
        lda HD_TEMPO
        cmp u_tempo
        beq +
        jsr player_set_tempo
+       lda #11                 ; "undo" / "redo"
        .byte $2c
_none   lda #0                  ; "nothing to ..."
        ldx u_t
        clc
        adc u_msg,x
        ldy #>s_undo
        jmp msg_set
_r      rts

        .enc "screen"
s_undo  .null "nothing to undo"
s_redo  .null "nothing to redo"
        .enc "none"
        .cerror (>s_undo) != (>(s_redo + 15)), "undo strings cross a page"
u_msg   .byte <s_undo, <s_redo

; --- Extended help: viewer = overlay OV_HELP, pages from SIDJ.HLP ------
; editor_main calls hp_mouse in place of mouse_input and hp_update in place
; of update. While the viewer is open (hp_on) the overlay gets every frame's
; keys and mouse buttons, the editor sees no input and nothing is redrawn.
hp_mouse
        lda hp_on
        bne hp_on1
        jsr mouse_input
        lda m_pr                ; left click on the help row: open (REU only)
        lsr
        bcc hp_r
        lda m_row
        cmp #24
        bne hp_r
        lda u_reu
        beq hp_r
help_open                       ; F2 (on_key) or the click above
        lda #<s_nreu
        ldy #>s_nreu
        ldx u_reu
        beq hp_msg
        lda #<s_nohlp
        ldy #>s_nohlp
        ldx hp_n
        beq hp_msg
        ldx #0                  ; X = 0 open, 1 one frame
        .byte $2c
hp_on1  ldx #1
        lda #OV_HELP
        jsr ov_call
        lda #0                  ; the viewer took this frame's input
        sta press
        sta m_pr
        sta m_rl
        sta m_btn
        lda #KC_NONE
        sta key
hp_r    rts
hp_msg  jmp msg_set

hp_update
        lda hp_on
        bne hp_r
        jmp update

; --- Extended presets (R2, REU): 32-byte records from bank 0 REU_XPPG ------
; (xpresets.asm). Entered from low.asm with C set (its compare):
; xp_inst A = id -> pbuf, xp_name A = id -> pnbuf, xp_tpl X = template -> tplbuf
xp_tpl  txa
        adc #XP_N - NTPL - 1    ; C set: record XP_N + X - NTPL
        ldy #2
        bne xp_get
xp_name ldy #1
        .byte $2c
xp_inst ldy #0
        sbc #NPRESETS
; A = record, Y = 0 instrument bytes, 1 name, 2 template
xp_get  ldx #0
        stx rx+4
        stx rx+6
        pha
        lsr
        lsr
        lsr
        ora #REU_XPPG
        sta rx+3
        pla
        asl
        asl
        asl
        asl
        asl
        ora xp_ofs,y
        sta rx+2
        lda xp_dst,y
        sta rx
        lda xp_dhi,y
        sta rx+1
        lda xp_len,y
        sta rx+5
        lda #$91
        jmp reu_xfer
xp_ofs  .byte 0, 16, 0
xp_dst  .byte <pbuf, <pnbuf, <tplbuf
xp_dhi  .byte >pbuf, >pnbuf, >tplbuf
xp_len  .byte 16, PRE_NAMELEN, 32

; pre_id tail: A = stored id (Z from it). 0 and the instrument at fb is the
; one an extended preset was applied to last: that id
xp_id   bne +
        lda fb
        eor fb+1                ; instrument key (fb low nibble is 0)
        cmp p_exf
        bne _z
        lda p_ext
        rts
_z      lda #0
+       rts

; apply_preset: remember the instrument and an extended id; A = p_v = the id
; to store (0 for an extended one)
xp_mark lda fb
        eor fb+1
        sta p_exf
        ldx #0
        lda p_v
        cmp #NPRESETS
        bcc +
        tax
        lda #0
        sta p_v
+       stx p_ext
        rts

; kits.asm kit_factory: A = byte X of the factory kit tables (presetdata.asm,
; RAM under I/O: ids at 0, names at NKALL * KIT_LEN). Y kept.
kit_get php
        sei
        lda #BANK_ALLRAM
        sta $01
        lda kit_ids,x
        pha
        lda #BANK_RAMIO
        sta $01
        pla
        plp
        rts

; --- File screen device: drive (fio_*) or REU slots (overlay OV_SLOTS) -----
; A = 0 save, 1 load (X = entry), 2 directory, 3 delete (X = entry), through
; fio_call (message on the help line, C set = error)
file_op ldy f_reu
        bne _reu
        tay
        lda fop_lo,y
        pha
        lda fop_hi,y
        tay
        pla
        jmp fio_call
_reu    sta rs_op
        lda #<rs_go
        ldy #>rs_go
        jmp fio_call
rs_go   ldy rs_op
        lda #OV_SLOTS
        jmp ov_call
fop_lo  .byte <fio_save, <fio_load, <fio_dir, <fio_delete
fop_hi  .byte >fio_save, >fio_load, >fio_dir, >fio_delete

; CRSR left/right on the File screen: switch drive / REU (when it has slots)
file_dev
        lda r_nslots
        bne +
        ldx #<s_nreu
        lda u_reu
        beq _m
        ldx #<s_small
_m      txa
        ldy #>s_nreu
        jmp msg_set
+       lda f_reu
        eor #1
        sta f_reu
        jsr file_dir
        jmp file_scroll

; File panel: the device
dev_show
        lda f_reu
        bne +
        lda fio_device
        jmp puthex
+       jsr prt
        .enc "screen"
        .null "reu"
        rts
s_nreu  .null "needs reu"
s_small .null "reu too small"
s_nohlp .null "no help file"
s_fp5   .null "crsr l/r device"
        .enc "none"
        .cerror (>s_nreu) != (>s_small), "device strings cross a page"

; --- REU slots: resident part of overlay OV_SLOTS (ov_slots.asm) ---------
; X = message: to fio_msg, padded; "-" for free slots in FIO_DIR
os_end  php
        ldy #0
-       lda os_m,x
        beq +
        sta fio_msg,y
        inx
        iny
        bne -
+       lda #$20
-       sta fio_msg,y
        iny
        cpy #20
        bcc -
        ldx #0
-       lda FIO_DIR,x
        jsr _free
        sta FIO_DIR,x
        lda FIO_DIR+$100,x
        jsr _free
        sta FIO_DIR+$100,x
        txa
        sbx #256-16             ; X += 16
        bne -
        plp
        rts
_free   cmp #$ff
        bne +
        lda #$2d                ; "-"
+       clc
        rts

; slot directory (bank 0 REU_DIRPG, 2 pages) -> FIO_DIR (os_rdir; also
; FIO_DIRCOUNT = r_nslots) or back (os_wdir2)
os_rdir lda r_nslots
        sta FIO_DIRCOUNT
        lda #$91
        .byte $2c
os_wdir2
        lda #$90
        ldy #REU_DIRPG
        sta os_cmd
        ldx #>FIO_DIR
        jsr reu_page
        ldx #(>FIO_DIR) + 1
        ldy #REU_DIRPG + 1
        lda os_cmd
        jmp reu_page

; ptr = FIO_DIR entry of os_slot, Y = 0
os_ptr  lda os_slot
        ldx #>FIO_DIR
        cmp #16
        bcc +
        inx
+       asl
        asl
        asl
        asl
        sta ptr
        stx ptr+1
        ldy #0
        rts

        .enc "screen"
os_m
om_save  .null "saved to reu"
om_load  .null "loaded from reu"
om_del   .null "slot deleted"
om_empty .null "empty slot"
om_full  .null "reu slots full"
om_list  .null "reu slots"
        .enc "none"


; variables (last in EDHI: tests compare the code before edhi_vars)
edhi_vars
f_reu   .byte 0                 ; File screen device: 0 = drive (fio_device), 1 = REU slots
r_nslots .byte 0                ; REU project slots (0: device REU unavailable), set at start-up
rs_op   .byte 0
hp_on   .byte 0                 ; 1 = the help viewer is open
hp_n    .byte 0                 ; help pages loaded from SIDJ.HLP (0 = none), set at start-up
hp_pg   .byte 0                 ; page shown
hp_mb   .byte 0                 ; mouse buttons last seen by the viewer
p_ext   .byte 0                 ; extended preset applied last (0 none) ...
p_exf   .byte 0                 ; ... to the instrument with this key (fb lo eor hi)
p_last  .byte NPRESETS-1        ; last preset id: + XP_N with an REU (start-up)
p_ncat  .byte NCATS             ; preset categories: + NXCATS with an REU
p_ntl   .byte NTPL-1            ; last table template: + XP_NT with an REU
k_nk    .byte NKITS             ; factory kits: + NXKITS with an REU

; Piano mode (loop.asm, M9): the jamming key let go -> gate off, unless the
; channel plays (its own notes go on)
jam_release
        lda jam_pos
        bmi _r
        lsr
        lsr
        lsr
        tax
        lda jam_pos
        and #7
        tay
        lda kb_mat,x
        and bitmask,y
        bne _r
        lda #$ff
        sta jam_pos
        ldx jam_ch
        lda pl_playing
        and bitmask,x
        bne _r
        jmp player_note_off
_r      rts

; variables: editor zero page $e0-$f9 (free elsewhere; fileio saves it)
u_reu   = $e0      ; highest REU bank, 0 = no REU (start-up)
u_state = $e1      ; 0 idle, 1 gesture, 2 scanning
u_head  = $e2      ; REU: next slot
u_base  = $e3      ;      oldest slot
u_top   = $e4      ;      end of the redo slots
u_gs    = $e5      ;      $80 = next record starts a gesture
u_p     = $e6      ;      scan page
u_cnt   = $e7
u_bank  = $e8      ; REU bank for reu_page (0 except while used)
u_s     = $e9
u_t     = $ea
u_tempo = $eb
fb_pair = $ec      ; no REU: pair taking the snapshot
fb_sp   = $ed      ;   its cursor page (0 none)
fb_rp   = $ee      ;   cursor page of the record (other pair)
fb_rs   = $ef      ;   0 none, 1 undo there, 2 redo there
fb_pg   = $f0
fb_op   = $f1
fb_diff = $f2
rx      = $f3      ; [7] reu_xfer: C64 address, REU address, bank, length
        .cerror rx + 6 > $f9, "undo / REU zero page"
