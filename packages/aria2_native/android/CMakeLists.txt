cmake_minimum_required(VERSION 3.10)
project(aria2_native_android)

# Flutter's Android plugin tooling expects this file. It delegates to the
# shared CMakeLists in ../src to avoid duplication.
set(ARIA2_NATIVE_ROOT "${CMAKE_CURRENT_LIST_DIR}/..")
set(ARIA2_NATIVE_PLATFORM android)
set(ARIA2_NATIVE_ARCH "${ANDROID_ABI}")

add_subdirectory("${ARIA2_NATIVE_ROOT}/src" "${CMAKE_CURRENT_BINARY_DIR}/aria2_native_src")
