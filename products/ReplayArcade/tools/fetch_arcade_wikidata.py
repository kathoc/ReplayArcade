# Fetches what tools/make_arcadedb.py needs from Wikidata (CC0) into data/wikidata-arcade.json, the cache
# the build uses (it never goes online): Japanese titles and readings for every FBNeo arcade set.
#
#   python3 -I tools/fetch_arcade_wikidata.py <FBNeo src/burn/drv> <data dir>
#
# Which items: those whose MAME ROM name (P2451) is an FBNeo set, and video games whose English label or
# alias is a title of an FBNeo clone family (each set's title, also without a subtitle after " - " / ": "
# or a leading "The "), compared as make_arcadedb.norm_title does (case, punctuation and spaces aside:
# "Arkanoid: Revenge of Doh" is "Arkanoid - Revenge of DOH"): exact labels, and the English labels of
# every video game with a Japanese label released 1970-2010, fetched a year at a time. For each item: English label and aliases, Japanese label, kana name (P1814),
# years (P577), platforms (P400), MAME ROM names, instance of (P31), and its Japanese Wikipedia article;
# from that article's opening sentence only the reading in parentheses after the title is kept (up to a comma: 「時計じかけのアクワリオ」（とけいじかけのアクワリオ、Clockwork Aquario）) (a fact,
# not the article's text). Standard library only; about 100 requests, one a second.
import json
import pathlib
import re
import sys
import time
import urllib.parse
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import make_arcadedb  # noqa: E402

UA = "ReplayArcade-arcadedb/1 (https://github.com/kathoc/ReplayArcade)"
SPARQL = "https://query.wikidata.org/sparql"
JAWIKI = "https://ja.wikipedia.org/w/api.php"


def get(url, params, accept="application/json"):
    req = urllib.request.Request(url + "?" + urllib.parse.urlencode(params), headers={"Accept": accept, "User-Agent": UA})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                return json.load(r)
        except Exception as e:  # rate limits and timeouts: wait and retry
            if attempt == 4:
                raise
            print(f"  retry ({e})", file=sys.stderr)
            time.sleep(10 * (attempt + 1))
        finally:
            time.sleep(1)


def sparql(query):
    return get(SPARQL, {"query": query}, "application/sparql-results+json")["results"]["bindings"]


def qid(uri):
    return uri.rsplit("/", 1)[1]


def title_variants(t):
    out = {t}
    for sep in (" - ", ": "):
        if sep in t:
            out.add(t.split(sep)[0].strip())
    for v in list(out):
        if v.startswith("The "):
            out.add(v[4:])
    return {v for v in out if len(v) >= 2}


KANA_READING = re.compile(r"[（(]([ぁ-ゖァ-ヺー・ 　\u3099-\u309c]+)[)）、,，]")


def reading_from_extract(text, title):
    """The kana in parentheses right after the article's title in its first sentence (「大魔界村」（だいまかいむら）)."""
    head = text.strip().split("\n", 1)[0][:300]
    i = head.find(title)
    if i < 0:
        return ""
    m = KANA_READING.match(head[i + len(title):].lstrip("』」》】 "))
    return m.group(1).replace(" ", "").replace("　", "") if m else ""


def main():
    drv, data = map(pathlib.Path, sys.argv[1:3])
    sets = make_arcadedb.read_sets(drv)
    titles = set()
    for g in sets.values():
        titles |= title_variants(g["en"])
    items = {}

    def item(q):
        return items.setdefault(q, {"en": "", "aliases": [], "ja": "", "kana": "", "years": [], "platforms": [],
                                    "roms": [], "types": [], "jawiki": "", "jawiki_reading": ""})

    print("MAME ROM names", file=sys.stderr)
    for b in sparql("SELECT ?item ?rom WHERE { ?item wdt:P2451 ?rom }"):
        if b["rom"]["value"] in sets:
            item(qid(b["item"]["value"]))["roms"].append(b["rom"]["value"])
    print(f"titles ({len(titles)})", file=sys.stderr)
    ordered = sorted(titles)
    for i in range(0, len(ordered), 150):
        vals = " ".join(json.dumps(t, ensure_ascii=False) + "@en" for t in ordered[i:i + 150])
        for b in sparql(f"""SELECT DISTINCT ?item WHERE {{ VALUES ?t {{ {vals} }}
              {{ ?item rdfs:label ?t }} UNION {{ ?item skos:altLabel ?t }}
              ?item wdt:P31/wdt:P279* wd:Q7889 . }}"""):
            item(qid(b["item"]["value"]))
    keys = set()
    for g in sets.values():
        keys |= {make_arcadedb.norm_title(g["en"])} | make_arcadedb.variants(g["en"])
    print("video games with a Japanese label, by year", file=sys.stderr)
    for year in range(1970, 2011):
        for b in sparql(f"""SELECT DISTINCT ?item ?en WHERE {{ ?item wdt:P31/wdt:P279* wd:Q7889 ; wdt:P577 ?d ;
              rdfs:label ?ja . FILTER(LANG(?ja) = "ja") FILTER(YEAR(?d) = {year})
              {{ ?item rdfs:label ?en FILTER(LANG(?en) = "en") }} UNION {{ ?item skos:altLabel ?en FILTER(LANG(?en) = "en") }} }}"""):
            if make_arcadedb.norm_title(b["en"]["value"]) in keys:
                item(qid(b["item"]["value"]))
    print(f"details ({len(items)} items)", file=sys.stderr)
    ids = sorted(items)
    for i in range(0, len(ids), 150):
        vals = " ".join("wd:" + q for q in ids[i:i + 150])
        for b in sparql(f"""SELECT ?item ?p ?v WHERE {{ VALUES ?item {{ {vals} }}
              {{ ?item rdfs:label ?v FILTER(LANG(?v) = "en") BIND("en" AS ?p) }}
              UNION {{ ?item rdfs:label ?v FILTER(LANG(?v) = "ja") BIND("ja" AS ?p) }}
              UNION {{ ?item skos:altLabel ?v FILTER(LANG(?v) = "en") BIND("alias" AS ?p) }}
              UNION {{ ?item wdt:P1814 ?v BIND("kana" AS ?p) }}
              UNION {{ ?item wdt:P577 ?v BIND("date" AS ?p) }}
              UNION {{ ?item wdt:P400 ?v BIND("platform" AS ?p) }}
              UNION {{ ?item wdt:P2451 ?v BIND("rom" AS ?p) }}
              UNION {{ ?item wdt:P31 ?v BIND("type" AS ?p) }}
              UNION {{ ?a schema:about ?item ; schema:isPartOf <https://ja.wikipedia.org/> ; schema:name ?v BIND("jawiki" AS ?p) }} }}"""):
            it, p, v = item(qid(b["item"]["value"])), b["p"]["value"], b["v"]["value"]
            if p in ("en", "ja", "kana", "jawiki"):
                it[p] = it[p] or v
            elif p == "alias":
                it["aliases"].append(v)
            elif p == "date" and re.match(r"\d{4}", v):
                it["years"].append(int(v[:4]))
            elif p == "platform":
                it["platforms"].append(qid(v))
            elif p == "rom":
                it["roms"].append(v)
            elif p == "type":
                it["types"].append(qid(v))
    pages = sorted({it["jawiki"] for it in items.values() if it["jawiki"] and it["ja"]})
    print(f"Japanese Wikipedia openings ({len(pages)})", file=sys.stderr)
    reading = {}
    for i in range(0, len(pages), 20):
        r = get(JAWIKI, {"action": "query", "prop": "extracts", "exintro": 1, "explaintext": 1, "exlimit": 20,
                         "redirects": 1, "format": "json", "titles": "|".join(pages[i:i + 20])})
        for page in r.get("query", {}).get("pages", {}).values():
            reading[page.get("title", "")] = page.get("extract", "")
        for n in r.get("query", {}).get("normalized", []) + r.get("query", {}).get("redirects", []):
            reading.setdefault(n["from"], reading.get(n["to"], ""))
    for it in items.values():
        text = reading.get(it["jawiki"], "")
        it["jawiki_reading"] = reading_from_extract(text, it["ja"]) or reading_from_extract(text, it["jawiki"])
    for it in items.values():
        for k in ("aliases", "years", "platforms", "roms", "types"):
            it[k] = sorted(set(it[k]))
    out = {"source": "Wikidata (CC0) and the readings in Japanese Wikipedia's openings; tools/fetch_arcade_wikidata.py",
           "items": {q: items[q] for q in sorted(items, key=lambda q: int(q[1:]))}}
    (data / "wikidata-arcade.json").write_text(json.dumps(out, ensure_ascii=False, indent=0, sort_keys=True) + "\n",
                                               encoding="utf-8")
    print(f"{len(items)} items, {sum(1 for it in items.values() if it['ja'])} with a Japanese title, "
          f"{sum(1 for it in items.values() if it['jawiki_reading'] or it['kana'])} with a reading", file=sys.stderr)


if __name__ == "__main__":
    main()
