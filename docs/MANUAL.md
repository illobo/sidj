# SIDJ

**A music tracker for the Commodore 64**

Version 0.4b · User's Manual

NOTE: SIDJ 0.4b is experimental. Some things may not work as described, and a crash can lose your work. Save often.

---

## CONTENTS

- LOADING INSTRUCTIONS
- CHAPTER 1: BEFORE YOU START
- CHAPTER 2: YOUR FIRST SOUND
- CHAPTER 3: YOUR FIRST SONG
- CHAPTER 4: DRUMS
- CHAPTER 5: THE SCREENS
- CHAPTER 6: EDITING
- CHAPTER 7: INSTRUMENTS AND TABLES
- CHAPTER 8: COMMANDS
- CHAPTER 9: GROOVES AND TEMPO
- CHAPTER 10: LIVE MODE
- CHAPTER 11: THE MOUSE
- CHAPTER 12: SAVING AND LOADING
- CHAPTER 13: EXPORTING A SONG
- CHAPTER 14: T.A.S.T.E.
- CHAPTER 15: LIMITS AND MESSAGES

A one-page key reference is in the file QUICKREF.md.

---

## LOADING INSTRUCTIONS

### Commodore 64 with disk drive

1. Switch on the disk drive, then your Commodore 64.
2. Insert the SIDJ disk in drive 8.
3. Type `LOAD"SIDJ",8` and press RETURN.
4. The screen will show `SEARCHING FOR SIDJ`, then `LOADING`, then `READY.`
5. Type `RUN` and press RETURN.
6. The menu appears. Press RETURN on SIDJ EDITOR, or press 1.

The menu also starts T.A.S.T.E. (2), the short guide (3) and this manual (4). Use CRSR or a joystick in port 2 and RETURN, or the keys 1-4 or F1/F3/F5/F7. To skip the menu, type `LOAD"SIDJ.EDITOR",8`.

SIDJ starts on the SONG screen with a short demo song.

### C64 Ultimate and Ultimate 64

1. Mount the SIDJ disk image on drive 8, then load and run it as above. You can also start `SIDJ` (the menu) or `SIDJ.EDITOR` from the file browser.
2. SIDJ saves and loads on drive 8. Keep a disk image mounted there for your songs.
3. To use the REU features, switch the REU on in the Ultimate menu before you start SIDJ.

NOTE: SIDJ cannot be loaded from or saved to tape.

---

## CHAPTER 1: BEFORE YOU START

### 1.1 What you need

- A Commodore 64, or a C64 Ultimate / Ultimate 64.
- A disk drive as device 8: a 1541, an SD2IEC, or the Ultimate's drive.
- Optional: a Commodore 1351 mouse (or compatible) in control port 1.
- Optional: a joystick in control port 2. It moves the cursor; FIRE works as SPACE.
- Optional: a RAM Expansion Unit (REU).

SIDJ runs fully without an REU. With an REU you also get:

| REU size | Adds |
|---|---|
| any | a long undo history (without an REU: one step), crash and reset recovery, the drum lane view |
| 512K or more | project slots in the REU: 8 slots with 512K, 24 with 1 MB, 32 with 2 MB or more |

In this manual, features that need an REU are marked **(REU)**.

### 1.2 How SIDJ is built

A SIDJ project is built in layers:

- The **SONG** is a list of rows. Each row has one chain per channel. There are 3 channels, one per SID voice.
- A **CHAIN** is a list of up to 16 phrases.
- A **PHRASE** is 16 steps. Each step can hold a note, an instrument and a command.
- An **INSTRUMENT** is a SID sound. It can run a **TABLE** for drums, arpeggios and sweeps.
- A **GROOVE** sets how long each step lasts.

All numbers are shown in hexadecimal (`00`–`FF`).

### 1.3 The keys

SIDJ uses four keys in combination:

| Key | Use |
|---|---|
| SPACE | edit |
| C= (the Commodore key) | second edit key |
| CTRL | select and move between screens |
| RETURN | play and stop |

The CRSR keys move the cursor. To move up, hold SHIFT and press CRSR ⇩. To move left, hold SHIFT and press CRSR ⇨. In this manual, UP, DOWN, LEFT and RIGHT mean these four cursor directions.

"SPACE + RIGHT" means: hold SPACE, then press RIGHT.
"SPACE, SPACE" means: press SPACE twice, quickly.

HINT: think of a game pad. SPACE is A, C= is B, CTRL is SELECT and RETURN is START.

---

## CHAPTER 2: YOUR FIRST SOUND

To play the demo song:

1. Check that the cursor is on row `00` of the SONG screen.
2. Press RETURN. The song plays from the cursor row.
3. Press RETURN again to stop.

The top line of the screen is the status line. It shows the screen name, the channel under the cursor (`C1`), the tempo, the channels playing (`P:`) and the channels muted (`M:`).

The bottom line is the help line. It explains the field under the cursor and shows messages.

---

## CHAPTER 3: YOUR FIRST SONG

In this chapter you write a short tune on channel 1, then add a second channel.

### 3.1 Clear the demo

1. Press CTRL + RIGHT twice. The screen will show the PHRASE screen.
2. Press CTRL + UP. The screen will show the PROJECT screen.
3. Move the cursor down to `CLEAN`.
4. Press SPACE. The help line will show `SPC AGAIN: CONFIRM`.
5. Press SPACE again. The project is now empty.

### 3.2 Put a chain in the song

1. Press CTRL + DOWN, then CTRL + LEFT twice. You are on the SONG screen.
2. Move the cursor to row `00`, channel 1 (the first column).
3. Press SPACE, SPACE. A new chain number appears: `00`.
4. Press CTRL + RIGHT. You are on the CHAIN screen, editing chain `00`.

### 3.3 Put a phrase in the chain

1. Move the cursor to step `0`, in the left column (the phrase column).
2. Press SPACE, SPACE. A new phrase number appears: `00`.
3. Press CTRL + RIGHT. You are on the PHRASE screen, editing phrase `00`.

### 3.4 Choose a sound

1. Press CTRL + RIGHT. You are on the INSTR screen, instrument `00`.
2. Move the cursor to `PRESET`.
3. Hold SPACE and press RIGHT. Each press loads the next factory sound and plays it.
4. Hold SPACE and press UP or DOWN to jump to the next or previous group: drums, basses, leads, pads, arps, fx.
5. Stop at a lead sound, for example `13 PWMLD`.
6. Press CTRL + LEFT to go back to the PHRASE screen.

### 3.5 Write notes

A phrase has four columns: note, instrument, command and command value.

1. Move the cursor to step `0`, note column.
2. Press SPACE. The note `C-4` appears with instrument `00`, and you hear it.
3. To change the note, hold SPACE and press RIGHT or LEFT (one semitone), UP or DOWN (one octave). Or type a letter `A`–`G` for the note name and a digit `0`–`7` for the octave.
4. Move down to step `4` and press SPACE. The last note you used appears.
5. Type `E`. The note changes to E in the same octave.
6. Add notes on steps `8` and `C` the same way.

To erase a note, move the cursor onto it and press C= + SPACE.

To listen, press RETURN. The phrase plays on its channel as part of the song. Press RETURN again to stop.

### 3.6 Fill the chain

1. Press CTRL + LEFT. You are on the CHAIN screen.
2. Move to step `1`, phrase column, and press SPACE. Phrase `00` is entered again.
3. Move to step `2` and press SPACE, SPACE. A new phrase `01` appears.
4. Press CTRL + RIGHT and write notes in phrase `01`.

The right column of the chain is a transpose. To play a phrase higher, move the cursor to its transpose field and hold SPACE + RIGHT (one semitone) or SPACE + UP (one octave).

Chain `00` now plays phrase `00`, `00`, `01` and starts again.

### 3.7 Build the song

1. Press CTRL + LEFT until the status line shows `SONG`.
2. Move to row `01`, channel 1, and press SPACE. Chain `00` is entered again.
3. For a bass line, move to row `00`, channel 2. Press SPACE, SPACE for a new chain and fill it as above.
4. On the PHRASE screen of the bass, type a new instrument number, for example `01`, in the instrument column. Press CTRL + RIGHT and choose a bass preset.

### 3.8 Play the song

1. Go to row `00` of the SONG screen.
2. Press RETURN.

Each channel plays its chains row by row. When a channel reaches an empty row, it goes back to the first row of its block, so the song repeats.

To play or stop the whole song from any screen, press CTRL + RETURN.

To keep your song, save it to disk (CHAPTER 12).

---

## CHAPTER 4: DRUMS

NOTE: A channel plays one note at a time. A kick and a hi-hat on the same step need two channels.

### 4.1 Load the drum kit

A kit fills 8 instruments in a row with factory sounds.

1. Go to the INSTR screen.
2. Choose the first instrument for the kit, for example `10`. Hold C= and press RIGHT until the title shows `10`, or type `10` in the title field.
3. Move the cursor to `PRESET`.
4. Hold CTRL and press SPACE. Instruments `10`–`17` now hold kick, snare, closed hat, open hat, tom, clap, rim and crash. The help line will show `DRUMS    10-17`.
5. Release CTRL.

While you hold CTRL, each further press of SPACE puts the next kit in the same 8 instruments: `BAND`, `SYNTH`, then `DRUMS` again.

HINT: The drum sounds are tuned for the note C-4. They are not changed by chain transpose.

### 4.2 Write a beat in the drum view (REU)

The drum view shows one phrase as 8 lanes (one per instrument) by 16 steps.

1. Make a chain and a phrase on channel 3, as in 3.2 and 3.3.
2. On the PHRASE screen, hold SHIFT and press CLR/HOME. The drum view appears. Its lanes start at the instrument you chose on the INSTR screen.
3. LEFT and RIGHT select the step. UP and DOWN select the lane.
4. Press SPACE to place a hit. You hear it. Press SPACE on the same lane again to remove it.
5. Press C= + SPACE to clear the step.
6. Hold SPACE and press UP or DOWN to tune the hit one semitone up or down.
7. Hold C= and press UP or DOWN to shift the lanes by one instrument.

Each step holds one hit. A hit on another lane replaces it.

Press CLR/HOME (without SHIFT) to go back to the list.

NOTE: Without an REU the help line shows `NEEDS REU` and the view does not change. Use the list instead (4.3).

### 4.3 Write a beat in the phrase list

1. On the PHRASE screen, move to step `0`, instrument column, and type `10` (kick).
2. Move to the note column and press SPACE. If the note is not `C-4`, type `C` and `4`.
3. On step `4`, press SPACE in the note column. Then type `11` (snare) in the instrument column.
4. Continue with steps `8` and `C`.

---

## CHAPTER 5: THE SCREENS

### 5.1 Moving between screens

The screens are arranged as a map. Hold CTRL and press a CRSR key to move on the map. The bottom right of the screen shows the map, with the current screen reversed:

```
        PRJ SID
SNG CHN PHR INS TBL
            GRV
```

| From | CTRL + UP | CTRL + DOWN | CTRL + LEFT | CTRL + RIGHT |
|---|---|---|---|---|
| SONG | – | – | live mode on/off | CHAIN |
| CHAIN | – | – | SONG | PHRASE |
| PHRASE | PROJECT | GROOVE | CHAIN | INSTR |
| INSTR | SID SETUP | GROOVE | PHRASE | TABLE |
| TABLE | – | – | INSTR | – |
| GROOVE | back | – | – | – |
| PROJECT | – | PHRASE | – | SID SETUP |
| SID SETUP | – | INSTR | PROJECT | – |
| FILE | PROJECT | – | – | – |

Moving right opens the item under the cursor: the chain on the SONG screen, the phrase on the CHAIN screen, the instrument of the phrase step, the table of the instrument. CTRL + DOWN on a phrase step with a `G` command opens that groove.

**Help pages (REU).** Press F2 (SHIFT + F1), or click the help line at the bottom, for a full page of help on the screen you are on. CRSR UP/DOWN turn the pages; any other key closes them. SIDJ loads the pages from the file `SIDJ.HLP` when it starts, so copy it to the disk next to SIDJ. Without an REU the help line shows `NEEDS REU`; without the file, `NO HELP FILE`.

The left half of the screen is the editor. The right half shows the chain, phrase or instrument under the cursor. Rows 18 to 23 hold the Live FX faders (10.4) and the map.

### 5.2 SONG

256 rows (`00`–`FF`), one column per channel. Each field holds a chain number (`00`–`7F`) or `--` (empty).

| Keys | Effect |
|---|---|
| SPACE, SPACE on `--` | new chain |
| RETURN | play from the cursor row, or stop |
| C= + UP / DOWN | page 16 rows, or jump to the previous / next bookmark if there are any |
| C=, C=, C= | set or remove a bookmark on this row |
| CTRL + LEFT | live mode on/off (CHAPTER 10) |

### 5.3 CHAIN

16 steps. Each step has a phrase number (`00`–`FE`) and a transpose. The chain ends at the first empty step.

| Keys | Effect |
|---|---|
| SPACE, SPACE on `--` | new phrase |
| SPACE + LEFT / RIGHT on transpose | −1 / +1 semitone |
| SPACE + UP / DOWN on transpose | +12 / −12 semitones |
| C= + UP / DOWN | first / last step |
| RETURN | play or stop this channel |
| SHIFT + F3 (F4) | piano mode on / off, see 10.5 |
| SHIFT + F5 (F6) | record into the playing phrase **(REU)**, see 10.5 |

### 5.4 PHRASE

16 steps (`0`–`F`). Each step has a note, an instrument, a command letter and a command value.

| Field | How to edit |
|---|---|
| note | SPACE + LEFT/RIGHT: semitone. SPACE + UP/DOWN: octave. Type `A`–`G` and `0`–`7`. |
| instrument | `00`–`3F`. A new note gets the last instrument used. CTRL + RIGHT edits it. |
| command | type a letter (CHAPTER 8). C= + SPACE clears it. |
| value | type two hex digits, or SPACE + LEFT/RIGHT (±1), SPACE + UP/DOWN (±10). |

| Keys | Effect |
|---|---|
| CLR/HOME | list view / grid view |
| SHIFT + CLR/HOME | drum view **(REU)**, see 4.2 |
| C= + UP / DOWN | first / last step |
| RETURN | play or stop this channel |

**The grid view** shows the 16 steps as a 4 × 4 grid of boxes. Each box shows the note (coloured by octave), the instrument when it changes, and the command. The playing step is white.

- The CRSR keys move between boxes (UP/DOWN: 4 steps).
- C= + LEFT/RIGHT selects the field in the box: note, instrument, command or value.
- SPACE, SPACE + CRSR, C= + SPACE and typing work as in the list.
- Marking blocks is not possible in the grid.

### 5.5 INSTR

Edits one of 64 instruments (`00`–`3F`). The fields are described in CHAPTER 7.

| Keys | Effect |
|---|---|
| C= + LEFT / RIGHT | previous / next instrument |
| SPACE | play the instrument |
| CTRL + SPACE on `PRESET` | factory kit (7.3) |

Rows 13 to 17 show which instruments are in use (`+`). The current one is reversed.

### 5.6 TABLE

16 steps with six columns: control byte (`CT`), transpose (`TR`) and two command/value pairs (7.4). The title row holds the table number. C= + LEFT/RIGHT selects the previous or next table. Each edit plays the current instrument.

### 5.7 GROOVE

The ticks per step (CHAPTER 9). The title row holds the groove number. C= + LEFT/RIGHT selects the previous or next groove. `--` ends the groove; it then starts again at step 0.

### 5.8 PROJECT

| Field | Use |
|---|---|
| TEMPO | 40–295 BPM. Type three digits, or SPACE + LEFT/RIGHT (±1), SPACE + UP/DOWN (±10). RETURN taps the tempo, C= + LEFT/RIGHT nudges it (9.2). |
| TRANSP | transposes the whole song. SPACE + LEFT/RIGHT ±1, SPACE + UP/DOWN ±12. |
| NAME | 16 characters, used as the file name. Type letters and digits; the cursor moves on. SPACE + CRSR steps through the characters. C= + SPACE puts a space. |
| CLONE | `DEEP` or `SLIM` (6.4). Saved with the project. |
| LOAD | SPACE: the FILE screen, cursor on the first file. |
| SAVE | SPACE: the FILE screen, cursor on the save row. |
| CLEAN | SPACE, then SPACE again: an empty project. |
| MOUSE | port (`OFF`, `PRT1`, `PRT2`), speed `0`–`3`, acceleration `ON`/`OFF`. |

NOTE: The `SYNC` and `KEYS` lines show fixed settings in this version.

### 5.9 SID SETUP

Shows the SID chip found at start-up: `6581` or `8580`. There is nothing to change here in this version.

### 5.10 FILE

Saves, loads and deletes projects and kits. Open it with `LOAD` or `SAVE` on the PROJECT screen. See CHAPTER 12.

---

## CHAPTER 6: EDITING

### 6.1 The key grammar

| Keys | Effect |
|---|---|
| CRSR | move the cursor |
| SPACE on an empty field | enter the last value used in this kind of field |
| SPACE on a filled field | take its value as the next value to enter, and play it |
| SPACE, SPACE | on an empty chain field (SONG), phrase field (CHAIN) or TABLE field (INSTR): a new, unused item |
| SPACE + LEFT / RIGHT | value −1 / +1 |
| SPACE + UP / DOWN | value up / down a large step (`10` hex; 12 for notes and transposes) |
| C= + SPACE | cut: copy the field and clear it |
| CTRL + SPACE | paste |
| CTRL + CRSR | change screen |
| C= + CRSR | page, jump, or previous/next item |
| RETURN | play / stop |

NOTE: SPACE + CRSR does not fill an empty field. Press SPACE first.

### 6.2 Typing values

- Hex fields: type `0`–`9` and `A`–`F`. Each digit enters from the right. If the number gets too large, the field starts again with the digit you typed.
- Note fields: `A`–`G` set the note, `0`–`7` the octave.
- Command fields: type the letter.
- Tempo: type the BPM in decimal. A value from 40 to 295 is taken at once.

NOTE: Typing has no effect while SPACE, C=, CTRL or SHIFT is held down.

### 6.3 Mark, copy, cut and paste

Blocks can be marked on the SONG, CHAIN, PHRASE (list) and TABLE screens.

To copy a block:

1. Hold CTRL and press C=. The field under the cursor is marked.
2. Move the cursor to make the block larger. You can release CTRL.
3. Press C=. The block is copied.

To cut a block: mark it, then press C= + SPACE. The block is copied and cleared.

To change every value in a block: mark it, then hold SPACE and press a CRSR key. For example, SPACE + UP on a block of notes raises them all one octave.

To paste: move the cursor to where the top left corner should go, and press CTRL + SPACE.

- A block pastes only on the screen it came from. Each column goes only into a field of the same kind.
- A single field pastes into any field of the same kind, on any screen.

HINT: The copy survives LOAD and CLEAN. Use it to move phrases from one project to another.

**Quick marking:**

1. Hold CTRL and press C=.
2. With CTRL still held, press C= again. The whole column is marked. On the SONG screen: rows `00` to the last row with a chain.
3. With CTRL still held, press C= once more. The whole screen is marked.

Then copy or cut as above.

### 6.4 Cloning

Cloning copies an item to a new number and puts the new number under the cursor. Use it to make a variation without changing the original.

1. Move the cursor onto the item number.
2. Hold CTRL and press C=.
3. Keep CTRL held, do not move the cursor, and press SPACE.

| Cursor on | Result |
|---|---|
| chain number (SONG) | a new chain. DEEP also copies its phrases (a phrase used twice gets one copy). SLIM uses the same phrases. |
| phrase number (CHAIN) | a new phrase |
| instrument number (PHRASE) | a new instrument. DEEP also copies its table. SLIM shares the table. |
| `TABLE` field (INSTR) | a new table for this instrument |

Choose DEEP or SLIM in the `CLONE` field of the PROJECT screen. When nothing is free, the help line shows `NONE FREE`, `NO FREE CHAIN` or `NOT ENOUGH PHRASES`.

### 6.5 Bookmarks

On the SONG screen:

- Press C= three times quickly to set or remove a bookmark on the cursor row.
- Press C= + DOWN or C= + UP to jump to the next or previous bookmark.

Without bookmarks, C= + UP/DOWN pages by 16 rows. Bookmarks are saved with the project.

### 6.6 Undo and redo

- Press F7 to undo.
- Press SHIFT + F7 (F8) to redo.

The help line shows `UNDO`, `REDO`, `NOTHING TO UNDO` or `NOTHING TO REDO`.

One undo step covers everything from the first key or mouse button you press until you release them all. A drag, a paste, a clone or a kit is one step.

Undo covers all song data, including tempo, transpose, name, clone setting and bookmarks. It does not cover the copy, the cursor, mutes, the live queue or the Live FX faders. LOAD and CLEAN clear the undo history.

- **(REU)** About 100 steps are kept. The oldest are dropped when the store is full.
- Without an REU, one step is kept (undo, then redo). It covers only the part of memory holding the item under the cursor. A paste or clone that changes other chains or phrases is not fully undone.

### 6.7 Mute and solo

| Keys | Effect |
|---|---|
| F1, F3, F5 | mute or unmute channel 1, 2, 3 |
| hold C=, press CTRL | mute or unmute the cursor's channel |
| C= + RETURN | solo the cursor's channel; again: unmute all |

On the SONG screen the cursor's channel is the cursor column. On the other screens it is the channel you came from.

---

## CHAPTER 7: INSTRUMENTS AND TABLES

### 7.1 Instrument fields

| Field | Meaning |
|---|---|
| PRESET | the factory sound applied last (7.2) |
| WAVE `T S P N RNG SYN` | triangle, sawtooth, pulse, noise; ring modulation, sync. SPACE + CRSR switches a bit on or off; `1` / `0` set it. RNG and SYN use the previous voice (voice 3 for voice 1). |
| AD, SR | attack/decay and sustain/release, as on the SID |
| PW | pulse width `000`–`FFF`. SPACE + LEFT/RIGHT ±10, SPACE + UP/DOWN ±100 |
| SWEEP | pulse width sweep `NONE`, `UP`, `DOWN`, `PING` (up and down), and its speed per tick |
| FILTER | `OFF`: not filtered. `USE`: filtered; the filter settings stay as they are. `OWN`: filtered; this instrument sets cutoff, resonance and mode at each note. With several `OWN` instruments, the last note wins. |
| `L B H 3` | filter type: low pass, band pass, high pass, voice 3 off |
| RES | resonance `0`–`F` |
| CUTOFF | cutoff `00`–`FF` |
| FSWEEP | cutoff change per tick, `+` or `−` |
| HRESTART | hard restart ticks (`0` = off, normally `2`) and mode: `GATE`, `ADSR` or `TEST`. Hard restart gives each note the same attack. |
| HRSR | SR value used during the hard restart |
| VIBRATO | speed and depth, then `DELAY` in ticks |
| TABLE | the table started with each note (`--` = none). SPACE, SPACE: a new table. CTRL + RIGHT: edit it. |
| SPEED | ticks per table step (`0` = every tick) |
| STEP | `ON`: the table moves one step per note instead of per tick |
| TRANSP | `ON`: chain and project transpose apply. `OFF`: they do not (for drums). |
| PITCH | `TICK` or `FAST`. Not used by the player in this version. |

### 7.2 Factory presets

There are 32 factory presets, tuned for the 8580 SID.

1. Move the cursor to `PRESET`.
2. Hold SPACE and press LEFT or RIGHT to step through them, UP or DOWN to jump between groups. Or type the two-digit number.

Each change replaces the instrument and plays it while SPACE is held. Nothing plays if that channel is playing the song. Presets with a table also fill a table.

| Group | Presets |
|---|---|
| BASIC | `00` CUSTOM, `01` LEAD, `02` BASS, `03` DRUM, `04` PAD, `05` ARP |
| DRUMS | `06` KICK, `07` SNARE, `08` CLHAT, `09` OPHAT, `0A` TOM, `0B` CLAP, `0C` RIM, `0D` CRASH |
| BASSES | `0E` PULSBS, `0F` SAWBAS, `10` ACID, `11` SUBBAS, `12` FATBAS |
| LEADS | `13` PWMLD, `14` SAWLD, `15` SYNC, `16` RING |
| PADS | `17` SLOWPD, `18` PWMPAD, `19` STRING |
| ARPS | `1A` MAJOR, `1B` MINOR, `1C` OCTAVE |
| FX | `1D` LASER, `1E` NOISUP, `1F` ZAP |

`00 CUSTOM` is the default instrument. After you edit an instrument, `PRESET` still shows the preset it started from.

**With an REU** the list goes on after `1F ZAP`: 42 more presets, `20`–`49`, in six more groups (drums `20`, basses `2C`, leads `34`, pads `3C`, arps `40`, fx `44`). Step to them with SPACE + RIGHT; typing a number still reaches `00`–`1F` only. An REU preset is stored as `00 CUSTOM`: its name shows only on the instrument you gave it last, and a saved song shows `00 CUSTOM` there (it sounds the same).

### 7.3 Kits

A kit is a group of instruments in a row.

**Factory kits.** On the INSTR screen, with the cursor on `PRESET`, hold CTRL and press SPACE. Eight instruments from the current one are filled (up to `3F`). Each further SPACE with CTRL held puts the next kit there. Release CTRL to keep it.

| Kit | Instruments |
|---|---|
| DRUMS | KICK, SNARE, CLHAT, OPHAT, TOM, CLAP, RIM, CRASH |
| BAND | KICK, SNARE, CLHAT, PULSBS, ACID, PWMLD, SLOWPD, MAJOR |
| SYNTH | PULSBS, ACID, SUBBAS, PWMLD, SAWLD, PWMPAD, MAJOR, MINOR |
| ELECTRO (REU) | 808KIK, ELSNAR, MTLHAT, OPHAT, ELTOM, CLAP, COWBEL, 808BAS |
| CHIP (REU) | SHTKIK, SNARE, PDLHAT, BLIP, PLCKBS, CHIPLD, SQULD, FSTMAJ |
| ROCK (REU) | HRDKIK, BIGSNR, CLHAT, OPHAT, TOM, CRASH, POWER, FATBAS |

**Kit files.** To save your own instruments as a kit:

1. On the INSTR screen, select the first instrument of the kit.
2. Go to the FILE screen (PROJECT screen, `SAVE`).
3. With the cursor on the `SV` row, press C= + SPACE.

The kit holds this instrument and the used instruments after it, up to the first default one, with their tables. The file is named `NAME.Kxx`, where `NAME` is the project name and `xx` the first instrument. The help line shows, for example, `KIT SAVED 10-13`.

To load a kit:

1. On the INSTR screen, select the instrument where the kit should start.
2. Go to the FILE screen.
3. Move the cursor to the kit file and press SPACE, SPACE.

The help line shows, for example, `KIT LOADED 20-23`. If there are not enough free tables, it shows `NO FREE TABLES` and nothing changes. Loading a kit is one undo step.

NOTE: Kit files are saved on the disk drive only, not in REU slots.

### 7.4 Tables

A table runs while a note plays: one step per tick, per `SPEED` ticks, or per note in `STEP` mode.

| Column | Meaning |
|---|---|
| CT | SID control byte for this tick: waveform bits plus gate. `--` = no change. Examples: `81` noise, `41` pulse, `21` sawtooth, `11` triangle. |
| TR | semitones added to the note on this tick |
| CMD, CMD | two commands with values (CHAPTER 8), for example `S` pulse width, `X` cutoff, `O` filter type |

`Hxy` in a table jumps to step `y`, `x` times. `x` = `0` repeats forever.

HINT: A drum is noise (`81`) for one tick, then pulse (`41`) with a falling transpose. An arpeggio is the transposes `0`, `4`, `7` followed by `H00`.

To start a table from a phrase, use the `A` command.

---

## CHAPTER 8: COMMANDS

A command is a letter and a value `xy` of two hex digits. Commands go in the phrase's command column or in a table's command columns.

| Cmd | Effect | Value |
|---|---|---|
| A | start a table | table number |
| B | play this step's note by chance | `y` in 16 (`F` = always) |
| C | chord: arpeggio 0, x, y semitones, one per tick | `xy` |
| D | delay the note | ticks |
| E | sustain and release | `x` sustain, `y` release |
| F | fine tune | signed, 1/128 semitone |
| G | groove for this channel from this step | groove number |
| H | hop. `H0y`: next phrase, starting at step `y`. `Hxy`: back to step `y`, `x` times. `HFF`: stop the channel. | |
| K | kill: gate off after `xy` ticks; the release plays | ticks |
| L | slide to this note | speed |
| M | master volume | `y` = `0`–`F` |
| O | filter type and resonance | `x`: 1 LP, 2 BP, 4 HP, 8 voice 3 off (add them); `y`: resonance |
| P | pitch bend | signed, 1/64 semitone per tick |
| Q | hard restart ticks for this note | `0`–`F` |
| R | retrigger the note every `y` ticks | `x`: sustain change per retrigger |
| S | pulse width = value × 16 | `00`–`FF` |
| T | tempo | `28`–`FF` = 40–255 BPM, `00`–`27` = 256–295 BPM |
| V | vibrato | `x` speed, `y` depth |
| W | SID control byte: waveform, ring, sync, test (SIDJ sets the gate) | byte |
| X | filter cutoff | `00`–`FF` |
| Z | repeat the channel's last command, adding 0 to `x` to its high digit and 0 to `y` to its low digit at random | `xy` |

NOTE: B, D, G, L, Q and Z work in phrases only.

---

## CHAPTER 9: GROOVES AND TEMPO

### 9.1 Grooves

A groove sets how many ticks each step lasts. Groove `00` is `6, 6`: every step lasts 6 ticks. At 125 BPM a 6-tick step is a sixteenth note.

To add swing:

1. On the PHRASE screen, press CTRL + DOWN. The GROOVE screen appears.
2. Change the two values to `08` and `04`. The steps now alternate long and short.

To use another groove on one channel, put a `G` command with the groove number in a phrase.

### 9.2 Tempo

To set the tempo, type it into `TEMPO` on the PROJECT screen, or use SPACE + CRSR.

To tap the tempo:

1. Move the cursor to `TEMPO`.
2. Press RETURN in time with the music, at least twice. SIDJ uses the average of the last four taps.

To nudge the tempo, for example to match another player by ear: on `TEMPO`, hold C= + RIGHT to play about 3% faster, or C= + LEFT to play about 3% slower. The tempo returns when you release the keys.

With the mouse, click `TEMPO` or the `TAP` label in time to tap, and hold `<` or `>` on the TAP row to nudge.

---

## CHAPTER 10: LIVE MODE

In live mode each channel repeats one chain. You choose the next chain for each channel, and it starts when the playing chain ends. Chains of different lengths play against each other.

### 10.1 To switch live mode on and off

On the SONG screen, press CTRL + LEFT. The status line shows `LIVE`. Press CTRL + LEFT again to go back to song mode.

### 10.2 To queue chains

On the SONG screen in live mode:

| Keys | Effect |
|---|---|
| RETURN | queue the chain under the cursor |
| RETURN, RETURN | the same, but switch at the end of the playing phrase |
| CTRL + RETURN | queue a stop of the cursor's channel |
| CTRL + RETURN, CTRL + RETURN | stop at the end of the playing phrase |
| hold LEFT (SHIFT + CRSR ⇨), press RETURN | queue the whole row |

A stopped channel starts in time with the channels that play.

The screen shows the playing chain with `>` and a white field, a queued chain with a blinking `*`, and a queued stop with a blinking `X` in the channel header.

HINT: `HFF` in a phrase stops the channel from inside the music.

### 10.3 Mute and solo

As in 6.7: F1, F3, F5; hold C= and press CTRL; C= + RETURN. With the mouse, click a channel header to mute, right-click to solo.

### 10.4 Live FX faders (mouse)

Rows 18 to 23 hold six faders. They are on every screen and are used with the mouse.

| Row | Fader | Range |
|---|---|---|
| CUT | filter cutoff | `00`–`FF` |
| RES | resonance | `0`–`F` |
| FLT | filter type: switches LP, BP, HP, 3O | |
| VOL | volume | `0`–`F` |
| TAP | tempo, tap and nudge | 40–295 |
| TRN | transpose | −12 to +12 |

- Drag on a bar to set the value. The fader now holds: it replaces what instruments, tables and commands set. The label is reversed and the bar turns yellow.
- Click LP, BP, HP or 3O on the FLT row to switch that filter type on or off.
- Click a label to hold the value shown.
- Right-click a row, or click it with C= held, to let go. The song's own values return.
- TAP row: the bar sets the project tempo. Click `TAP` in time to tap. Hold `<` or `>` to nudge.

The TRN fader moves new notes on all channels, for instruments with `TRANSP ON`.

NOTE: Fader settings are not saved and cannot be undone. LOAD and CLEAN let go of all faders.

### 10.5 Recording loops

On the PHRASE screen you can play notes on the keyboard and record them into the playing phrase.

**Piano mode.** Press F4 (SHIFT + F3). The help line shows `PIANO +-:OCTAVE`. Two rows of keys are a piano:

| Keys | Notes |
|---|---|
| Z S X D C V G B H N J M | C to B |
| Q 2 W 3 E R 5 T 6 Y 7 U | C to B, one octave higher |
| + / − | octave up / down (0–6) |

A key plays the last instrument you entered on the cursor's channel. It writes nothing. While piano mode is on, typing notes and values is off. Press SHIFT + F3 again to switch it off.

**To record (REU).**

1. Put the cursor on the phrase and press RETURN, so its channel plays it.
2. Press F6 (SHIFT + F5). The phrase now loops, and `REC` shows at the right of the help line.
3. Play the piano keys. Each note sounds at once and goes into the nearest step, over what is there. A note late in a step goes into the next step.
4. Hold C= to erase the steps that the playhead passes.
5. Press SHIFT + F5 again to stop.

The whole take is one undo step: press F7 to remove it.

NOTE: The C64 has no F2, F4, F6 or F8 keys: they are SHIFT + F1, F3, F5 and F7. Plain F3 and F5 mute channels 2 and 3.

NOTE: Without an REU, F6 shows `NEEDS REU`; piano mode works.

**Beat repeat.** Hold one of these keys to repeat the last steps of every channel: `,` 8 steps, `.` 4 steps, `/` 2 steps, `;` 1 step. Let go and the song plays on. In live mode the queued chains wait until you let go.

### 10.6 The mouse in live mode

On the SONG screen in live mode:

- Click a chain to queue it.
- Click it twice to queue it at the end of the playing phrase.
- Right-click a chain to queue a stop of its channel.

---

## CHAPTER 11: THE MOUSE

### 11.1 Setting up

1. Switch off your Commodore 64.
2. Plug the 1351 mouse into control port 1.
3. Switch on and load SIDJ. The pointer appears when SIDJ finds the mouse.

To use control port 2, or to change the speed, go to the PROJECT screen. Set `MOUSE` to `PRT1` or `PRT2`, `SPD` from `0` (slow) to `3` (fast), and `ACC` (acceleration) `ON` or `OFF`. These settings are not saved with the project.

NOTE: The mouse must be in 1351 (proportional) mode. A mouse in joystick mode is not found.

### 11.2 Using the mouse

| Action | Effect |
|---|---|
| click a field | move the cursor there |
| click the same field again | SPACE |
| drag up / down | SPACE + UP / DOWN, one step per 8 pixels |
| drag left / right | SPACE + LEFT / RIGHT |
| right button | C=, while held |
| click with C= or the right button held | C= + SPACE (cut) |
| click with CTRL held | CTRL + SPACE (paste) |
| click the map | go to that screen |
| click a channel header (SONG) | mute; right-click: solo |
| click `TEMPO` (PROJECT) | tap the tempo |
| click an instrument in the list (INSTR rows 13–17) | edit it |
| move the pointer | the help line explains what is under it |

A drag moves in one direction only, chosen by the first movement.

**Grid view:** a click switches a step on or off. Drag up or down to change the note, left or right to change the instrument. Drag with the right button to change the command value (up/down ±10, left/right ±1). Click `GRID` or `LIST` on row 1 to change the view.

**Drum view (REU):** a click on a field places or removes a hit; with C= or the right button held it clears the step. A click on a lane number selects the lane. Click `DRUM` on row 1 to open or close the view.

---

## CHAPTER 12: SAVING AND LOADING

### 12.1 To save a project

1. On the PROJECT screen, enter a `NAME`. It becomes the file name.
2. Move to `SAVE` and press SPACE. The FILE screen appears with the cursor on the `SV` row.
3. Press SPACE. The help line shows `SAVED`.

A file with the same name is replaced. A project without a name is saved as `UNTITLED`.

### 12.2 To load a project

1. On the PROJECT screen, move to `LOAD` and press SPACE. The FILE screen lists the SIDJ projects and kits on drive 8.
2. Move the cursor to the file.
3. Press SPACE, SPACE. The help line shows `LOADED` and the SONG screen appears.

Loading stops the music, clears the undo history and lets go of the Live FX faders. Mutes and live mode stay as they are.

### 12.3 To delete a file

On the FILE screen, move the cursor to the file. Press C= + SPACE, then C= + SPACE again.

### 12.4 FILE screen keys

| Keys | Effect |
|---|---|
| UP / DOWN | select a row |
| SPACE on `SV` | save the project |
| SPACE, SPACE on a file | load it (project or kit) |
| C= + SPACE on `SV` | save a kit (drive only) |
| C= + SPACE, C= + SPACE on a file | delete it |
| LEFT / RIGHT | drive 8 or REU slots **(REU, 512K or more)** |
| CTRL + UP | back to the PROJECT screen |

The right side shows the device and the number of files.

### 12.5 REU project slots (REU, 512K or more)

Slots keep whole projects in the REU. A slot saves or loads in a fraction of a second, so you can change songs during a live set.

1. On the FILE screen, press RIGHT. The device changes to `REU`. All slots are listed; free slots show `-`.
2. To save: press SPACE on the `SV` row. The project goes into the slot with the same name, or into the first free slot. The help line shows `SAVED TO REU`, or `REU SLOTS FULL`.
3. To load: press SPACE, SPACE on a slot. The help line shows `LOADED FROM REU`, or `EMPTY SLOT`.
4. To delete: press C= + SPACE twice on a slot. The help line shows `SLOT DELETED`.

NOTE: Slots are lost when you switch off the computer. Save your work to disk.

Without an REU, LEFT/RIGHT shows `NEEDS REU`. With an REU smaller than 512K, it shows `REU TOO SMALL`.

### 12.6 Recovery after a reset (REU)

With an REU, SIDJ keeps a copy of your project there. After a reset or a crash:

1. Load and run SIDJ again.
2. SIDJ starts with your last project instead of the demo. The help line shows `RECOVERED`.

To start with the demo instead, hold down C= while SIDJ starts.

NOTE: This works only if the REU keeps its contents over the reset.

### 12.7 File format

Projects are saved as PRG files, format version 2. An empty project takes 2 blocks on disk. Files from other versions and other programs are refused with `NOT A SIDJ PROJECT`. The FILE screen lists only SIDJ projects and kits.

---

## CHAPTER 13: EXPORTING A SONG

To play a song outside SIDJ, convert it on a personal computer with the program `tools/sidj2sid.py`. It writes a `.sid` file for SID music players, or a `.prg` file that plays the song on a Commodore 64.

You need Python 3 and the SIDJ source folder, built with `make`. To read directly from a disk image you also need `c1541`, part of the VICE emulator.

1. Copy the project file from your disk to the computer, or use the disk image.
2. In the SIDJ folder, type one of these lines:

```
python3 tools/sidj2sid.py SONG -o song.sid
python3 tools/sidj2sid.py SONG -o song.prg
python3 tools/sidj2sid.py mydisk.d64:SONG -o song.sid
```

The ending of the output name selects the type. Without `-o`, the file is named after the project, with `.sid`.

Options for `.sid` files:

| Option | Meaning |
|---|---|
| `--title T` | title (default: the project name) |
| `--author A` | author |
| `--released R` | release line |
| `--model 8580` / `6581` / `any` | SID model (default 8580) |
| `--clock pal` / `ntsc` / `any` | video standard (default pal) |

To play a `.prg` on your Commodore 64, load it and type `RUN`.

---

## CHAPTER 14: T.A.S.T.E.

T.A.S.T.E. (The Approximate SidJ Transverter-Encoder) is a separate program for your Commodore 64. It plays part of a `.sid` tune, writes down the notes, and saves them as a SIDJ project. The result is approximate. Use it as a starting point.

### 14.1 To convert a tune

1. Copy `TASTE` and the `.sid` files onto one disk and insert it in drive 8.
2. Type `LOAD"TASTE",8` and press RETURN.
3. Type `RUN` and press RETURN.
4. The screen will show the files on the disk. Select a tune with UP/DOWN and press RETURN. Press `R` to read the directory again.
5. The screen will show the tune's name, author, addresses, number of songs and `REU: YES` or `REU: NO`.
6. Set the options (14.2).
7. Press RETURN. T.A.S.T.E. runs the tune and saves the project on drive 8 under the output name. If the file exists, the screen will show `FILE EXISTS. REPLACE IT? (Y/N)`.
8. Load SIDJ and load the project.

Press RUN/STOP to stop a capture. Press F1 to go back to the file list.

### 14.2 Options

UP and DOWN select a row. LEFT and RIGHT change the value. `+` and `-` change it in larger steps.

| Option | Meaning |
|---|---|
| SUBTUNE | which song in the file |
| VOICES | which SID voices to record; press `1`, `2` or `3` to switch each on or off |
| START (S) | seconds to skip before recording, 0–999 |
| LENGTH | how many steps to record; the screen also shows the song rows needed |
| FRAMES/STEP | the length of a step in frames; `AUTO` lets T.A.S.T.E. find it |
| NOTES | `OFF`: every note is C-4 (rhythm only) |
| INSTRUMENTS | `OFF`: every note uses instrument `00` |
| NOTE-OFFS | `OFF`: no `K` commands |
| OUTPUT NAME | the file name, up to 16 characters; DEL deletes |

Each voice goes to the SIDJ channel with the same number. Each different sound becomes an instrument, up to 64, with waveform, envelope and pulse width. Filter, sweeps, vibrato and wave tables are not recorded.

### 14.3 Limits

- Only PSID files. RSID files and tunes without a play address are refused.
- **With an REU (256K or more):** up to 256 song rows (16384 steps). The tune may use nearly all of the memory.
- **Without an REU:** up to 512 steps. The tune must load inside `$0800`–`$9FFF` or `$E000`–`$FFFF`. A tune that writes over T.A.S.T.E. stops with `TUNE OVERWRITES T.A.S.T.E. KEY: RESET`.
- When the project runs out of phrases or chains, the recording ends early and the screen shows `CUT AT STEP n`.
- Tunes that play several times per frame on the screen interrupt are recorded once per frame.

### 14.4 Hints

HINT: Record a short slice first (64 or 128 steps) to check the frames-per-step value.

HINT: If the notes fall between steps, set FRAMES/STEP by hand. Common values are 3, 6 and 12.

HINT: Record one voice at a time to take only the bass or the drums.

HINT: Use START to skip an intro.

---

## CHAPTER 15: LIMITS AND MESSAGES

### 15.1 Limits

| Item | Number |
|---|---|
| channels | 3 |
| song rows | 256 |
| chains | 128 (`00`–`7F`) |
| phrases | 255 (`00`–`FE`) |
| instruments | 64 (`00`–`3F`) |
| tables | 32 |
| grooves | 32 |
| notes | C-0 to B-7 |
| tempo | 40–295 BPM |

NOTE: The music stops while SIDJ uses the disk drive.

### 15.2 Messages

| Message | Meaning | What to do |
|---|---|---|
| `SPC AGAIN: CONFIRM` | this action needs a second press | press the same keys again |
| `NEEDS REU` | this feature needs an REU | switch the REU on, or use the list or the drive |
| `PLAY THIS PHRASE` | F6 needs the phrase on screen playing on its channel | press RETURN first |
| `REU TOO SMALL` | slots need 512K or more | use the drive |
| `REU SLOTS FULL` | all slots are in use | delete a slot, or save to disk |
| `EMPTY SLOT` | the slot holds no project | – |
| `NOT A SIDJ PROJECT` | not a SIDJ file, or an older version | – |
| `DEVICE NOT PRESENT` | no drive 8 | switch on the drive and check the cable |
| `I/O ERROR`, or a drive message | the drive reported an error, for example a full disk | use another disk |
| `NO FREE TABLES` | the kit needs more free tables | free some tables and try again |
| `NONE FREE`, `NO FREE CHAIN`, `NOT ENOUGH PHRASES` | nothing free for a clone or a new item | delete unused items |
| `NOTHING TO UNDO` | no undo step left | – |

### 15.3 If something does not work

- **SPACE + CRSR does nothing.** The field is empty. Press SPACE first.
- **Typing does nothing.** Release SPACE, C=, CTRL and SHIFT, then type.
- **No sound while editing.** SIDJ does not play notes on a channel that is playing the song. Stop the music, or edit another channel.
- **The filter sounds different on another computer.** The 6581 and 8580 SID filters differ. The presets are tuned for the 8580.
- **No mouse pointer.** Check `MOUSE` on the PROJECT screen. The mouse must be in 1351 mode.
- **The keyboard does not react while you move the joystick.** While the joystick in port 2 is moved, SIDJ reads only the joystick. FIRE works as SPACE.
