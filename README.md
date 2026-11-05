# SIDJ 0.4b

A DJ-style tracker for the Commodore 64, by illobo/netmilk.

**Experimental.** Some things may not work as described, and a crash can lose
your work. Save often.

SIDJ is a music tracker for the C64 and its SID chip. Songs are built from
chains, chains from phrases, phrases from notes and commands. Each channel can
loop its own chain in live mode. A stock C64 with a disk drive runs it; a RAM
Expansion Unit, a second SID and a 1351 mouse add extras.

The disk also holds T.A.S.T.E. (turns PSID tunes into SIDJ projects), a README
and the user's manual as readers with music, ten demo songs and three drum kits.

## Try it

`sidj.d64` is the release disk. On a C64 or in VICE:

    LOAD"*",8,1
    RUN

Pick SIDJ EDITOR in the menu. The manual is on the disk (MANUAL) and in
[docs/MANUAL.md](docs/MANUAL.md); the key card is
[docs/QUICKREF.md](docs/QUICKREF.md). `site/` is the same manual as a small
website with screenshots and the box art, online at
<https://illobo.github.io/sidj/>.

## Build

You need:

- [64tass](https://sourceforge.net/projects/tass64/) 1.60 or later
- Python 3
- [Exomizer](https://bitbucket.org/magli143/exomizer/wiki/Home) 3.1 (crunches the programs for the disk)
- [VICE](https://vice-emu.sourceforge.io/) 3.x: `c1541` for the disk, `x64sc` for the tests and screenshots
- Pillow (`pip install pillow`) for the site; py65 (`pip install py65`) for the profiler and two editor tests

Then:

| Command | Result |
|---|---|
| `make` | `build/sidj.prg` (the editor), `build/taste.prg`, the player images, `SIDJ.HLP`, the demo songs |
| `make disks` | `build/sidj.d64`, the release disk |
| `make run` | the editor in VICE |
| `make site` | `build/site/`, the manual as a website with fresh screenshots (run `make test-loader` once first) |

The box art (front, back, quick reference cards) is in `art/boxart/`.

The editor, player and file code are in `src/`; the loader menu in
`src/loader/`, T.A.S.T.E. in `src/tx/`, the doc reader in `src/doc/`. The
memory map is in `src/defs.inc`. The Python tools in `tools/` generate the
loader tables, songs, kits, help pages, docs and the disk.

## Tests

The tests run in VICE through its remote monitor (ports 6511-6513) and start
and stop their own emulator: `make test-player`, `make test-editor`,
`make test-undo`, `make test-reu`, `make test-fileio`, `make test-presets`,
`make test-help`, `make test-kit`, `make test-tx`, `make test-doc`,
`make test-songs`, `make test-loader`. On macOS with Homebrew VICE the scripts
set `GSETTINGS_SCHEMA_DIR` for the GTK UI.

## License

MIT, see [LICENSE](LICENSE).
