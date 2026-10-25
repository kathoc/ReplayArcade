# Licensing

ReplayArcade combines two bodies of code under different licences.

## ReplayArcade and ReplayNES code: GPL-2.0-or-later with an additional permission

The code in this repository (except `third_party/`) and the ReplayNES code it is built from
(`third_party/replaynes`, https://github.com/kathoc/ReplayNES) are licensed under the GNU General
Public License, version 2 or (at your option) any later version (`LICENSE`), with the following
additional permission.

> **Additional permission (FinalBurn Neo).** As a special exception, the copyright holder of
> ReplayArcade and of ReplayNES (kathoc) gives you permission to combine this program, and ReplayNES
> code used by it, with FinalBurn Neo (https://github.com/finalburnneo/FBNeo, including its libretro
> port and modified versions of it), and to distribute the resulting combined work, provided that the
> FinalBurn Neo parts are distributed under the terms of the FinalBurn Neo licence
> (`LICENSE-FBNeo.txt`) and the rest under the GNU GPL. You may extend this exception to your
> modified versions of this program, but you are not obliged to do so; if you do not wish to, delete
> this exception statement from your version.
>
> This permission covers only code whose copyright is held by kathoc. It does not apply to any
> third-party code licensed under the GPL; ReplayArcade builds contain no such code linked together
> with FinalBurn Neo (in particular, the Nestopia core of ReplayNES is not built into ReplayArcade).

## FinalBurn Neo: its own non-commercial licence

`third_party/fbneo` (libretro/FBNeo) and the patch applied to it (`patches/fbneo/`) are under the
FinalBurn Neo licence, reproduced verbatim in `LICENSE-FBNeo.txt`. In short: no selling or other
monetary profit, no donations requested for projects using it, source changes must be public (they
are: `patches/fbneo/`), the licence text must be included, and it must not be distributed with ROM
images. Parts of FinalBurn Neo come from MAME and other projects with their own licences (listed in
`LICENSE-FBNeo.txt`). ReplayArcade is free and asks for no donations.

## Other third-party components

See `THIRD_PARTY_NOTICES.md`.

## No game software

ReplayArcade contains no game ROMs, BIOS files or other copyrighted game data, and none are
distributed with it. Use only ROM images you have the legal right to use.
