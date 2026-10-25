# ReplayArcade

ReplayArcade is [ReplayNES](https://github.com/kathoc/ReplayNES) for arcade games: the same
record-everything player, with [FinalBurn Neo](https://github.com/finalburnneo/FBNeo) as its core.

- Every session is recorded: rewind (L2), retry from any point, takes, bookmarks.
- Practice sections (A/B) with a countdown, autosave and resume.
- Make Video: MP4 export of any range.
- Per-game button assignment and turbo, remembered separately for pads and arcade sticks
  (detected automatically, changeable on the Controller page).
- Controller-only operation, Japanese and English UI.
- Replays are exact: FinalBurn Neo is patched for determinism (`patches/fbneo/`); a recording replays
  identically on Linux and Windows.

Platforms: Steam Deck / Linux (Flatpak) and Windows x64.

**No ROMs are included.** Put the ROM zips you are entitled to use (FinalBurn Neo set names,
non-merged; e.g. `gradius.zip`) in `Documents/ReplayArcade/ROM`.

## Building

```bash
git clone --recursive https://github.com/kathoc/ReplayArcade.git
cd ReplayArcade
scripts/fbneo-patches.sh            # applies the FinalBurn Neo patch

# Linux app and tests (engine tests need ROMs: REPLAYARCADE_ROMS=<dir>)
cmake -S . -B build && cmake --build build -j
# Flatpak (Steam Deck): packaging/linux/io.github.kathoc.ReplayArcade.yml
# Windows x64 (cross build with llvm-mingw, see ReplayNES's docs/WINDOWS.md)
scripts/build-windows.sh x86_64
```

## License

GPL-2.0-or-later with an additional permission to combine with FinalBurn Neo, which is under its own
non-commercial licence. See `COPYING.md`, `LICENSE`, `LICENSE-FBNeo.txt` and
`THIRD_PARTY_NOTICES.md`. ReplayArcade is free and asks for no donations.
