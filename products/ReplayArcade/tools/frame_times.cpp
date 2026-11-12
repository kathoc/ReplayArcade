// Where the time of each recorded frame goes: rn_step per frame from power-on, as the app records
// (dense checkpoints every 30 frames and the rest of the session's own work inside rn_step), and the
// frames that take much longer than the median, with their spacing (a periodic stall shows as one).
//   frame_times <rom.zip> [frames=3600] [project dir: autosave every 300 frames like the app]
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <map>
#include <string>
#include <vector>

#include "core/FbneoCore.h"
#include "replaynes/replaynes.h"

int main(int argc, char** argv) {
  if (argc < 2) {
    std::fprintf(stderr, "usage: frame_times <rom.zip> [frames] [project dir]\n");
    return 2;
  }
  rac::registerFbneoCore();
  const uint64_t frames = argc > 2 ? uint64_t(std::atoll(argv[2])) : 3600;
  const char* dir = argc > 3 ? argv[3] : nullptr;
  rn_session_options opt;
  rn_session_options_init(&opt);
  opt.core = RN_CORE_EXTERNAL;
  if (std::getenv("FRAME_TIMES_NO_CHECKPOINTS")) opt.dense_interval = opt.sparse_interval = 1u << 30;  // the game alone
  rn_session* s = nullptr;
  if (rn_session_new(argv[1], dir, &opt, &s) != RN_OK) return std::fprintf(stderr, "%s\n", rn_last_error()), 1;
  if (dir && rn_session_save(s) != RN_OK) return std::fprintf(stderr, "save: %s\n", rn_last_error()), 1;
  using clock = std::chrono::steady_clock;
  std::vector<double> ms(frames), saveMs;
  for (uint64_t f = 0; f < frames; ++f) {
    auto a = clock::now();
    rn_step_info info{};
    rn_step(s, (f / 7) % 3 == 0 ? 0x01 : 0, 0, 0, &info);
    ms[f] = std::chrono::duration<double, std::milli>(clock::now() - a).count();
    if (dir && f % 300 == 299) {
      a = clock::now();
      rn_session_autosave_background(s);  // as the app does while playing
      saveMs.push_back(std::chrono::duration<double, std::milli>(clock::now() - a).count());
    }
  }
  std::vector<double> sorted = ms;
  std::sort(sorted.begin(), sorted.end());
  const double median = sorted[sorted.size() / 2];
  std::printf("%s: %llu frames, median %.2f ms, 99%% %.2f ms, max %.2f ms\n", argv[1], (unsigned long long)frames, median,
              sorted[sorted.size() * 99 / 100], sorted.back());
  // Slow frames (over 3 x the median and 2 ms more): how often, at which frame numbers mod 30 / 60 / 300.
  std::vector<uint64_t> slow;
  for (uint64_t f = 0; f < frames; ++f)
    if (ms[f] > median * 3 && ms[f] > median + 2) slow.push_back(f);
  std::printf("slow frames: %zu\n", slow.size());
  std::map<uint64_t, int> gaps;
  for (size_t i = 1; i < slow.size(); ++i) ++gaps[slow[i] - slow[i - 1]];
  int shown = 0;
  for (auto it = gaps.begin(); it != gaps.end() && shown < 8; ++it, ++shown) std::printf("  gap %llu frames: %d times\n", (unsigned long long)it->first, it->second);
  for (size_t i = 0; i < slow.size() && i < 12; ++i) std::printf("  frame %llu: %.2f ms\n", (unsigned long long)slow[i], ms[slow[i]]);
  std::vector<uint64_t> worst(frames);
  for (uint64_t f = 0; f < frames; ++f) worst[f] = f;
  std::sort(worst.begin(), worst.end(), [&](uint64_t a, uint64_t b) { return ms[a] > ms[b]; });
  std::printf("worst:");
  for (size_t i = 0; i < worst.size() && i < 8; ++i) std::printf(" %llu (%.1f ms)", (unsigned long long)worst[i], ms[worst[i]]);
  std::printf("\n");
  if (!saveMs.empty()) {
    std::sort(saveMs.begin(), saveMs.end());
    std::printf("autosave: %zu times, median %.1f ms, max %.1f ms\n", saveMs.size(), saveMs[saveMs.size() / 2], saveMs.back());
  }
  rn_session_close(s);
  return 0;
}
