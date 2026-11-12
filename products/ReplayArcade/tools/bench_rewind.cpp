// Measures holding Rewind as the app does it: one rn_rewind per display tick (2, then 3, then 4
// frames per tick, rnf_hold_speed), and how long each call takes.
//   bench_rewind <rom.zip> <project | -> [ticks=270] [record_frames=1800] [background=0]
// background=1: a renderer replays the whole take on another thread meanwhile (as the seek bar's
// thumbnails do after a session is resumed), sharing FBNeo's one machine with the session.
// With a project: opens it and starts at the end of the take (as resuming a session does).
// With "-": records record_frames frames first (a session played until now).
// With "autosave:<dir>": records record_frames frames into a new project at <dir>, autosaving every
// 300 frames as the app does (no full save after the first), closes it, then opens it as a resume does.
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <thread>
#include <atomic>
#include <vector>

#include "core/FbneoCore.h"
#include "replaynes/replaynes.h"

int main(int argc, char** argv) {
  if (argc < 3) {
    std::fprintf(stderr, "usage: bench_rewind <rom.zip> <project|-> [ticks] [record_frames]\n");
    return 2;
  }
  rac::registerFbneoCore();
  const int ticks = argc > 3 ? std::atoi(argv[3]) : 270;
  const uint64_t recordFrames = argc > 4 ? uint64_t(std::atoll(argv[4])) : 1800;
  const bool background = argc > 5 && std::atoi(argv[5]) != 0;
  rn_session_options opt;
  rn_session_options_init(&opt);
  opt.core = RN_CORE_EXTERNAL;
  rn_session* s = nullptr;
  using clock = std::chrono::steady_clock;
  auto t0 = clock::now();
  std::string project = argv[2];
  if (project.rfind("autosave:", 0) == 0) {
    std::string dir = project.substr(9);
    if (rn_session_new(argv[1], dir.c_str(), &opt, &s) != RN_OK) return std::fprintf(stderr, "%s\n", rn_last_error()), 1;
    if (rn_session_save(s) != RN_OK) return std::fprintf(stderr, "save: %s\n", rn_last_error()), 1;
    for (uint64_t f = 0; f < recordFrames; ++f) {
      rn_step_info info{};
      rn_step(s, 0, 0, 0, &info);
      if (f % 300 == 299 && rn_session_autosave(s) != RN_OK) return std::fprintf(stderr, "autosave: %s\n", rn_last_error()), 1;
    }
    rn_session_autosave(s);
    rn_session_close(s);
    s = nullptr;
    t0 = clock::now();
    if (rn_session_open(dir.c_str(), argv[1], &opt, &s) != RN_OK) return std::fprintf(stderr, "open: %s\n", rn_last_error()), 1;
    if (rn_seek(s, rn_take_length(s)) != RN_OK) return std::fprintf(stderr, "seek: %s\n", rn_last_error()), 1;
  } else if (project == "-") {
    if (rn_session_new(argv[1], nullptr, &opt, &s) != RN_OK) return std::fprintf(stderr, "%s\n", rn_last_error()), 1;
    for (uint64_t f = 0; f < recordFrames; ++f) {
      rn_step_info info{};
      rn_step(s, 0, 0, 0, &info);
    }
  } else {
    if (rn_session_open(project.c_str(), argv[1], &opt, &s) != RN_OK) return std::fprintf(stderr, "%s\n", rn_last_error()), 1;
    uint64_t end = std::getenv("BENCH_FROM") ? uint64_t(std::atoll(std::getenv("BENCH_FROM"))) : rn_take_length(s);
    if (rn_seek(s, end) != RN_OK) return std::fprintf(stderr, "seek: %s\n", rn_last_error()), 1;
  }
  double setup = std::chrono::duration<double>(clock::now() - t0).count();
  // BENCH_IDLE_S: the paused pause before pressing Rewind, with the app's idle work each frame.
  if (const char* idle = std::getenv("BENCH_IDLE_S")) {
    auto until = clock::now() + std::chrono::milliseconds(int(std::atof(idle) * 1000));
    while (clock::now() < until) {
      rn_session_idle_work(s, 4);
      std::this_thread::sleep_for(std::chrono::milliseconds(11));
    }
  }
  uint64_t start = rn_frame(s);
  std::atomic<bool> stop{false};
  std::atomic<uint64_t> rendered{0};
  rn_renderer* r = nullptr;
  std::thread bg;
  if (background && rn_renderer_new(s, 0, rn_take_length(s), &r) == RN_OK) {
    bg = std::thread([&] {
      const uint32_t* v = nullptr;
      const int16_t* a = nullptr;
      size_t n = 0;
      uint64_t i = 0;
      while (!stop && rn_renderer_next(r, &v, &a, &n, &i) == RN_OK) ++rendered;
    });
  }
  std::vector<double> ms;
  // The app rewinds in record mode (paused at the take end); BENCH_MODE=replay switches first.
  if (std::getenv("BENCH_MODE") && std::string(std::getenv("BENCH_MODE")) == "replay") rn_set_mode(s, RN_MODE_REPLAY);
  std::printf("mode %d at frame %llu of %llu\n", int(rn_get_mode(s)), (unsigned long long)rn_frame(s), (unsigned long long)rn_take_length(s));
  for (int tick = 1; tick <= ticks && rn_frame(s) > 0; ++tick) {
    uint64_t n = tick <= 30 ? 2 : tick <= 90 ? 3 : 4;
    auto a = clock::now();
    if (rn_rewind(s, n) != RN_OK) return std::fprintf(stderr, "rewind: %s\n", rn_last_error()), 1;
    ms.push_back(std::chrono::duration<double, std::milli>(clock::now() - a).count());
    // BENCH_TICK_SLEEP_MS: wait between ticks like the app's frame loop (vsync), so another thread
    // gets the machine in between.
    if (const char* w = std::getenv("BENCH_TICK_SLEEP_MS")) std::this_thread::sleep_for(std::chrono::milliseconds(std::atoi(w)));
    if (std::getenv("BENCH_TRACE")) std::printf("tick %d: frame %llu (%.1f ms)\n", tick, (unsigned long long)rn_frame(s), ms.back());
  }
  stop = true;
  if (bg.joinable()) bg.join();
  if (r) rn_renderer_free(r);
  if (background) std::printf("background renderer: %llu frames meanwhile\n", (unsigned long long)rendered.load());
  std::vector<double> sorted = ms;
  std::sort(sorted.begin(), sorted.end());
  double total = 0;
  for (double v : ms) total += v;
  int over = 0;
  for (double v : ms) over += v > 1000.0 / 90;
  std::printf("setup %.2f s; from frame %llu to %llu in %zu ticks; total %.0f ms (ideal %.0f ms at 90 Hz)\n", setup,
              (unsigned long long)start, (unsigned long long)rn_frame(s), ms.size(), total, ms.size() * 1000.0 / 90);
  std::printf("per tick: median %.2f ms, p90 %.2f ms, max %.2f ms; ticks over 11.1 ms: %d\n", sorted[sorted.size() / 2],
              sorted[sorted.size() * 9 / 10], sorted.back(), over);
  std::printf("first 12 ticks (ms):");
  for (size_t i = 0; i < ms.size() && i < 12; ++i) std::printf(" %.1f", ms[i]);
  std::printf("\n");
  rn_session_close(s);
  return 0;
}
