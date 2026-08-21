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
