cmake_minimum_required(VERSION 3.14)
project(aria2_native_windows LANGUAGES CXX C)

set(ARIA2_NATIVE_ROOT "${CMAKE_CURRENT_LIST_DIR}/..")
set(ARIA2_NATIVE_PLATFORM windows)
if(NOT DEFINED ARIA2_NATIVE_ARCH)
  set(ARIA2_NATIVE_ARCH x86_64)
endif()

add_subdirectory("${ARIA2_NATIVE_ROOT}/src" "${CMAKE_CURRENT_BINARY_DIR}/aria2_native_src")

set(aria2_native_bundled_libraries
  $<TARGET_FILE:aria2_native>
  PARENT_SCOPE)
