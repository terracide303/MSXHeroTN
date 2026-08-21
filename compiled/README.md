# The bitstream to flash

**`msxnano-mistle_tangnano20k.fs` is the one.** It is the 1.1 release, built from the source
beside it and verified running on real hardware.

Note that 1.1 changed only the boot menu, which lives in the BIOS pack rather than in the
bitstream — so this file is byte-identical to the one shipped with 1.0. Upgrading from 1.0
means reflashing [`bin/goauld_rom_int.bin`](../bin/) only.

```sh
openFPGALoader -b tangnano20k -f compiled/msxnano-mistle_tangnano20k.fs
```

Take the Tang out of the shield first. Full instructions in the [main README](../README.md).

| | |
|---|---|
| Release | 1.1, tag `msxherotn-1.1` |
| Built from | `25f80b8` |
| SHA-256 | `4733604d83c59867…` |
| Timing | `clock_54m` 54.306 MHz against 54.000, zero negative slack |

There is deliberately only one file here, so there is nothing to choose between. On this branch
the bitstream always matches the source next to it, because `main` only advances when a build
has been confirmed working on the board.

## Going back to an earlier release

Each release is tagged and carries its own matching bitstream:

```sh
git checkout msxherotn-1.1
openFPGALoader -b tangnano20k -f compiled/msxnano-mistle_tangnano20k.fs
openFPGALoader -b tangnano20k --external-flash -o 0x200000 --file-type raw bin/goauld_rom_int.bin
```

Builds that failed, and the timing history behind them, are on the `dev` branch.
