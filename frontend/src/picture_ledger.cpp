// The library pictures' ledger (frontend.h "library pictures: the ledger";
// docs/plans/2026-11-22-library-pictures-robust.md).
// SPDX-License-Identifier: GPL-2.0-or-later
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include "replaynes/frontend.h"
#include "util/Json.h"

namespace {
struct Entry {
  int crashes = 0;
  bool failed = false;  // failed for a reason the worker saw: skipped at once
  std::string reason;
};
constexpr int kCrashesToSkip = 2;

std::string readAll(const std::filesystem::path& p) {
  std::ifstream f(p, std::ios::binary);
  std::stringstream ss;
  ss << f.rdbuf();
  return ss.str();
}

// File name and size: a ROM put back with other contents is tried again.
std::string keyFor(const char* path) {
  if (!path || !*path) return "";
  std::error_code ec;
  const auto size = std::filesystem::file_size(std::filesystem::path(path), ec);
  return std::filesystem::path(path).filename().string() + "|" + (ec ? std::string("?") : std::to_string(size));
}
}  // namespace

struct rnf_picture_ledger {
  std::filesystem::path dir;
  std::map<std::string, Entry> entries;

  std::filesystem::path progressFile() const { return dir / "pictures-in-progress"; }
  std::filesystem::path failedFile() const { return dir / "pictures-failed.json"; }

  void save() const {
    rn::Json root = rn::Json::object();
    for (const auto& [key, e] : entries) {
      rn::Json j = rn::Json::object();
      j.set("crashes", e.crashes);
      j.set("failed", e.failed);
      j.set("reason", e.reason);
      root.set(key, std::move(j));
    }
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);
    const auto tmp = failedFile().string() + ".tmp";
    {
      std::ofstream f(tmp, std::ios::binary | std::ios::trunc);
      f << root.dump();
    }
    std::filesystem::rename(tmp, failedFile(), ec);
  }
};

extern "C" {

rnf_picture_ledger* rnf_picture_ledger_open(const char* dir) {
  auto* l = new rnf_picture_ledger;
  l->dir = dir ? dir : "";
  rn::Json root;
  if (rn::Json::parse(readAll(l->failedFile()), root) && root.isObject())
    for (const auto& [key, j] : root.members())
      l->entries[key] = Entry{int(j["crashes"].asInt()), j["failed"].asBool(), j["reason"].asString()};
  // Left over: the app ended while that ROM ran (a crash, or the OS ended it).
  std::error_code ec;
  if (std::filesystem::exists(l->progressFile(), ec)) {
    const std::string key = readAll(l->progressFile());
    if (!key.empty()) {
      Entry& e = l->entries[key];
      ++e.crashes;
      e.reason = "the app ended while its picture was being made";
      std::fprintf(stderr, "library pictures: %s ended the app before (%d time(s))\n", key.c_str(), e.crashes);
    }
    std::filesystem::remove(l->progressFile(), ec);
    l->save();
  }
  return l;
}

void rnf_picture_ledger_close(rnf_picture_ledger* l) { delete l; }

int rnf_picture_ledger_skipped(const rnf_picture_ledger* l, const char* rom_path) {
  if (!l) return 0;
  auto it = l->entries.find(keyFor(rom_path));
  return it != l->entries.end() && (it->second.failed || it->second.crashes >= kCrashesToSkip);
}

void rnf_picture_ledger_begin(rnf_picture_ledger* l, const char* rom_path) {
  if (!l) return;
  std::error_code ec;
  std::filesystem::create_directories(l->dir, ec);
  // Flushed and closed before the ROM runs: a crash right after still finds it.
  std::FILE* f = std::fopen(l->progressFile().string().c_str(), "wb");
  if (!f) return;
  const std::string key = keyFor(rom_path);
  std::fwrite(key.data(), 1, key.size(), f);
  std::fflush(f);
  std::fclose(f);
}

void rnf_picture_ledger_abandon(rnf_picture_ledger* l) {
  if (!l) return;
  std::error_code ec;
  std::filesystem::remove(l->progressFile(), ec);
}

void rnf_picture_ledger_end(rnf_picture_ledger* l, const char* rom_path, int ok, const char* reason) {
  if (!l) return;
  rnf_picture_ledger_abandon(l);
  const std::string key = keyFor(rom_path);
  if (ok) {
    if (l->entries.erase(key)) l->save();
    return;
  }
  Entry& e = l->entries[key];
  e.failed = true;
  e.reason = reason ? reason : "";
  l->save();
}

void rnf_picture_ledger_crashed(rnf_picture_ledger* l, const char* rom_path, const char* reason) {
  if (!l) return;
  rnf_picture_ledger_abandon(l);
  Entry& e = l->entries[keyFor(rom_path)];
  ++e.crashes;
  e.reason = reason ? reason : "";
  l->save();
}

}  // extern "C"
