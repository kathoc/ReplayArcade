// ReplayArcade's start-up hook for ReplayNES's Linux app (RN_PRODUCT_STARTUP_TARGET): registers
// FinalBurn Neo as the external core and identifies library files by their arcade set.
#include <cstring>
#include <string>

#include "core/FbneoCore.h"
#include "replaynes/frontend.h"

namespace {
int contentId(const char* path, char* out, size_t cap, void*) {
  if (!path || !out) return 0;
  std::string id = rac::contentIdForPath(path);
  if (id.empty() || id.size() + 1 > cap) return 0;
  std::memcpy(out, id.c_str(), id.size() + 1);
  return 1;
}
int arcadeOnly(const char* path, void*) { return path && rac::isArcadeFile(path) ? 1 : 0; }
}  // namespace

extern "C" void rn_product_startup(void) {
  rac::registerFbneoCore();
  rnf_set_content_id_provider(contentId, nullptr);
  rnf_set_rom_filter(arcadeOnly, nullptr);
}
