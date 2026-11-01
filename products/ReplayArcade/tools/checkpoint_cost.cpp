// The rewind checkpoints' cost per game, for a whole ROM folder: the state size (what every checkpoint
// holds) and how much longer a checkpoint frame (every 30 frames) takes than the others.
//   checkpoint_cost <rom.zip> [frames=240]   one game per process (FBNeo is global): prints one TSV line
//   set <TAB> state bytes <TAB> median frame ms <TAB> median checkpoint frame ms <TAB> max checkpoint frame ms
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "core/FbneoCore.h"
#include "replaynes/replaynes.h"

extern "C" size_t retro_serialize_size(void);

int main(int argc, char** argv) {
  if (argc < 2) return 2;
  rac::registerFbneoCore();
  const uint64_t frames = argc > 2 ? uint64_t(std::atoll(argv[2])) : 240;
  std::string set = argv[1];
  set = set.substr(set.find_last_of('/') + 1);
  set = set.substr(0, set.rfind('.'));
  rn_session_options opt;
  rn_session_options_init(&opt);
  opt.core = RN_CORE_EXTERNAL;
  rn_session* s = nullptr;
  if (rn_session_new(argv[1], nullptr, &opt, &s) != RN_OK) {
    std::printf("%s\topen-failed\n", set.c_str());
    return 1;
  }
  const size_t stateBytes = retro_serialize_size();
  using clock = std::chrono::steady_clock;
  std::vector<double> plain, cp;
  for (uint64_t f = 0; f < frames; ++f) {
    auto a = clock::now();
    rn_step_info info{};
    rn_step(s, 0, 0, 0, &info);
    const double ms = std::chrono::duration<double, std::milli>(clock::now() - a).count();
    if (f < 30) continue;  // boot
    ((f + 1) % 30 == 0 ? cp : plain).push_back(ms);
  }
  auto median = [](std::vector<double> v) {
    if (v.empty()) return 0.0;
    std::sort(v.begin(), v.end());
    return v[v.size() / 2];
  };
  std::printf("%s\t%zu\t%.2f\t%.2f\t%.2f\n", set.c_str(), stateBytes, median(plain), median(cp),
              cp.empty() ? 0.0 : *std::max_element(cp.begin(), cp.end()));
  rn_session_close(s);
  return 0;
}
