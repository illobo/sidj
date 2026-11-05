# SIDJ · QUICK REFERENCE CARD

Keep this card next to your Commodore 64. **(REU)** = needs a RAM Expansion Unit.

Load: `LOAD"SIDJ",8` RETURN · `RUN` RETURN · menu: RETURN or 1 (editor), 2 T.A.S.T.E., 3 README, 4 MANUAL. Without the menu: `LOAD"SIDJ.EDITOR",8`. Hold C= while it starts to skip `RECOVERED` (REU).

UP = SHIFT + CRSR ⇩ · LEFT = SHIFT + CRSR ⇨ · `+` = hold · `,` = press in turn, quickly

---

### THE FOUR KEYS

| SPACE | C= | CTRL | RETURN |
|:---:|:---:|:---:|:---:|
| edit (A) | second edit (B) | select (SELECT) | play (START) |

### SCREEN MAP · CTRL + CRSR

```
               PROJECT ── SID SETUP
                  │           │
SONG ── CHAIN ── PHRASE ──── INSTR ── TABLE
                  │           │
                  └─ GROOVE ──┘     (GROOVE: CTRL + UP goes back)

FILE: open from PROJECT (LOAD / SAVE) · CTRL + UP returns
SONG: CTRL + LEFT = live mode on / off
```

Moving RIGHT opens the item under the cursor. PHRASE CTRL + DOWN on a `G` command opens that groove.

---

### EDITING

| Keys | Effect |
|---|---|
| CRSR | move cursor |
| SPACE | empty field: enter last value · filled: take its value, play it |
| SPACE, SPACE | new chain (SONG) · new phrase (CHAIN) · new table (INSTR TABLE) |
| SPACE + ⇦ ⇨ | −1 / +1 (note: semitone) |
| SPACE + ⇧ ⇩ | ±10 hex (note, transpose: ±12) |
| C= + SPACE | cut field (clear) |
| CTRL + SPACE | paste |
| C= + ⇧ ⇩ | SONG: page 16 rows / bookmarks · lists: first / last step |
| C= + ⇦ ⇨ | INSTR, TABLE, GROOVE: previous / next item |
| `0`–`9` `A`–`F` | hex digit, enters from the right |
| `A`–`G`, `0`–`7` | note name, octave (note field) |
| `A`–`Z` | command letter (command field) |
| F7 / SHIFT + F7 | undo / redo |
| F2 (SHIFT + F1) | help page for this screen, CRSR ⇧⇩ pages, any key closes **(REU, `SIDJ.HLP` on the disk)** |

### MARK · COPY · CLONE

| Keys | Effect |
|---|---|
| CTRL + C= | start mark (SONG, CHAIN, PHRASE list, TABLE) |
| CRSR | grow the block |
| C= | copy block, end mark |
| C= + SPACE | cut block |
| SPACE + CRSR | change every value in the block |
| CTRL held: C=, C=, C= | mark · whole column · whole screen |
| CTRL held: C=, SPACE | clone (cursor not moved): chain (SONG), phrase (CHAIN), instrument (PHRASE), table (INSTR TABLE) |
| C=, C=, C= | SONG: bookmark on / off |

Clone DEEP / SLIM: PROJECT screen, `CLONE`.

---

### PLAY · MUTE

| Keys | SONG mode | LIVE mode (SONG screen) |
|---|---|---|
| RETURN | SONG: play from row / stop · other screens: play / stop this channel | queue chain |
| RETURN, RETURN | – | queue at phrase end |
| CTRL + RETURN | play all / stop | queue stop of channel (twice: phrase end) |
| hold ⇦, RETURN | – | queue whole row |
| CTRL + ⇦ (SONG) | live mode on | live mode off |

| Keys | Effect |
|---|---|
| F1 · F3 · F5 | mute channel 1 · 2 · 3 |
| hold C=, press CTRL | mute cursor channel |
| C= + RETURN | solo (again: all on) |

### TEMPO (PROJECT, cursor on `TEMPO`)

| Keys | Effect |
|---|---|
| `0`–`9` | type BPM 40–295 |
| RETURN, RETURN … | tap tempo |
| C= + ⇦ / ⇨ held | nudge −3 % / +3 % |

---

### PHRASE VIEWS

| Keys | Effect |
|---|---|
| CLR/HOME | list ⇄ grid |
| SHIFT + CLR/HOME | drum view on / off **(REU)** |
| Grid: C= + ⇦ ⇨ | field: note · instr · cmd · value |

### PIANO · LOOP RECORD (PHRASE)

| Keys | Effect |
|---|---|
| SHIFT + F3 (F4) | piano mode on / off |
| Z S X D C V G B H N J M | C–B (piano mode) |
| Q 2 W 3 E R 5 T 6 Y 7 U | one octave higher |
| + / − | octave up / down |
| SHIFT + F5 (F6) | record on / off **(REU)**: the phrase loops |
| hold C= (recording) | erase the steps passed |
| F7 after recording | undo the take |
| hold `,` `.` `/` `;` | beat repeat: 8 · 4 · 2 · 1 steps (all channels) |

### DRUM VIEW (REU)

| Keys | Effect |
|---|---|
| ⇦ ⇨ / ⇧ ⇩ | step / lane |
| SPACE | hit on / off |
| C= + SPACE | clear step |
| SPACE + ⇧ ⇩ | hit ±1 semitone |
| C= + ⇧ ⇩ | shift lanes one instrument |
| CLR/HOME | back to list |

### INSTRUMENT · `PRESET`

| Keys | Effect |
|---|---|
| SPACE + ⇦ ⇨ | previous / next preset (plays it) |
| SPACE + ⇧ ⇩ | next / previous group |
| `00`–`1F` | preset by number (REU: browse on to `20`–`49`) |
| CTRL + SPACE (CTRL held: SPACE again) | factory kit into 8 instruments: DRUMS · BAND · SYNTH (REU: · ELECTRO · CHIP · ROCK) |

### FILE SCREEN

| Keys | Effect |
|---|---|
| SPACE on `SV` | save project |
| SPACE, SPACE on a file | load project or kit |
| C= + SPACE on `SV` | save kit `NAME.Kxx` (drive only) |
| C= + SPACE, C= + SPACE | delete file / slot |
| ⇦ ⇨ | drive 8 ⇄ REU slots **(REU 512K+)** |
| CTRL + ⇧ | back to PROJECT |

PROJECT: `CLEAN` = SPACE, SPACE (new project).

---

### COMMANDS · `Lxy`

| | | | | | |
|---|---|---|---|---|---|
| **A** table | **B** maybe | **C** chord | **D** delay | **E** sus/rel | **F** finetune |
| **G** groove | **H** hop (`HFF` stop) | **K** kill | **L** slide | **M** volume | **O** filter type/res |
| **P** bend | **Q** hard restart | **R** retrigger | **S** pulse width | **T** tempo | **V** vibrato |
| **W** waveform | **X** cutoff | **Z** random | | | |

Table CT column: `81` noise · `41` pulse · `21` saw · `11` triangle · `--` no change.

---

### MOUSE (1351, port 1)

| Action | Effect |
|---|---|
| click · click again | cursor to field · SPACE |
| drag ⇧⇩ / ⇦⇨ | SPACE + ⇧⇩ / ⇦⇨ |
| right button | C= |
| C= + click / CTRL + click | cut / paste |
| click map | change screen |
| click / right-click channel header | mute / solo |
| LIVE: click chain · twice · right-click | queue · at phrase end · stop |
| grid: click · drag | step on/off · note ⇧⇩, instrument ⇦⇨ |
| Live FX row 18–23: drag bar | hold value (CUT RES VOL TRN) |
| FLT: click LP BP HP 3O | switch filter type |
| right-click / C= + click fader | let go |
| TAP: click in time · hold `<` `>` | tap tempo · nudge |

Port, speed 0–3, acceleration: PROJECT screen, `MOUSE`.
