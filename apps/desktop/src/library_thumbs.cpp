// SPDX-License-Identifier: GPL-2.0-or-later
#include "replaynes/product.h"
#include "library_thumbs.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <map>
#include <fstream>
#include <vector>

#include "replaynes/replaynes.h"

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#elif defined(__linux__)
#include <sys/resource.h>
#include <sys/syscall.h>
#include <unistd.h>
#endif

namespace rnl {

namespace {
constexpr char kMagic[8] = {'R', 'N', 'T', 'H', 'U', 'M', 'B', '1'};

uint64_t fnv1a(const std::string& s) {
  uint64_t h = 1469598103934665603ull;
  for (unsigned char c : s) {
    h ^= c;
    h *= 1099511628211ull;
  }
  return h;
}

bool writeFile(const std::string& path, const std::vector<uint32_t>& px, uint32_t width, uint32_t height) {
  std::string tmp = path + ".tmp";
  {
    std::ofstream f(std::filesystem::path(tmp), std::ios::binary | std::ios::trunc);
    if (!f) return false;
    const bool legacy = width == RNF_THUMB_WIDTH && height == RNF_THUMB_HEIGHT;
    char magic[8];
    std::memcpy(magic, kMagic, sizeof magic);
    if (!legacy) magic[7] = '2';
    f.write(magic, sizeof magic);
    if (!legacy) {
      // Little-endian dimensions make the new cache format portable.
      for (uint32_t n : {width, height}) for (int shift = 0; shift < 32; shift += 8) f.put(char(n >> shift));
    }
    f.write(reinterpret_cast<const char*>(px.data()), std::streamsize(px.size() * 4));
    if (!f) return false;
  }
  std::error_code ec;
  std::filesystem::rename(std::filesystem::path(tmp), std::filesystem::path(path), ec);
  return !ec;
}

// The calling thread below the UI and the game (the picture worker).
void lowerThreadPriority() {
#ifdef _WIN32
  SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_LOWEST);
#elif defined(__linux__)
  setpriority(PRIO_PROCESS, id_t(syscall(SYS_gettid)), 19);  // per thread on Linux
#endif
}
}  // namespace

LibraryThumbs::LibraryThumbs(std::string dir) : dir_(std::move(dir)) {}

LibraryThumbs::~LibraryThumbs() {
  {
    std::lock_guard<std::mutex> lk(picMutex_);
    picStop_ = true;
    picQueue_.clear();
    picLater_.clear();
  }
  picCv_.notify_all();
  if (picThread_.joinable()) picThread_.join();
  rnf_picture_ledger_close(ledger_);
  if (writer_.joinable()) writer_.join();
  for (auto& [rom, img] : picDone_) if (img) img->release();
  for (auto& [k, img] : cache_)
    if (img) img->release();
}

std::string LibraryThumbs::fileFor(const std::string& key) const {
  char name[32];
  std::snprintf(name, sizeof name, "%016llx.thumb", (unsigned long long)fnv1a(key));
  return dir_ + "/" + name;
}

void LibraryThumbs::put(const std::string& key, ThumbImage* img) {
  auto it = cache_.find(key);
  if (it != cache_.end() && it->second) it->second->release();
  cache_[key] = img;
}

ThumbImage* LibraryThumbs::readThumbFile(const std::string& path) {
    ThumbImage* img = nullptr;
    std::ifstream f(std::filesystem::path(path), std::ios::binary);
    char magic[8] = {};
    if (f && f.read(magic, sizeof magic) && std::memcmp(magic, kMagic, 7) == 0 &&
        (magic[7] == '1' || magic[7] == '2')) {
      uint32_t width = RNF_THUMB_WIDTH, height = RNF_THUMB_HEIGHT;
      if (magic[7] == '2') {
        uint32_t dims[2] = {};
        for (uint32_t& n : dims) for (int shift = 0; shift < 32; shift += 8) {
          int ch = f.get();
          if (ch == EOF) { f.setstate(std::ios::failbit); break; }
          n |= uint32_t(ch) << shift;
        }
        width = dims[0]; height = dims[1];
      }
      if (f && width == RNF_THUMB_WIDTH && height && height <= 65536) {
        std::vector<uint32_t> px(size_t(width) * height);
        if (f.read(reinterpret_cast<char*>(px.data()), std::streamsize(px.size() * 4)))
          img = ThumbImage::fromThumb(px.data(), width, height);
      }
    }
    return img;
}

ThumbRef LibraryThumbs::get(const std::string& key) {
  auto it = cache_.find(key);
  if (it == cache_.end()) it = cache_.emplace(key, readThumbFile(fileFor(key))).first;
  if (!it->second) return {};
  it->second->retain();
  return ThumbRef(it->second);
}

void LibraryThumbs::save(const std::string& projectPath, const std::string& romPath, const uint32_t* frame) {
  if (!frame || (projectPath.empty() && romPath.empty())) return;
  saveImage(projectPath, romPath, ThumbImage::make(frame));
}

void LibraryThumbs::save(const std::string& projectPath, const std::string& romPath,
                         const rn_video_frame_info& frame, const rn_media_info& media, bool nesPicture) {
  if (!frame.pixels || (projectPath.empty() && romPath.empty())) return;
  saveImage(projectPath, romPath, ThumbImage::make(frame, media, nesPicture));
}

void LibraryThumbs::saveImage(const std::string& projectPath, const std::string& romPath, ThumbImage* img) {
  if (!img) return;
  const uint32_t width = img->width, height = img->height;
  std::vector<std::pair<std::string, std::vector<uint32_t>>> writes;
  for (const std::string& key : {projectPath.empty() ? std::string() : "p:" + projectPath,
                                 romPath.empty() ? std::string() : "r:" + romPath}) {
    if (key.empty()) continue;
    img->retain();
    put(key, img);
    writes.emplace_back(fileFor(key), img->px);
  }
  img->release();
  // One write at a time; a save while the previous one runs waits for it (they are seconds apart).
  if (writer_.joinable()) writer_.join();
  std::string dir = dir_;
  writer_ = std::thread([dir, width, height, writes = std::move(writes)] {
    std::error_code ec;
    std::filesystem::create_directories(std::filesystem::path(dir), ec);
    for (const auto& [path, px] : writes)
      if (!writeFile(path, px, width, height)) std::fprintf(stderr, "cannot write %s\n", path.c_str());
  });
}

void LibraryThumbs::startPictureWorker() {
  if (!picThread_.joinable()) picThread_ = std::thread([this] { pictureWorker(); });
  picCv_.notify_one();
}

void LibraryThumbs::requestRomPicture(const std::string& romPath) {
  if (romPath.empty()) return;
  auto [it, added] = asked_.emplace(romPath, true);
  if (!added && it->second) return;
  it->second = true;
  {
    std::lock_guard<std::mutex> lk(picMutex_);
    if (!added) {  // queued for later: now, unless the worker has it already
      auto later = std::find(picLater_.begin(), picLater_.end(), romPath);
      if (later == picLater_.end()) return;
      picLater_.erase(later);
    }
    picQueue_.push_back(romPath);
  }
  startPictureWorker();
}

void LibraryThumbs::requestRomPictureLater(const std::string& romPath) {
  if (romPath.empty() || !asked_.emplace(romPath, false).second) return;
  {
    std::lock_guard<std::mutex> lk(picMutex_);
    picLater_.push_back(romPath);
  }
  startPictureWorker();
}

bool LibraryThumbs::blankPicture(const ThumbImage& img) {
  if (img.px.empty()) return true;
  // The commonest colour (16 levels a channel), then the pixels clearly away from it: under 5 % of
  // the picture is blank (black with a line or a notice in small letters: a game still starting).
  std::map<uint32_t, size_t> counts;
  for (uint32_t p : img.px) ++counts[p & 0xF0F0F0u];
  uint32_t common = 0;
  size_t most = 0;
  for (auto& [c, n] : counts)
    if (n > most) { most = n; common = c; }
  auto channel = [](uint32_t p, int shift) { return int((p >> shift) & 0xFF); };
  size_t away = 0;
  for (uint32_t p : img.px) {
    int d = 0;
    for (int shift : {0, 8, 16}) d = std::max(d, std::abs(channel(p, shift) - (channel(common, shift) + 8)));
    if (d > 40) ++away;
  }
  return away * 20 < img.px.size();
}

void LibraryThumbs::setPicturesPaused(bool paused) {
  {
    std::lock_guard<std::mutex> lk(picMutex_);
    if (picPaused_ == paused) return;
    picPaused_ = paused;
  }
  picCv_.notify_all();
}

bool LibraryThumbs::pollRomPictures() {
  std::vector<std::pair<std::string, ThumbImage*>> done;
  {
    std::lock_guard<std::mutex> lk(picMutex_);
    done.swap(picDone_);
  }
  // On disk already (the worker wrote it): a card that looked for the picture gets it now, any
  // other ROM's is read when its card shows.
  for (const auto& [rom, img] : done) {
    if (cache_.count("r:" + rom)) put("r:" + rom, img);
    else img->release();
  }
  return !done.empty();
}

void LibraryThumbs::pictureWorker() {
  lowerThreadPriority();
  if (!ledger_) ledger_ = rnf_picture_ledger_open(dir_.c_str());
  for (;;) {
    std::string rom;
    bool later = false;
    {
      std::unique_lock<std::mutex> lk(picMutex_);
      picCv_.wait(lk, [this] { return picStop_ || (!picPaused_ && (!picQueue_.empty() || !picLater_.empty())); });
      if (picStop_) return;
      std::deque<std::string>& q = picQueue_.empty() ? picLater_ : picQueue_;
      later = &q == &picLater_;
      rom = std::move(q.front());
      q.pop_front();
    }
    std::error_code ec;
    if (later && std::filesystem::exists(std::filesystem::path(fileFor("r:" + rom)), ec)) continue;
    if (rnf_picture_ledger_skipped(ledger_, rom.c_str())) continue;  // its card keeps the name tile
    rnf_picture_ledger_begin(ledger_, rom.c_str());
    const std::string out = fileFor("r:" + rom);
    std::string reason;
    if (pictureProcess_) {
      // Another process makes it: a crash or a hang there leaves the app running.
      std::filesystem::create_directories(std::filesystem::path(dir_), ec);
      const auto result = pictureProcess_(rom, out, [this] {
        std::lock_guard<std::mutex> lk(picMutex_);
        return picStop_ || picPaused_;
      }, &reason);
      if (result != PictureProcess::unavailable) {
        if (result == PictureProcess::made) {
          if (ThumbImage* img = readThumbFile(out)) {
            rnf_picture_ledger_end(ledger_, rom.c_str(), 1, nullptr);
            std::lock_guard<std::mutex> lk(picMutex_);
            picDone_.emplace_back(rom, img);
          } else {
            rnf_picture_ledger_end(ledger_, rom.c_str(), 0, "the picture process wrote no picture");
          }
        } else if (result == PictureProcess::failed) {
          rnf_picture_ledger_end(ledger_, rom.c_str(), 0, reason.c_str());
        } else if (result == PictureProcess::crashed) {
          std::fprintf(stderr, "library pictures: %s ended the picture process (%s)\n", rom.c_str(), reason.c_str());
          rnf_picture_ledger_crashed(ledger_, rom.c_str(), reason.c_str());
        } else {  // cancelled: a game opened (again from power-on once it closes) or the app is closing
          rnf_picture_ledger_abandon(ledger_);
          std::lock_guard<std::mutex> lk(picMutex_);
          if (!picStop_) (later ? picLater_ : picQueue_).push_front(rom);
        }
        continue;
      }
    }
    // In this process (no picture process on this platform): a crash here ends the app, the ledger keeps the
    // next start-ups from running that ROM again (twice at most).
    bool cancelled = false;
    ThumbImage* img = renderRomPicture(rom, &reason, &cancelled, [this, later](double seconds) {
      std::unique_lock<std::mutex> lk(picMutex_);
      if (picStop_ || picPaused_) return false;
      // As long a rest as the frame took: half of one core at most. Woken by a pause or stop.
      if (later) picCv_.wait_for(lk, std::chrono::duration<double>(seconds), [this] { return picStop_ || picPaused_; });
      return !(picStop_ || picPaused_);
    });
    if (cancelled) {
      rnf_picture_ledger_abandon(ledger_);  // not a failure: run again later
      std::lock_guard<std::mutex> lk(picMutex_);
      if (!picStop_) (later ? picLater_ : picQueue_).push_front(rom);  // a game opened: again once it closes
      continue;
    }
    rnf_picture_ledger_end(ledger_, rom.c_str(), img != nullptr, reason.c_str());
    if (img) {
      // Written before it is announced, so a card never looks for a file still to come.
      std::filesystem::create_directories(std::filesystem::path(dir_), ec);
      if (!writeFile(out, img->px, img->width, img->height)) std::fprintf(stderr, "cannot write %s\n", out.c_str());
      std::lock_guard<std::mutex> lk(picMutex_);
      picDone_.emplace_back(rom, img);
    }
  }
}

ThumbImage* LibraryThumbs::renderRomPicture(const std::string& rom, std::string* reason, bool* cancelled,
                                            const std::function<bool(double)>& afterFrame) {
  *cancelled = false;
  // Power-on, no input: in memory only (no project directory). The product's default core (an external core
  // reads files the NES cores cannot).
  rn_session* s = nullptr;
  rn_session_options opt;
  rn_session_options_init(&opt);
  const bool external = std::strcmp(RN_PRODUCT_DEFAULT_CORE, "external") == 0;
  if (external) opt.core = RN_CORE_EXTERNAL;
  if (rn_session_new(rom.c_str(), nullptr, external ? &opt : nullptr, &s) != RN_OK || !s) {
    *reason = "the engine cannot open it";
    return nullptr;
  }
  ThumbImage* img = nullptr;
  bool ok = true;
  for (int f = 0; ok && f < kRomPictureMaxFrame; ++f) {
    const auto t0 = std::chrono::steady_clock::now();
    ok = rn_step(s, 0, 0, 0, nullptr) == RN_OK;
    if (!ok) { *reason = "a frame failed"; break; }
    if (!afterFrame(std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count())) {
      *cancelled = true;
      ok = false;
      break;
    }
    if ((f + 1) % kRomPictureFrame != 0) continue;
    // Frame kRomPictureFrame, 2x, ...: the picture, unless it is still blank and there is time left (the last kept).
    rn_video_frame_info frame{};
    rn_media_info media{};
    if (rn_session_video_frame(s, &frame) != RN_OK || rn_session_media_info(s, &media) != RN_OK) {
      *reason = "no picture";
      ok = false;
      break;
    }
    if (img) img->release();
    img = ThumbImage::make(frame, media, rn_session_core_kind(s) != RN_CORE_EXTERNAL);
    if (!img || !blankPicture(*img)) break;
  }
  if (!ok && img) {
    img->release();
    img = nullptr;
  }
  if (ok && !img) *reason = "no picture";
  rn_session_close(s);
  return img;
}

bool LibraryThumbs::makeRomPictureFile(const std::string& rom, const std::string& out, std::string* reason) {
  // Test hook: a ROM file named rn-picture-crash-test* ends the picture process as a core crash would
  // (docs/plans/2026-11-22-library-pictures-robust.md, "Done when").
  if (std::filesystem::path(rom).filename().string().rfind("rn-picture-crash-test", 0) == 0) std::abort();
  bool cancelled = false;
  ThumbImage* img = renderRomPicture(rom, reason, &cancelled, [](double) { return true; });
  if (!img) return false;
  const bool written = writeFile(out, img->px, img->width, img->height);
  img->release();
  if (!written) *reason = "cannot write " + out;
  return written;
}

}  // namespace rnl
