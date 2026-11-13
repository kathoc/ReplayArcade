#pragma once
#include <cstdlib>
#include <string>

#ifndef RNL_TEST_TMP
#error "RNL_TEST_TMP must name the build tree's scratch directory"
#endif

namespace rnl_test {

// Scratch root: $RN_TEST_TMP at run time (tests run on another machine than the one that built them:
// the Windows runner of the llvm-mingw CI job, the Windows VM), else the build tree's directory baked
// in at compile time. The same rule as rntest::tempRoot() (tests/support/TestUtil.h).
inline std::string tmpRoot() {
  const char* env = std::getenv("RN_TEST_TMP");
  return env && *env ? std::string(env) : std::string(RNL_TEST_TMP);
}

}  // namespace rnl_test
