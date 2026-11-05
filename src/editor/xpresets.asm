; Extended preset library: REU only. Staged in the
; .prg (main.asm stage_xp) and stashed at start-up to REU bank 0 page
; REU_XPPG (boot_reu.asm); read back one record at a time by xp_get (high.asm).
; Same recipes as presetdata.asm, tuned for the 8580.
;
; Ids NPRESETS.. (20-49): record id - NPRESETS, 32 bytes: the 16 instrument
; bytes (flags without the id, byte $E = table template: NTPL.. = extended,
; $ff none), the name (PRE_NAMELEN screen codes) at +16, 10 unused bytes
; (staged without them: XP_REC bytes, stashed one record at a time). Then the
; extended templates NTPL.., one record each: the template as tpl_load
; builds it in tplbuf (rows 0-7 of columns 0-3, col*8 + row).
; Applying an extended preset stores id 0 (custom) in the instrument; the
; name shows while that instrument is the one last given a preset (xp_id).
;
;        name      flags wave AD  SR  pwlo pwhi spd cut res fsw hr hrsr vib vdly tpl tspd
XPRESETS := [("808kik",[$00,$10,$0b,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00, 14,$00])]  ; 20 drums: triangle boom
XPRESETS ..= [("hrdkik",[$00,$40,$08,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00, 15,$00])] ; 21 punchy
XPRESETS ..= [("shtkik",[$00,$40,$05,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,  3,$00])] ; 22 short
XPRESETS ..= [("elsnar",[$00,$80,$07,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00, 16,$00])] ; 23 tight
XPRESETS ..= [("bigsnr",[$00,$80,$0a,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00, 17,$00])] ; 24 long tail
XPRESETS ..= [("mtlhat",[$00,$80,$04,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00, 18,$00])] ; 25 noise/pulse
XPRESETS ..= [("pdlhat",[$00,$80,$01,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,  5,$00])] ; 26 very short
XPRESETS ..= [("ride",  [$00,$80,$0a,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00, 18,$00])] ; 27
XPRESETS ..= [("cowbel",[$00,$40,$06,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00, 19,$00])] ; 28 12/19 alternating
XPRESETS ..= [("eltom", [$00,$10,$09,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00, 20,$00])] ; 29 bends down
XPRESETS ..= [("shaker",[$00,$80,$34,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,  5,$00])] ; 2A soft attack
XPRESETS ..= [("blip",  [$00,$40,$06,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00, 28,$00])] ; 2B +24/+12/0
XPRESETS ..= [("808bas",[$01,$10,$0b,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,$ff,$00])] ; 2C basses
XPRESETS ..= [("plckbs",[$01,$40,$08,$a6,$00,$06,$00,$00,$00,$00,$20,$00,$00,$00, 24,$00])] ; 2D octave on tick 0
XPRESETS ..= [("squbas",[$01,$40,$09,$a8,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,$ff,$00])] ; 2E 50 % pulse
XPRESETS ..= [("opnbas",[$09,$20,$09,$a9,$00,$08,$00,$20,$c1,$03,$20,$00,$00,$00,$ff,$00])] ; 2F own LP res 12, opens
XPRESETS ..= [("thinbs",[$01,$40,$08,$a6,$00,$11,$10,$00,$00,$00,$20,$00,$00,$00,$ff,$00])] ; 30 6 % pulse, PW up
XPRESETS ..= [("reso",  [$09,$40,$08,$a6,$00,$08,$00,$28,$f1,$fd,$20,$00,$00,$00,$ff,$00])] ; 31 own LP res 15, falls
XPRESETS ..= [("syncbs",[$01,$22,$08,$a6,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,$ff,$00])] ; 32 saw synced
XPRESETS ..= [("combbs",[$01,$60,$08,$a6,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00,$ff,$00])] ; 33 saw+pulse (8580)
XPRESETS ..= [("chipld",[$01,$40,$09,$a9,$00,$02,$00,$00,$00,$00,$20,$00,$25,$08,$ff,$00])] ; 34 leads: 12 % pulse
XPRESETS ..= [("squld", [$01,$40,$09,$a9,$00,$08,$00,$00,$00,$00,$20,$00,$34,$10,$ff,$00])] ; 35 50 % pulse
XPRESETS ..= [("vibld", [$01,$20,$09,$a9,$00,$08,$00,$00,$00,$00,$20,$00,$48,$00,$ff,$00])] ; 36 deep vibrato
XPRESETS ..= [("brass", [$09,$20,$68,$a9,$00,$08,$00,$10,$21,$02,$20,$00,$00,$00,$ff,$00])] ; 37 own LP opens
XPRESETS ..= [("flute", [$01,$10,$58,$a9,$00,$08,$00,$00,$00,$00,$20,$00,$23,$14,$ff,$00])] ; 38 triangle, slow
XPRESETS ..= [("chime", [$01,$10,$0a,$0a,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00, 24,$00])] ; 39
XPRESETS ..= [("pwmfst",[$01,$40,$09,$a9,$00,$34,$40,$00,$00,$00,$20,$00,$00,$00,$ff,$00])] ; 3A fast PW ping-pong
XPRESETS ..= [("combld",[$01,$50,$09,$a9,$00,$08,$00,$00,$00,$00,$20,$00,$34,$10,$ff,$00])] ; 3B tri+pulse (8580)
XPRESETS ..= [("sawpad",[$09,$20,$a8,$ac,$00,$08,$00,$40,$41,$00,$20,$00,$22,$20,$ff,$00])] ; 3C pads: own LP
XPRESETS ..= [("warmpd",[$01,$10,$b8,$ac,$00,$08,$00,$00,$00,$00,$20,$00,$22,$20,$ff,$00])] ; 3D triangle
XPRESETS ..= [("sweppd",[$09,$40,$c8,$ac,$00,$38,$08,$08,$61,$01,$20,$00,$00,$00,$ff,$00])] ; 3E PW ping-pong, LP opens
XPRESETS ..= [("choir", [$01,$40,$98,$9b,$00,$16,$06,$00,$00,$00,$20,$00,$33,$18,$ff,$00])] ; 3F PW up, vibrato
XPRESETS ..= [("sus4",  [$01,$40,$00,$f4,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00, 21,$01])] ; 40 arps: 0/5/7/12
XPRESETS ..= [("dom7",  [$01,$20,$00,$f4,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00, 22,$01])] ; 41 0/4/7/10
XPRESETS ..= [("power", [$01,$40,$00,$f4,$00,$04,$00,$00,$00,$00,$20,$00,$00,$00, 23,$01])] ; 42 0/7
XPRESETS ..= [("fstmaj",[$01,$40,$00,$f4,$00,$38,$20,$00,$00,$00,$20,$00,$00,$00,  9,$00])] ; 43 0/4/7/12 every tick
XPRESETS ..= [("siren", [$01,$40,$00,$f0,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00, 25,$00])] ; 44 fx: rises (P)
XPRESETS ..= [("stuttr",[$01,$40,$00,$f4,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00, 26,$00])] ; 45 gate 2 on, 2 off
XPRESETS ..= [("bomb",  [$01,$80,$0c,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00, 27,$00])] ; 46 noise falls (P)
XPRESETS ..= [("wind",  [$09,$80,$ca,$cc,$00,$08,$00,$20,$82,$01,$20,$00,$00,$00,$ff,$00])] ; 47 noise, own BP
XPRESETS ..= [("chirp", [$01,$20,$04,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00, 25,$00])] ; 48 short rise
XPRESETS ..= [("nsfall",[$01,$80,$0b,$00,$00,$08,$00,$00,$00,$00,$20,$00,$00,$00, 12,$00])] ; 49 noise, laser bend
XP_N    = len(XPRESETS)
XP_REC  = 16 + PRE_NAMELEN      ; staged bytes per preset
XP_LIST = XPRESETS
; category starts (SPACE + Up/Down with an REU): drums, basses, leads, pads, arps, fx
XP_CATS = [$20, $2c, $34, $3c, $40, $44]
NXCATS  = len(XP_CATS)

; Extended templates NTPL.. (rows as in presetdata.asm TPLS)
XTPLS := [[($81,$00,0), ($11,$f4,0), ($11,$ee,0), ($11,$ea,0), ($11,$e8,0), ($11,$e6,0), ($11,$e5,$16)]]  ; 14 808 kick
XTPLS ..= [[($81,$0c,0), ($41,$fa,0), ($41,$f2,0), ($41,$ec,0), ($11,$e8,0), ($11,$e6,$15)]]  ; 15 hard kick
XTPLS ..= [[($81,$1c,0), ($41,$02,0), ($81,$1a,0), ($81,$18,$13)]]                         ; 16 electro snare
XTPLS ..= [[($81,$1a,0), ($41,$fe,0), ($41,$fa,0), ($81,$1c,0), ($81,$1a,$14)]]             ; 17 big snare
XTPLS ..= [[($81,$24,0), ($41,$30,0), ($81,$26,$11)]]                                      ; 18 metal hat: pulse/noise
XTPLS ..= [[($41,$0c,0), ($41,$13,$10)]]                                                   ; 19 cowbell
XTPLS ..= [[($81,$0c,0), ($11,$0c,$c0), ($11,$0c,$12)]]                                    ; 20 electro tom: bend down
XTPLS ..= [[($ff,$00,0), ($ff,$05,0), ($ff,$07,0), ($ff,$0c,$10)]]                          ; 21 sus4
XTPLS ..= [[($ff,$00,0), ($ff,$04,0), ($ff,$07,0), ($ff,$0a,$10)]]                          ; 22 dom7
XTPLS ..= [[($ff,$00,0), ($ff,$07,$10)]]                                                   ; 23 power
XTPLS ..= [[($ff,$0c,0), ($ff,$00,$11)]]                                                   ; 24 pluck: +12 on tick 0
XTPLS ..= [[($ff,$f4,$30), ($ff,$f4,$11)]]                                                 ; 25 rise
XTPLS ..= [[($ff,$00,0), ($ff,$00,0), ($40,$00,0), ($40,$00,$10)]]                          ; 26 stutter (gate)
XTPLS ..= [[($81,$18,$c0), ($81,$18,$11)]]                                                 ; 27 noise fall
XTPLS ..= [[($41,$18,0), ($41,$0c,0), ($41,$00,$12)]]                                      ; 28 blip
XP_NT   = len(XTPLS)

; REU factory kits (CTRL + SPACE on PRESET continues after SYNTH; kits.asm)
X_808KIK = $20
X_HRDKIK = $21
X_SHTKIK = $22
X_ELSNAR = $23
X_BIGSNR = $24
X_MTLHAT = $25
X_PDLHAT = $26
X_COWBEL = $28
X_ELTOM  = $29
X_BLIP   = $2b
X_808BAS = $2c
X_PLCKBS = $2d
X_CHIPLD = $34
X_SQULD  = $35
X_POWER  = $42
X_FSTMAJ = $43
P_FATBAS = $12
XKITS := [("electro", [X_808KIK, X_ELSNAR, X_MTLHAT, P_OPHAT, X_ELTOM, P_CLAP, X_COWBEL, X_808BAS])]
XKITS ..= [("chip", [X_SHTKIK, P_SNARE, X_PDLHAT, X_BLIP, X_PLCKBS, X_CHIPLD, X_SQULD, X_FSTMAJ])]
XKITS ..= [("rock", [X_HRDKIK, X_BIGSNR, P_CLHAT, P_OPHAT, P_TOM, P_CRASH, X_POWER, P_FATBAS])]
NXKITS  = len(XKITS)
KITS_ALL = KITS_BASE .. XKITS
        .cerror XP_LIST[X_808KIK-$20][0] != "808kik" || XP_LIST[X_COWBEL-$20][0] != "cowbel" || XP_LIST[X_808BAS-$20][0] != "808bas", "kit ids"
        .cerror XP_LIST[X_PLCKBS-$20][0] != "plckbs" || XP_LIST[X_SQULD-$20][0] != "squld" || XP_LIST[X_FSTMAJ-$20][0] != "fstmaj", "kit ids"
        .cerror XP_LIST[X_POWER-$20][0] != "power" || XP_LIST[X_BLIP-$20][0] != "blip" || XP_LIST[X_PDLHAT-$20][0] != "pdlhat", "kit ids"
        .cerror NPRESETS != $20, "extended ids start at $20"
        .cerror XP_N + XP_NT > 128, "extended presets exceed REU pages $70-$7f"

        .enc "screen"
        .for _p in XPRESETS
        .cerror len(_p[0]) > PRE_NAMELEN, "preset name too long"
        .cerror _p[1][14] != $ff && _p[1][14] >= NTPL + XP_NT, "template out of range"
        .byte _p[1]
        .text format("%-6s", _p[0])  ; (staged without the padding: boot_reu.asm)
        .endfor
        .enc "none"
        .for _t in XTPLS
        .cerror len(_t) > 8, "template longer than 8 rows"
        .for _r in range(8)             ; column 0: control ($ff = no write after the template)
        .if _r < len(_t)
        .byte _t[_r][0]
        .else
        .byte $ff
        .endif
        .endfor
        .for _r in range(8)             ; column 1: transpose
        .if _r < len(_t)
        .byte _t[_r][1]
        .else
        .byte 0
        .endif
        .endfor
        .for _r in range(8)             ; column 2: command (H or P)
        .if _r < len(_t) && _t[_r][2] != 0
        .byte (_t[_r][2] < $20) ? CMD_HOP : CMD_BEND
        .else
        .byte 0
        .endif
        .endfor
        .for _r in range(8)             ; column 3: value
        .if _r < len(_t) && _t[_r][2] != 0
        .byte (_t[_r][2] < $20) ? (_t[_r][2] & 15) : _t[_r][2]
        .else
        .byte 0
        .endif
        .endfor
        .endfor
