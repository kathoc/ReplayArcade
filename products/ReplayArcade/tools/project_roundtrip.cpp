// Checks that a project saved by one build of ReplayArcade opens and replays identically in another (a
// change of FinalBurn Neo's state layout must keep the projects saved before).
//
//   project_roundtrip make  <rom.zip> <project dir> <frames.txt> [frames=3000]
//       records `frames` frames (coin, start, then button 1 and the stick now and then), saves the project
//       (checkpoints included) and writes each frame's picture and sound hash to frames.txt
//   project_roundtrip check <rom.zip> <project dir> <frames.txt>
//       opens the project, seeks to frames scattered over the take (from the project's checkpoints) and
//       replays from each; every frame must equal frames.txt. Exit 0 = all equal.
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "core/FbneoCore.h"
#include "replaynes/replaynes.h"
#include "util/Hash.h"

namespace {

struct Hashes {
  uint64_t video = 0, audio = 0;
};

Hashes frameHash(rn_session* s) {
  rn_video_frame_info v{};
  rn_session_video_frame(s, &v);
  rn::Hasher64 h;
  for (uint32_t y = 0; y < v.height; ++y) h.update(v.pixels + size_t(y) * v.stride, size_t(v.width) * 4);
  size_t n = 0;
  const int16_t* a = rn_audio(s, &n);
  return {h.digest(), rn::Hasher64::of(a, n * 2 * sizeof(int16_t), n)};
}

rn_session_options options() {
  rn_session_options opt;
  rn_session_options_init(&opt);
  opt.core = RN_CORE_EXTERNAL;
  return opt;
}

int make(const std::string& zip, const std::string& project, const std::string& out, int frames) {
  rn_session_options opt = options();
  rn_session* s = nullptr;
  if (rn_session_new(zip.c_str(), nullptr, &opt, &s) != RN_OK) {
    std::printf("open: %s\n", rn_last_error());
    return 2;
  }
  char* lj = rn_session_input_layout_json(s);
  rn_input* in = rn_input_new();
  rn_input_set_layout_json(in, lj);
  rn_string_free(lj);
  rn_input_bind(in, "t:coin", "p1.coin");
  rn_input_bind(in, "t:start", "p1.start");
  rn_input_bind(in, "t:b1", "p1.b1");
  rn_input_bind(in, "t:left", "p1.left");
  rn_input_bind(in, "t:right", "p1.right");
  FILE* f = std::fopen(out.c_str(), "w");
  for (int i = 0; i < frames; ++i) {
    rn_input_set_pressed(in, "t:coin", (i >= 600 && i < 610) || (i >= 660 && i < 670));
    rn_input_set_pressed(in, "t:start", (i >= 800 && i < 810) || (i >= 860 && i < 870));
    rn_input_set_pressed(in, "t:b1", i >= 1000 && (i / 15) % 3 == 0);
    rn_input_set_pressed(in, "t:left", i >= 1000 && (i / 90) % 4 == 1);
    rn_input_set_pressed(in, "t:right", i >= 1000 && (i / 90) % 4 == 3);
    rn_input_record rec;
    rn_input_sample_record(in, uint64_t(i), &rec);
    if (rn_step_record(s, &rec, nullptr) != RN_OK) {
      std::printf("step %d: %s\n", i, rn_last_error());
      return 2;
    }
    Hashes h = frameHash(s);
    std::fprintf(f, "%d %016llx %016llx\n", i, (unsigned long long)h.video, (unsigned long long)h.audio);
  }
  std::fclose(f);
  rn_input_free(in);
  if (rn_session_save_as(s, project.c_str()) != RN_OK) {
    std::printf("save: %s\n", rn_last_error());
    return 2;
  }
  rn_session_close(s);
  std::printf("recorded %d frames into %s\n", frames, project.c_str());
  return 0;
}

int check(const std::string& zip, const std::string& project, const std::string& in) {
  std::vector<Hashes> want;
  FILE* f = std::fopen(in.c_str(), "r");
  int i;
  unsigned long long v, a;
  while (f && std::fscanf(f, "%d %llx %llx", &i, &v, &a) == 3) want.push_back({v, a});
  if (f) std::fclose(f);
  rn_session_options opt = options();
  rn_session* s = nullptr;
  if (rn_session_open(project.c_str(), zip.c_str(), &opt, &s) != RN_OK) {
    std::printf("FAIL: the project does not open: %s\n", rn_last_error());
    return 1;
  }
  rn_set_mode(s, RN_MODE_REPLAY);
  const uint64_t n = want.size();
  const uint64_t starts[] = {n - 200, 0, n / 2, 1234 % n, n / 3, 2 * n / 3, 77, n - 1};
  int bad = 0;
  for (uint64_t from : starts) {
    if (rn_seek(s, from) != RN_OK) {
      std::printf("FAIL: seek to %llu: %s\n", (unsigned long long)from, rn_last_error());
      ++bad;
      continue;
    }
    for (uint64_t fr = from; fr < from + 150 && fr < n; ++fr) {
      rn_step_info info{};
      if (rn_step(s, 0, 0, 0, &info) != RN_OK) break;
      Hashes h = frameHash(s);
      if (h.video != want[fr].video || h.audio != want[fr].audio) {
        std::printf("FAIL: from %llu, frame %llu differs (%s)\n", (unsigned long long)from, (unsigned long long)fr,
                    h.video != want[fr].video ? "picture" : "sound");
        ++bad;
        break;
      }
    }
  }
  rn_session_close(s);
  std::printf("%s: %d seek(s) failed\n", bad ? "FAIL" : "PASS", bad);
  return bad ? 1 : 0;
}

}  // namespace

int main(int argc, char** argv) {
  rac::registerFbneoCore();
  if (argc >= 5 && std::string(argv[1]) == "make") return make(argv[2], argv[3], argv[4], argc > 5 ? std::atoi(argv[5]) : 3000);
  if (argc >= 5 && std::string(argv[1]) == "check") return check(argv[2], argv[3], argv[4]);
  std::printf("usage: project_roundtrip make|check <rom.zip> <project dir> <frames.txt> [frames]\n");
  return 2;
}
