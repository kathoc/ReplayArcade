// The library pictures' ledger (frontend.h; docs/plans/2026-11-22-library-pictures-robust.md): an unknown ROM
// that crashes the picture worker or fails is skipped, not run again at every start-up.
#include <filesystem>
#include <fstream>
#include "support/FrontendTestUtil.h"
#include "support/rn_test.h"

namespace {
std::filesystem::path freshDir(const char* name) {
  auto d = std::filesystem::temp_directory_path() / name;
  std::filesystem::remove_all(d);
  std::filesystem::create_directories(d);
  return d;
}
std::string makeRom(const std::filesystem::path& dir, const char* name, size_t size) {
  auto p = dir / name;
  std::ofstream(p, std::ios::binary) << std::string(size, 'x');
  return p.string();
}
}  // namespace

TEST_CASE("a ROM that ended the app twice is skipped; once is not enough") {
  auto d = freshDir("rn-ledger-crash");
  const std::string rom = makeRom(d, "bad.zip", 100), good = makeRom(d, "good.zip", 50);
  auto* l = rnf_picture_ledger_open(d.string().c_str());
  rnf_picture_ledger_begin(l, rom.c_str());
  rnf_picture_ledger_close(l);  // the app "crashed": the in-progress record stays
  l = rnf_picture_ledger_open(d.string().c_str());
  CHECK(!rnf_picture_ledger_skipped(l, rom.c_str()));  // one end (perhaps the OS): tried again
  rnf_picture_ledger_begin(l, rom.c_str());
  rnf_picture_ledger_close(l);
  l = rnf_picture_ledger_open(d.string().c_str());
  CHECK(rnf_picture_ledger_skipped(l, rom.c_str()));   // the second time: skipped
  CHECK(!rnf_picture_ledger_skipped(l, good.c_str()));
  rnf_picture_ledger_close(l);
  l = rnf_picture_ledger_open(d.string().c_str());     // stays skipped across start-ups
  CHECK(rnf_picture_ledger_skipped(l, rom.c_str()));
  rnf_picture_ledger_close(l);
}

TEST_CASE("a failure the worker saw skips at once; success, abandon and a replaced file do not") {
  auto d = freshDir("rn-ledger-fail");
  const std::string rom = makeRom(d, "broken.zip", 10), paused = makeRom(d, "long.zip", 20);
  auto* l = rnf_picture_ledger_open(d.string().c_str());
  rnf_picture_ledger_begin(l, rom.c_str());
  rnf_picture_ledger_end(l, rom.c_str(), 0, "could not open");
  CHECK(rnf_picture_ledger_skipped(l, rom.c_str()));
  rnf_picture_ledger_begin(l, paused.c_str());
  rnf_picture_ledger_abandon(l);                       // a game opened: put back, not a failure
  rnf_picture_ledger_close(l);
  l = rnf_picture_ledger_open(d.string().c_str());
  CHECK(!rnf_picture_ledger_skipped(l, paused.c_str()));
  CHECK(rnf_picture_ledger_skipped(l, rom.c_str()));
  makeRom(d, "broken.zip", 11);                        // the file replaced (another size): tried again
  CHECK(!rnf_picture_ledger_skipped(l, rom.c_str()));
  rnf_picture_ledger_crashed(l, paused.c_str(), "the picture process died");
  rnf_picture_ledger_crashed(l, paused.c_str(), "the picture process died");
  CHECK(rnf_picture_ledger_skipped(l, paused.c_str()));
  rnf_picture_ledger_end(l, paused.c_str(), 1, nullptr);  // a later success clears it
  CHECK(!rnf_picture_ledger_skipped(l, paused.c_str()));
  rnf_picture_ledger_close(l);
}
