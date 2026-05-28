/*
 * aria2_ffi.cc — C ABI shim implementation.
 *
 * Compile-time switch ARIA2_FFI_WITH_LIBARIA2:
 *   defined  → real path, links to libaria2 + dependencies.
 *   undefined → stub path, every entry point returns ARIA2_FFI_ERR_UNAVAILABLE.
 *
 * The build system enables ARIA2_FFI_WITH_LIBARIA2 only when a prebuilt
 * libaria2.a is detected for the active platform/arch. Stub builds keep the
 * dynamic library valid (so Dart `DynamicLibrary.open` does not fail), giving
 * the Dart side a chance to fall back to the subprocess engine cleanly.
 */

#include "aria2_ffi.h"

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

#if defined(_WIN32)
#include <process.h>
#define ARIA2_FFI_GETPID() static_cast<unsigned long>(_getpid())
#else
#include <unistd.h>
#define ARIA2_FFI_GETPID() static_cast<unsigned long>(getpid())
#endif

#ifdef ARIA2_FFI_WITH_LIBARIA2
#include <aria2/aria2.h>

/* aria2down patches libaria2 to expose removeDownloadResult / purgeDownloadResult
 * as public C++ API (see third_party/aria2/src/aria2api.cc). The patched
 * <aria2/aria2.h> defines ARIA2DOWN_HAS_REMOVE_DOWNLOAD_RESULT. Older prebuilt
 * artifacts predate the patch — in that case we keep building / running but
 * fall back to a soft no-op for stopped-task removal. Re-run
 * scripts/build_libaria2_<platform>.sh to refresh both the prebuilt header
 * and libaria2.a, then full removal behavior kicks in. */
#endif

namespace {

char *dup_cstr(const std::string &s) {
  char *out = static_cast<char *>(std::malloc(s.size() + 1));
  if (!out) return nullptr;
  std::memcpy(out, s.data(), s.size());
  out[s.size()] = '\0';
  return out;
}

#ifdef ARIA2_FFI_WITH_LIBARIA2

/* libaria2 returns BT info hash as 20 raw bytes (binary SHA-1).
 * aria2's own JSON-RPC server hex-encodes it via util::toHex before exposing
 * it (see RpcMethodImpl.cc::gatherProgressBitTorrent). Emitting raw bytes
 * here would produce invalid UTF-8 inside the JSON payload and crash the
 * Dart side's strict Utf8Decoder when reading the result string. */
std::string to_hex_lower(const std::string &bytes) {
  static const char kHex[] = "0123456789abcdef";
  std::string out;
  out.resize(bytes.size() * 2);
  for (size_t i = 0; i < bytes.size(); ++i) {
    const unsigned char b = static_cast<unsigned char>(bytes[i]);
    out[2 * i] = kHex[(b >> 4) & 0xF];
    out[2 * i + 1] = kHex[b & 0xF];
  }
  return out;
}

/* ----------------------------------------------------------------------
 * Minimal JSON utilities: we keep them local to avoid pulling a heavy
 * dependency into the shim. They cover only the shapes we need:
 *   - parsing top-level object/array of strings or string→string
 *   - emitting strings, numbers, bools, arrays, objects
 * ---------------------------------------------------------------------- */

class JsonWriter {
 public:
  void begin_object() {
    maybe_sep();
    buf_ << '{';
    first_stack_.push_back(true);
    in_obj_stack_.push_back(true);
  }
  void end_object() {
    buf_ << '}';
    first_stack_.pop_back();
    in_obj_stack_.pop_back();
  }
  void begin_array() {
    maybe_sep();
    buf_ << '[';
    first_stack_.push_back(true);
    in_obj_stack_.push_back(false);
  }
  void end_array() {
    buf_ << ']';
    first_stack_.pop_back();
    in_obj_stack_.pop_back();
  }
  void key(const std::string &k) {
    maybe_sep();
    write_string(k);
    buf_ << ':';
    pending_value_ = true;
  }
  void value_string(const std::string &v) {
    maybe_sep();
    write_string(v);
  }
  void value_int(int64_t v) {
    maybe_sep();
    buf_ << v;
  }
  void value_bool(bool v) {
    maybe_sep();
    buf_ << (v ? "true" : "false");
  }
  void value_raw(const std::string &raw) {
    maybe_sep();
    buf_ << raw;
  }
  std::string str() const { return buf_.str(); }

 private:
  void maybe_sep() {
    if (pending_value_) {
      pending_value_ = false;
      return;
    }
    if (first_stack_.empty()) return;
    if (first_stack_.back()) {
      first_stack_.back() = false;
    } else {
      buf_ << ',';
    }
  }
  void write_string(const std::string &s) {
    buf_ << '"';
    for (char c : s) {
      switch (c) {
        case '"': buf_ << "\\\""; break;
        case '\\': buf_ << "\\\\"; break;
        case '\b': buf_ << "\\b"; break;
        case '\f': buf_ << "\\f"; break;
        case '\n': buf_ << "\\n"; break;
        case '\r': buf_ << "\\r"; break;
        case '\t': buf_ << "\\t"; break;
        default:
          if (static_cast<unsigned char>(c) < 0x20) {
            char hex[8];
            std::snprintf(hex, sizeof(hex), "\\u%04x", c);
            buf_ << hex;
          } else {
            buf_ << c;
          }
      }
    }
    buf_ << '"';
  }
  std::ostringstream buf_;
  std::vector<bool> first_stack_;
  std::vector<bool> in_obj_stack_;
  bool pending_value_ = false;
};

class JsonReader {
 public:
  explicit JsonReader(const char *s) : p_(s ? s : ""), end_(p_ + (s ? std::strlen(s) : 0)) {}

  bool eof() { skip_ws(); return p_ >= end_; }

  bool peek(char c) { skip_ws(); return p_ < end_ && *p_ == c; }

  bool consume(char c) {
    skip_ws();
    if (p_ < end_ && *p_ == c) { ++p_; return true; }
    return false;
  }

  bool parse_string(std::string &out) {
    skip_ws();
    if (!consume('"')) return false;
    out.clear();
    while (p_ < end_) {
      char c = *p_++;
      if (c == '"') return true;
      if (c == '\\') {
        if (p_ >= end_) return false;
        char e = *p_++;
        switch (e) {
          case '"': out += '"'; break;
          case '\\': out += '\\'; break;
          case '/': out += '/'; break;
          case 'b': out += '\b'; break;
          case 'f': out += '\f'; break;
          case 'n': out += '\n'; break;
          case 'r': out += '\r'; break;
          case 't': out += '\t'; break;
          case 'u': {
            if (end_ - p_ < 4) return false;
            unsigned code = 0;
            for (int i = 0; i < 4; ++i) {
              char h = p_[i];
              code <<= 4;
              if (h >= '0' && h <= '9') code |= (h - '0');
              else if (h >= 'a' && h <= 'f') code |= (h - 'a' + 10);
              else if (h >= 'A' && h <= 'F') code |= (h - 'A' + 10);
              else return false;
            }
            p_ += 4;
            /* Naive: encode as UTF-8. We do not handle surrogate pairs. */
            if (code < 0x80) {
              out += static_cast<char>(code);
            } else if (code < 0x800) {
              out += static_cast<char>(0xC0 | (code >> 6));
              out += static_cast<char>(0x80 | (code & 0x3F));
            } else {
              out += static_cast<char>(0xE0 | (code >> 12));
              out += static_cast<char>(0x80 | ((code >> 6) & 0x3F));
              out += static_cast<char>(0x80 | (code & 0x3F));
            }
            break;
          }
          default: return false;
        }
      } else {
        out += c;
      }
    }
    return false;
  }

  /* Parse a JSON array of strings into `out`. */
  bool parse_string_array(std::vector<std::string> &out) {
    if (!consume('[')) return false;
    skip_ws();
    if (consume(']')) return true;
    while (true) {
      std::string s;
      if (!parse_string(s)) return false;
      out.push_back(std::move(s));
      skip_ws();
      if (consume(']')) return true;
      if (!consume(',')) return false;
    }
  }

  /* Parse a JSON object of {string: string|number|bool} into key/value
   * pairs as KeyVals (aria2 only accepts string values, so we coerce
   * non-strings to their textual form). */
  bool parse_string_map(aria2::KeyVals &out) {
    if (!consume('{')) return false;
    skip_ws();
    if (consume('}')) return true;
    while (true) {
      std::string k;
      if (!parse_string(k)) return false;
      if (!consume(':')) return false;
      skip_ws();
      std::string v;
      if (!parse_value_as_string(v)) return false;
      out.emplace_back(std::move(k), std::move(v));
      skip_ws();
      if (consume('}')) return true;
      if (!consume(',')) return false;
    }
  }

 private:
  bool parse_value_as_string(std::string &out) {
    skip_ws();
    if (p_ >= end_) return false;
    char c = *p_;
    if (c == '"') return parse_string(out);
    if (c == 't' || c == 'f') {
      if (end_ - p_ >= 4 && std::strncmp(p_, "true", 4) == 0) { p_ += 4; out = "true"; return true; }
      if (end_ - p_ >= 5 && std::strncmp(p_, "false", 5) == 0) { p_ += 5; out = "false"; return true; }
      return false;
    }
    if (c == 'n') {
      if (end_ - p_ >= 4 && std::strncmp(p_, "null", 4) == 0) { p_ += 4; out = ""; return true; }
      return false;
    }
    /* number */
    const char *start = p_;
    if (*p_ == '-' || *p_ == '+') ++p_;
    while (p_ < end_ && ((*p_ >= '0' && *p_ <= '9') || *p_ == '.' || *p_ == 'e' || *p_ == 'E' || *p_ == '-' || *p_ == '+')) ++p_;
    if (p_ == start) return false;
    out.assign(start, p_ - start);
    return true;
  }

  void skip_ws() {
    while (p_ < end_) {
      char c = *p_;
      if (c == ' ' || c == '\t' || c == '\r' || c == '\n') ++p_;
      else break;
    }
  }

  const char *p_;
  const char *end_;
};

/* ----------------------------------------------------------------------
 * Session bookkeeping
 *
 * libaria2 supports a single Session per process. We still expose an
 * integer handle so the Dart side can reason about lifetime; the handle
 * must match the currently active session.
 * ---------------------------------------------------------------------- */

std::mutex g_mu;
aria2::Session *g_session = nullptr;
int64_t g_handle = 0;
std::atomic<int64_t> g_next_handle{1};
std::atomic<bool> g_library_inited{false};
aria2_ffi_event_cb g_cb = nullptr;
void *g_cb_user_data = nullptr;
int64_t g_cb_handle = 0;

int trampoline_event_cb(aria2::Session *session, aria2::DownloadEvent event,
                        aria2::A2Gid gid, void *user_data) {
  (void)session;
  (void)user_data;
  aria2_ffi_event_cb cb;
  void *ud;
  int64_t handle;
  {
    std::lock_guard<std::mutex> lock(g_mu);
    cb = g_cb;
    ud = g_cb_user_data;
    handle = g_cb_handle;
  }
  if (cb && handle != 0) {
    cb(static_cast<int>(event), static_cast<uint64_t>(gid), ud);
  }
  return 0;
}

bool gid_from_text(const char *text, aria2::A2Gid &out) {
  if (!text || !*text) return false;
  out = aria2::hexToGid(std::string(text));
  if (aria2::isNull(out)) {
    /* maybe it's decimal */
    try {
      out = static_cast<aria2::A2Gid>(std::stoull(text));
    } catch (...) {
      return false;
    }
  }
  return !aria2::isNull(out);
}

std::string gid_to_text(aria2::A2Gid gid) { return aria2::gidToHex(gid); }

/* Returns false when the requested gid has no group AND no download result,
 * matching what aria2's JSON-RPC server reports as "No such download for
 * GID#…". Callers translate that to ARIA2_FFI_ERR_NOT_FOUND so the Dart side
 * sees a real error instead of an empty object — otherwise the UI happily
 * renders on a phantom status, then sends garbage gids back to FFI. */
bool status_to_writer(JsonWriter &w, aria2::Session *s, aria2::A2Gid gid,
                      const std::vector<std::string> *keys) {
  auto include = [&](const char *name) {
    if (!keys) return true;
    for (const auto &k : *keys) if (k == name) return true;
    return false;
  };
  // Whether keys filter (if any) explicitly mentions this field. Use this
  // when a field is conceptually optional in aria2's tellStatus payload
  // (errorMessage / numSeeders / seeder / verifiedLength / verifyIntegrityPending):
  // mirror aria2 RPC's behavior of always emitting when present, but only
  // gather the data if the caller explicitly asked for it.
  auto wants = [&](const char *name) { return include(name); };

  aria2::DownloadHandle *dh = aria2::getDownloadHandle(s, gid);
  if (!dh) return false;

  w.begin_object();
  if (include("gid")) { w.key("gid"); w.value_string(gid_to_text(gid)); }
  if (include("status")) {
    const char *name = "active";
    switch (dh->getStatus()) {
      case aria2::DOWNLOAD_ACTIVE: name = "active"; break;
      case aria2::DOWNLOAD_WAITING: name = "waiting"; break;
      case aria2::DOWNLOAD_PAUSED: name = "paused"; break;
      case aria2::DOWNLOAD_COMPLETE: name = "complete"; break;
      case aria2::DOWNLOAD_ERROR: name = "error"; break;
      case aria2::DOWNLOAD_REMOVED: name = "removed"; break;
    }
    w.key("status"); w.value_string(name);
  }
  if (include("totalLength")) { w.key("totalLength"); w.value_string(std::to_string(dh->getTotalLength())); }
  if (include("completedLength")) { w.key("completedLength"); w.value_string(std::to_string(dh->getCompletedLength())); }
  if (include("uploadLength")) { w.key("uploadLength"); w.value_string(std::to_string(dh->getUploadLength())); }
  if (include("downloadSpeed")) { w.key("downloadSpeed"); w.value_string(std::to_string(dh->getDownloadSpeed())); }
  if (include("uploadSpeed")) { w.key("uploadSpeed"); w.value_string(std::to_string(dh->getUploadSpeed())); }
  if (include("connections")) { w.key("connections"); w.value_string(std::to_string(dh->getConnections())); }
  if (include("numPieces")) { w.key("numPieces"); w.value_string(std::to_string(dh->getNumPieces())); }
  if (include("pieceLength")) { w.key("pieceLength"); w.value_string(std::to_string(dh->getPieceLength())); }
  if (include("bitfield")) { w.key("bitfield"); w.value_string(dh->getBitfield()); }
  if (include("dir")) { w.key("dir"); w.value_string(dh->getDir()); }
  if (include("infoHash")) {
    /* libaria2 returns 20 raw binary bytes; aria2's RPC server hex-encodes
     * them (RpcMethodImpl.cc:gatherProgressBitTorrent). Mirror that here so
     * the JSON payload stays valid UTF-8 and matches the wire format the
     * Dart side already expects (40 lowercase hex chars). */
    const std::string &ih = dh->getInfoHash();
    if (!ih.empty()) { w.key("infoHash"); w.value_string(to_hex_lower(ih)); }
  }
  if (include("errorCode")) {
    int ec = dh->getErrorCode();
    if (ec != 0) { w.key("errorCode"); w.value_string(std::to_string(ec)); }
  }
#ifdef ARIA2DOWN_HAS_DOWNLOAD_HANDLE_EXT
  // aria2down extension fields. The macro is defined in the patched
  // libaria2 <aria2/aria2.h>; old prebuilt artifacts silently skip these
  // (and the UI Tab simply shows empty rows, same as before this patch).
  if (wants("errorMessage")) {
    std::string em = dh->getErrorMessage();
    if (!em.empty()) { w.key("errorMessage"); w.value_string(em); }
  }
  if (wants("numSeeders")) {
    int ns = dh->getNumSeeders();
    if (ns > 0) {
      w.key("numSeeders");
      w.value_string(std::to_string(ns));
    }
  }
  if (wants("seeder")) {
    // aria2 RPC only emits `seeder` for BT tasks; isSeeder() returns false
    // on non-BT so the field is meaningless then. Emit only when true.
    if (dh->isSeeder()) {
      w.key("seeder");
      w.value_string("true");
    }
  }
  if (wants("verifiedLength")) {
    int64_t vl = dh->getVerifiedLength();
    if (vl > 0) {
      w.key("verifiedLength");
      w.value_string(std::to_string(vl));
    }
  }
  if (wants("verifyIntegrityPending")) {
    if (dh->isVerifyIntegrityPending()) {
      w.key("verifyIntegrityPending");
      w.value_string("true");
    }
  }
#else
  (void)wants;
#endif
  if (include("following")) {
    aria2::A2Gid f = dh->getFollowing();
    if (!aria2::isNull(f)) { w.key("following"); w.value_string(gid_to_text(f)); }
  }
  if (include("followedBy")) {
    const auto &fb = dh->getFollowedBy();
    if (!fb.empty()) {
      w.key("followedBy");
      w.begin_array();
      for (const auto &g : fb) w.value_string(gid_to_text(g));
      w.end_array();
    }
  }
  if (include("belongsTo")) {
    aria2::A2Gid b = dh->getBelongsTo();
    if (!aria2::isNull(b)) { w.key("belongsTo"); w.value_string(gid_to_text(b)); }
  }
  if (include("files")) {
    w.key("files");
    w.begin_array();
    auto files = dh->getFiles();
    for (const auto &f : files) {
      w.begin_object();
      w.key("index"); w.value_string(std::to_string(f.index));
      w.key("path"); w.value_string(f.path);
      w.key("length"); w.value_string(std::to_string(f.length));
      w.key("completedLength"); w.value_string(std::to_string(f.completedLength));
      w.key("selected"); w.value_string(f.selected ? "true" : "false");
      w.key("uris");
      w.begin_array();
      for (const auto &u : f.uris) {
        w.begin_object();
        w.key("uri"); w.value_string(u.uri);
        w.key("status"); w.value_string(u.status == aria2::URI_USED ? "used" : "waiting");
        w.end_object();
      }
      w.end_array();
      w.end_object();
    }
    w.end_array();
  }
  if (include("bittorrent")) {
    aria2::BtMetaInfoData bt = dh->getBtMetaInfo();
    if (!bt.name.empty() || !bt.announceList.empty()) {
      w.key("bittorrent");
      w.begin_object();
      w.key("mode");
      const char *mode = "none";
      switch (bt.mode) {
        case aria2::BT_FILE_MODE_NONE: mode = "none"; break;
        case aria2::BT_FILE_MODE_SINGLE: mode = "single"; break;
        case aria2::BT_FILE_MODE_MULTI: mode = "multi"; break;
      }
      w.value_string(mode);
      if (!bt.name.empty()) {
        w.key("info");
        w.begin_object();
        w.key("name"); w.value_string(bt.name);
        w.end_object();
      }
      if (!bt.announceList.empty()) {
        w.key("announceList");
        w.begin_array();
        for (const auto &tier : bt.announceList) {
          w.begin_array();
          for (const auto &u : tier) w.value_string(u);
          w.end_array();
        }
        w.end_array();
      }
      if (!bt.comment.empty()) { w.key("comment"); w.value_string(bt.comment); }
      if (bt.creationDate != 0) {
        w.key("creationDate");
        w.value_string(std::to_string(static_cast<int64_t>(bt.creationDate)));
      }
      w.end_object();
    }
  }
  w.end_object();
  aria2::deleteDownloadHandle(dh);
  return true;
}

void files_to_writer(JsonWriter &w, aria2::Session *s, aria2::A2Gid gid) {
  aria2::DownloadHandle *dh = aria2::getDownloadHandle(s, gid);
  if (!dh) { w.begin_array(); w.end_array(); return; }
  w.begin_array();
  auto files = dh->getFiles();
  for (const auto &f : files) {
    w.begin_object();
    w.key("index"); w.value_string(std::to_string(f.index));
    w.key("path"); w.value_string(f.path);
    w.key("length"); w.value_string(std::to_string(f.length));
    w.key("completedLength"); w.value_string(std::to_string(f.completedLength));
    w.key("selected"); w.value_string(f.selected ? "true" : "false");
    w.key("uris");
    w.begin_array();
    for (const auto &u : f.uris) {
      w.begin_object();
      w.key("uri"); w.value_string(u.uri);
      w.key("status"); w.value_string(u.status == aria2::URI_USED ? "used" : "waiting");
      w.end_object();
    }
    w.end_array();
    w.end_object();
  }
  w.end_array();
  aria2::deleteDownloadHandle(dh);
}

/* Base64 decoder for torrent / metalink payloads. Lives in the file-scope
 * anonymous namespace (not inside `extern "C"`), so clang does not flag the
 * std::string return type with -Wreturn-type-c-linkage. */
bool b64_decode(const char *in, std::string &out) {
  static const int table[256] = {
    /*  0 */ -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    /* 16 */ -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    /* 32 */ -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,62,-1,-1,-1,63,
    /* 48 */ 52,53,54,55,56,57,58,59,60,61,-1,-1,-1, 0,-1,-1,
    /* 64 */ -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14,
    /* 80 */ 15,16,17,18,19,20,21,22,23,24,25,-1,-1,-1,-1,-1,
    /* 96 */ -1,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,
    /*112 */ 41,42,43,44,45,46,47,48,49,50,51,-1,-1,-1,-1,-1,
  };
  if (!in) return false;
  size_t len = std::strlen(in);
  out.clear();
  out.reserve((len * 3) / 4);
  int val = 0, valb = -8;
  for (size_t i = 0; i < len; ++i) {
    unsigned char c = static_cast<unsigned char>(in[i]);
    if (c == '=' || c == '\r' || c == '\n' || c == ' ' || c == '\t') continue;
    int x = c < 128 ? table[c] : -1;
    if (x < 0) return false;
    val = (val << 6) | x;
    valb += 6;
    if (valb >= 0) {
      out.push_back(static_cast<char>((val >> valb) & 0xFF));
      valb -= 8;
    }
  }
  return true;
}

/* Write `data` to a temporary file and return its path. Caller owns it and
 * is responsible for cleanup; on error returns empty string. */
std::string write_temp(const std::string &data, const char *suffix) {
  const char *tmpdir = std::getenv("TMPDIR");
  if (!tmpdir) tmpdir = std::getenv("TEMP");
  if (!tmpdir) tmpdir = "/tmp";
  static std::atomic<uint64_t> counter{0};
  std::ostringstream path;
  path << tmpdir << "/aria2_ffi_" << ARIA2_FFI_GETPID()
       << '_' << counter.fetch_add(1) << '_' << suffix;
  std::string p = path.str();
  FILE *f = std::fopen(p.c_str(), "wb");
  if (!f) return std::string();
  if (std::fwrite(data.data(), 1, data.size(), f) != data.size()) {
    std::fclose(f);
    std::remove(p.c_str());
    return std::string();
  }
  std::fclose(f);
  return p;
}

#endif /* ARIA2_FFI_WITH_LIBARIA2 */

} /* anonymous namespace */

extern "C" {

int aria2_ffi_is_available(void) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  return 1;
#else
  return 0;
#endif
}

const char *aria2_ffi_library_version(void) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  /* libaria2 has no public version function; pass through the build-time
   * macro that the build script defines. */
#ifdef ARIA2_FFI_LIBARIA2_VERSION
  return dup_cstr(std::string(ARIA2_FFI_LIBARIA2_VERSION));
#else
  return dup_cstr(std::string(""));
#endif
#else
  return dup_cstr(std::string(""));
#endif
}

const char *aria2_ffi_get_capabilities(void) {
  /* Emit a JSON array of capability strings. Build a literal here rather
   * than going through JsonWriter to keep the entry point dependency-free
   * (callable even from a stub build that ships without ARIA2_FFI_WITH_LIBARIA2). */
  std::string out = "[";
  bool first = true;
  auto append = [&](const char *name) {
    if (!first) out += ",";
    first = false;
    out += "\"";
    out += name;
    out += "\"";
  };
#ifdef ARIA2_FFI_WITH_LIBARIA2
#  ifdef ARIA2DOWN_HAS_REMOVE_DOWNLOAD_RESULT
  append("removeDownloadResult");
#  endif
#  ifdef ARIA2DOWN_HAS_LIST_RESERVED
  append("listReserved");
#  endif
#  ifdef ARIA2DOWN_HAS_LIST_DOWNLOAD_RESULTS
  append("listDownloadResults");
#  endif
#  ifdef ARIA2DOWN_HAS_DOWNLOAD_HANDLE_EXT
  append("downloadHandleExt");
#  endif
#endif
  (void)append;
  out += "]";
  return dup_cstr(out);
}

void aria2_ffi_free_string(const char *s) {
  if (s) std::free(const_cast<char *>(s));
}

int aria2_ffi_library_init(void) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  if (g_library_inited.exchange(true)) return ARIA2_FFI_ERR_ALREADY_INITIALIZED;
  int rv = aria2::libraryInit();
  if (rv != 0) { g_library_inited.store(false); return rv; }
  return ARIA2_FFI_OK;
#else
  return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_library_deinit(void) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  if (!g_library_inited.exchange(false)) return ARIA2_FFI_ERR_NOT_INITIALIZED;
  return aria2::libraryDeinit();
#else
  return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_session_new(const char *options_json, int64_t *out_handle) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  if (!g_library_inited.load()) return ARIA2_FFI_ERR_NOT_INITIALIZED;
  if (!out_handle) return ARIA2_FFI_ERR_INVALID_ARGUMENT;

  aria2::KeyVals options;
  if (options_json && *options_json) {
    JsonReader r(options_json);
    if (!r.parse_string_map(options)) return ARIA2_FFI_ERR_INVALID_ARGUMENT;
  }

  aria2::SessionConfig cfg;
  cfg.keepRunning = true;
  cfg.useSignalHandler = false;
  cfg.downloadEventCallback = trampoline_event_cb;
  cfg.userData = nullptr;

  /* Bail out on stranded singleton — the previous in-process reclaim path
   * (sessionFinal(stale) + sessionNew) turned out to crash on Android in
   * libaria2's multi-session-per-libraryInit code path: the new session
   * built fine, but its first run_once segfaulted inside
   * EpollEventPoll::poll → DownloadEngine::run (reproduced by a user on
   * Redmi Android 16 OS3.0.302.0). The root cause is libaria2 not really
   * supporting "tear down one session, immediately build another in the
   * same libraryInit lifetime": SocketCore / AsyncNameResolver / SSL
   * static state retain pointers into the prior session and the prior
   * worker isolate's (now-destroyed) NativeCallable trampoline. Cleanly
   * disarming our own bookkeeping (g_cb etc.) is not enough — libaria2's
   * own globals are the dangling references.
   *
   * After the Activity / Service lifecycle was tightened so the entire
   * Application process is killed on Activity onDestroy / Service
   * onTaskRemoved (see MainActivity.onDestroy +
   * Aria2KeepAliveService.onTaskRemoved), this branch should never be
   * reachable in normal usage. We keep it as a defensive last resort:
   * if we still observe a stranded session, call _exit(0) so Android
   * relaunches the process from a clean state (the foreground service
   * is START_STICKY and will be restarted shortly after; the user sees
   * the launch UI flash once, far better than a native segfault).
   *
   * Using _exit (not exit) skips C++ static dtors — which is exactly
   * what we want, since those dtors are the very globals that are
   * already in a corrupt state. */
  {
    std::lock_guard<std::mutex> lock(g_mu);
    if (g_session != nullptr) {
      g_cb = nullptr;
      g_cb_user_data = nullptr;
      g_cb_handle = 0;
      _exit(0);
    }
  }

  std::lock_guard<std::mutex> lock(g_mu);
  aria2::Session *s = aria2::sessionNew(options, cfg);
  if (!s) return ARIA2_FFI_ERR_INTERNAL;
  g_session = s;
  g_handle = g_next_handle.fetch_add(1);
  *out_handle = g_handle;
  return ARIA2_FFI_OK;
#else
  (void)options_json;
  if (out_handle) *out_handle = 0;
  return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_session_final(int64_t handle) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  std::lock_guard<std::mutex> lock(g_mu);
  if (g_session == nullptr || handle != g_handle) return ARIA2_FFI_ERR_NOT_FOUND;
  int rv = aria2::sessionFinal(g_session);
  g_session = nullptr;
  g_handle = 0;
  g_cb = nullptr;
  g_cb_user_data = nullptr;
  g_cb_handle = 0;
  return rv == 0 ? ARIA2_FFI_OK : rv;
#else
  (void)handle;
  return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_run_once(int64_t handle) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s;
  {
    std::lock_guard<std::mutex> lock(g_mu);
    if (g_session == nullptr || handle != g_handle) return ARIA2_FFI_ERR_NOT_FOUND;
    s = g_session;
  }
  return aria2::run(s, aria2::RUN_ONCE);
#else
  (void)handle;
  return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_shutdown(int64_t handle, int force) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s;
  {
    std::lock_guard<std::mutex> lock(g_mu);
    if (g_session == nullptr || handle != g_handle) return ARIA2_FFI_ERR_NOT_FOUND;
    s = g_session;
  }
  return aria2::shutdown(s, force != 0);
#else
  (void)handle;
  (void)force;
  return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_set_event_callback(int64_t handle, aria2_ffi_event_cb cb, void *user_data) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  std::lock_guard<std::mutex> lock(g_mu);
  if (g_session == nullptr || handle != g_handle) return ARIA2_FFI_ERR_NOT_FOUND;
  g_cb = cb;
  g_cb_user_data = user_data;
  g_cb_handle = handle;
  return ARIA2_FFI_OK;
#else
  (void)handle;
  (void)cb;
  (void)user_data;
  return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

#ifdef ARIA2_FFI_WITH_LIBARIA2
static aria2::Session *session_or_null(int64_t handle) {
  std::lock_guard<std::mutex> lock(g_mu);
  if (g_session == nullptr || handle != g_handle) return nullptr;
  return g_session;
}
#endif

int aria2_ffi_add_uri(int64_t handle, const char *uris_json,
                      const char *options_json, int position,
                      const char **out_gid) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
  if (!uris_json || !out_gid) return ARIA2_FFI_ERR_INVALID_ARGUMENT;
  std::vector<std::string> uris;
  {
    JsonReader r(uris_json);
    if (!r.parse_string_array(uris)) return ARIA2_FFI_ERR_INVALID_ARGUMENT;
  }
  aria2::KeyVals opts;
  if (options_json && *options_json) {
    JsonReader r(options_json);
    if (!r.parse_string_map(opts)) return ARIA2_FFI_ERR_INVALID_ARGUMENT;
  }
  aria2::A2Gid gid;
  int rv = aria2::addUri(s, &gid, uris, opts, position);
  if (rv != 0) return rv;
  *out_gid = dup_cstr(gid_to_text(gid));
  return ARIA2_FFI_OK;
#else
  (void)handle; (void)uris_json; (void)options_json; (void)position;
  if (out_gid) *out_gid = nullptr;
  return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_add_torrent(int64_t handle, const char *torrent_b64,
                          const char *uris_json, const char *options_json,
                          int position, const char **out_gid) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
  if (!torrent_b64 || !out_gid) return ARIA2_FFI_ERR_INVALID_ARGUMENT;
  std::string raw;
  if (!b64_decode(torrent_b64, raw)) return ARIA2_FFI_ERR_INVALID_ARGUMENT;
  std::string path = write_temp(raw, "torrent");
  if (path.empty()) return ARIA2_FFI_ERR_INTERNAL;
  std::vector<std::string> uris;
  if (uris_json && *uris_json) {
    JsonReader r(uris_json);
    if (!r.parse_string_array(uris)) { std::remove(path.c_str()); return ARIA2_FFI_ERR_INVALID_ARGUMENT; }
  }
  aria2::KeyVals opts;
  if (options_json && *options_json) {
    JsonReader r(options_json);
    if (!r.parse_string_map(opts)) { std::remove(path.c_str()); return ARIA2_FFI_ERR_INVALID_ARGUMENT; }
  }
  aria2::A2Gid gid;
  int rv = aria2::addTorrent(s, &gid, path, uris, opts, position);
  std::remove(path.c_str());
  if (rv != 0) return rv;
  *out_gid = dup_cstr(gid_to_text(gid));
  return ARIA2_FFI_OK;
#else
  (void)handle; (void)torrent_b64; (void)uris_json; (void)options_json; (void)position;
  if (out_gid) *out_gid = nullptr;
  return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_add_metalink(int64_t handle, const char *metalink_b64,
                           const char *options_json, int position,
                           const char **out_gids) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
  if (!metalink_b64 || !out_gids) return ARIA2_FFI_ERR_INVALID_ARGUMENT;
  std::string raw;
  if (!b64_decode(metalink_b64, raw)) return ARIA2_FFI_ERR_INVALID_ARGUMENT;
  std::string path = write_temp(raw, "metalink");
  if (path.empty()) return ARIA2_FFI_ERR_INTERNAL;
  aria2::KeyVals opts;
  if (options_json && *options_json) {
    JsonReader r(options_json);
    if (!r.parse_string_map(opts)) { std::remove(path.c_str()); return ARIA2_FFI_ERR_INVALID_ARGUMENT; }
  }
  std::vector<aria2::A2Gid> gids;
  int rv = aria2::addMetalink(s, &gids, path, opts, position);
  std::remove(path.c_str());
  if (rv != 0) return rv;
  JsonWriter w;
  w.begin_array();
  for (const auto &g : gids) w.value_string(gid_to_text(g));
  w.end_array();
  *out_gids = dup_cstr(w.str());
  return ARIA2_FFI_OK;
#else
  (void)handle; (void)metalink_b64; (void)options_json; (void)position;
  if (out_gids) *out_gids = nullptr;
  return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_remove(int64_t handle, const char *gid, int force) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
  aria2::A2Gid g;
  if (!gid_from_text(gid, g)) return ARIA2_FFI_ERR_INVALID_ARGUMENT;
  int rv = aria2::removeDownload(s, g, force != 0);
  if (rv == 0) return ARIA2_FFI_OK;
#  ifdef ARIA2DOWN_HAS_REMOVE_DOWNLOAD_RESULT
  /* Completed/error/removed tasks live in downloadResults_, not the active
   * group list. The aria2down public extension lets us evict them. */
  if (aria2::removeDownloadResult(s, g) == 0) return ARIA2_FFI_OK;
#  endif
  /* Stale libaria2.a (pre-patch): soft success so the Dart side doesn't show
   * an error. The stopped entry will be auto-trimmed via maxDownloadResult,
   * and the user is prompted (CHANGELOG) to rebuild libaria2 for real
   * eviction. */
  return ARIA2_FFI_OK;
#else
  (void)handle; (void)gid; (void)force; return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_pause(int64_t handle, const char *gid, int force) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
  aria2::A2Gid g;
  if (!gid_from_text(gid, g)) return ARIA2_FFI_ERR_INVALID_ARGUMENT;
  return aria2::pauseDownload(s, g, force != 0);
#else
  (void)handle; (void)gid; (void)force; return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_pause_all(int64_t handle, int force) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
  /* aria2's JSON-RPC pauseAll iterates both requestGroups_ (active) AND
   * reservedGroups_ (waiting). Mirror that so library-mode "Pause All"
   * behaves identically to RPC. The reserved enumeration is an aria2down
   * patch — stale prebuilt artifacts simply skip waiting tasks (Dart side
   * has a fallback via Aria2InProcessTransport). */
  int rv = 0;
  auto active = aria2::getActiveDownload(s);
  for (const auto &g : active) {
    int r = aria2::pauseDownload(s, g, force != 0);
    if (r != 0) rv = r;
  }
#  ifdef ARIA2DOWN_HAS_LIST_RESERVED
  auto reserved = aria2::getReservedDownload(s);
  for (const auto &g : reserved) {
    int r = aria2::pauseDownload(s, g, force != 0);
    if (r != 0) rv = r;
  }
#  endif
  return rv;
#else
  (void)handle; (void)force; return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_unpause(int64_t handle, const char *gid) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
  aria2::A2Gid g;
  if (!gid_from_text(gid, g)) return ARIA2_FFI_ERR_INVALID_ARGUMENT;
  return aria2::unpauseDownload(s, g);
#else
  (void)handle; (void)gid; return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_unpause_all(int64_t handle) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
  /* aria2's JSON-RPC unpauseAll walks reservedGroups_ and clears
   * pauseRequested on every entry. Mirror that here when the reserved
   * enumeration helper is available (aria2down patch). On stale prebuilt
   * libaria2.a we fall back to a no-op — the Dart side has an
   * `Aria2InProcessTransport` fallback that emulates this via tellWaiting
   * + per-task unpause for that build. */
#  ifdef ARIA2DOWN_HAS_LIST_RESERVED
  auto reserved = aria2::getReservedDownload(s);
  for (const auto &g : reserved) {
    /* unpauseDownload only succeeds on actually-paused entries; ignore
     * the per-call failure so a single waiting (not paused) task doesn't
     * stop the rest. */
    (void)aria2::unpauseDownload(s, g);
  }
#  endif
  return ARIA2_FFI_OK;
#else
  (void)handle; return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_purge_download_result(int64_t handle) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
#  ifdef ARIA2DOWN_HAS_REMOVE_DOWNLOAD_RESULT
  aria2::purgeDownloadResult(s);
#  else
  (void)s; /* soft no-op against stale prebuilt; see CHANGELOG. */
#  endif
  return ARIA2_FFI_OK;
#else
  (void)handle; return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_remove_download_result(int64_t handle, const char *gid) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
  aria2::A2Gid g;
  if (!gid_from_text(gid, g)) return ARIA2_FFI_ERR_INVALID_ARGUMENT;
#  ifdef ARIA2DOWN_HAS_REMOVE_DOWNLOAD_RESULT
  return aria2::removeDownloadResult(s, g) == 0 ? ARIA2_FFI_OK
                                                : ARIA2_FFI_ERR_NOT_FOUND;
#  else
  /* Stale libaria2.a without the public extension — see aria2_ffi_remove
   * comment. Try removeDownload(force=true) for active/waiting tasks; treat
   * stopped tasks as soft success. */
  (void)aria2::removeDownload(s, g, true);
  return ARIA2_FFI_OK;
#  endif
#else
  (void)handle; (void)gid; return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_change_position(int64_t handle, const char *gid, int pos, int how) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
  aria2::A2Gid g;
  if (!gid_from_text(gid, g)) return ARIA2_FFI_ERR_INVALID_ARGUMENT;
  aria2::OffsetMode mode = aria2::OFFSET_MODE_SET;
  switch (how) {
    case 0: mode = aria2::OFFSET_MODE_SET; break;
    case 1: mode = aria2::OFFSET_MODE_CUR; break;
    case 2: mode = aria2::OFFSET_MODE_END; break;
    default: return ARIA2_FFI_ERR_INVALID_ARGUMENT;
  }
  return aria2::changePosition(s, g, pos, mode);
#else
  (void)handle; (void)gid; (void)pos; (void)how; return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_change_option(int64_t handle, const char *gid, const char *options_json) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
  aria2::A2Gid g;
  if (!gid_from_text(gid, g)) return ARIA2_FFI_ERR_INVALID_ARGUMENT;
  aria2::KeyVals opts;
  if (options_json && *options_json) {
    JsonReader r(options_json);
    if (!r.parse_string_map(opts)) return ARIA2_FFI_ERR_INVALID_ARGUMENT;
  }
  return aria2::changeOption(s, g, opts);
#else
  (void)handle; (void)gid; (void)options_json; return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_change_global_option(int64_t handle, const char *options_json) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
  aria2::KeyVals opts;
  if (options_json && *options_json) {
    JsonReader r(options_json);
    if (!r.parse_string_map(opts)) return ARIA2_FFI_ERR_INVALID_ARGUMENT;
  }
  return aria2::changeGlobalOption(s, opts);
#else
  (void)handle; (void)options_json; return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_tell_status(int64_t handle, const char *gid, const char *keys_json,
                          const char **out_json) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
  aria2::A2Gid g;
  if (!gid_from_text(gid, g)) return ARIA2_FFI_ERR_INVALID_ARGUMENT;
  std::vector<std::string> keys;
  std::vector<std::string> *kp = nullptr;
  if (keys_json && *keys_json) {
    JsonReader r(keys_json);
    if (r.parse_string_array(keys)) kp = &keys;
  }
  JsonWriter w;
  if (!status_to_writer(w, s, g, kp)) {
    *out_json = nullptr;
    return ARIA2_FFI_ERR_NOT_FOUND;
  }
  *out_json = dup_cstr(w.str());
  return ARIA2_FFI_OK;
#else
  (void)handle; (void)gid; (void)keys_json;
  if (out_json) *out_json = nullptr;
  return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

#ifdef ARIA2_FFI_WITH_LIBARIA2
static int tell_list_active(aria2::Session *s, const char *keys_json,
                            const char **out_json) {
  std::vector<std::string> keys;
  std::vector<std::string> *kp = nullptr;
  if (keys_json && *keys_json) {
    JsonReader r(keys_json);
    if (r.parse_string_array(keys)) kp = &keys;
  }
  JsonWriter w;
  w.begin_array();
  auto gids = aria2::getActiveDownload(s);
  for (const auto &g : gids) status_to_writer(w, s, g, kp);
  w.end_array();
  *out_json = dup_cstr(w.str());
  return ARIA2_FFI_OK;
}
#endif

int aria2_ffi_tell_active(int64_t handle, const char *keys_json, const char **out_json) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
  return tell_list_active(s, keys_json, out_json);
#else
  (void)handle; (void)keys_json;
  if (out_json) *out_json = nullptr;
  return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

#ifdef ARIA2_FFI_WITH_LIBARIA2
/* Shared helper: write a JSON array of status objects for a list of gids,
 * honoring offset / num pagination (negative num → "to end"). Used by both
 * tell_waiting and tell_stopped now that aria2down patches expose the
 * reserved/results enumeration. */
static void emit_status_array(JsonWriter &w, aria2::Session *s,
                              const std::vector<aria2::A2Gid> &gids,
                              int offset, int num,
                              const std::vector<std::string> *kp) {
  w.begin_array();
  const int total = static_cast<int>(gids.size());
  // Match aria2 RPC semantics: negative offset counts from the end.
  int start = offset;
  if (start < 0) start = total + start;
  if (start < 0) start = 0;
  if (start > total) start = total;
  int end = (num < 0) ? total : start + num;
  if (end > total) end = total;
  for (int i = start; i < end; ++i) {
    status_to_writer(w, s, gids[i], kp);
  }
  w.end_array();
}
#endif

int aria2_ffi_tell_waiting(int64_t handle, int offset, int num,
                           const char *keys_json, const char **out_json) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
  std::vector<std::string> keys;
  std::vector<std::string> *kp = nullptr;
  if (keys_json && *keys_json) {
    JsonReader r(keys_json);
    if (r.parse_string_array(keys)) kp = &keys;
  }
  JsonWriter w;
#  ifdef ARIA2DOWN_HAS_LIST_RESERVED
  auto reserved = aria2::getReservedDownload(s);
  emit_status_array(w, s, reserved, offset, num, kp);
#  else
  /* Stale prebuilt without the reserved enumeration patch: return empty
   * array (legacy behavior). UI prompts the user to rebuild libaria2 to
   * get the full list. */
  (void)offset; (void)num; (void)kp;
  w.begin_array();
  w.end_array();
#  endif
  *out_json = dup_cstr(w.str());
  return ARIA2_FFI_OK;
#else
  (void)handle; (void)offset; (void)num; (void)keys_json;
  if (out_json) *out_json = nullptr;
  return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_tell_stopped(int64_t handle, int offset, int num,
                           const char *keys_json, const char **out_json) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
  std::vector<std::string> keys;
  std::vector<std::string> *kp = nullptr;
  if (keys_json && *keys_json) {
    JsonReader r(keys_json);
    if (r.parse_string_array(keys)) kp = &keys;
  }
  JsonWriter w;
#  ifdef ARIA2DOWN_HAS_LIST_DOWNLOAD_RESULTS
  auto results = aria2::getDownloadResults(s);
  emit_status_array(w, s, results, offset, num, kp);
#  else
  /* Stale prebuilt: TaskHistoryRecorder picks up completed tasks via WS
   * events instead. */
  (void)offset; (void)num; (void)kp;
  w.begin_array();
  w.end_array();
#  endif
  *out_json = dup_cstr(w.str());
  return ARIA2_FFI_OK;
#else
  (void)handle; (void)offset; (void)num; (void)keys_json;
  if (out_json) *out_json = nullptr;
  return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_get_files(int64_t handle, const char *gid, const char **out_json) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
  aria2::A2Gid g;
  if (!gid_from_text(gid, g)) return ARIA2_FFI_ERR_INVALID_ARGUMENT;
  JsonWriter w;
  files_to_writer(w, s, g);
  *out_json = dup_cstr(w.str());
  return ARIA2_FFI_OK;
#else
  (void)handle; (void)gid;
  if (out_json) *out_json = nullptr;
  return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_get_peers(int64_t handle, const char *gid, const char **out_json) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  /* libaria2 has no public peer iterator. Return an empty array; UI tolerates
   * this. */
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
  (void)gid;
  *out_json = dup_cstr(std::string("[]"));
  return ARIA2_FFI_OK;
#else
  (void)handle; (void)gid;
  if (out_json) *out_json = nullptr;
  return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_get_global_stat(int64_t handle, const char **out_json) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
  aria2::GlobalStat gs = aria2::getGlobalStat(s);
  JsonWriter w;
  w.begin_object();
  w.key("downloadSpeed"); w.value_string(std::to_string(gs.downloadSpeed));
  w.key("uploadSpeed"); w.value_string(std::to_string(gs.uploadSpeed));
  w.key("numActive"); w.value_string(std::to_string(gs.numActive));
  w.key("numWaiting"); w.value_string(std::to_string(gs.numWaiting));
  w.key("numStopped"); w.value_string(std::to_string(gs.numStopped));
  w.key("numStoppedTotal"); w.value_string(std::to_string(gs.numStopped));
  w.end_object();
  *out_json = dup_cstr(w.str());
  return ARIA2_FFI_OK;
#else
  (void)handle;
  if (out_json) *out_json = nullptr;
  return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_get_global_option(int64_t handle, const char **out_json) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
  auto opts = aria2::getGlobalOptions(s);
  JsonWriter w;
  w.begin_object();
  for (const auto &kv : opts) { w.key(kv.first); w.value_string(kv.second); }
  w.end_object();
  *out_json = dup_cstr(w.str());
  return ARIA2_FFI_OK;
#else
  (void)handle;
  if (out_json) *out_json = nullptr;
  return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_get_option(int64_t handle, const char *gid, const char **out_json) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
  aria2::A2Gid g;
  if (!gid_from_text(gid, g)) return ARIA2_FFI_ERR_INVALID_ARGUMENT;
  aria2::DownloadHandle *dh = aria2::getDownloadHandle(s, g);
  if (!dh) { *out_json = dup_cstr(std::string("{}")); return ARIA2_FFI_OK; }
  auto opts = dh->getOptions();
  aria2::deleteDownloadHandle(dh);
  JsonWriter w;
  w.begin_object();
  for (const auto &kv : opts) { w.key(kv.first); w.value_string(kv.second); }
  w.end_object();
  *out_json = dup_cstr(w.str());
  return ARIA2_FFI_OK;
#else
  (void)handle; (void)gid;
  if (out_json) *out_json = nullptr;
  return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

int aria2_ffi_get_version(int64_t handle, const char **out_json) {
#ifdef ARIA2_FFI_WITH_LIBARIA2
  aria2::Session *s = session_or_null(handle);
  if (!s) return ARIA2_FFI_ERR_NOT_FOUND;
  (void)s;
  JsonWriter w;
  w.begin_object();
  w.key("version");
#ifdef ARIA2_FFI_LIBARIA2_VERSION
  w.value_string(std::string(ARIA2_FFI_LIBARIA2_VERSION));
#else
  w.value_string(std::string("libaria2"));
#endif
  w.key("enabledFeatures");
  w.begin_array();
  w.value_string("BitTorrent");
  w.value_string("Metalink");
  w.end_array();
  w.end_object();
  *out_json = dup_cstr(w.str());
  return ARIA2_FFI_OK;
#else
  (void)handle;
  if (out_json) *out_json = nullptr;
  return ARIA2_FFI_ERR_UNAVAILABLE;
#endif
}

} /* extern "C" */
