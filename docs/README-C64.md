# SIDJ · READ ME FIRST

The short guide. The full manual is on the same disk: MANUAL in the menu.

NOTE: SIDJ 0.4b is experimental. Some things may not work as described, and a crash can lose your work. Save often.

## LOADING

1. Switch on the disk drive, then your Commodore 64.
2. Insert the SIDJ disk in drive 8.
3. Type `LOAD"SIDJ",8` (or `LOAD"*",8,1`) and press RETURN.
4. Type `RUN` and press RETURN.
5. The menu appears. Press RETURN on SIDJ EDITOR, or press 1.

The menu also starts T.A.S.T.E. (2), this guide (3) and the manual (4). Use CRSR or a joystick in port 2 and RETURN, or the keys 1-4 or F1/F3/F5/F7. To skip the menu, type `LOAD"SIDJ.EDITOR",8`.

SIDJ starts on the SONG screen with a short demo song. Press RETURN to play it, and RETURN again to stop.

On a C64 Ultimate, mount the disk image on drive 8 and start `SIDJ` (the menu) or `SIDJ.EDITOR` from the file browser. To use the REU features, switch the REU on before you start SIDJ.

NOTE: Keep `SIDJ.HLP` on the disk next to SIDJ. With an REU, F2 (SHIFT + F1) then shows a help page for each screen.

## THE KEYS

SIDJ works with four keys:

| Key | Use |
|---|---|
| SPACE | edit |
| C= | second edit key |
| CTRL | select, change screen |
| RETURN | play and stop |

UP is SHIFT + CRSR ⇩. LEFT is SHIFT + CRSR ⇨.

"SPACE + RIGHT" means: hold SPACE, then press RIGHT. "SPACE, SPACE" means: press SPACE twice, quickly.

| Keys | Effect |
|---|---|
| CTRL + CRSR | change screen |
| SPACE | enter a value, or play it |
| SPACE, SPACE | new chain or phrase |
| SPACE + CRSR | change the value |
| C= + SPACE | cut |
| CTRL + SPACE | paste |
| RETURN | play / stop |
| CTRL + RETURN | play / stop the song |
| F1 F3 F5 | mute channel 1 2 3 |
| F7 | undo |

## YOUR FIRST SONG

1. CTRL + RIGHT twice, then CTRL + UP: the PROJECT screen. Move to `CLEAN` and press SPACE, SPACE. The project is now empty.
2. CTRL + DOWN, then CTRL + LEFT twice: the SONG screen. On row `00`, channel 1, press SPACE, SPACE. Chain `00` appears.
3. CTRL + RIGHT: the CHAIN screen. On step `0` press SPACE, SPACE. Phrase `00` appears.
4. CTRL + RIGHT: the PHRASE screen. CTRL + RIGHT again: the INSTR screen.
5. Move to `PRESET`. Hold SPACE and press RIGHT to hear the factory sounds. Stop at a lead.
6. CTRL + LEFT: back to the PHRASE screen. On step `0`, note column, press SPACE. You hear `C-4`.
7. Hold SPACE and press RIGHT or UP to change the note. Or type a note letter `A`–`G` and an octave `0`–`7`.
8. Add notes on steps `4`, `8` and `C` with SPACE.
9. Press RETURN to hear the phrase. Press RETURN again to stop.
10. CTRL + LEFT twice: the SONG screen. On row `01`, channel 1, press SPACE to play chain `00` again. Press RETURN on row `00` to play the song.

To save, enter a `NAME` on the PROJECT screen, move to `SAVE` and press SPACE, then SPACE again.

HINT: For drums, go to the INSTR screen, move to `PRESET` and press CTRL + SPACE. Eight drum sounds fill eight instruments.

## MORE ON THE DISK

Also on the disk:

| File | Content |
|---|---|
| MANUAL | the full user's manual and the quick reference card, in this reader |
| DEMO | the demo song |
| 10 demo songs | techno songs to load, play and change |
| DRUMS.K00 | factory kit: drums |
| BAND.K00 | factory kit: band |
| SYNTH.K00 | factory kit: synth |

To read the manual, type `LOAD"MANUAL",8` and press RETURN, then `RUN`.

Load the demo songs and kits in SIDJ from the PROJECT screen, `LOAD`. A kit goes into the instruments from the one shown on the INSTR screen.

In this reader: CRSR UP and DOWN choose and scroll, RETURN opens a chapter, SPACE and SHIFT + SPACE turn the page, RUN/STOP goes back. M switches the music on and off.
