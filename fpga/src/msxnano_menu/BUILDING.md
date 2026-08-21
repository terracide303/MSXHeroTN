# Building the boot menu

The menu is Z80 assembly, not RTL. It compiles to `fm_logo_menu.bin`, which
`fpga/src/rom/build.bat` concatenates into the BIOS pack — so changing it needs
no FPGA rebuild, only a reflash of the pack at `0x200000`.

## Toolchain

Upstream's `Makefile` expects four binaries in `bin/`, which are **not** in the
repository. All build from source on macOS and Linux:

| Tool | Source | Build |
|---|---|---|
| `asmsx` | [Fubukimaru/asMSX](https://github.com/Fubukimaru/asMSX) | `make` (needs flex, bison) |
| `zx0` | [einar-saukas/ZX0](https://github.com/einar-saukas/ZX0) | `gcc -O2 -o zx0 src/zx0.c src/optimize.c src/compress.c src/memory.c` — its own Makefile wants the Watcom compiler |
| `zx7mini` | [antoniovillena/zx7mini](https://github.com/antoniovillena/zx7mini) | `gcc -O2 -o zx7mini zx7mini.c` |
| `pletter` | — | **not needed.** `src/menu.asm` includes `menu_main.zx0`, so ZX7 and Pletter are run only for a size comparison. A stub that does nothing is enough |

## Verified reproducible, 2026-08-21

The committed `fm_logo_menu.bin` was rebuilt from the committed source and came out
**byte-identical** — SHA-256 `a0861febab5b8af3ee859473…`. So the binary in the tree really is
built from the source in the tree, with nothing hand-patched, and the build is deterministic:
after an edit, a diff against the old binary shows only what you actually changed.

Worth re-running that check before and after any menu work. On macOS the whole toolchain builds
in a couple of minutes:

```sh
git clone --depth 1 https://github.com/Fubukimaru/asMSX && (cd asMSX && make)
git clone --depth 1 https://github.com/einar-saukas/ZX0
gcc -O2 -o zx0 ZX0/src/zx0.c ZX0/src/optimize.c ZX0/src/compress.c ZX0/src/memory.c
git clone --depth 1 https://github.com/antoniovillena/zx7mini
gcc -O2 -o zx7mini zx7mini/zx7mini.c
printf '#!/bin/sh\nexit 0\n' > pletter && chmod +x pletter   # only used for a size comparison
```

Symlink the four into `bin/`, `mkdir out` (the Makefile does not create it), then follow the
two quirks below.

## Two quirks

**`incbin` resolves against the working directory** in asmsx v1.2.0, not against
the source file, so `make rom` fails at `menu.asm` line 36 looking for
`menu_main.zx0`. Copy `out/menu_main.zx0` next to the Makefile before the final
assembly step, or run it by hand:

```sh
./bin/asmsx -z -r ./out/ ./out/menu.asm
cp assets/16k_msx2p_fm_logo_menu.bin fm_logo_menu.bin
dd if=out/menu.z80 of=fm_logo_menu.bin bs=1 seek=1888 conv=notrunc
```

**Strings are width-constrained.** Several are padded to a fixed column count and
some come in matched pairs of exactly the same length — `RETURN=RUN  M=MAPPER
S=SRAM ESC` and `RETURN=RUN  M=MAPPER ESC` are both 32 characters. The help
screen is aligned on its colons, and the status bar has to keep fitting the
screen width. A replacement must fit its original footprint or the layout has to
be adjusted with it.

## Getting it onto a board without the system ROMs

`build.bat` assembles the BIOS pack from copyrighted MSX ROMs. If you do not have
them, splice the new menu into an existing pack instead — it occupies 16 KB at
offset `0x6C000`:

```python
pack = bytearray(open('bin/goauld_rom_int.bin','rb').read())
pack[0x6C000:0x70000] = open('fm_logo_menu.bin','rb').read()
open('goauld_rom_int_new.bin','wb').write(pack)
```

Then flash that at `0x200000`.

**Commit the spliced pack, do not only flash it.** `bin/goauld_rom_int.bin` shipped with the
stock Spanish v1.7 menu for the whole of 1.0's development, because the English menu was built,
spliced at flash time onto one board, and never written back into the pack the repository ships.
Anyone following the instructions would have got a working MSX with the wrong front end. Verify
after splicing:

```sh
python3 -c "d=open('bin/goauld_rom_int.bin','rb').read()[0x6C000:0x70000]; print(b'R/D/A=Filter' in d)"
```
