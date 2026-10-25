// Finds what makes a FinalBurn Neo game replay differently after a state load (a seek, a second session of
// the same game: FbneoCore restores the power-on state instead of loading the game again).
//
//   fbneo_diverge <rom.zip> [frames=1200] [globals.txt]
//
// Session A loads the game and runs `frames` frames (coin at 300, start at 360, button 1 now and then);
// session B (the power-on state restored) runs the same input. Printed:
//  - the first frame whose picture or sound differs, and the FBNeo state areas (BurnAreaScan) whose bytes
//    differ there;
//  - the program's global variables (.data / .bss) that differ between A and B after that frame (B's
//    power-on state is restored as its first frame starts): state the save states leave out (a function-local static, a driver variable nobody
//    scans). As offsets from the program's base, one per line in globals.txt, for tools/fbneo_diverge.sh
//    to name with the symbol table.
#include <dlfcn.h>
#include <link.h>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <vector>

#include "core/FbneoCore.h"
#include "replaynes/replaynes.h"
#include "util/Hash.h"

extern "C" {
struct BurnArea {
  void* Data;
  unsigned nLen;
  int nAddress;
  char* szName;
};
int BurnAreaScan(int nAction, int* pnMin);
size_t retro_serialize_size(void);
bool retro_serialize(void* data, size_t size);
bool retro_unserialize(const void* data, size_t size);
extern int (*BurnAcb)(BurnArea* pba);
}
extern char __data_start[], _end[];

namespace {

constexpr int kFullScanRead = 1 | 8 | 16 | 32 | 64;  // ACB_READ | ACB_FULLSCAN

std::vector<std::pair<std::string, uint64_t>>* gAreas = nullptr;
int collect(BurnArea* a) {
  gAreas->push_back({a->szName ? a->szName : "?", rn::Hasher64::of(a->Data, a->nLen, a->nLen)});
  return 0;
}
// Each state area's name and hash, in scan order (a name may repeat: numbered).
std::vector<std::pair<std::string, uint64_t>> areas() {
  std::vector<std::pair<std::string, uint64_t>> out;
  gAreas = &out;
  auto saved = BurnAcb;
  BurnAcb = collect;
  BurnAreaScan(kFullScanRead, nullptr);
  BurnAcb = saved;
  return out;
}

// The picture's hash, and the sound's.
std::pair<uint64_t, uint64_t> frameHash(rn_session* s) {
  rn_video_frame_info v{};
  rn_session_video_frame(s, &v);
  rn::Hasher64 h;
  for (uint32_t y = 0; y < v.height; ++y) h.update(v.pixels + size_t(y) * v.stride, size_t(v.width) * 4);
  size_t n = 0;
  const int16_t* a = rn_audio(s, &n);
  return {h.digest(), rn::Hasher64::of(a, n * 2 * sizeof(int16_t), n)};
}

std::vector<uint8_t> globals() { return std::vector<uint8_t>(__data_start, _end); }

// The writable anonymous memory (the heap: what the drivers allocate) as (start, length).
std::vector<std::pair<uintptr_t, size_t>> heapRegions() {
  std::vector<std::pair<uintptr_t, size_t>> out;
  FILE* f = std::fopen("/proc/self/maps", "r");
  char line[512];
  while (f && std::fgets(line, sizeof line, f)) {
    unsigned long a = 0, b = 0;
    char perms[8] = {}, path[400] = {};
    unsigned long off = 0, inode = 0;
    char dev[16] = {};
    int n = std::sscanf(line, "%lx-%lx %7s %lx %15s %lu %399s", &a, &b, perms, &off, dev, &inode, path);
    if (n < 6 || std::strcmp(perms, "rw-p") != 0) continue;
    if (n == 7 && std::strcmp(path, "[heap]") != 0) continue;  // files, [stack], ...
    out.push_back({uintptr_t(a), size_t(b - a)});
  }
  if (f) std::fclose(f);
  return out;
}

// Run A writes its heap to `file`; run B compares its own heap with it and returns the differing ranges.
std::vector<std::pair<uintptr_t, size_t>> heapDiff(const char* file, bool write) {
  std::vector<std::pair<uintptr_t, size_t>> diffs;
  if (write) {
    FILE* f = std::fopen(file, "wb");
    for (auto [a, n] : heapRegions()) {
      std::fwrite(&a, sizeof a, 1, f);
      std::fwrite(&n, sizeof n, 1, f);
      std::fwrite(reinterpret_cast<const void*>(a), 1, n, f);
    }
    std::fclose(f);
    return diffs;
  }
  auto now = heapRegions();
  auto mapped = [&](uintptr_t a, size_t n) {
    for (auto [s, m] : now)
      if (a >= s && a + n <= s + m) return true;
    return false;
  };
  FILE* f = std::fopen(file, "rb");
  std::vector<uint8_t> buf;
  uintptr_t a;
  size_t n;
  while (f && std::fread(&a, sizeof a, 1, f) == 1 && std::fread(&n, sizeof n, 1, f) == 1) {
    buf.resize(n);
    if (std::fread(buf.data(), 1, n, f) != n) break;
    if (!mapped(a, n)) continue;
    const uint8_t* cur = reinterpret_cast<const uint8_t*>(a);
    for (size_t i = 0; i < n; ++i) {
      if (cur[i] == buf[i]) continue;
      size_t j = i;
      while (j < n && cur[j] != buf[j]) ++j;
      diffs.push_back({a + i, j - i});
      i = j;
    }
  }
  if (f) std::fclose(f);
  return diffs;
}

uintptr_t programBase() {
  Dl_info info{};
  dladdr(reinterpret_cast<void*>(&programBase), &info);
  return reinterpret_cast<uintptr_t>(info.dli_fbase);
}

struct Run {
  std::vector<std::pair<uint64_t, uint64_t>> frames;
  std::vector<std::vector<std::pair<std::string, uint64_t>>> states;  // after each frame
  std::vector<uint8_t> globalsAtStart;  // after frame `snapAt` (the restore is done when a frame runs)
};

Run run(const std::string& zip, int frames, int snapAt, const char* heapFile = nullptr, bool writeHeap = false,
        std::vector<std::pair<uintptr_t, size_t>>* heapDiffs = nullptr) {
  Run r;
  rn_session_options opt;
  rn_session_options_init(&opt);
  opt.core = RN_CORE_EXTERNAL;
  rn_session* s = nullptr;
  if (rn_session_new(zip.c_str(), nullptr, &opt, &s) != RN_OK) {
    std::printf("cannot open %s: %s\n", zip.c_str(), rn_last_error());
    std::exit(2);
  }
  if (snapAt == -2) {  // before any frame: A keeps its fresh load's state, B restores it as FbneoCore would
    static std::vector<uint8_t> startState;
    if (writeHeap) {
      startState.resize(retro_serialize_size());
      retro_serialize(startState.data(), startState.size());
    } else {
      retro_unserialize(startState.data(), startState.size());
    }
    if (heapFile && writeHeap) heapDiff(heapFile, true);
    if (heapFile && !writeHeap && heapDiffs) *heapDiffs = heapDiff(heapFile, false);
    r.globalsAtStart = globals();
  }
  char* lj = rn_session_input_layout_json(s);
  rn_input* in = rn_input_new();
  rn_input_set_layout_json(in, lj);
  rn_string_free(lj);
  rn_input_bind(in, "t:coin", "p1.coin");
  rn_input_bind(in, "t:start", "p1.start");
  rn_input_bind(in, "t:b1", "p1.b1");
  for (int f = 0; f < frames; ++f) {
    rn_input_set_pressed(in, "t:coin", f >= 300 && f < 310);
    rn_input_set_pressed(in, "t:start", f >= 360 && f < 370);
    rn_input_set_pressed(in, "t:b1", f >= 420 && (f / 20) % 3 == 0);
    rn_input_record rec;
    rn_input_sample_record(in, uint64_t(f), &rec);
    if (rn_step_record(s, &rec, nullptr) != RN_OK) break;
    r.frames.push_back(frameHash(s));
    r.states.push_back(areas());
    if (f == snapAt) {
      if (heapFile && writeHeap) heapDiff(heapFile, true);
      if (heapFile && !writeHeap && heapDiffs) *heapDiffs = heapDiff(heapFile, false);
      r.globalsAtStart = globals();
    }
  }
  rn_input_free(in);
  rn_session_close(s);
  return r;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) {
    std::printf("usage: fbneo_diverge <rom.zip> [frames=1200] [globals.txt]\n");
    return 2;
  }
  rac::registerFbneoCore();
  const std::string zip = argv[1];
  const int frames = argc > 2 ? std::atoi(argv[2]) : 1200;
  Run a = run(zip, frames, -1);
  Run b = run(zip, frames, -1);
  int firstPicture = -1, firstVideo = -1, firstAudio = -1, firstState = -1;
  for (size_t f = 0; f < a.frames.size() && f < b.frames.size(); ++f) {
    if (firstVideo < 0 && a.frames[f].first != b.frames[f].first) firstVideo = int(f);
    if (firstAudio < 0 && a.frames[f].second != b.frames[f].second) firstAudio = int(f);
    if (firstState < 0 && a.states[f] != b.states[f]) firstState = int(f);
  }
  size_t videoFrames = 0, audioFrames = 0;
  for (size_t f = 0; f < a.frames.size() && f < b.frames.size(); ++f) {
    videoFrames += a.frames[f].first != b.frames[f].first;
    audioFrames += a.frames[f].second != b.frames[f].second;
  }
  std::printf("  frames differing: picture %zu, sound %zu\n", videoFrames, audioFrames);
  firstPicture = firstVideo < 0 ? firstAudio : firstAudio < 0 ? firstVideo : std::min(firstVideo, firstAudio);
  std::printf("%s: %zu frames; first picture/sound difference: %d; first state difference: %d (picture %d, sound %d)\n",
              zip.c_str(), a.frames.size(), firstPicture, firstState, firstVideo, firstAudio);
  if (firstState >= 0) {
    const auto& x = a.states[size_t(firstState)];
    const auto& y = b.states[size_t(firstState)];
    if (x.size() != y.size()) std::printf("  state areas: %zu vs %zu\n", x.size(), y.size());
    int shown = 0;
    for (size_t i = 0; i < x.size() && i < y.size() && shown < 30; ++i)
      if (x[i] != y[i]) {
        std::printf("  area %zu \"%s\" differs\n", i, x[i].first.c_str());
        ++shown;
      }
  }
  // Globals that differ between A and B after the first frame whose output differs (B's power-on state
  // is restored as that frame starts): a second pass, as copies of all globals are big.
  if (firstPicture < 0) return 0;
  const std::string heapFile = std::string(argc > 3 ? argv[3] : "/tmp/fbneo_diverge") + ".heap";
  std::vector<std::pair<uintptr_t, size_t>> heapDiffs;
  // At the start (B's restored power-on state against A's fresh load: what a load leaves out), or after
  // the first differing frame ($FBNEO_DIVERGE_AT=frame).
  const int at = std::getenv("FBNEO_DIVERGE_AT") ? std::atoi(std::getenv("FBNEO_DIVERGE_AT")) : -2;
  a = run(zip, at < 0 ? 1 : at + 1, at, heapFile.c_str(), true);
  b = run(zip, at < 0 ? 1 : at + 1, at, heapFile.c_str(), false, &heapDiffs);
  std::remove(heapFile.c_str());
  const uintptr_t base = programBase();
  const uintptr_t start = reinterpret_cast<uintptr_t>(__data_start);
  FILE* out = argc > 3 ? std::fopen(argv[3], "w") : nullptr;
  size_t ranges = 0;
  for (size_t i = 0; i < a.globalsAtStart.size() && i < b.globalsAtStart.size(); ++i) {
    if (a.globalsAtStart[i] == b.globalsAtStart[i]) continue;
    size_t j = i;
    while (j < a.globalsAtStart.size() && j < b.globalsAtStart.size() && a.globalsAtStart[j] != b.globalsAtStart[j]) ++j;
    if (out) std::fprintf(out, "%zx %zu\n", size_t(start + i - base), j - i);
    ++ranges;
    i = j;
  }
  // Heap differences, named by the global pointer nearest below them (the buffer a driver allocated).
  std::vector<std::pair<uintptr_t, size_t>> pointers;  // (value, global offset)
  for (size_t i = 0; i + sizeof(uintptr_t) <= b.globalsAtStart.size(); i += sizeof(uintptr_t)) {
    uintptr_t v;
    std::memcpy(&v, b.globalsAtStart.data() + i, sizeof v);
    if (v) pointers.push_back({v, i});
  }
  std::sort(pointers.begin(), pointers.end());
  size_t heapBytes = 0;
  for (auto [addr, n] : heapDiffs) {
    heapBytes += n;
    auto it = std::upper_bound(pointers.begin(), pointers.end(), std::make_pair(addr, ~size_t(0)));
    if (it == pointers.begin()) continue;
    --it;
    if (addr - it->first > (64u << 20)) continue;  // nothing of ours points near it
    if (out) std::fprintf(out, "heap %zx %zu %zu\n", size_t(start + it->second - base), size_t(addr - it->first), n);
  }
  if (out) std::fclose(out);
  std::printf("  globals differing %s: %zu ranges; heap: %zu ranges, %zu bytes\n", at < 0 ? "at the start" : "after the frame", ranges,
              heapDiffs.size(), heapBytes);
  return firstPicture < 0 ? 0 : 1;
}
