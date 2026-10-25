cmake_minimum_required(VERSION 3.20)
project(ReplayArcade C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ReplayNES's sources (engine, shared frontend, apps): the submodule third_party/replaynes, pinned to a
# ReplayNES commit. -DREPLAYNES_DIR=<another ReplayNES tree> builds against a working copy instead.
set(REPLAYNES_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/replaynes" CACHE PATH "ReplayNES source tree")
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
  add_executable(test_arcadedb tests/test_arcadedb.cpp)
  target_link_libraries(test_arcadedb PRIVATE replaynes_frontend)
  add_test(NAME test_arcadedb COMMAND test_arcadedb ${CMAKE_CURRENT_SOURCE_DIR}/data)
  # data/arcadedb.tsv is what tools/make_arcadedb.py writes from the pinned FBNeo and data/.
  find_package(Python3 COMPONENTS Interpreter)
  if(Python3_FOUND)
    add_test(NAME arcadedb_up_to_date
             COMMAND ${Python3_EXECUTABLE} -I ${CMAKE_CURRENT_SOURCE_DIR}/tools/make_arcadedb.py --check
                     ${CMAKE_CURRENT_SOURCE_DIR}/third_party/fbneo/src/burn/drv ${CMAKE_CURRENT_SOURCE_DIR}/data)
    # src/core/FbneoRelative.inc (which analog inputs are dials) likewise.
    add_test(NAME fbneo_relative_up_to_date
             COMMAND ${Python3_EXECUTABLE} -I ${CMAKE_CURRENT_SOURCE_DIR}/tools/make_fbneo_relative.py --check
                     ${CMAKE_CURRENT_SOURCE_DIR}/third_party/fbneo/src/burn/drv ${CMAKE_CURRENT_SOURCE_DIR}/src/core/FbneoRelative.inc)
  endif()
endif()

# Rewind cost as the app sees it (tools/bench_rewind.cpp); not a test.
add_executable(bench_rewind tools/bench_rewind.cpp)
target_link_libraries(bench_rewind PRIVATE replayarcade_core)
# The input layout of games (tools/dump_layout.cpp); not a test.
add_executable(dump_layout tools/dump_layout.cpp)
target_link_libraries(dump_layout PRIVATE replayarcade_core)
# What a state load leaves out, for one game (tools/fbneo_diverge.cpp); not a test.
add_executable(fbneo_diverge tools/fbneo_diverge.cpp)
target_link_libraries(fbneo_diverge PRIVATE replayarcade_core ${CMAKE_DL_LIBS})
# A project saved by another build opens and replays the same (tools/project_roundtrip.cpp); not a test.
add_executable(project_roundtrip tools/project_roundtrip.cpp)
target_link_libraries(project_roundtrip PRIVATE replayarcade_core)
add_executable(fbneo_bisect tools/fbneo_bisect.cpp)
target_link_libraries(fbneo_bisect PRIVATE replayarcade_core ${CMAKE_DL_LIBS})
