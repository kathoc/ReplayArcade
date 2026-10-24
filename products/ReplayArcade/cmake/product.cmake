# ReplayArcade's product profile for ReplayNES's sources (see ReplayNES cmake/Product.cmake).
set(RN_PRODUCT_NAME "ReplayArcade")
set(RN_PRODUCT_APP_ID "io.github.kathoc.ReplayArcade")
set(RN_PRODUCT_EXECUTABLE "replayarcade-linux")
set(RN_PRODUCT_DATA_DIR "ReplayArcade")
set(RN_PRODUCT_ENV_PREFIX "REPLAYARCADE_")
set(RN_PRODUCT_PROJECT_EXT ".arcrec")
set(RN_PRODUCT_PROJECT_FORMAT "replayarcade-project")
set(RN_PRODUCT_ROM_EXTS "zip")
set(RN_PRODUCT_TEMP_PREFIX "replayarcade")
# Japanese names of FBNeo's input labels (the layout labels are looked up in the localization table).
set(RN_PRODUCT_L10N_OVERRIDES "${CMAKE_CURRENT_LIST_DIR}/../data/l10n-overrides.json")
set(RN_PRODUCT_STARTUP_TARGET "replayarcade_startup")
set(RN_PRODUCT_DEFAULT_CORE "external")
set(RN_PRODUCT_GAMEDB "${CMAKE_CURRENT_LIST_DIR}/../data/arcadedb.tsv")
set(RN_PRODUCT_NES OFF)
# Library pictures at 30 s: past the boards' start-up self tests, into the attract mode.
set(RN_PRODUCT_LIBRARY_PICTURE_FRAME 1800)
# Linux packaging (packaging/linux); the artwork is a placeholder until the final design.
set(RN_PRODUCT_LINUX_DESKTOP_FILE "${CMAKE_CURRENT_LIST_DIR}/../packaging/linux/io.github.kathoc.ReplayArcade.desktop")
set(RN_PRODUCT_LINUX_METAINFO_FILE "${CMAKE_CURRENT_LIST_DIR}/../packaging/linux/io.github.kathoc.ReplayArcade.metainfo.xml")
set(RN_PRODUCT_STEAM_ARTWORK_DIR "${CMAKE_CURRENT_LIST_DIR}/../packaging/linux/artwork")

# ReplayArcade's targets (FBNeo, its core, the start-up hook): defined once per configure.
if(NOT TARGET replayarcade_startup)
  include(${CMAKE_CURRENT_LIST_DIR}/AppTargets.cmake)
endif()
