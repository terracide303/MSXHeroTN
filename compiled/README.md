# The bitstream to flash

**`msxnano-mistle_tangnano20k.fs` is the one.** It is the 1.0 release, built from the source
beside it and verified running on real hardware.

```sh
openFPGALoader -b tangnano20k -f compiled/msxnano-mistle_tangnano20k.fs
```

Take the Tang out of the shield first. Full instructions in the [main README](../README.md).

| | |
|---|---|
| Release | 1.0, tag `msxherotn-1.0` |
| Built from | `25f80b8` |
| SHA-256 | `4733604d83c59867…` |
| Timing | `clock_54m` 54.306 MHz against 54.000, zero negative slack |

There is deliberately only one file here, so there is nothing to choose between. On this branch
the bitstream always matches the source next to it, because `main` only advances when a build
has been confirmed working on the board.

## Going back to an earlier release

Each release is tagged and carries its own matching bitstream:

```sh
git checkout msxherotn-1.0
openFPGALoader -b tangnano20k -f compiled/msxnano-mistle_tangnano20k.fs
```

Builds that failed, and the timing history behind them, are on the `dev` branch.
