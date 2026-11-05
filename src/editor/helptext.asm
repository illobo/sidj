; Help line per field (max 40 characters), H_* = index (text.asm).
; Lives in RAM under I/O at HELPTEXT: main stages it in the .prg and copies it
; there at start-up; draw_help copies one string out with $01 = $34.
        .enc "screen"
helps
_h0     .null "chain 00-7f  spc spc:new  ret:play song"
_h1     .null "phrase 00-fe  spc spc:new  ret:play ch"
_h2     .null "transpose  spc+l/r:1  spc+u/d:12"
_h3     .null "note  spc+l/r:semi u/d:oct  type a-g 0-7"
_h4     .null "instrument 00-3f  ctrl+right:edit"
_h5     .null "command a-z  type a letter  c=+spc:clear"
_h6     .null "command value 00-ff  spc+u/d:10"
_h7     .null "ctrl+crsr:move on the map"
_h8     .null "number  spc+crsr or type  c=+l/r:prev/nx"
_h9     .null "preset spc+l/r u/d:group  ctrl+spc:kit"
_h10    .null "waveform bit  spc+crsr:toggle"
_h11    .null "byte 00-ff  spc+l/r:1  spc+u/d:10  type"
_h12    .null "nibble 0-f  spc+l/r:1  spc+u/d:4  type"
_h13    .null "pulse width 000-fff  spc+l/r:10 u/d:100"
_h14    .null "choice  spc+l/r  spc+u/d"
_h15    .null "filter type: l=low b=band h=high 3=v3off"
_h16    .null "signed byte  spc+l/r:1  spc+u/d:10"
_h17    .null "table  spc spc:new  ctrl+right:edit"
_h18    .null "table ctl: sid control byte  --:no write"
_h19    .null "table transpose  spc+l/r:1  spc+u/d:12"
_h20    .null "groove ticks per step  --:end, loops"
_h21    .null "tempo 40-295 bpm  spc+l/r:1 u/d:10 type"
_h22    .null "global transpose  spc+l/r:1  u/d:12"
_h23    .null "project name: type a-z 0-9  spc+crsr"
_h24    .null "spc: load save clean(x2)"
_h25    .null "cutoff 00-ff (bits 3-10)  spc+u/d:10"
_h26    .null "mark: c=:copy ctrl+spc:cut spc+crsr:edit"
_h27    .null "spc:save/load(x2) c=+spc:delete(x2)"
_h28    .null "clone: deep copies phrases, slim shares"
_h29    .null "1351 mouse: port, speed 0-3, accelerate"
_h30    .null "click:mute  right click:solo"
_h31    .null "click:queue twice:phrase end right:stop"
_h32    .null "grid c=+l/r:field click:on/off home:list"
_h33    .null "home or click: grid / list  clr: drums"
_h34    .null "cutoff: drag=latch  right/c=+click:free"
_h35    .null "res: drag=latch  right/c=+click:free"
_h36    .null "filter: click lp bp hp 3o  right:free"
_h37    .null "volume: drag=latch  right/c=+click:free"
_h38    .null "tap:click in time  <>:nudge  bar:tempo"
_h39    .null "transp: drag=latch  right/c=+click:free"
_h40    .null "drum spc:hit spc+u/d:pitch c=+u/d:lanes"
_h41    .null "piano +-:octave"
        .enc "none"
; X = help index: its string -> HELPBUF (M10: a pointer per 8 strings, the
; rest scanned: <= 7 strings, ~3000 cycles). Called with $01 = BANK_ALLRAM
; and IRQs off.
help_copy = *                   ; (an assignment: the _h* labels stay in scope)
        txa
        lsr
        lsr
        lsr
        tay
        lda hc_lo,y
        sta ptr
        lda hc_hi,y
        sta ptr+1
        txa
        and #7
        tax
_str    dex
        bmi _copy
        ldy #$ff                ; skip a string: ptr += its length + 1
-       iny
        lda (ptr),y
        bne -
        tya
        sec
        adc ptr
        sta ptr
        bcc _str
        inc ptr+1
        bcs _str
_copy   ldy #0
-       lda (ptr),y
        sta HELPBUF,y
        beq +
        iny
        bne -
+       rts
hc_lo   .byte <_h0, <_h8, <_h16, <_h24, <_h32, <_h40
hc_hi   .byte >_h0, >_h8, >_h16, >_h24, >_h32, >_h40

