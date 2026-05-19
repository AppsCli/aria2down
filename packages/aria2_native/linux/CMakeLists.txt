cmake_minimum_required(VERSION 3.10)
project(aria2_native_linux LANGUAGES CXX C)

# Flutter Linux desktop plugin entrypoint. Delegates to the shared CMake.
set(ARIA2_NATIVE_ROOT "${CMAKE_CURRENT_LIST_DIR}/..")
set(ARIA2_NATIVE_PLATFORM linux)
if(NOT DEFINED ARIA2_NATIVE_ARCH)
  if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
    set(ARIA2_NATIVE_ARCH arm64)
  else()
    set(ARIA2_NATIVE_ARCH x86_64)
  endif()
endif()

add_subdirectory("${ARIA2_NATIVE_ROOT}/src" "${CMAKE_CURRENT_BINARY_DIR}/aria2_native_src")

# Re-export the bundled libraries variable the Flutter Linux tool expects.
set(aria2_native_bundled_libraries
  $<TARGET_FILE:aria2_native>
  PARENT_SCOPE)
