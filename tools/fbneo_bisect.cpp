// Finds the memory a state load leaves out, for one FinalBurn Neo game, by bisection.
//
//   fbneo_bisect <rom.zip> [frames=600]
//
// Session A loads the game and runs `frames` frames (coin at 300, start at 360, button 1 now and then);
// its state right after loading is kept. Session B restores that state at once (as FbneoCore does when a
// second session of the game starts, or a seek returns to power-on) and runs the same input. Where B's
// picture or sound first differs (frame k), the memory that differed between A and B at the start (the
// program's globals, FBNeo's BurnMalloc blocks and its malloc'd FM chips) is the suspect. Each trial forks: the child sets a
// subset of the suspects to A's values, runs to frame k and says whether the difference is gone. The
// smallest set of ranges that removes it is printed, globals as offsets from the program's base (name
// them with `nm -C -S --defined-only fbneo_bisect`), blocks by the global pointer that holds them.
//
// $FBNEO_BISECT_FROM=<n>: a seek instead: A runs n frames and keeps the state there, runs on to the end,
// and the same session restores that state (B) and runs frames n... again (what a seek back does).
// $FBNEO_BISECT_SEEK=1 (with FROM): B is the engine's own seek (rn_seek in Playback, then rn_step), A
// the recording it replays.
// $FBNEO_BISECT_SAVEPROBE=1: does saving a state change the game? A runs `frames` frames; a fork of
// the fresh session runs them again saving a state (retro_serialize) before every frame. Prints the
// first frame that differs (-1: none).
// $FBNEO_BISECT_INTERLEAVE=<c> (with FROM): two machines take turns, as an export beside the session:
// before each of B's frames (from FROM, restored from its own state) another machine C (from frame c)
// runs one frame from its state. At the first frame k that differs, the memory that differs between A
// and B just before frame k is the suspect, bisected on frame k.
// $FBNEO_BISECT_INPUT=test: tests/test_fbneo_core.cpp's input (every button and axis) instead.
#include <dlfcn.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "core/FbneoCore.h"
#include "replaynes/replaynes.h"
#include "util/Hash.h"
#include "util/Json.h"

extern "C" {
size_t retro_serialize_size(void);
bool retro_serialize(void* data, size_t size);
bool retro_unserialize(const void* data, size_t size);
}
int BurnMallocBlocks(unsigned char** ptrs, int* sizes, int max);  // patched FBNeo (burn_memory.cpp)
extern "C" int FMChipMemory(void** ptrs, int* sizes);             // patched FBNeo (snd/fm.c): malloc'd chips
extern "C" int OPLChipMemory(void** ptrs, int* sizes);            // patched FBNeo (snd/fmopl.c): the OPL chips
extern char __data_start[], _end[];

namespace {

struct Range {
  uint8_t* at;
  size_t len;
  std::vector<uint8_t> a;  // A's bytes at the start
  int block = -1;          // BurnMalloc block index, -1 = globals
  size_t blockOffset = 0;
};

std::vector<std::pair<uint8_t*, size_t>> trackedMemory() {
  std::vector<std::pair<uint8_t*, size_t>> out;
  out.push_back({reinterpret_cast<uint8_t*>(__data_start), size_t(_end - __data_start)});
  static unsigned char* ptrs[4096];
  static int sizes[4096];
  int n = BurnMallocBlocks(ptrs, sizes, 4096);
  for (int i = 0; i < n; ++i) out.push_back({ptrs[i], size_t(sizes[i])});
  void* fm[16];
  int fmSizes[16];
  int m = FMChipMemory(fm, fmSizes);
  m += OPLChipMemory(fm + m, fmSizes + m);
  for (int i = 0; i < m; ++i) out.push_back({static_cast<uint8_t*>(fm[i]), size_t(fmSizes[i])});
  return out;
}

std::vector<std::vector<uint8_t>> snapshot() {
  std::vector<std::vector<uint8_t>> out;
  for (auto [p, n] : trackedMemory()) out.emplace_back(p, p + n);
  return out;
}

std::pair<uint64_t, uint64_t> frameHash(rn_session* s) {
  rn_video_frame_info v{};
  rn_session_video_frame(s, &v);
  rn::Hasher64 h;
  for (uint32_t y = 0; y < v.height; ++y) h.update(v.pixels + size_t(y) * v.stride, size_t(v.width) * 4);
  size_t n = 0;
  const int16_t* a = rn_audio(s, &n);
  return {h.digest(), rn::Hasher64::of(a, n * 2 * sizeof(int16_t), n)};
}

rn_session* open(const std::string& zip) {
  rn_session_options opt;
  rn_session_options_init(&opt);
  opt.core = RN_CORE_EXTERNAL;
  rn_session* s = nullptr;
  if (rn_session_new(zip.c_str(), nullptr, &opt, &s) != RN_OK) {
    std::printf("cannot open %s: %s\n", zip.c_str(), rn_last_error());
    std::exit(2);
  }
  return s;
}

// tests/test_fbneo_core.cpp's recording input (kept in step with it by hand).
std::vector<rn_input_record> testScript(rn_input* in, const std::string& layoutJson, int frames) {
  rn::Json layout;
  rn::Json::parse(layoutJson, layout);
  std::vector<std::string> buttons, coins, starts;
  for (auto& b : layout["buttons"].items()) {
    std::string id = b["id"].asString();
    rn_input_bind(in, ("t:" + id).c_str(), id.c_str());
    std::string turbo = b.has("turbo") ? b["turbo"].asString() : id + ".turbo";
    rn_input_bind(in, ("t:" + turbo).c_str(), turbo.c_str());
    if (id.find(".coin") != std::string::npos) coins.push_back(id);
    else if (id.find(".start") != std::string::npos) starts.push_back(id);
    else if (id.find(".service") == std::string::npos) buttons.push_back(id);
  }
  for (auto& a : layout["axes"].items()) {
    std::string id = a["id"].asString();
    rn_input_bind(in, (id.find(".axis.r") != std::string::npos ? "t:rstick.-y" : id.find(".axis.y") != std::string::npos ? "t:lstick.-y" : "t:lstick.x"), id.c_str());
  }
  rn_input_set_turbo(in, 4, 2);
  std::vector<rn_input_record> out(static_cast<size_t>(frames));
  for (uint64_t f = 0; f < uint64_t(frames); ++f) {
    uint64_t c = f % 1200;
    for (auto& id : coins) rn_input_set_pressed(in, ("t:" + id).c_str(), (c >= 60 && c < 66) || (c >= 90 && c < 96));
    for (auto& id : starts) rn_input_set_pressed(in, ("t:" + id).c_str(), (c >= 120 && c < 126) || (c >= 150 && c < 156));
    uint64_t x = (f / 8 + 1) * 0x9E3779B97F4A7C15ull;
    x ^= x >> 31;
    for (size_t i = 0; i < buttons.size(); ++i)
      rn_input_set_pressed(in, ("t:" + buttons[i]).c_str(), f >= 200 && ((x >> (i * 3)) & 3) == 1);
    if (!buttons.empty()) rn_input_set_pressed(in, ("t:" + buttons.back() + ".turbo").c_str(), f >= 200 && (f / 300) % 2);
    rn_input_set_axis(in, "t:lstick", float(int(f % 41) - 20) / 20.f, float(int(f % 29) - 14) / 14.f);
    rn_input_set_axis(in, "t:rstick", 0.f, f % 600 < 300 ? -1.f : 0.3f);
    rn_input_sample_record(in, f, &out[size_t(f)]);
  }
  return out;
}

std::vector<rn_input_record> script(rn_session* s, int frames) {
  char* lj = rn_session_input_layout_json(s);
  rn_input* in = rn_input_new();
  rn_input_set_layout_json(in, lj);
  if (const char* kind = std::getenv("FBNEO_BISECT_INPUT"); kind && std::string(kind) == "test") {
    auto out = testScript(in, lj, frames);
    rn_string_free(lj);
    rn_input_free(in);
    return out;
  }
  rn_string_free(lj);
  rn_input_bind(in, "t:coin", "p1.coin");
  rn_input_bind(in, "t:start", "p1.start");
  rn_input_bind(in, "t:b1", "p1.b1");
  std::vector<rn_input_record> out(static_cast<size_t>(frames));
  for (int f = 0; f < frames; ++f) {
    rn_input_set_pressed(in, "t:coin", f >= 300 && f < 310);
    rn_input_set_pressed(in, "t:start", f >= 360 && f < 370);
    rn_input_set_pressed(in, "t:b1", f >= 420 && (f / 20) % 3 == 0);
    rn_input_sample_record(in, uint64_t(f), &out[size_t(f)]);
  }
  rn_input_free(in);
  return out;
}

bool gReplay = false;  // B replays the session's own recording (FBNEO_BISECT_SEEK)

// Frames from, from + 1 ... from + upTo.
std::vector<std::pair<uint64_t, uint64_t>> runFrames(rn_session* s, const std::vector<rn_input_record>& in, int upTo,
                                                     int from = 0) {
  std::vector<std::pair<uint64_t, uint64_t>> out;
  for (int f = from; f <= from + upTo && f < int(in.size()); ++f) {
    rn_step_info info{};
    if (gReplay ? rn_step(s, 0, 0, 0, &info) != RN_OK : rn_step_record(s, &in[size_t(f)], nullptr) != RN_OK) break;
    out.push_back(frameHash(s));
  }
  return out;
}

// The child of a trial: A's bytes for `subset`, then frames 0..k; exit 0 when they all equal A's.
bool trial(rn_session* b, const std::vector<Range>& ranges, const std::vector<size_t>& subset,
           const std::vector<rn_input_record>& in, const std::vector<std::pair<uint64_t, uint64_t>>& want, int k,
           int from) {
  std::fflush(stdout);
  pid_t pid = fork();
  if (pid == 0) {
    for (size_t i : subset) std::memcpy(ranges[i].at, ranges[i].a.data(), ranges[i].len);
    auto got = runFrames(b, in, k, from);
    bool same = got.size() == size_t(k + 1) && std::equal(got.begin(), got.end(), want.begin());
    _exit(same ? 0 : 1);
  }
  int status = 0;
  waitpid(pid, &status, 0);
  return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

// The smallest subset of `cand` that, with `base` applied too, removes the difference (it is known to).
std::vector<size_t> minimal(rn_session* b, const std::vector<Range>& ranges, std::vector<size_t> base,
                            std::vector<size_t> cand, const std::vector<rn_input_record>& in,
                            const std::vector<std::pair<uint64_t, uint64_t>>& want, int k, int from, int& trials) {
  if (cand.size() <= 1) return cand;
  std::vector<size_t> h1(cand.begin(), cand.begin() + long(cand.size() / 2)), h2(cand.begin() + long(cand.size() / 2), cand.end());
  auto with = [&](const std::vector<size_t>& x) {
    std::vector<size_t> s = base;
    s.insert(s.end(), x.begin(), x.end());
    ++trials;
    return trial(b, ranges, s, in, want, k, from);
  };
  if (with(h1)) return minimal(b, ranges, base, h1, in, want, k, from, trials);
  if (with(h2)) return minimal(b, ranges, base, h2, in, want, k, from, trials);
  // Both halves are needed: the part of h1 needed with all of h2, then the part of h2 with that.
  std::vector<size_t> b1 = base;
  b1.insert(b1.end(), h2.begin(), h2.end());
  std::vector<size_t> m1 = minimal(b, ranges, b1, h1, in, want, k, from, trials);
  std::vector<size_t> b2 = base;
  b2.insert(b2.end(), m1.begin(), m1.end());
  std::vector<size_t> m2 = minimal(b, ranges, b2, h2, in, want, k, from, trials);
  m1.insert(m1.end(), m2.begin(), m2.end());
  return m1;
}

uintptr_t programBase() {
  Dl_info info{};
  dladdr(reinterpret_cast<void*>(&programBase), &info);
  return reinterpret_cast<uintptr_t>(info.dli_fbase);
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) {
    std::printf("usage: fbneo_bisect <rom.zip> [frames=600]\n");
    return 2;
  }
  rac::registerFbneoCore();
  const std::string zip = argv[1];
  const int frames = argc > 2 ? std::atoi(argv[2]) : 600;

  const int from = std::getenv("FBNEO_BISECT_FROM") ? std::max(0, std::atoi(std::getenv("FBNEO_BISECT_FROM"))) : 0;
  if (from >= frames) {
    std::printf("FBNEO_BISECT_FROM must be below the frames\n");
    return 2;
  }
  rn_session* a = open(zip);
  auto in = script(a, frames);
  if (std::getenv("FBNEO_BISECT_SAVEPROBE")) {
    std::vector<uint8_t> scratch(retro_serialize_size());
    auto runSaving = [&](bool save) {
      std::vector<std::pair<uint64_t, uint64_t>> out;
      for (int f = 0; f < frames; ++f) {
        if (save) retro_serialize(scratch.data(), scratch.size());
        if (rn_step_record(a, &in[size_t(f)], nullptr) != RN_OK) break;
        out.push_back(frameHash(a));
      }
      return out;
    };
    std::fflush(stdout);
    int fds[2];
    if (pipe(fds) != 0) return 2;
    pid_t pid = fork();
    if (pid == 0) {
      close(fds[0]);
      auto plain = runSaving(false);
      size_t n = plain.size();
      if (write(fds[1], &n, sizeof n) != sizeof n || write(fds[1], plain.data(), n * sizeof plain[0]) != ssize_t(n * sizeof plain[0])) _exit(2);
      _exit(0);
    }
    close(fds[1]);
    size_t n = 0;
    std::vector<std::pair<uint64_t, uint64_t>> plain;
    if (read(fds[0], &n, sizeof n) == sizeof n) {
      plain.resize(n);
      size_t got = 0;
      while (got < n * sizeof plain[0]) {
        ssize_t r = read(fds[0], reinterpret_cast<char*>(plain.data()) + got, n * sizeof plain[0] - got);
        if (r <= 0) break;
        got += size_t(r);
      }
    }
    close(fds[0]);
    waitpid(pid, nullptr, 0);
    auto saving = runSaving(true);
    int first = -1;
    for (size_t f = 0; f < plain.size() && f < saving.size(); ++f)
      if (plain[f] != saving[f]) { first = int(f); break; }
    std::printf("%s: %d frames; saving a state every frame first changes frame %d\n", zip.c_str(), frames, first);
    return first < 0 ? 0 : 1;
  }
  if (from > 0) runFrames(a, in, from - 1);
  std::vector<uint8_t> start(retro_serialize_size());
  retro_serialize(start.data(), start.size());
  auto mem = trackedMemory();
  auto a0 = snapshot();
  auto want = runFrames(a, in, frames - 1 - from, from);
  rn_session* b = a;
  const bool seek = std::getenv("FBNEO_BISECT_SEEK") != nullptr;
  if (seek) {
    rn_set_mode(a, RN_MODE_REPLAY);
    if (rn_seek(a, uint64_t(from)) != RN_OK) {
      std::printf("seek to %d: %s\n", from, rn_last_error());
      return 2;
    }
    gReplay = true;
  } else {
    if (from == 0) {
      rn_session_close(a);
      b = open(zip);
    }
    retro_unserialize(start.data(), start.size());  // what FbneoCore does as B's first frame starts / a seek
  }
  // Two machines taking turns (FBNEO_BISECT_INTERLEAVE): B's state is `start`; find k, then bring B
  // to just before frame k (C's run in between included) and compare with A there.
  std::vector<uint8_t> stateB, stateC;
  int interleaveK = -1;
  if (const char* il = std::getenv("FBNEO_BISECT_INTERLEAVE")) {
    const int c0 = std::atoi(il);
    // A's states at every frame from `from`, and A at frame c0 for C.
    rn_session_close(b);  // the live one: A, or the second session when FROM is 0 (A is closed then)
    a = open(zip);
    b = a;
    std::vector<uint8_t> st(retro_serialize_size());
    std::vector<uint8_t> atC = st, atFrom = st;
    for (int f = 0; f < std::max(from, c0); ++f) {
      if (f == c0) retro_serialize(atC.data(), atC.size());
      if (f == from) retro_serialize(atFrom.data(), atFrom.size());
      rn_step_record(a, &in[size_t(f)], nullptr);
    }
    if (std::max(from, c0) == c0) retro_serialize(atC.data(), atC.size());
    if (std::max(from, c0) == from) retro_serialize(atFrom.data(), atFrom.size());
    auto turns = [&](int upTo, bool stopBefore) {  // B's frames from..upTo; true: stop before upTo's frame
      stateB = atFrom;
      stateC = atC;
      std::vector<std::pair<uint64_t, uint64_t>> got;
      for (int f = from, fc = c0; f <= upTo && f < frames; ++f, ++fc) {
        if (fc < frames) {
          retro_unserialize(stateC.data(), stateC.size());
          rn_step_record(a, &in[size_t(fc)], nullptr);
          retro_serialize(stateC.data(), stateC.size());
        }
        retro_unserialize(stateB.data(), stateB.size());
        if (stopBefore && f == upTo) break;
        rn_step_record(a, &in[size_t(f)], nullptr);
        got.push_back(frameHash(a));
        retro_serialize(stateB.data(), stateB.size());
      }
      return got;
    };
    // k from a child (the parent stays clean).
    std::fflush(stdout);
    int fds[2];
    if (pipe(fds) != 0) return 2;
    pid_t pid = fork();
    if (pid == 0) {
      close(fds[0]);
      auto got = turns(frames - 1, false);
      int first = -1;
      for (size_t i = 0; i < got.size() && i < want.size(); ++i)
        if (got[i] != want[i]) { first = int(i); break; }
      if (write(fds[1], &first, sizeof first) != sizeof first) _exit(2);
      _exit(0);
    }
    close(fds[1]);
    if (read(fds[0], &interleaveK, sizeof interleaveK) != sizeof interleaveK) interleaveK = -2;
    close(fds[0]);
    waitpid(pid, nullptr, 0);
    std::printf("%s: two machines (C from %d): B from %d first differs at %d\n", zip.c_str(), c0, from,
                interleaveK < 0 ? interleaveK : from + interleaveK);
    if (interleaveK < 0) return interleaveK == -1 ? 0 : 2;
    // A just before frame from + k (memory to compare), then B there.
    retro_unserialize(atFrom.data(), atFrom.size());
    for (int f = from; f < from + interleaveK; ++f) rn_step_record(a, &in[size_t(f)], nullptr);
    mem = trackedMemory();
    a0 = snapshot();
    turns(from + interleaveK, true);
    // Trials run frame k only (one frame, from B's state there).
    want.erase(want.begin(), want.begin() + interleaveK);
  }
  const int bFrom = interleaveK >= 0 ? from + interleaveK : from;
  auto memB = trackedMemory();
  if (memB.size() != mem.size()) {
    std::printf("the allocations changed between the sessions (%zu vs %zu blocks)\n", mem.size(), memB.size());
    return 2;
  }
  // Globals of the engine and of this tool (C++ namespaces) are left out: setting them to A's values
  // would break the child, not explain anything ($FBNEO_BISECT_EXCLUDE: "offset length" per line).
  std::vector<std::pair<uintptr_t, size_t>> exclude;
  if (const char* ex = std::getenv("FBNEO_BISECT_EXCLUDE")) {
    if (FILE* f = std::fopen(ex, "r")) {
      unsigned long off, len;
      while (std::fscanf(f, "%lx %lu", &off, &len) == 2) exclude.push_back({uintptr_t(off), size_t(len)});
      std::fclose(f);
    }
  }
  const uintptr_t programAt = programBase();
  auto excluded = [&](const uint8_t* p) {
    const uintptr_t o = reinterpret_cast<uintptr_t>(p) - programAt;
    for (auto [s, n] : exclude)
      if (o >= s && o < s + n) return true;
    return false;
  };
  std::vector<Range> ranges;
  for (size_t r = 0; r < mem.size(); ++r) {
    if (mem[r].second != memB[r].second || mem[r].first != memB[r].first) continue;
    uint8_t* p = mem[r].first;
    const std::vector<uint8_t>& old = a0[r];
    for (size_t i = 0; i < old.size(); ++i) {
      if (p[i] == old[i] || (r == 0 && excluded(p + i))) continue;
      size_t j = i;
      while (j < old.size() && p[j] != old[j] && !(r == 0 && excluded(p + j))) ++j;
      Range x;
      x.at = p + i;
      x.len = j - i;
      x.a.assign(old.begin() + long(i), old.begin() + long(j));
      x.block = r == 0 ? -1 : int(r - 1);
      x.blockOffset = i;
      ranges.push_back(std::move(x));
      i = j;
    }
  }
  // Where B first differs, from B's own run in a child (B itself stays at its start).
  int k = -1;
  {
    std::fflush(stdout);
    int fds[2];
    if (pipe(fds) != 0) return 2;
    pid_t pid = fork();
    if (pid == 0) {
      close(fds[0]);
      auto got = runFrames(b, in, frames - 1 - bFrom, bFrom);
      int first = -1;
      for (size_t f = 0; f < got.size() && f < want.size(); ++f)
        if (got[f] != want[f]) { first = int(f); break; }
      if (write(fds[1], &first, sizeof first) != sizeof first) _exit(2);
      _exit(0);
    }
    close(fds[1]);
    if (read(fds[0], &k, sizeof k) != sizeof k) k = -2;
    close(fds[0]);
    waitpid(pid, nullptr, 0);
  }
  std::printf("%s: %d frames from %d; first difference: %d; %zu ranges differ at the start\n", zip.c_str(), frames,
              from, k < 0 ? k : from + k, ranges.size());
  if (k < 0) return k == -1 ? 0 : 2;
  std::vector<size_t> all(ranges.size());
  for (size_t i = 0; i < all.size(); ++i) all[i] = i;
  int trials = 1;
  if (!trial(b, ranges, all, in, want, k, bFrom)) {
    std::printf("  A's values for all of them do not remove it: the cause is outside the tracked memory\n");
    return 1;
  }
  std::vector<size_t> need = minimal(b, ranges, {}, all, in, want, k, bFrom, trials);
  std::printf("  %zu range(s) needed (%d trials):\n", need.size(), trials);
  // Name a block by the global pointer holding its address.
  const uintptr_t base = programBase();
  const uint8_t* g = reinterpret_cast<const uint8_t*>(__data_start);
  const size_t gn = size_t(_end - __data_start);
  for (size_t i : need) {
    const Range& x = ranges[i];
    if (x.block < 0) {
      std::printf("  global  offset %zx  %zu bytes\n", size_t(reinterpret_cast<uintptr_t>(x.at) - base), x.len);
      continue;
    }
    const uintptr_t blockStart = reinterpret_cast<uintptr_t>(x.at) - x.blockOffset;
    long holder = -1;
    for (size_t o = 0; o + sizeof(uintptr_t) <= gn; o += sizeof(uintptr_t)) {
      uintptr_t v;
      std::memcpy(&v, g + o, sizeof v);
      if (v == blockStart && !excluded(g + o)) { holder = long(o); break; }  // not this tool's own lists
    }
    // The driver's pointer nearest below the range (AllMem-style blocks hold many regions: Rom01, RamStart ...).
    long nearest = -1;
    uintptr_t nearestValue = 0;
    for (size_t o = 0; o + sizeof(uintptr_t) <= gn; o += sizeof(uintptr_t)) {
      uintptr_t v;
      std::memcpy(&v, g + o, sizeof v);
      if (v >= blockStart && v <= reinterpret_cast<uintptr_t>(x.at) && v >= nearestValue && !excluded(g + o)) {
        nearest = long(o);
        nearestValue = v;
      }
    }
    std::printf("  block %d (held by global offset %lx) + %zu  %zu bytes (global offset %lx + %zu)\n", x.block,
                holder < 0 ? 0L : long(reinterpret_cast<uintptr_t>(g + holder) - base), x.blockOffset, x.len,
                nearest < 0 ? 0L : long(reinterpret_cast<uintptr_t>(g + nearest) - base),
                nearest < 0 ? size_t(0) : size_t(reinterpret_cast<uintptr_t>(x.at) - nearestValue));
  }
  return 1;
}
