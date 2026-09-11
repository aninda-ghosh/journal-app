# Builds the dictation helper against whisper.cpp.
#
# Everything is linked statically into one binary, so the app ships a single
# executable with no dylibs to find at runtime. Letting CMake pull in
# whisper.cpp as a subproject means the link line — OpenMP on Linux, Metal and
# Accelerate on macOS — is worked out per platform rather than guessed at.

cmake_minimum_required(VERSION 3.16)
project(journal_transcriber CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

# One self-contained binary.
set(BUILD_SHARED_LIBS      OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS    OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER   OFF CACHE BOOL "" FORCE)

# Embed the Metal shaders rather than shipping a .metallib beside the binary.
set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)

add_subdirectory(whisper.cpp EXCLUDE_FROM_ALL)

add_executable(transcriber transcriber.cpp)
target_link_libraries(transcriber PRIVATE whisper)
