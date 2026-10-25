// Prints the input layout ReplayArcade builds for each FinalBurn Neo game (rn_session_input_layout_json):
// its buttons and analog axes, with FBNeo's names for them.
//   dump_layout <rom.zip>...
#include <cstdio>

#include "core/FbneoCore.h"
#include "replaynes/replaynes.h"

int main(int argc, char** argv) {
  rac::registerFbneoCore();
  for (int i = 1; i < argc; ++i) {
    rn_session_options opt;
    rn_session_options_init(&opt);
    opt.core = RN_CORE_EXTERNAL;
    rn_session* s = nullptr;
    if (rn_session_new(argv[i], nullptr, &opt, &s) != RN_OK) {
      std::printf("%s: %s\n", argv[i], rn_last_error());
      continue;
    }
    char* json = rn_session_input_layout_json(s);
    std::printf("%s\n%s\n", argv[i], json ? json : "(none)");
    rn_string_free(json);
    rn_session_close(s);
  }
  return 0;
}
