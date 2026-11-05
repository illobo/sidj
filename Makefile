AS      = 64tass
VER    := $(shell cat VERSION)
ASFLAGS = -a -C -B --line-numbers -D 'SIDJ_VER="$(VER)"'

all: build/sidj.prg build/sidj-prg.bin build/sidj-sid.bin build/taste.prg build/SIDJ.HLP songs

# Extended help pages (REU): put SIDJ.HLP on the disk next to SIDJ
build/SIDJ.HLP: tools/mkhelp.py $(wildcard docs/help/*.txt)
	@mkdir -p build
	python3 tools/mkhelp.py $@ docs/help

# Player images for tools/sidj2sid.py (.prg and .sid from a saved project)
build/sidj-prg.bin: src/standalone.asm src/player.asm src/defs.inc
	@mkdir -p build
	$(AS) $(ASFLAGS) -I src src/standalone.asm -o $@ -D PSID=0 -L build/sidj-prg.lst
build/sidj-sid.bin: src/standalone.asm src/player.asm src/defs.inc
	@mkdir -p build
	$(AS) $(ASFLAGS) -I src src/standalone.asm -o $@ -D PSID=1 -L build/sidj-sid.lst

build/sidj.prg: $(wildcard src/*.asm src/*.inc src/editor/*.asm) VERSION
	@mkdir -p build
	$(AS) $(ASFLAGS) -I src src/main.asm -o $@ -L build/sidj.lst --labels=build/sidj.labels

# Free bytes per memory area (64tass warnings)
mem: $(wildcard src/*.asm src/*.inc src/editor/*.asm)
	@mkdir -p build
	@$(AS) $(ASFLAGS) -D MEMREPORT=1 -I src src/main.asm -o build/sidj-mem.prg 2>&1 | grep -o "free [A-Za-z].*[0-9]$$"

.PHONY: mem

# Illegal opcodes: the editor may use LAX (not #),
# SAX, DCP, ISB, SLO, RLA, SRE, RRA, ANC, ASR, ARR, SBX and the NOPs; the
# unstable ones are banned. The player has none (.cpu "6502" in main.asm).
ILLEGAL_BANNED = ane|xaa|las|lds|lae|sha|ahx|axa|shx|sxa|shy|sya|tas|shs|xas|jam|lxa
check-illegal: build/sidj.prg
	@if grep -nE "	(($(ILLEGAL_BANNED))( |	|$$)|lax #)" build/sidj.lst; then echo "check-illegal: banned illegal opcode"; exit 1; fi
	@echo "check-illegal: ok ($$(grep -cE '	(lax|sax|dcp|isb|slo|rla|sre|rra|anc|asr|alr|arr|sbx) ' build/sidj.lst) allowed illegal opcodes)"

.PHONY: check-illegal

# Editor development against the stub player
stub: $(wildcard src/*.asm src/*.inc src/editor/*.asm)
	@mkdir -p build
	$(AS) $(ASFLAGS) -D STUB=1 -I src src/main.asm -o build/sidj-stub.prg -L build/sidj-stub.lst --labels=build/sidj-stub.labels

run: build/sidj.prg
	x64sc -autostart build/sidj.prg

clean:
	rm -rf build

.PHONY: all stub run clean

# Headless player test in VICE (remote monitor port 6511): trace + checks
build/player_test.prg: tests/player_test.asm src/player.asm src/defs.inc
	@mkdir -p build
	$(AS) $(ASFLAGS) -I src tests/player_test.asm -o $@ -L build/player_test.lst --labels=build/player_test.labels

test-player: build/player_test.prg
	python3 tests/run_player_test.py

.PHONY: test-player

# Cycle profile of pl.tick in py65 (no VICE): slowest ticks with breakdown
build/player_test.vlabels: tests/player_test.asm src/player.asm src/defs.inc
	@mkdir -p build
	$(AS) $(ASFLAGS) -I src tests/player_test.asm -o build/player_test_prof.prg --vice-labels -l $@ >/dev/null

profile-player: build/player_test.prg build/player_test.vlabels
	python3 tests/profile_player.py build/player_test.prg build/player_test.vlabels

.PHONY: profile-player

# File I/O round trip in VICE (port 6511, true drive emulation, fresh .d64),
# format check with c1541, exported .prg run in a second VICE
test-fileio: build/sidj.prg
	python3 tests/fileio_test.py

.PHONY: test-fileio

# Same for the table scenario (three channels with tables, retriggers)
profile-player-tables: build/player_test.prg build/player_test.vlabels
	python3 tests/profile_player.py build/player_test.prg build/player_test.vlabels --tables

.PHONY: profile-player-tables

# Same for the 2SID scenario (six voices, sid2_test)
profile-player-six: build/player_test.prg build/player_test.vlabels
	python3 tests/profile_player.py build/player_test.prg build/player_test.vlabels --six

.PHONY: profile-player-six

# Undo / redo in VICE (port 6511), with an REU and without
test-undo: build/sidj.prg
	python3 tests/editor/undo.py

.PHONY: test-undo

# REU support in VICE (port 6511): 128 KB, 256 KB, 512 KB, 16 MB and none;
# detection, File screen device REU (slots), crash/reset recovery
test-reu: build/sidj.prg
	SIDJ_VICE_PORT=6511 python3 tests/editor/reu.py

# Editor tests in VICE (port 6511) without an REU (undo code at $0300) and with one;
# drum lane view (REU only, overlays 2-4) with and without; 2SID (mono, $d500, $d420);
# loop record, piano and beat repeat (port 6512, REU and none); stuck NMI line recovery
test-editor: build/sidj.prg
	SIDJ_VICE_PORT=6511 SIDJ_VICE_ARGS="+reu" python3 tests/editor/tests.py
	SIDJ_VICE_PORT=6511 SIDJ_VICE_ARGS="-reu -reusize 512" python3 tests/editor/tests.py
	SIDJ_VICE_PORT=6511 python3 tests/editor/drum.py
	SIDJ_VICE_PORT=6511 python3 tests/editor/sid2.py
	SIDJ_VICE_PORT=6512 python3 tests/editor/loop.py
	SIDJ_VICE_PORT=6511 python3 tests/editor/nmi.py

.PHONY: test-reu test-editor

# Instrument kits in VICE (port 6511, true drive emulation, fresh .d64)
test-presets: build/sidj.prg
	python3 tests/editor/presets.py

# Extended help (REU) and the REU presets/kits in VICE (port 6512; SIDJ.HLP on a .d64)
test-help: build/sidj.prg build/SIDJ.HLP
	python3 tests/editor/help.py

.PHONY: test-presets test-help

test-kit: build/sidj.prg
	python3 tests/kit_test.py

.PHONY: test-kit

# T.A.S.T.E, The Approximate SidJ Transverter-Encoder (standalone .prg)
build/taste.prg: $(wildcard src/tx/*.asm) src/defs.inc
	@mkdir -p build
	$(AS) $(ASFLAGS) -I src -I src/tx src/tx/main.asm -o $@ -L build/taste.lst --labels=build/taste.labels

# T.A.S.T.E in VICE (port 6512, true drive emulation, generated test PSIDs),
# result checked with c1541 + Python and loaded into SIDJ once
test-tx: build/taste.prg build/sidj.prg
	python3 tests/tx_test.py

.PHONY: test-tx

# Doc reader (src/doc/reader.asm, a noter with the SIDJ player): the short
# guide (README) and the manual + quick reference (MANUAL) (tools/mkdocs.py)
build/goodies/demo.sidj: tools/mkgoodies.py tools/sidj2sid.py src/editor/presetdata.asm src/editor/kits.asm
	python3 tools/mkgoodies.py build/goodies

build/doc/readme.asm: tools/mkdocs.py docs/README-C64.md build/goodies/demo.sidj
	@mkdir -p build/doc
	python3 tools/mkdocs.py $@ build/doc/readme.json "READ ME FIRST" --song build/goodies/demo.sidj docs/README-C64.md
build/doc/manual.asm: tools/mkdocs.py docs/MANUAL.md docs/QUICKREF.md build/goodies/demo.sidj
	@mkdir -p build/doc
	python3 tools/mkdocs.py $@ build/doc/manual.json "USER'S MANUAL" --song build/goodies/demo.sidj docs/MANUAL.md docs/QUICKREF.md

build/readme.prg: src/doc/reader.asm build/doc/readme.asm src/player.asm src/defs.inc
	$(AS) $(ASFLAGS) -I src -I . -D 'DOCSRC="build/doc/readme.asm"' -D 'SIDE="README"' src/doc/reader.asm -o $@ -L build/doc/readme.lst --labels=build/doc/readme.labels
build/manual.prg: src/doc/reader.asm build/doc/manual.asm src/player.asm src/defs.inc
	$(AS) $(ASFLAGS) -I src -I . -D 'DOCSRC="build/doc/manual.asm"' -D 'SIDE="MANUAL"' src/doc/reader.asm -o $@ -L build/doc/manual.lst --labels=build/doc/manual.labels

docs: build/readme.prg build/manual.prg

test-doc: build/readme.prg build/manual.prg
	python3 tests/doc_test.py

.PHONY: docs test-doc

# Loader menu: "SIDJ", the first file on the disk; it
# chains to SIDJ.EDITOR, TASTE, README and MANUAL
build/loader/gen.asm: tools/mkloader.py VERSION
	@mkdir -p build/loader
	python3 tools/mkloader.py $@
build/loader.prg: src/loader/loader.asm build/loader/gen.asm src/tx/reu.asm src/editor/boot_sid.asm
	$(AS) $(ASFLAGS) -I build/loader -I src/tx -I src/editor src/loader/loader.asm -o $@ -L build/loader/loader.lst --labels=build/loader/loader.labels
loader: build/loader.prg

# Loader in VICE (port 6511, true drive emulation, the release disk)
test-loader: disks
	python3 tests/loader_test.py

.PHONY: loader test-loader

# Release disk: build/sidj.d64 (SIDJ, SIDJ.EDITOR, T.A.S.T.E, README, MANUAL,
# SIDJ.HLP, the demo, build/songs/*.sidj if made, factory kits): crunched, it all fits one 1541 disk.
# No HVSC tunes on these: they belong to their composers.
# Exomizer (brew install exomizer): self-extracting .prg files for the disks,
# border flash while unpacking (-x1); same names, load and RUN as before
CRUNCH = loader sidj taste readme manual
build/x/%.prg: build/%.prg
	@mkdir -p build/x
	exomizer sfx sys -x1 -q $< -o $@

crunch: $(CRUNCH:%=build/x/%.prg)

.PHONY: crunch

disks: all build/loader.prg build/readme.prg build/manual.prg build/goodies/demo.sidj crunch
	python3 tools/mkdisks.py release

# Local test disk with HVSC tunes from build/hvsc (not for release)
disk-hvsc: build/loader.prg build/sidj.prg build/taste.prg build/SIDJ.HLP crunch
	python3 tools/mkdisks.py hvsc

.PHONY: disks disk-hvsc

# Ten demo songs as SIDJ projects (tools/mksongs.py): build/songs/*.sidj
build/songs/.done: tools/mksongs.py tools/sidj2sid.py src/editor/presetdata.asm
	python3 tools/mksongs.py build/songs
	@touch $@

songs: build/songs/.done

# Demo songs: format, limits, references, alloc bits; each rendered to .sid
# and played in VICE vsid (port 6512)
test-songs: build/songs/.done build/sidj-sid.bin
	python3 tests/songs_test.py

.PHONY: songs test-songs

# Minisite (build/site): every editor screen shot in VICE (port 6513), then the
# manual chapters, quick reference and front page as static HTML
site: build/sidj.prg disks
	python3 tools/mkshots.py
	python3 tools/mksite.py

.PHONY: site