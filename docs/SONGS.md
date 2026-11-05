# Demo songs

Ten techno songs for SIDJ, all original. `make songs` writes them as project files to `build/songs/*.sidj` (tools/mksongs.py); `make test-songs` checks them and plays each one as a .sid in VICE.

Each song uses three channels (it plays on every C64), groove 00 (6/6, a step is a sixteenth note) and only the 32 base factory presets, some with their bytes changed. Channel 1 is drums, channel 2 bass, channel 3 lead, arpeggio, chords or pad. Every song is 80 bars long: intro, build, drop, break, build, second drop, outro. At the end the song starts again from the top.

| Title | Style | BPM | Length | |
|---|---|---|---|---|
| ACID RASTER | acid | 132 | 2:25 | 303-style A-minor line on the acid preset. X raises the cutoff bar by bar. A minor-arp stab answers the line, and a saw hook plays over the second drop. |
| POKE 53280 | driving minimal | 128 | 2:30 | Off-beat pulse bass in F minor. A blip on every third step shifts against the bar while S widens its pulse. Minor stabs come in for the second drop. |
| SPRITE SKIES | melodic trance | 138 | 2:19 | Am-F-C-G with a rolling saw bass. The saw arpeggio's low-pass opens over the first half. String chords play in the break, a 3-3-2 saw hook in the second drop. |
| TAPE LOOP DUB | dub techno | 124 | 2:34 | Filtered Dm7 stabs, each echoed three times a dotted eighth apart, every repeat darker and shorter. Triangle sub bass, rim and open-hat shuffle. |
| JOYPORT ELECTRO | electro | 128 | 2:30 | Plucked filtered bass in E minor, a staccato PWM riff, toms at three pitches, rims and claps. A sync lead takes over in the second drop. |
| KERNAL PANIC | hard / industrial | 138 | 2:19 | Rolling filtered bass in E phrygian and a snare-heavy beat. Bells are ring-modulated by the bass voice, with noise stabs, lasers and zaps. A noise riser leads into each drop. |
| BASIC HOUSE | piano house | 124 | 2:34 | C-Am-F-G as decaying pulse chords in a syncopated piano rhythm. A slow low-pass pad plays in the intro and the break. Off-beat saw bass. |
| PETSCII BOUNCE | chiptune techno | 130 | 2:27 | G-Em-C-D over an octave-bouncing pulse bass. Chord stabs come from the major and minor arp presets, and a PWM melody plays in the second drop. |
| UNDER THE ROM | dark rolling | 132 | 2:25 | Rolling PWM bass in G minor with a flat-second turn; its cutoff opens and closes over the song. A plucked saw motif and a slow string line play over it. |
| SYS 64738 | big room | 128 | 2:30 | The closer, in F minor. PWM pad chords, then a snare roll that doubles in speed every two bars into a noise riser and a half-bar gap. Octave saw stabs drop over the kick and a triangle sub. |

## Files

- `build/songs/<name>.sidj`: the project, to put on a disk image and load with SIDJ. `c1541 IMAGE -write build/songs/acid_raster.sidj "acid raster"` writes it under the name SIDJ lists.
- `build/songs/<name>.sid`: written by `make test-songs` (`tools/sidj2sid.py --author SIDJ`), for SID players.

## Changing a song

The songs are Python functions in `tools/mksongs.py`. A phrase is 16 tokens: `C-4`, `.` (no note), `-` (note off, `K00`), each optionally with `@instrument` and `:Cvv` (a command). A drum phrase is 16 letters from the song's kit, for example `k.h.k.h.k.h.k.h.`. Chains list phrases with a transpose. Song rows name one chain per channel. Phrases, chains, instruments and tables are numbered in the order the song first uses them.
