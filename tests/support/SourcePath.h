#pragma once
#include <cstdlib>
#include <string>

#ifndef RN_SOURCE_ROOT
#error "RN_SOURCE_ROOT must name the repository root (the test reads files from the source tree)"
#endif

namespace rntest {

// A file of the source tree (fixtures, baselines), given relative to the repository root.
// The root is $RN_TEST_SOURCE at run time when the tests run on another machine than the one that
// built them (the Windows runner of the llvm-mingw CI job, the Windows VM), else the source tree
// baked in at compile time; the same rule as tempRoot() and $RN_TEST_TMP in TestUtil.h.
inline std::string sourcePath(const std::string& relative) {
  const char* env = std::getenv("RN_TEST_SOURCE");
  return (env && *env ? std::string(env) : std::string(RN_SOURCE_ROOT)) + "/" + relative;
}

}  // namespace rntest
