# FinalBurn Neo (libretro fork, third_party/fbneo) as a static library with ReplayArcade's patches.
# The libretro Makefile builds in its own tree; STATIC_LINKING=1 leaves out libretro-common's file and
# string helpers (a libretro frontend normally provides them), so they are compiled here.
set(FBNEO_DIR ${REPLAYARCADE_DIR}/third_party/fbneo)
set(FBNEO_LIBRETRO_DIR ${FBNEO_DIR}/src/burner/libretro)
set(FBNEO_ARCHIVE ${FBNEO_LIBRETRO_DIR}/fbneo_libretro_static.a)
include(ProcessorCount)
ProcessorCount(FBNEO_JOBS)
if(FBNEO_JOBS EQUAL 0)
  set(FBNEO_JOBS 4)
endif()

add_custom_command(
  OUTPUT ${FBNEO_ARCHIVE}
  COMMAND ${REPLAYARCADE_DIR}/scripts/fbneo-patches.sh
  COMMAND make -C ${FBNEO_LIBRETRO_DIR} STATIC_LINKING=1 TARGET=fbneo_libretro_static.a -j${FBNEO_JOBS}
  DEPENDS ${REPLAYARCADE_DIR}/patches/fbneo/0001-replayarcade-determinism.patch
  COMMENT "Building FinalBurn Neo (libretro, static, patched)"
  VERBATIM)
add_custom_target(fbneo_build DEPENDS ${FBNEO_ARCHIVE})

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
find_package(ZLIB REQUIRED)
find_package(Threads REQUIRED)
target_link_libraries(fbneo INTERFACE fbneo_libretro_common ZLIB::ZLIB Threads::Threads)
target_include_directories(fbneo INTERFACE ${LRC}/include)
