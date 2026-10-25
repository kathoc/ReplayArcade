// ReplayArcade's game database (data/arcadedb.tsv, written by tools/make_arcadedb.py) as the library
// reads it: a ROM zip is identified by its set name alone, every set with a Japanese title in
// data/arcadedb-ja.tsv shows it, and the hand-written rows of data/arcadedb-base.tsv win.
//   test_arcadedb <data dir>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "replaynes/frontend.h"

namespace {

int failures = 0;
#define EXPECT(cond, what)                                                                    \
  do {                                                                                        \
    if (!(cond)) {                                                                            \
      ++failures;                                                                             \
      std::printf("    FAILED: %s (%s:%d)\n", std::string(what).c_str(), __FILE__, __LINE__); \
    }                                                                                         \
  } while (0)

std::string idOf(const std::string& file) {
  rnf_game_info g{};
  return rnf_gamedb_find_name(file.c_str(), &g) ? g.id : "";
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) {
    std::printf("usage: test_arcadedb <data dir>\n");
    return 2;
  }
  // Every set of the Japanese table: found by its zip, with that title and reading.
  std::ifstream ja(std::string(argv[1]) + "/arcadedb-ja.tsv");
  EXPECT(ja.good(), "arcadedb-ja.tsv");
  int sets = 0;
  for (std::string line; std::getline(ja, line);) {
    std::vector<std::string> c;
    std::stringstream ss(line);
    for (std::string f; std::getline(ss, f, '\t');) c.push_back(f);
    if (c.size() < 4 || c[0] != "G") continue;
    ++sets;
    rnf_game_info g{};
    bool found = rnf_gamedb_find_name((c[1] + ".zip").c_str(), &g) != 0;
    EXPECT(found, c[1] + ".zip: not identified");
    if (!found) continue;
    EXPECT(std::string(g.id) == "a-" + c[1], c[1] + ".zip: identified as " + g.id);
    EXPECT(c[2] == g.title_ja, c[1] + ": Japanese title " + g.title_ja);
    EXPECT(c[3] == g.reading, c[1] + ": reading " + g.reading);
    EXPECT(g.year > 0 && *g.publisher_en, c[1] + ": no maker or year");
  }
  EXPECT(sets >= 100, "Japanese titles: " + std::to_string(sets));
  // The set name alone: 1942.zip is 1942, not another set titled "1942" (1942a, 1942b, ...).
  EXPECT(idOf("1942.zip") == "a-1942", "1942.zip: " + idOf("1942.zip"));
  EXPECT(idOf("1942a.zip") == "a-1942a", "1942a.zip: " + idOf("1942a.zip"));
  EXPECT(idOf("Gradius.zip") == "x-gradius", "Gradius.zip: " + idOf("Gradius.zip"));  // file names fold case
  EXPECT(idOf("Space Invaders.zip").empty(), "a title is not a set name");
  EXPECT(idOf("notagame.zip").empty(), "notagame.zip");
  // Hand-written rows keep their sets; a clone of the same title gets the Japanese title.
  EXPECT(idOf("aburner2.zip") == "x-aburner2", "aburner2.zip: " + idOf("aburner2.zip"));
  EXPECT(idOf("ghouls.zip") == "x-daimakai", "ghouls.zip: " + idOf("ghouls.zip"));
  rnf_game_info g{};
  EXPECT(rnf_gamedb_find_name("gradius3j.zip", &g) && std::strcmp(g.title_ja, "グラディウスIII 伝説から神話へ") == 0,
         "gradius3j: the Japanese title of gradius3ja");
  // Neither a console game nor a BIOS.
  EXPECT(idOf("neogeo.zip").empty(), "neogeo.zip (BIOS)");
  EXPECT(idOf("md_sonic.zip").empty(), "md_sonic.zip (Mega Drive)");
  EXPECT(idOf("sonic.zip") == "a-sonic", "sonic.zip (SegaSonic The Hedgehog, arcade)");
  std::printf("%s: %d sets with Japanese titles, %d failures\n", failures ? "FAIL" : "PASS", sets, failures);
  return failures ? 1 : 0;
}
