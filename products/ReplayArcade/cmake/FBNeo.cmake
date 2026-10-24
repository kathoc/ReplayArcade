# FinalBurn Neo (libretro fork, third_party/fbneo) as a static library with ReplayArcade's patches.
# The libretro Makefile builds next to its sources, so each CMake build directory gets its own copy of
# the (patched) tree without object files: builds with different toolchains (host, Flatpak SDK,
# llvm-mingw for Windows) never share objects. The copy keeps the sources' timestamps, so make only
# rebuilds what changed. STATIC_LINKING=1 leaves out libretro-common's file and string helpers (a
# libretro frontend normally provides them), so they are compiled here. zlib is FBNeo's own copy
# (EXTERNAL_ZLIB=0, in the archive).
set(FBNEO_DIR ${REPLAYARCADE_DIR}/third_party/fbneo)
set(FBNEO_TREE ${CMAKE_BINARY_DIR}/fbneo-src)
set(FBNEO_LIBRETRO_DIR ${FBNEO_DIR}/src/burner/libretro)
set(FBNEO_ARCHIVE ${FBNEO_TREE}/src/burner/libretro/fbneo_libretro_static.a)
include(ProcessorCount)
ProcessorCount(FBNEO_JOBS)
if(FBNEO_JOBS EQUAL 0)
  set(FBNEO_JOBS 4)
endif()

set(FBNEO_MAKE_ARGS STATIC_LINKING=1 TARGET=fbneo_libretro_static.a
  CC=${CMAKE_C_COMPILER} CXX=${CMAKE_CXX_COMPILER} AR=${CMAKE_AR})
if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
  # SPLIT_UP_LINK adds the objects one by one (a Windows shell limit); this make runs on a POSIX host.
  list(APPEND FBNEO_MAKE_ARGS platform=win SPLIT_UP_LINK=0)
endif()

# Always run: the patch check, the copy and make are all incremental.
add_custom_target(fbneo_build
  COMMAND ${REPLAYARCADE_DIR}/scripts/fbneo-patches.sh
  COMMAND ${CMAKE_COMMAND} -DSRC=${FBNEO_DIR} -DDST=${FBNEO_TREE} -P ${CMAKE_CURRENT_LIST_DIR}/FBNeoCopy.cmake
  COMMAND make -C ${FBNEO_TREE}/src/burner/libretro ${FBNEO_MAKE_ARGS} -j${FBNEO_JOBS}
  BYPRODUCTS ${FBNEO_ARCHIVE}
  COMMENT "Building FinalBurn Neo (libretro, static, patched)"
  VERBATIM)

set(LRC ${FBNEO_LIBRETRO_DIR}/libretro-common)
add_library(fbneo_libretro_common STATIC
  ${LRC}/file/file_path.c ${LRC}/file/file_path_io.c ${LRC}/file/retro_dirent.c
  ${LRC}/streams/file_stream.c ${LRC}/streams/file_stream_transforms.c
  ${LRC}/vfs/vfs_implementation.c ${LRC}/string/stdstring.c ${LRC}/encodings/encoding_utf.c
  ${LRC}/compat/compat_strl.c ${LRC}/compat/compat_posix_string.c ${LRC}/compat/compat_strcasestr.c
  ${LRC}/compat/fopen_utf8.c ${LRC}/time/rtime.c)
target_include_directories(fbneo_libretro_common PUBLIC ${LRC}/include)
set_target_properties(fbneo_libretro_common PROPERTIES POSITION_INDEPENDENT_CODE ON)

add_library(fbneo STATIC IMPORTED GLOBAL)
set_target_properties(fbneo PROPERTIES IMPORTED_LOCATION ${FBNEO_ARCHIVE})
add_dependencies(fbneo fbneo_build)
find_package(Threads REQUIRED)
target_link_libraries(fbneo INTERFACE fbneo_libretro_common Threads::Threads)
target_include_directories(fbneo INTERFACE ${LRC}/include)
