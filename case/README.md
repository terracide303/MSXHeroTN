# Case (3D-printable enclosure)

3D-printable enclosure inherited from upstream MSXnano (Tang Nano 20K based MSX2+).

> **Does not fit this fork as-is.** These parts are upstream's, designed around a bare Tang
> Nano 20K. MSXHeroTN stacks a MiSTeryShield20k on top of the board, which changes the
> height and moves every external connector — USB, DB9 and MIDI are all on the shield, not
> the Tang. The STLs are kept here unchanged for reference and for anyone building the
> upstream configuration; a shield-aware enclosure has not been designed.

## Quick print
Open **`msxnano_case_bambulab.3mf`** in **Bambu Studio** — it contains every part laid
out and ready to print all at once.

**Recommended material: white PETG.**

## Parts (STL)

| File | Part | Qty |
|------|------|-----|
| `upper_left.stl` | Top — left | 1 |
| `upper_right.stl` | Top — right | 1 |
| `lower_left.stl` | Bottom — left | 1 |
| `lower_right.stl` | Bottom — right | 1 |
| `lower_side.stl` | Bottom side (TN20K case v4) | 1 |
| `keyboard_support_a.stl` | Keyboard support A | 1 |
| `keyboard_support_b.stl` | Keyboard support B | 1 |
| `raspberry_support.stl` | Board support | 1 |
| `pillar1.stl` | Pillar 1 | 2 |
| `pillar2.stl` | Pillar 2 | 2 |
| `msxnano_case_bambulab.3mf` | Bambu Lab project (all parts) | — |

## Credits
Based on [this Thingiverse design](https://www.thingiverse.com/thing:4066021), which served
as the inspiration and starting point for this improved version.

## Assembly
See the bill of materials in [`../docs/MSXnano_BOM.xlsx`](../docs/MSXnano_BOM.xlsx) (or
[`../docs/BOM.md`](../docs/BOM.md)) and the wiring/flashing steps in the [main README](../README.md).
