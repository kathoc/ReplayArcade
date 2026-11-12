// Measures the seek bar's thumbnails as the desktop app makes them (ThumbnailManager): one renderer
// per picture, rn_renderer_new(s, f - 1, f) then one rn_renderer_next, for every 5 s of the take.
//   thumb_bench <rom.zip> <- | autosave:<dir>> [record_frames=18000]
// "-": the take just played (the session's dense checkpoints in memory).
// "autosave:<dir>": recorded into a project autosaving every 300 frames, closed and opened again
// (a resumed session: only the checkpoints the project keeps).
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "core/FbneoCore.h"
#include "replaynes/replaynes.h"

int main(int argc, char** argv) {
  if (argc < 3) {
    std::fprintf(stderr, "usage: thumb_bench <rom.zip> <-|autosave:dir> [record_frames]\n");
    return 2;
  }
  rac::registerFbneoCore();
  const uint64_t recordFrames = argc > 3 ? uint64_t(std::atoll(argv[3])) : 18000;
  rn_session_options opt;
  rn_session_options_init(&opt);
  opt.core = RN_CORE_EXTERNAL;
  rn_session* s = nullptr;
  using clock = std::chrono::steady_clock;
  const std::string mode = argv[2];
  const std::string dir = mode.rfind("autosave:", 0) == 0 ? mode.substr(9) : "";
  if (rn_session_new(argv[1], dir.empty() ? nullptr : dir.c_str(), &opt, &s) != RN_OK)
    return std::fprintf(stderr, "%s\n", rn_last_error()), 1;
  if (!dir.empty() && rn_session_save(s) != RN_OK) return std::fprintf(stderr, "save: %s\n", rn_last_error()), 1;
  auto t0 = clock::now();
  for (uint64_t f = 0; f < recordFrames; ++f) {
    rn_step_info info{};
    // Some input now and then, so the take is not a demo loop.
    rn_step(s, (f / 7) % 3 == 0 ? 0x01 : 0, 0, 0, &info);
    if (!dir.empty() && f % 300 == 299 && rn_session_autosave(s) != RN_OK)
      return std::fprintf(stderr, "autosave: %s\n", rn_last_error()), 1;
  }
  const double rec = std::chrono::duration<double>(clock::now() - t0).count();
  std::printf("recorded %llu frames in %.1f s (%.2f ms/frame)\n", (unsigned long long)recordFrames, rec,
              rec * 1000 / double(recordFrames));
  if (!dir.empty()) {
    rn_session_autosave(s);
    rn_session_close(s);
    s = nullptr;
    if (rn_session_open(dir.c_str(), argv[1], &opt, &s) != RN_OK) return std::fprintf(stderr, "open: %s\n", rn_last_error()), 1;
    if (rn_seek(s, rn_take_length(s)) != RN_OK) return std::fprintf(stderr, "seek: %s\n", rn_last_error()), 1;
  }
  std::vector<double> ms;
  t0 = clock::now();
  for (uint64_t f = 300; f <= rn_take_length(s); f += 300) {
    auto a = clock::now();
    rn_renderer* r = nullptr;
    if (rn_renderer_new(s, f - 1, f, &r) != RN_OK) return std::fprintf(stderr, "renderer: %s\n", rn_last_error()), 1;
    const uint32_t* video = nullptr;
    const int16_t* audio = nullptr;
    size_t n = 0;
    uint64_t idx = 0;
    if (rn_renderer_next(r, &video, &audio, &n, &idx) != RN_OK || idx + 1 != f)
      return std::fprintf(stderr, "next %llu: %s\n", (unsigned long long)f, rn_last_error()), 1;
    rn_renderer_free(r);
    ms.push_back(std::chrono::duration<double, std::milli>(clock::now() - a).count());
  }
  const double total = std::chrono::duration<double>(clock::now() - t0).count();
  std::vector<double> sorted = ms;
  std::sort(sorted.begin(), sorted.end());
  std::printf("%s: %zu thumbnails in %.1f s: median %.0f ms, max %.0f ms\n", dir.empty() ? "just played" : "reopened",
              ms.size(), total, sorted[sorted.size() / 2], sorted.back());
  rn_session_close(s);
  return 0;
}
