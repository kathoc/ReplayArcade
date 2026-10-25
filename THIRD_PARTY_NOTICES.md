# Third-Party Notices

ReplayArcade is built from ReplayNES's sources (`third_party/replaynes`) and FinalBurn Neo
(`third_party/fbneo`). Licensing of the combination: `COPYING.md`.

## FinalBurn Neo (arcade emulation core)

- Project: https://github.com/finalburnneo/FBNeo, used as its libretro port
  https://github.com/libretro/FBNeo (pinned commit in `third_party/fbneo`).
- Changes: `patches/fbneo/0001-replayarcade-determinism.patch` (replay determinism), applied at build time.
- License: the FinalBurn Neo licence, reproduced verbatim in `LICENSE-FBNeo.txt` (includes the list of
  MAME-derived and other components inside FinalBurn Neo and their own licences). FinalBurn Neo
  bundles its own zlib (zlib licence) and LZMA SDK (public domain).

## libretro-common and the libretro API (FinalBurn Neo's frontend interface)

- Project: https://github.com/libretro/libretro-common (copy inside `third_party/fbneo`).
- License: MIT (libretro-common); the `libretro.h` header carries its own MIT-style statement.

## Components from ReplayNES

The following are used as in ReplayNES; their full licence texts are in
`third_party/replaynes/THIRD_PARTY_NOTICES.md`:

- Dear ImGui (MIT) - user interface.
- SDL3 (zlib) - window, audio, gamepads; Vulkan loader on Linux (Apache-2.0).
- Tabler Icons (MIT) - menu icons.
- Noto Sans Black (SIL Open Font License 1.1) - Steam artwork wordmark.
- nesterm physical CRT model (MIT, by kathoc) - CRT display code (used by the NES picture path only).
- WinSparkle (MIT) - in-app updates of the Windows app, when updates are enabled.

Not part of ReplayArcade: the Nestopia NES core (GPL), Sparkle and Syphon (macOS app only) and the NES
game database.

## FFmpeg (MP4 export, Linux app)

Not bundled: the Linux app uses the FFmpeg libraries of the `org.freedesktop.Platform` runtime
(LGPL-2.1-or-later; its `codecs-extra` extension provides the H.264 encoders). The Windows app uses
Windows Media Foundation.

## Game titles (data/arcadedb.tsv)

- Titles, makers, years and genres of the arcade sets come from FinalBurn Neo's driver table.
- Japanese titles and readings: [Wikidata](https://www.wikidata.org/) (CC0), cached in
  `data/wikidata-arcade.json` by `tools/fetch_arcade_wikidata.py`; of Japanese Wikipedia only the reading
  given in parentheses after an article's title is kept (no article text). Hand-written corrections in
  `data/arcadedb-ja.tsv`.

## No game software

No ROM images, BIOS files or other game data are included or distributed.
