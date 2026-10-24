# cmake -DSRC=<third_party/fbneo> -DDST=<build>/fbneo-src -P FBNeoCopy.cmake
# Copies FBNeo's tree without build products. file(COPY) keeps timestamps and skips files whose copy
# has the same timestamp, so an unchanged source never looks newer than its object file.
if(NOT SRC OR NOT DST)
  message(FATAL_ERROR "FBNeoCopy.cmake: SRC and DST are required")
endif()
file(MAKE_DIRECTORY ${DST})
file(COPY ${SRC}/ DESTINATION ${DST}
  PATTERN ".git" EXCLUDE
  PATTERN "*.o" EXCLUDE
  PATTERN "*.a" EXCLUDE
  PATTERN "*.d" EXCLUDE
  PATTERN "*.so" EXCLUDE
  PATTERN "*.dll" EXCLUDE)
