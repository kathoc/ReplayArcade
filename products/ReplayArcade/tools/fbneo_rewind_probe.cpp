// Holds Rewind as tests/test_fbneo_core.cpp does and says where it first differs from the recording: for one
// FinalBurn Neo game, the frame whose picture differs after a rewind step, and which FBNeo state areas
// (BurnAreaScan) differ from the recording's at that frame. "picture only" (every area equal) points at
// something outside the state: the picture buffer, or memory no area holds.
//
//   fbneo_rewind_probe <rom.zip> [frames=3000]
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "core/FbneoCore.h"
#include "replaynes/replaynes.h"
#include "util/Hash.h"
#include "util/Json.h"

extern "C" {
struct BurnArea {
  void* Data;
  unsigned nLen;
  int nAddress;
  char* szName;
};
int BurnAreaScan(int nAction, int* pnMin);
extern int (*BurnAcb)(BurnArea* pba);
}

namespace {

constexpr int kFullScanRead = 1 | 8 | 16 | 32 | 64;  // ACB_READ | ACB_FULLSCAN

std::vector<std::pair<std::string, uint64_t>>* gAreas = nullptr;
std::vector<unsigned>* gSizes = nullptr;
int collect(BurnArea* a) {
  gAreas->push_back({a->szName ? a->szName : "?", rn::Hasher64::of(a->Data, a->nLen, a->nLen)});
  if (gSizes) gSizes->push_back(a->nLen);
  return 0;
}
std::vector<std::pair<std::string, uint64_t>> areas() {
  std::vector<std::pair<std::string, uint64_t>> out;
  gAreas = &out;
  auto saved = BurnAcb;
  BurnAcb = collect;
  BurnAreaScan(kFullScanRead, nullptr);
  BurnAcb = saved;
  return out;
}

uint64_t pictureHash(rn_session* s) {
  rn_video_frame_info v{};
  rn_session_video_frame(s, &v);
  rn::Hasher64 h;
  for (uint32_t y = 0; y < v.height; ++y) h.update(v.pixels + size_t(y) * v.stride, size_t(v.width) * 4);
  return h.digest();
}

// tests/test_fbneo_core.cpp's recording input.
void testInput(rn_input* in, const std::string& layoutJson, uint64_t f) {
  static std::vector<std::string> buttons, coins, starts;
  static bool bound = false;
  if (!bound) {
    bound = true;
    rn::Json layout;
    rn::Json::parse(layoutJson, layout);
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
  }
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
}

std::vector<uint32_t> gFirst;
uint32_t gFirstW = 0, gFirstH = 0;

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) {
    std::printf("usage: fbneo_rewind_probe <rom.zip> [frames=3000]\n");
    return 2;
  }
  rac::registerFbneoCore();
  const uint64_t frames = argc > 2 ? uint64_t(std::atoll(argv[2])) : 3000;
  rn_session_options opt;
  rn_session_options_init(&opt);
  opt.core = RN_CORE_EXTERNAL;
  rn_session* s = nullptr;
  if (rn_session_new(argv[1], nullptr, &opt, &s) != RN_OK) {
    std::printf("cannot open %s: %s\n", argv[1], rn_last_error());
    return 2;
  }
  char* lj = rn_session_input_layout_json(s);
  rn_input* in = rn_input_new();
  rn_input_set_layout_json(in, lj);
  const std::string layoutJson = lj;
  rn_string_free(lj);
  std::vector<uint64_t> picture;
  std::vector<std::vector<std::pair<std::string, uint64_t>>> state;  // after each frame
  for (uint64_t f = 0; f < frames; ++f) {
    testInput(in, layoutJson, f);
    rn_input_record rec;
    rn_input_sample_record(in, f, &rec);
    if (rn_step_record(s, &rec, nullptr) != RN_OK) {
      std::printf("record %llu: %s\n", (unsigned long long)f, rn_last_error());
      return 2;
    }
    picture.push_back(pictureHash(s));
    state.push_back(areas());
    if (f == 0) {  // frame 0's pixels (PROBE_POWERON says where they differ)
      rn_video_frame_info v{};
      rn_session_video_frame(s, &v);
      gFirstW = v.width;
      gFirstH = v.height;
      gFirst.clear();
      for (uint32_t y = 0; y < v.height; ++y) gFirst.insert(gFirst.end(), v.pixels + size_t(y) * v.stride, v.pixels + size_t(y) * v.stride + v.width);
    }
  }
  if (const char* show = std::getenv("PROBE_SHOW")) {  // the size of area n, and its rank among areas of its name
    std::vector<unsigned> sizes;
    gSizes = &sizes;
    auto a = areas();
    gSizes = nullptr;
    const size_t n = size_t(std::atoi(show));
    int rank = 0;
    for (size_t i = 0; i < n && i < a.size(); ++i) rank += a[i].first == a[n].first ? 1 : 0;
    if (n < a.size()) std::printf("area %zu: %s, %u bytes, %d-th of that name\n", n, a[n].first.c_str(), sizes[n], rank);
  }
  if (std::getenv("PROBE_POWERON")) {  // a second session of the game (a power-on restore), the same input
    rn_session_close(s);
    if (rn_session_new(argv[1], nullptr, &opt, &s) != RN_OK) return 2;
    for (uint64_t f = 0; f < frames; ++f) {
      testInput(in, layoutJson, f);
      rn_input_record rec;
      rn_input_sample_record(in, f, &rec);
      if (rn_step_record(s, &rec, nullptr) != RN_OK) return 2;
      size_t na = 0;
      rn_audio(s, &na);
      const bool pic = pictureHash(s) == picture[size_t(f)];
      auto now = areas();
      std::vector<std::string> diff;
      for (size_t i = 0; i < now.size() && i < state[size_t(f)].size(); ++i)
        if (now[i].second != state[size_t(f)][i].second) diff.push_back(now[i].first + "#" + std::to_string(i));
      if (!pic && f == 0)
        std::printf("frame 0's picture %s the first session's last picture\n",
                    pictureHash(s) == picture.back() ? "IS" : "is not");
      if (!pic && f == 0) {
        rn_video_frame_info v{};
        rn_session_video_frame(s, &v);
        size_t n = 0;
        uint32_t x0 = 99999, y0 = 99999, x1 = 0, y1 = 0, a = 0, b = 0;
        for (uint32_t y = 0; y < v.height && y < gFirstH; ++y)
          for (uint32_t x = 0; x < v.width && x < gFirstW; ++x) {
            uint32_t p = v.pixels[size_t(y) * v.stride + x], q = gFirst[size_t(y) * gFirstW + x];
            if (p == q) continue;
            if (!n) { a = q; b = p; }
            ++n; x0 = std::min(x0, x); y0 = std::min(y0, y); x1 = std::max(x1, x); y1 = std::max(y1, y);
          }
        std::printf("frame 0: %ux%u vs %ux%u, %zu pixels differ in (%u,%u)-(%u,%u), e.g. %08x -> %08x\n", gFirstW, gFirstH,
                    v.width, v.height, n, x0, y0, x1, y1, a, b);
      }
      if (!pic || !diff.empty()) {
        std::printf("second session, frame %llu: picture %s, %zu area(s) differ:", (unsigned long long)f, pic ? "equal" : "DIFFERS", diff.size());
        for (size_t i = 0; i < diff.size() && i < 12; ++i) std::printf(" %s", diff[i].c_str());
        std::printf("\n");
        return 1;
      }
    }
    std::printf("second session: all %llu frames equal\n", (unsigned long long)frames);
    return 0;
  }
  rn_set_mode(s, RN_MODE_REPLAY);
  if (rn_seek(s, frames) != RN_OK) return 2;
  int tick = 0, compared = 0, wrong = 0, wrongPictures = 0;
  while (rn_frame(s) > 1000) {
    ++tick;
    uint64_t n = tick <= 30 ? 2 : tick <= 90 ? 3 : 4;
    if (rn_rewind(s, n) != RN_OK) break;
    const uint64_t f = rn_frame(s);
    if (f == 0) break;
    ++compared;
    const bool pic = pictureHash(s) == picture[size_t(f - 1)];
    auto now = areas();
    std::vector<std::string> diff;
    const auto& want = state[size_t(f - 1)];
    for (size_t i = 0; i < now.size() && i < want.size(); ++i)
      if (now[i].second != want[i].second) diff.push_back(now[i].first + "#" + std::to_string(i));
    if (now.size() != want.size()) diff.push_back("(area count " + std::to_string(now.size()) + " vs " + std::to_string(want.size()) + ")");
    if (!pic) ++wrongPictures;
    if (!pic || !diff.empty()) {
      ++wrong;
      if (wrong <= 5) {
        std::printf("rewind step %d to frame %llu: picture %s, %zu area(s) differ:", tick, (unsigned long long)f,
                    pic ? "equal" : "DIFFERS", diff.size());
        for (size_t i = 0; i < diff.size() && i < 12; ++i) std::printf(" %s", diff[i].c_str());
        std::printf("\n");
      }
    }
  }
  std::printf("%s: %d rewind steps compared, %d differ (%d in the picture)\n", argv[1], compared, wrong, wrongPictures);
  return wrongPictures ? 1 : wrong ? 3 : 0;
}
