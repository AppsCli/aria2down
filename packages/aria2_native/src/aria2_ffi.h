/*
 * aria2_ffi.h — C ABI shim over libaria2's C++ API.
 *
 * Designed so Dart FFI can drive the aria2 engine in-process. Every function
 * returns either an int status code (0 == success, negative == error from
 * libaria2 or ARIA2_FFI_ERR_*) or an owning `char*` JSON string that the caller
 * must release via aria2_ffi_free_string().
 *
 * All strings are UTF-8. JSON shapes are JSON-RPC compatible so the Dart side
 * can reuse the existing Aria2Client parsing path.
 */

#ifndef ARIA2_FFI_H_
#define ARIA2_FFI_H_

#include <stdint.h>

#if defined(_WIN32)
#define ARIA2_FFI_EXPORT __declspec(dllexport)
#else
#define ARIA2_FFI_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Error codes returned by the shim itself (libaria2's own negative codes are
 * propagated as-is when applicable). */
#define ARIA2_FFI_OK                  0
#define ARIA2_FFI_ERR_UNAVAILABLE  -1001  /* libaria2 not linked into this build */
#define ARIA2_FFI_ERR_NOT_INITIALIZED -1002
#define ARIA2_FFI_ERR_ALREADY_INITIALIZED -1003
#define ARIA2_FFI_ERR_INVALID_ARGUMENT -1004
#define ARIA2_FFI_ERR_INTERNAL     -1005
#define ARIA2_FFI_ERR_NOT_FOUND    -1006
#define ARIA2_FFI_ERR_RUNTIME      -1007

/* Returns 1 when this build was compiled with real libaria2, 0 when running
 * as a pure stub. Lets the Dart side detect environment without exercising any
 * other entry point. */
ARIA2_FFI_EXPORT int aria2_ffi_is_available(void);

/* Library version string ("1.37.0" etc.) when available, "" on stub builds.
 * Returns an owning pointer; release with aria2_ffi_free_string. */
ARIA2_FFI_EXPORT const char *aria2_ffi_library_version(void);

/* Returns a JSON array of strings listing optional capabilities compiled into
 * this build. Each element corresponds to one ARIA2DOWN_HAS_* macro in the
 * patched <aria2/aria2.h>. Possible values include:
 *
 *   - "removeDownloadResult" — public aria2::{removeDownloadResult,
 *     purgeDownloadResult} available; stopped-task removal works hard.
 *   - "listReserved"         — public aria2::getReservedDownload available;
 *     real waiting/paused enumeration (no Dart-side fallback needed).
 *   - "listDownloadResults"  — public aria2::getDownloadResults available;
 *     real stopped enumeration.
 *   - "downloadHandleExt"    — DownloadHandle exposes errorMessage,
 *     numSeeders, seeder, verifiedLength, verifyIntegrityPending.
 *
 * Older prebuilt libaria2.a binaries predate every patch — in that case the
 * array is empty AND the symbol may be missing entirely (Dart side must
 * provide a soft fallback when `lookupSymbol` fails).
 *
 * The returned pointer is owning; release with aria2_ffi_free_string. */
ARIA2_FFI_EXPORT const char *aria2_ffi_get_capabilities(void);

/* Releases a string returned by any aria2_ffi_* function. NULL-safe. */
ARIA2_FFI_EXPORT void aria2_ffi_free_string(const char *s);

/* ------------------------------------------------------------------------
 * Lifecycle
 * ------------------------------------------------------------------------ */

/* Call once per process before sessionNew. Wraps aria2::libraryInit. */
ARIA2_FFI_EXPORT int aria2_ffi_library_init(void);

/* Call once at the end. Wraps aria2::libraryDeinit. */
ARIA2_FFI_EXPORT int aria2_ffi_library_deinit(void);

/* Create the (singleton, per-process) session with a JSON object whose
 * top-level string properties become aria2 options (passed to KeyVals).
 * On success, *out_handle receives a non-zero opaque handle.
 *
 * Returns ARIA2_FFI_OK or a negative error code. */
ARIA2_FFI_EXPORT int aria2_ffi_session_new(const char *options_json,
                                           int64_t *out_handle);

/* Tear down the session created via aria2_ffi_session_new. */
ARIA2_FFI_EXPORT int aria2_ffi_session_final(int64_t handle);

/* Drives the aria2 event loop once. Equivalent to aria2::run(RUN_ONCE).
 * Returns 1 if downloads are still in progress, 0 if none, negative on error.
 */
ARIA2_FFI_EXPORT int aria2_ffi_run_once(int64_t handle);

/* Schedules shutdown (graceful unless force != 0). After this, callers should
 * keep calling aria2_ffi_run_once until it returns <= 0, then session_final. */
ARIA2_FFI_EXPORT int aria2_ffi_shutdown(int64_t handle, int force);

/* ------------------------------------------------------------------------
 * Event callback bridge
 *
 * The Dart side passes a function pointer obtained via NativeCallable.listener
 * (i.e. a pointer that is safe to call from any thread). The callback
 * signature is (event, gid_low_64, user_data). The caller is responsible for
 * threading semantics on the Dart side.
 * ------------------------------------------------------------------------ */

typedef void (*aria2_ffi_event_cb)(int event, uint64_t gid, void *user_data);

ARIA2_FFI_EXPORT int aria2_ffi_set_event_callback(int64_t handle,
                                                  aria2_ffi_event_cb cb,
                                                  void *user_data);

/* ------------------------------------------------------------------------
 * Download CRUD
 * ------------------------------------------------------------------------ */

/* Adds new HTTP/FTP/Magnet URIs.
 *
 *   uris_json:    JSON array of strings, e.g. ["https://...","https://..."]
 *   options_json: JSON object of aria2 options (may be NULL or "").
 *   position:     -1 to append to the end.
 *   out_gid:      receives the assigned GID as decimal text (caller frees with
 *                 aria2_ffi_free_string).
 */
ARIA2_FFI_EXPORT int aria2_ffi_add_uri(int64_t handle,
                                       const char *uris_json,
                                       const char *options_json,
                                       int position,
                                       const char **out_gid);

/* Adds a torrent. `torrent_b64` is base64 of the raw .torrent bytes. */
ARIA2_FFI_EXPORT int aria2_ffi_add_torrent(int64_t handle,
                                           const char *torrent_b64,
                                           const char *uris_json,
                                           const char *options_json,
                                           int position,
                                           const char **out_gid);

/* Adds a metalink. `metalink_b64` is base64 of the metalink XML.
 * Returns a JSON array of GID strings in *out_gids. */
ARIA2_FFI_EXPORT int aria2_ffi_add_metalink(int64_t handle,
                                            const char *metalink_b64,
                                            const char *options_json,
                                            int position,
                                            const char **out_gids);

ARIA2_FFI_EXPORT int aria2_ffi_remove(int64_t handle, const char *gid, int force);

ARIA2_FFI_EXPORT int aria2_ffi_pause(int64_t handle, const char *gid, int force);

ARIA2_FFI_EXPORT int aria2_ffi_pause_all(int64_t handle, int force);

ARIA2_FFI_EXPORT int aria2_ffi_unpause(int64_t handle, const char *gid);

ARIA2_FFI_EXPORT int aria2_ffi_unpause_all(int64_t handle);

ARIA2_FFI_EXPORT int aria2_ffi_purge_download_result(int64_t handle);

ARIA2_FFI_EXPORT int aria2_ffi_remove_download_result(int64_t handle,
                                                      const char *gid);

ARIA2_FFI_EXPORT int aria2_ffi_change_position(int64_t handle,
                                               const char *gid,
                                               int pos,
                                               int how /* 0:SET 1:CUR 2:END */);

ARIA2_FFI_EXPORT int aria2_ffi_change_option(int64_t handle,
                                             const char *gid,
                                             const char *options_json);

ARIA2_FFI_EXPORT int aria2_ffi_change_global_option(int64_t handle,
                                                    const char *options_json);

/* ------------------------------------------------------------------------
 * Queries (return JSON in JSON-RPC compatible shape)
 * ------------------------------------------------------------------------ */

/* tell_status: returns a JSON object compatible with aria2.tellStatus.
 *   keys_json: NULL or a JSON array of property names to filter. */
ARIA2_FFI_EXPORT int aria2_ffi_tell_status(int64_t handle,
                                           const char *gid,
                                           const char *keys_json,
                                           const char **out_json);

/* JSON arrays compatible with aria2.tellActive / tellWaiting / tellStopped. */
ARIA2_FFI_EXPORT int aria2_ffi_tell_active(int64_t handle,
                                           const char *keys_json,
                                           const char **out_json);
ARIA2_FFI_EXPORT int aria2_ffi_tell_waiting(int64_t handle,
                                            int offset,
                                            int num,
                                            const char *keys_json,
                                            const char **out_json);
ARIA2_FFI_EXPORT int aria2_ffi_tell_stopped(int64_t handle,
                                            int offset,
                                            int num,
                                            const char *keys_json,
                                            const char **out_json);

ARIA2_FFI_EXPORT int aria2_ffi_get_files(int64_t handle,
                                         const char *gid,
                                         const char **out_json);
ARIA2_FFI_EXPORT int aria2_ffi_get_peers(int64_t handle,
                                         const char *gid,
                                         const char **out_json);
ARIA2_FFI_EXPORT int aria2_ffi_get_global_stat(int64_t handle,
                                               const char **out_json);
ARIA2_FFI_EXPORT int aria2_ffi_get_global_option(int64_t handle,
                                                 const char **out_json);
ARIA2_FFI_EXPORT int aria2_ffi_get_option(int64_t handle,
                                          const char *gid,
                                          const char **out_json);

/* Returns {"version": "x.y.z", "enabledFeatures": [...]} compatible with
 * aria2.getVersion. */
ARIA2_FFI_EXPORT int aria2_ffi_get_version(int64_t handle, const char **out_json);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* ARIA2_FFI_H_ */
