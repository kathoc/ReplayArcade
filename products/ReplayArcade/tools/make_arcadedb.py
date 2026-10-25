# Writes ReplayArcade's game database (data/arcadedb.tsv, the format of ReplayNES's nesdb.tsv) from
# FBNeo's driver table: one G row per arcade set (its title without the version in parentheses,
# maker, year, genre; the set name as the alias the ROM file is matched by), after the hand-written
# rows of data/arcadedb-base.tsv (those sets keep them). Console drivers, BIOS sets and the like are
# left out.
#
# Japanese titles, for every set (also sets added to FBNeo later), first source that has one:
#   1. data/arcadedb-ja.tsv (hand-written; also the set's clones of the same English title)
#   2. Wikidata (data/wikidata-arcade.json, tools/fetch_arcade_wikidata.py): the item whose MAME ROM name
#      is the set, else one of its clone family's
#   3. Wikidata: the video game whose English label or alias is the set's title (then its parent's, its
#      clones'), released within 2 years of the set; several candidates count only when they agree
#   4. the Japanese part of FBNeo's wide name (szFullNameW: "English\0日本語\0")
# Readings: arcadedb-ja.tsv > Wikidata kana name (P1814) > the title itself when written in kana >
# the reading in Japanese Wikipedia's opening > the set's FBNeo title read as romaji (Daimakaimura) >
# none; the last two only when they fit the kana of the title (kanji may stand for 1-4 kana each).
#
# usage: python3 -I make_arcadedb.py [--check] [--report] <FBNeo src/burn/drv> <data dir>
#   --check: write nothing, fail when data/arcadedb.tsv differs from what would be written
#   --report: also print how many sets got a Japanese title / a reading, by source
import collections
import json
import pathlib
import re
import sys
import unicodedata

# Home systems by the hardware prefix of the driver (burn.h HARDWARE_PREFIX_*): they live in console
# directories and also among the arcade drivers (Neo Geo Pocket in neogeo/, Bally Astrocade in pre90s/).
CONSOLE_PREFIXES = {"SEGA_MEGADRIVE", "PCENGINE", "SEGA_MASTER_SYSTEM", "SEGA_SG1000", "COLECO", "SEGA_GAME_GEAR", "MSX",
                    "SPECTRUM", "NES", "FDS", "NGP", "CHANNELF", "SNES", "ASTROHOME", "GBA"}
CONSOLE_DIRS = {"channelf", "coleco", "gba", "megadrive", "msx", "nes", "pce", "sg1000", "sms", "snes", "spectrum"}
# FBNeo genre flags (burn.h) -> ReplayNES genre codes, the first that matches.
GENRES = [
    (1 << 3, "fighting"), (1 << 0 | 1 << 1 | 1 << 19 | 1 << 20, "shooter"), (1 << 18, "racing"),
    (1 << 12, "puzzle"), (1 << 14 | 1 << 15, "sports"), (1 << 25, "rpg"), (1 << 27, "adventure"),
    (1 << 23, "strategy"), (1 << 6 | 1 << 17 | 1 << 28 | 1 << 29, "table"),
    (1 << 2 | 1 << 5 | 1 << 7 | 1 << 8 | 1 << 11 | 1 << 21 | 1 << 22 | 1 << 10, "action"),
]
GBF_BIOS = 1 << 4
DRIVER = re.compile(r'struct\s+BurnDriver\w*\s+BurnDrv\w+\s*=\s*\{(.*?)\};', re.S)
# A string (narrow, or wide L"..." with \uXXXX escapes), or a bare token (NULL, flags, numbers).
TOKEN = re.compile(r'(L?)"((?:[^"\\]|\\.)*)"|([^,"\s][^,"]*)')


def fields(body):
    out = []
    for m in TOKEN.finditer(body):
        if m.group(2) is not None and m.group(1):  # wide: keep the \0 separators
            out.append(re.sub(r"\\u([0-9A-Fa-f]{4})", lambda u: chr(int(u.group(1), 16)), m.group(2)).replace("\\0", "\0"))
        elif m.group(2) is not None:
            out.append(m.group(2).replace("\\0", "").replace('\\"', '"'))
        else:
            v = m.group(3).strip()
            out.append(None if v == "NULL" else v)
        if len(out) == 17:
            break
    return out


def flags(expr, names):
    v = 0
    for part in (expr or "").split("|"):
        part = part.strip()
        if part in names:
            v |= names[part]
        elif re.fullmatch(r"0x[0-9a-fA-F]+|\d+", part):
            v |= int(part, 0)
    return v


def title(full):
    """The name without the version in (nested) parentheses at its end, nor an " / " alternative."""
    t = full.split(" / ")[0].strip()
    while t.endswith(")"):
        depth = 0
        for i in range(len(t) - 1, -1, -1):
            depth += {")": 1, "(": -1}.get(t[i], 0)
            if depth == 0:
                break
        if depth or i == 0:
            break
        t = t[:i].rstrip()
    return t


def read_sets(drv):
    """{set: {parent, en, maker, year, genre}} of FBNeo's arcade drivers (no consoles, BIOS or board sets)."""
    burn_h = (drv.parent / "burn.h").read_text(errors="ignore")
    names = {m.group(1): int(m.group(2), 0) for m in re.finditer(r"#define\s+(GBF_\w+|BDF_\w+)\s+\(?\s*(?:1\s*<<\s*)?(\d+|0x[0-9a-fA-F]+)", burn_h)}
    for m in re.finditer(r"#define\s+(GBF_\w+|BDF_\w+)\s+\(\s*1\s*<<\s*(\d+)\s*\)", burn_h):
        names[m.group(1)] = 1 << int(m.group(2))
    console_hw = {m.group(1) for m in re.finditer(r"#define\s+(HARDWARE_\w+)\s+\(?\s*HARDWARE_PREFIX_(\w+)", burn_h)
                  if m.group(2) in CONSOLE_PREFIXES}
    sets, bios = {}, set()
    for p in sorted(drv.rglob("d_*.cpp")):
        if p.relative_to(drv).parts[0] in CONSOLE_DIRS:
            continue
        for m in DRIVER.finditer(p.read_text(errors="ignore")):
            f = fields(m.group(1))
            if len(f) < 17 or not f[0] or not f[5]:
                continue
            if any(h.strip() in console_hw for h in (f[15] or "").split("|")):
                continue
            bdf, genre = flags(f[13], names), flags(f[16], names)
            if bdf & names.get("BDF_BOARDROM", 0) or genre & GBF_BIOS:
                bios.add(f[0])  # also when another driver of that name (#if'd) is a system
                continue
            year = re.match(r"\d{4}", f[4] or "")
            wide = (f[9] or "").split("\0")
            sets[f[0]] = dict(parent=f[1], en=title(f[5]), maker=(f[7] or "").strip(), year=year.group(0) if year else "",
                              genre=next((g for bits, g in GENRES if genre & bits), "other" if genre else ""),
                              wide_ja=title(wide[1]) if len(wide) > 1 and JAPANESE.search(wide[1]) else "")
    for s in bios:
        sets.pop(s, None)
    return sets


# ---- kana
JAPANESE = re.compile(r"[぀-ヿ㐀-鿿豈-﫿]")
KANJI = re.compile(r"[々〆㐀-鿿豈-﫿]")
DROP = re.compile(r"[\s・･\-‐－―~〜～!！?？:：、。,.，．'’\"“”「」『』（）()\[\]【】&＆/／☆★♪]")


def hiragana(s):
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in s)


def katakana(s):
    return "".join(chr(ord(c) + 0x60) if "ぁ" <= c <= "ゖ" else c for c in s)


def kana_only(s):
    """The title's reading when it is written in kana alone (digits kept), else ""."""
    t = DROP.sub("", unicodedata.normalize("NFKC", s))
    return katakana(t) if t and re.fullmatch(r"[ぁ-ゖァ-ヺー0-9]+", t) else ""


KANA = dict(zip(
    """a i u e o ka ki ku ke ko sa shi su se so ta chi tsu te to na ni nu ne no ha hi fu he ho ma mi mu me mo
    ya yu yo ra ri ru re ro wa wo ga gi gu ge go za ji zu ze zo da de do ba bi bu be bo pa pi pu pe po
    kya kyu kyo sha shu sho cha chu cho nya nyu nyo hya hyu hyo mya myu myo rya ryu ryo gya gyu gyo ja ju jo
    bya byu byo pya pyu pyo si ti tu hu zi du dzu je fa fi fe fo""".split(),
    """あ い う え お か き く け こ さ し す せ そ た ち つ て と な に ぬ ね の は ひ ふ へ ほ ま み む め も
    や ゆ よ ら り る れ ろ わ を が ぎ ぐ げ ご ざ じ ず ぜ ぞ だ で ど ば び ぶ べ ぼ ぱ ぴ ぷ ぺ ぽ
    きゃ きゅ きょ しゃ しゅ しょ ちゃ ちゅ ちょ にゃ にゅ にょ ひゃ ひゅ ひょ みゃ みゅ みょ りゃ りゅ りょ ぎゃ ぎゅ ぎょ じゃ じゅ じょ
    びゃ びゅ びょ ぴゃ ぴゅ ぴょ し ち つ ふ じ づ づ じぇ ふぁ ふぃ ふぇ ふぉ""".split()))

def romaji(s):
    """FBNeo's romanized title (Daimakaimura, Juuouki, Ougon no Shiro) in hiragana, or None when it is not
    romaji (English words do not parse: l, q, th, ...). Digits are kept."""
    t = unicodedata.normalize("NFKD", s.lower())
    t = t.replace("̄", "u").replace("̂", "u")  # ō / ô (Hepburn long vowels) as ou
    t = re.sub(r"[^a-z0-9]", "", t)
    out, i = "", 0
    while i < len(t):
        if t[i].isdigit():
            out += t[i]; i += 1; continue
        if t[i] == "n" and (i + 1 == len(t) or t[i + 1] not in "aiueoy"):
            out += "ん"; i += 1; continue
        if i + 1 < len(t) and t[i] == t[i + 1] and t[i] not in "aiueon":
            out += "っ"; i += 1; continue
        if t[i] == "t" and t[i + 1:i + 3] == "ch":
            out += "っ"; i += 1; continue
        for n in (3, 2, 1):
            if t[i:i + n] in KANA:
                out += KANA[t[i:i + n]]; i += n; break
        else:
            return None
    return out or None


def fit(title, reading):
    """The reading (hiragana) in katakana when it fits the title: the title's kana (in their own spelling:
    ー stays) and digits as written, each run of n kanji 1..4n kana. "" when it does not fit."""
    t = hiragana(DROP.sub("", unicodedata.normalize("NFKC", title)))
    if not t or re.search(r"[A-Za-z]", t):
        return ""
    parts, pattern = [], ""
    for run in re.finditer(r"[々〆㐀-鿿豈-﫿]+|[ぁ-ゖー0-9]+|.", t):
        r = run.group(0)
        if KANJI.match(r):
            pattern += f"(.{{{len(r)},{4 * len(r)}}}?)"; parts.append(None)
        elif re.fullmatch(r"[ぁ-ゖー0-9]+", r):
            pattern += "(" + "".join("[ぁ-ゖー]" if c == "ー" else re.escape(c) for c in r) + ")"; parts.append(r)
        else:
            return ""
    m = re.fullmatch(pattern, hiragana(DROP.sub("", reading)))
    if not m:
        return ""
    return katakana("".join(p if p is not None else m.group(k + 1) for k, p in enumerate(parts)))


def norm_title(s):
    s = unicodedata.normalize("NFKC", s).lower().replace("&", "and")
    return re.sub(r"[^a-z0-9]+", "", s)


def variants(t):
    """Shorter forms of a title: without the subtitle after " - " / ": ", without a leading "The "."""
    out = {t}
    for sep in (" - ", ": "):
        if sep in t:
            out.add(t.split(sep)[0].strip())
    for v in list(out):
        if v.startswith("The "):
            out.add(v[4:])
    return {norm_title(v) for v in out if len(v) >= 2} - {norm_title(t)}


ARCADE = "Q192851"


def wikidata_ja(label):
    """A Wikidata Japanese label as a title: without a Wikipedia-style disambiguation at its end
    ("サイドアーム (シューティングゲーム)", "サブマリン (ナムコ)"); "" for a label naming a section ("...#...")."""
    if "#" in label:
        return ""
    return re.sub(r"\s+[（(][^()（）]*[)）]$", "", label).strip()


def wikidata_titles(sets, items):
    """{set: (Japanese title, reading or "", source)} from the Wikidata cache (sources 2 and 3)."""
    by_rom, by_title = collections.defaultdict(set), collections.defaultdict(set)
    items = {q: dict(it, ja=wikidata_ja(it["ja"])) for q, it in items.items()}
    for q, it in items.items():
        if not it["ja"]:
            continue
        for r in it["roms"]:
            by_rom[r].add(q)
        for t in [it["en"]] + it["aliases"]:
            by_title[norm_title(t)].add(q)
    family = collections.defaultdict(list)
    for s, g in sets.items():
        family[g["parent"] or s].append(s)
    # A shorter form that is another family's title names that game (Arkanoid - Revenge of DOH -> Arkanoid).
    family_of_title = collections.defaultdict(set)
    for s, g in sets.items():
        family_of_title[norm_title(g["en"])].add(g["parent"] or s)
    out = {}
    for s, g in sets.items():
        fam = g["parent"] or s
        members = [fam] + [o for o in family[fam] if o != fam]
        found = by_rom.get(s) or by_rom.get(fam) or set().union(*(by_rom.get(o, set()) for o in members))
        source = "rom"
        if len(found) != 1:
            year = int(g["year"] or 0)
            found = set()
            # The set's own title first, then its family's; each full, then its shorter forms.
            tries = [(o, full) for o in [s] + members if o in sets for full in (True, False)]
            for o, full in tries:
                keys = {norm_title(sets[o]["en"])} if full else \
                    {v for v in variants(sets[o]["en"]) if not family_of_title.get(v, set()) - {fam}}
                c = set().union(*(by_title.get(v, set()) for v in keys))
                c = {q for q in c if not year or not items[q]["years"] or min(abs(y - year) for y in items[q]["years"]) <= 2}
                if len(c) > 1:  # prefer arcade releases / items with a MAME ROM name
                    c = {q for q in c if ARCADE in items[q]["platforms"] or items[q]["roms"]} or c
                if c:
                    found = c
                    break
            source = "title"
        if not found or len({items[q]["ja"] for q in found}) != 1:
            continue
        q = min(found, key=lambda q: int(q[1:]))
        it = items[q]
        out[s] = (it["ja"], it["kana"], it["jawiki_reading"], source)
    return out


def main():
    args = sys.argv[1:]
    check = "--check" in args
    report = "--report" in args
    args = [a for a in args if not a.startswith("--")]
    drv, data = map(pathlib.Path, args[:2])
    sets = read_sets(drv)
    # Japanese: "G set ja reading" (also its clones of the same English title), "M maker ja".
    ja, makers_ja = {}, {}
    for line in (data / "arcadedb-ja.tsv").read_text(encoding="utf-8").splitlines():
        if line.startswith("#"):
            continue
        c = line.split("\t")
        if c[0] == "G" and len(c) >= 4:
            ja[c[1]] = (c[2], c[3])
        elif c[0] == "M" and len(c) >= 3:
            makers_ja[c[1]] = c[2]
    unknown = [s for s in ja if s not in sets]
    if unknown:
        sys.exit("arcadedb-ja.tsv: not FBNeo sets: " + " ".join(unknown))
    for s, (t, r) in list(ja.items()):
        fam = sets[s]["parent"] or s
        for o, g in sets.items():
            if o not in ja and (o == fam or g["parent"] == fam) and g["en"] == sets[s]["en"]:
                ja[o] = (t, r)
    sources = {s: "hand" for s in ja}
    cache = data / "wikidata-arcade.json"
    wd = wikidata_titles(sets, json.loads(cache.read_text(encoding="utf-8"))["items"]) if cache.exists() else {}
    for s, g in sets.items():
        if s in ja:
            continue
        if s in wd:
            t, kana, wiki, src = wd[s]
        elif g["wide_ja"]:
            t, kana, wiki, src = g["wide_ja"], "", "", "fbneo"
        else:
            continue
        own = romaji(g["en"])
        r = (katakana(hiragana(DROP.sub("", kana))) if kana else "") or kana_only(t) or (fit(t, wiki) if wiki else "") \
            or (fit(t, own) if own else "")
        ja[s] = (t, r)
        sources[s] = src
    base = (data / "arcadedb-base.tsv").read_text(encoding="utf-8")
    taken = set()
    for line in base.splitlines():
        c = line.split("\t")
        if c[0] == "G" and len(c) >= 10:
            taken.update(c[9].split("|"))
    makers = sorted({g["maker"] for s, g in sets.items() if s not in taken and g["maker"]})
    out = [base.rstrip("\n")]
    out += [f"P\tm:{m}\t{m}\t{makers_ja.get(m, '')}" for m in makers]
    for s in sorted(sets):
        if s in taken:
            continue
        g = sets[s]
        t, r = ja.get(s, ("", ""))
        out.append("\t".join(["G", "a-" + s, g["en"], t, r, "m:" + g["maker"] if g["maker"] else "", g["year"], g["genre"], "", s]))
    text = "\n".join(out) + "\n"
    target = data / "arcadedb.tsv"
    if check:
        if not target.exists() or target.read_text(encoding="utf-8") != text:
            sys.exit(f"{target} is out of date: run tools/make_arcadedb.py")
        print(f"{target}: up to date")
        return
    target.write_text(text, encoding="utf-8")
    print(f"{len(sets) - len(taken & set(sets))} sets, {len(makers)} makers, {sum(1 for s in ja if s not in taken)} with Japanese titles")
    if report:
        by = collections.Counter(sources[s] for s in ja if s not in taken)
        print("  Japanese title by source:", dict(by))
        print("  with a reading:", sum(1 for s in ja if s not in taken and ja[s][1]))


if __name__ == "__main__":
    main()
