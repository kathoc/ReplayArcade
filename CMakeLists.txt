cmake_minimum_required(VERSION 3.20)
project(ReplayArcade C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ReplayNES's sources (engine, shared frontend, apps). During Phase 1 this is the ReplayNES worktree
# with the generalisation branch; later a submodule pinned to a ReplayNES commit.
set(REPLAYNES_DIR "$ENV{HOME}/Playground/ReplayNES/.claude/worktrees/generalize" CACHE PATH "ReplayNES source tree")
set(RN_PRODUCT_FILE "${CMAKE_CURRENT_SOURCE_DIR}/cmake/product.cmake" CACHE FILEPATH "Product profile" FORCE)
option(REPLAYARCADE_BUILD_TESTS "Build ReplayArcade's tests" ON)
set(REPLAYNES_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(REPLAYNES_BUILD_CLI OFF CACHE BOOL "" FORCE)
set(REPLAYNES_BUILD_DESKTOP OFF CACHE BOOL "" FORCE)
add_subdirectory(${REPLAYNES_DIR} replaynes)

# fbneo, replayarcade_core and replayarcade_startup come from the product profile
# (cmake/product.cmake -> cmake/AppTargets.cmake), included while ReplayNES's sources configure.

if(REPLAYARCADE_BUILD_TESTS)
  enable_testing()
  add_executable(test_fbneo_core tests/test_fbneo_core.cpp)
  target_link_libraries(test_fbneo_core PRIVATE replayarcade_core)
  add_test(NAME test_fbneo_core COMMAND test_fbneo_core)
  set_tests_properties(test_fbneo_core PROPERTIES TIMEOUT 1800)
endif()

# Rewind cost as the app sees it (tools/bench_rewind.cpp); not a test.
add_executable(bench_rewind tools/bench_rewind.cpp)
target_link_libraries(bench_rewind PRIVATE replayarcade_core)
