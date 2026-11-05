; Factory instrument presets. Lives in RAM under I/O
; right after the help text (main.asm stages both at HELPTEXT); low.asm reads
; it with $01 = BANK_ALLRAM and IRQs off (pre_fetch, pre_name, tpl_load).
; Tuned for the 8580. Ids 0-5 keep their pre-library meaning.
;
; Instrument bytes per preset, as in defs.inc, except: flags without the id
; (apply_preset adds it), byte $E = table template ($ff none). Stored as a
; bit mask of the bytes that differ from preset 0 (PRESET_DEF, form.asm)
; plus those bytes; pd_ofs = offset of each record.
;
; Drums play best around C-4 (the preview note): their tables transpose.
;        name      flags wave AD  SR  pwlo pwhi spd cut res fsw hr hrsr vib vdly tpl tspd
PRESETS := [("custom", [$01,$40,$09,$a0,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,$ff,$00])]  ; 0 basic
PRESETS ..= [("lead",  [$01,$40,$09,$a9,$00,$14,$18,$00,$00,$00,$20,$00,$34,$0a,$ff,$00])]  ; 1 PW up, vibrato
PRESETS ..= [("bass",  [$09,$40,$09,$a6,$00,$06,$00,$30,$81,$fe,$20,$00,$00,$00,$ff,$00])]  ; 2 own LP, sweep down
PRESETS ..= [("drum",  [$00,$80,$08,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,  0,$00])]  ; 3
PRESETS ..= [("pad",   [$01,$20,$88,$8a,$00,$08,$00,$00,$00,$00,$20,$00,$22,$20,$ff,$00])]  ; 4
PRESETS ..= [("arp",   [$01,$40,$00,$f4,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,  1,$01])]  ; 5 0/4/7
PRESETS ..= [("kick",  [$00,$40,$07,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,  3,$00])]  ; 6 drums
PRESETS ..= [("snare", [$00,$40,$08,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,  4,$00])]  ; 7
PRESETS ..= [("clhat", [$00,$80,$03,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,  5,$00])]  ; 8
PRESETS ..= [("ophat", [$00,$80,$08,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,  5,$00])]  ; 9
PRESETS ..= [("tom",   [$00,$40,$09,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,  6,$00])]  ; 10
PRESETS ..= [("clap",  [$00,$80,$07,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,  7,$00])]  ; 11
PRESETS ..= [("rim",   [$00,$40,$04,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,  8,$00])]  ; 12
PRESETS ..= [("crash", [$00,$80,$0a,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,  5,$00])]  ; 13
PRESETS ..= [("pulsbs",[$01,$40,$08,$a6,$00,$34,$20,$00,$00,$00,$20,$00,$00,$00,$ff,$00])]  ; 14 basses: PWM
PRESETS ..= [("sawbas",[$01,$20,$08,$a6,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,$ff,$00])]  ; 15
PRESETS ..= [("acid",  [$09,$20,$09,$86,$00,$08,$00,$70,$c1,$fa,$20,$00,$00,$00,$ff,$00])]  ; 16 own LP res 12, cutoff falls
PRESETS ..= [("subbas",[$01,$10,$08,$c8,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,$ff,$00])]  ; 17 triangle
PRESETS ..= [("fatbas",[$09,$40,$08,$a7,$00,$36,$18,$38,$41,$00,$20,$00,$00,$00,$ff,$00])]  ; 18 PWM + own LP
PRESETS ..= [("pwmld", [$01,$40,$08,$a9,$00,$38,$20,$00,$00,$00,$20,$00,$35,$10,$ff,$00])]  ; 19 leads
PRESETS ..= [("sawld", [$01,$20,$09,$a9,$00,$08,$00,$00,$00,$00,$20,$00,$34,$0c,$ff,$00])]  ; 20
PRESETS ..= [("sync",  [$01,$22,$09,$a9,$00,$08,$00,$00,$00,$00,$20,$00,$34,$0c,$ff,$00])]  ; 21 saw synced to the previous voice
PRESETS ..= [("ring",  [$01,$14,$0a,$0a,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,$ff,$00])]  ; 22 triangle ring-modulated by the previous voice
PRESETS ..= [("slowpd",[$09,$20,$b8,$ac,$00,$08,$00,$20,$81,$01,$20,$00,$23,$20,$ff,$00])]  ; 23 pads: own LP opens slowly
PRESETS ..= [("pwmpad",[$01,$40,$98,$9b,$00,$38,$0c,$00,$00,$00,$20,$00,$22,$20,$ff,$00])]  ; 24
PRESETS ..= [("string",[$01,$20,$68,$8a,$00,$08,$00,$00,$00,$00,$20,$00,$33,$18,$ff,$00])]  ; 25
PRESETS ..= [("major", [$01,$20,$00,$f4,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,  9,$01])]  ; 26 arps: 0/4/7/12
PRESETS ..= [("minor", [$01,$40,$00,$f4,$00,$38,$20,$00,$00,$00,$20,$00,$00,$00, 10,$01])]  ; 27 0/3/7/12
PRESETS ..= [("octave",[$01,$40,$00,$f4,$00,$04,$00,$00,$00,$00,$20,$00,$00,$00, 11,$01])]  ; 28 0/12
PRESETS ..= [("laser", [$01,$40,$0a,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00, 12,$00])]  ; 29 fx: +24, falls 1 semitone a tick
PRESETS ..= [("noisup",[$01,$80,$c0,$f8,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00, 13,$00])]  ; 30 noise rising
PRESETS ..= [("zap",   [$01,$20,$06,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00, 12,$00])]  ; 31
        .cerror len(PRESETS) != NPRESETS, "preset count"
        .cerror any(PRESETS[0][1] != PRESET_DEF), "preset 0 is the default instrument"

; category starts (SPACE+Up/Down on the PRESET field): basic, drums, basses,
; leads, pads, arps, fx (low.asm holds the copy pre_cat)
PRESET_CATS = [0, 6, 14, 19, 23, 26, 29]

; Table templates: rows (ctl, transpose, c); c = 0 none, $10-$1f = H to row
; c & 15, else P (pitch bend, 1/64 semitone per tick) with value c. Rows
; after the template are empty ($ff, 0, ...); command 2 is always empty.
; Template 2 = empty table (TPL_EMPTY).
TPLS := [[($81,$00,0), ($41,$fb,0), ($41,$f6,0), ($41,$f1,$13)]]                     ; 0 drum (pre-library)
TPLS ..= [[($ff,$00,0), ($ff,$04,0), ($ff,$07,$10)]]                                 ; 1 arp 0/4/7
TPLS ..= [[]]                                                                         ; 2 empty
TPLS ..= [[($81,$00,0), ($41,$f4,0), ($41,$ee,0), ($11,$ea,0), ($11,$e7,$14)]]        ; 3 kick: noise click, pulse/tri falling 2 octaves
TPLS ..= [[($81,$18,0), ($41,$fe,0), ($41,$fa,0), ($81,$14,$13)]]                     ; 4 snare: noise, pulse body, noise tail
TPLS ..= [[($81,$22,$10)]]                                                           ; 5 hat / crash: bright noise
TPLS ..= [[($81,$0c,0), ($41,$fe,0), ($11,$fc,0), ($11,$fa,0), ($11,$f8,$14)]]        ; 6 tom
TPLS ..= [[($81,$1e,0), ($88,$1e,0), ($81,$1e,0), ($88,$1e,0), ($81,$1c,$14)]]        ; 7 clap: noise bursts (test bit mutes)
TPLS ..= [[($81,$18,0), ($41,$0c,0), ($41,$07,$12)]]                                 ; 8 rim
TPLS ..= [[($ff,$00,0), ($ff,$04,0), ($ff,$07,0), ($ff,$0c,$10)]]                     ; 9 major
TPLS ..= [[($ff,$00,0), ($ff,$03,0), ($ff,$07,0), ($ff,$0c,$10)]]                     ; 10 minor
TPLS ..= [[($ff,$00,0), ($ff,$0c,$10)]]                                              ; 11 octave
TPLS ..= [[($ff,$18,$c0), ($ff,$18,$11)]]                                            ; 12 laser / zap
TPLS ..= [[($ff,$00,$20), ($ff,$00,$11)]]                                            ; 13 noise up
        .cerror len(TPLS) != NTPL, "template count"

        .enc "screen"
pd_names                                ; PRE_NAMELEN characters each
        .for _p in PRESETS
        .cerror len(_p[0]) > PRE_NAMELEN, "preset name too long"
        .text format("%-6s", _p[0])
        .endfor
        .enc "none"

pd_ofs                                  ; record offsets from pd_inst
pd_o    := 0
        .for _p in PRESETS
        .cerror pd_o > 255, "preset records exceed one page"
        .byte pd_o
pd_o    += 2
        .for _i in range(16)
        .if _p[1][_i] != PRESET_DEF[_i]
pd_o    += 1
        .endif
        .endfor
        .endfor

pd_inst
        .for _p in PRESETS
pd_m    := 0
        .for _i in range(16)
        .if _p[1][_i] != PRESET_DEF[_i]
pd_m    |= 1 << _i
        .endif
        .endfor
        .word pd_m
        .for _i in range(16)
        .if _p[1][_i] != PRESET_DEF[_i]
        .byte _p[1][_i]
        .endif
        .endfor
        .endfor

pd_tofs                                 ; template offsets from pd_tpl, NTPL + 1
pd_o    := 0
        .for _t in TPLS
        .byte pd_o
pd_o    += 3 * len(_t)
        .endfor
        .byte pd_o
        .cerror pd_o > 255, "templates exceed one page"
pd_tpl
        .for _t in TPLS
        .for _r in _t
        .byte _r
        .endfor
        .endfor

; Factory kits (kits.asm kit_factory, read by high.asm kit_get): KIT_LEN
; preset ids each, then the 8-character names; the REU kits after NKITS
; (xpresets.asm XKITS, kit count k_nk)
NKALL   = len(KITS_ALL)
kit_ids
        .for _k in KITS_ALL
        .cerror len(_k[1]) != KIT_LEN, "kit length"
        .byte _k[1]
        .endfor
        .enc "screen"
kit_names
        .cerror kit_names - kit_ids != NKALL * KIT_LEN, "kit tables"
        .for _k in KITS_ALL
        .text format("%-8s", _k[0])
        .endfor
        .enc "none"

