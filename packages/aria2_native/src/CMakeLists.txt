# The Flutter tooling requires that developers have CMake 3.10 or later.
# Newer features are guarded behind version checks.
cmake_minimum_required(VERSION 3.10)

project(aria2_native_library VERSION 0.1.0 LANGUAGES C CXX)

# This CMake file is included from each platform's plugin scaffolding
# (android/CMakeLists.txt, linux/CMakeLists.txt, windows/CMakeLists.txt).
# It defines a single shared library target named "aria2_native" that
# exposes the C ABI shim. If a prebuilt libaria2.a is present under
# packages/aria2_native/prebuilt/<platform>/<arch>/, the shim is compiled
# against it; otherwise a stub-only library is produced.

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Caller (platform-level CMake) is expected to set ARIA2_NATIVE_ROOT to the
# packages/aria2_native directory. Fall back to this file's directory.
if(NOT DEFINED ARIA2_NATIVE_ROOT)
  set(ARIA2_NATIVE_ROOT "${CMAKE_CURRENT_LIST_DIR}/..")
endif()

# Caller can also set ARIA2_NATIVE_PLATFORM (android | linux | windows | macos | ios)
# and ARIA2_NATIVE_ARCH so we can locate the prebuilt static archive.
if(NOT DEFINED ARIA2_NATIVE_PLATFORM)
  if(ANDROID)
    set(ARIA2_NATIVE_PLATFORM android)
    set(ARIA2_NATIVE_ARCH "${ANDROID_ABI}")
  elseif(WIN32)
    set(ARIA2_NATIVE_PLATFORM windows)
    set(ARIA2_NATIVE_ARCH x86_64)
  elseif(APPLE)
    set(ARIA2_NATIVE_PLATFORM macos)
    set(ARIA2_NATIVE_ARCH universal)
  else()
    set(ARIA2_NATIVE_PLATFORM linux)
    set(ARIA2_NATIVE_ARCH x86_64)
  endif()
endif()

set(ARIA2_NATIVE_PREBUILT_ROOT
  "${ARIA2_NATIVE_ROOT}/prebuilt/${ARIA2_NATIVE_PLATFORM}/${ARIA2_NATIVE_ARCH}")

set(ARIA2_NATIVE_LIBARIA2 "${ARIA2_NATIVE_PREBUILT_ROOT}/libaria2.a")

set(ARIA2_NATIVE_SOURCES "${ARIA2_NATIVE_ROOT}/src/aria2_ffi.cc")

add_library(aria2_native SHARED ${ARIA2_NATIVE_SOURCES})
target_include_directories(aria2_native PRIVATE "${ARIA2_NATIVE_ROOT}/src")
set_target_properties(aria2_native PROPERTIES
  PUBLIC_HEADER "${ARIA2_NATIVE_ROOT}/src/aria2_ffi.h"
  OUTPUT_NAME aria2_native
)

# Android 15+ / Google Play 要求 64-bit ABI 的所有 .so 段对齐到 16 KB。
# NDK r28 起 ld.lld 默认 `-z max-page-size=16384`；项目锁定 NDK r27
# （见 android/app/build.gradle.kts 的 ndkVersion），必须显式声明这个
# 链接选项，否则 `arm64-v8a` / `x86_64` 上的 libaria2_native.so PT_LOAD
# 段 p_align 仍是 0x1000（4 KB），上传 Play Console 触发：
#   "您的应用不支持 16 KB 内存页面大小"
# common-page-size 影响首段头部 padding，max-page-size 影响段间 padding；
# 一起声明保证整个 .so 都按 16 KB 排版。32-bit `armeabi-v7a` 上 lld 仍
# 会按 4 KB 算 vaddr 偏移，但加这个 flag 不会破坏 32-bit 链接，可以
# 无脑统一开。
if(ANDROID)
  target_link_options(aria2_native PRIVATE
    "-Wl,-z,max-page-size=16384"
    "-Wl,-z,common-page-size=16384")
endif()

if(EXISTS "${ARIA2_NATIVE_LIBARIA2}")
  message(STATUS "aria2_native: linking against prebuilt libaria2 at ${ARIA2_NATIVE_LIBARIA2}")
  target_compile_definitions(aria2_native PRIVATE ARIA2_FFI_WITH_LIBARIA2=1)
  target_include_directories(aria2_native PRIVATE
    "${ARIA2_NATIVE_PREBUILT_ROOT}/include")

  set(_aria2_ffi_deps_dir "${ARIA2_NATIVE_PREBUILT_ROOT}/deps")
  file(GLOB _aria2_ffi_static_deps "${_aria2_ffi_deps_dir}/*.a")
  target_link_libraries(aria2_native PRIVATE
    "${ARIA2_NATIVE_LIBARIA2}"
    ${_aria2_ffi_static_deps})

  if(ANDROID)
    # Android Bionic 把 pthread / rt 都合进 libc，单独 `-lpthread -lrt` 会让
    # ld.lld 报 "unable to find library"。这里只链 dl + m。
    # log 是 __android_log_print 所在的 liblog.so，aria2 子模块本地补丁里
    # 在 Platform.cc / LibsslTLSContext.cc 用它做 SSL/RAND 自检日志。
    target_link_libraries(aria2_native PRIVATE dl m log)
  elseif(UNIX AND NOT APPLE)
    target_link_libraries(aria2_native PRIVATE pthread dl m)
  elseif(APPLE)
    target_link_libraries(aria2_native PRIVATE "-framework CoreFoundation" "-framework Security")
  elseif(WIN32)
    target_link_libraries(aria2_native PRIVATE ws2_32 crypt32 iphlpapi)
  endif()
else()
  message(STATUS "aria2_native: prebuilt libaria2 NOT found (expected at ${ARIA2_NATIVE_LIBARIA2}). Building STUB-only library.")
endif()

# Bundled libraries the Flutter tool ships alongside the plugin output.
# Each platform-level CMake re-exports this list.
set(aria2_native_bundled_libraries
  $<TARGET_FILE:aria2_native>
  PARENT_SCOPE)
