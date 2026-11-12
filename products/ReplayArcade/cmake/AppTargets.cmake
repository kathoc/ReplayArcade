# ReplayArcade's targets, defined once wherever ReplayNES's sources are configured with ReplayArcade's
# product profile (ReplayArcade's own build for tests, or ReplayNES's apps/linux for the app).
set(REPLAYARCADE_DIR ${CMAKE_CURRENT_LIST_DIR}/..)
include(${REPLAYARCADE_DIR}/cmake/FBNeo.cmake)
add_library(replayarcade_core STATIC ${REPLAYARCADE_DIR}/src/core/FbneoCore.cpp)
target_include_directories(replayarcade_core PUBLIC ${REPLAYARCADE_DIR}/src)
target_link_libraries(replayarcade_core PUBLIC replaynes_engine PRIVATE fbneo)
target_compile_features(replayarcade_core PUBLIC cxx_std_17)
add_library(replayarcade_startup STATIC ${REPLAYARCADE_DIR}/src/app/startup.cpp)
target_link_libraries(replayarcade_startup PUBLIC replayarcade_core replaynes_frontend)
