// Thin wrapper: the real implementation lives in
// packages/aria2_native/src/aria2_ffi.cc. CocoaPods only consumes
// source files inside Classes/, so we re-include the shared source.
//
// We use a relative path so the build still works in `pub global` style
// checkouts.

#include "../../src/aria2_ffi.cc"
