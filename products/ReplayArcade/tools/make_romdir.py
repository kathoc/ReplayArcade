# Builds a ReplayArcade ROM folder: for each game, finds the files its FBNeo driver needs
# by CRC in the zips of a source ROM folder and writes a zip complete for that game alone (non-merged).
# The source folder is never written. Clones in merged sets (daimakai inside ghouls.zip) and files
# shared with another set (ordyneje's C65 MCU inside assault.zip) are found the same way.
#
# usage: python3 -I make_romdir.py <FBNeo src/burn/drv> <source ROM dir> <output dir> [games...]
import pathlib
import sys
import zipfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from fbneo_romcheck import driver, load, roms  # noqa: E402

GAMES = "aburner2 gforce2ja sharrier splatter ordyneje dspirit genpeitd daimakai gradius gradius2 salamand aliens".split()


def main():
    drv, src, dst = map(pathlib.Path, sys.argv[1:4])
    games = sys.argv[4:] or GAMES
    load(drv)
    dst.mkdir(parents=True, exist_ok=True)
    # CRC -> (zip, member) over the whole source folder; the game's own zip and its parent first.
    index = {}
    for z in sorted(src.glob("*.zip")):
        try:
            with zipfile.ZipFile(z) as f:
                for i in f.infolist():
                    if not i.is_dir():
                        index.setdefault(i.CRC, (z, i.filename))
        except zipfile.BadZipFile:
            print(f"skip broken zip: {z.name}")
    failed = 0
    for g in games:
        d = driver(g)
        if not d:
            print(f"{g}: no FBNeo driver")
            failed += 1
            continue
        _, text, parent, _, info = d
        need = roms(text, info)
        preferred = {}
        for name in filter(None, [g, parent]):
            z = src / f"{name}.zip"
            if z.exists():
                with zipfile.ZipFile(z) as f:
                    for i in f.infolist():
                        preferred.setdefault(i.CRC, (z, i.filename))
        missing = [r for r in need if r[2] not in preferred and r[2] not in index]
        if missing:
            print(f"{g}: missing {len(missing)}: " + ", ".join(f"{r[0]} {r[2]:08x}" for r in missing[:5]))
            failed += 1
            continue
        out = dst / f"{g}.zip"
        tmp = out.with_suffix(".zip.tmp")
        with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as w:
            written = set()
            for name, _size, crc in need:
                if name in written:
                    continue
                z, member = preferred.get(crc) or index[crc]
                with zipfile.ZipFile(z) as f:
                    w.writestr(name, f.read(member))
                written.add(name)
        tmp.replace(out)
        print(f"{g}: {len(need)} files -> {out.name}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
