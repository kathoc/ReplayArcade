// Phase 0 probe: load one FBNeo (libretro) game, then check that save -> run -> load -> rerun
// reproduces every frame exactly, and measure state size, save/load time and frame time.
//
// usage: fbneo_probe <core.so> <rom.zip> <system_dir> <save_dir> <out_dir>
//                    [warmup_frames=900] [compare_frames=600] [context=normal|runahead]
// Prints one JSON object on stdout. Exit code 0 = deterministic, 1 = mismatch, 2 = setup error.
#include <dlfcn.h>

#include <chrono>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "libretro.h"

namespace {

struct Core {
  void (*set_environment)(retro_environment_t);
  void (*set_video_refresh)(retro_video_refresh_t);
  void (*set_audio_sample)(retro_audio_sample_t);
  void (*set_audio_sample_batch)(retro_audio_sample_batch_t);
  void (*set_input_poll)(retro_input_poll_t);
  void (*set_input_state)(retro_input_state_t);
  void (*init)();
  void (*deinit)();
  void (*get_system_av_info)(retro_system_av_info*);
  bool (*load_game)(const retro_game_info*);
  void (*run)();
  size_t (*serialize_size)();
  bool (*serialize)(void*, size_t);
  bool (*unserialize)(const void*, size_t);
} core;

std::string g_system_dir, g_save_dir;
int g_context = RETRO_SAVESTATE_CONTEXT_NORMAL;
retro_pixel_format g_pixfmt = RETRO_PIXEL_FORMAT_0RGB1555;
unsigned g_rotation = 0;

// Per-frame observations, reset by the caller.
uint64_t g_frame = 0;  // our own frame counter; inputs are a pure function of it
uint64_t g_video_hash = 0, g_audio_hash = 0;
size_t g_audio_samples = 0;
unsigned g_width = 0, g_height = 0;
std::vector<uint8_t> g_last_frame;  // tightly packed copy of the last non-dupe frame
unsigned g_last_w = 0, g_last_h = 0, g_bpp = 2;

uint64_t fnv(const void* p, size_t n, uint64_t h = 1469598103934665603ull) {
  auto* b = static_cast<const uint8_t*>(p);
  for (size_t i = 0; i < n; i++) h = (h ^ b[i]) * 1099511628211ull;
  return h;
}

// Every 20 s: coins at +1 s and +1.5 s, start at +2 s and +2.5 s (boards that are still booting
// ignore the first ones, so it repeats), then buttons that change every 8 frames.
int16_t scripted_input(unsigned port, unsigned id, uint64_t f) {
  if (port > 1) return 0;
  uint64_t c = f % 1200;
  if (id == RETRO_DEVICE_ID_JOYPAD_SELECT) return port == 0 && ((c >= 60 && c < 66) || (c >= 90 && c < 96));
  if (id == RETRO_DEVICE_ID_JOYPAD_START) return port == 0 && ((c >= 120 && c < 126) || (c >= 150 && c < 156));
  if (f < 200) return 0;
  uint64_t x = (f / 8) * 0x9E3779B97F4A7C15ull + port * 0xBF58476D1CE4E5B9ull;
  x ^= x >> 31; x *= 0x94D049BB133111EBull; x ^= x >> 29;
  switch (id) {
    case RETRO_DEVICE_ID_JOYPAD_B: case RETRO_DEVICE_ID_JOYPAD_A: case RETRO_DEVICE_ID_JOYPAD_Y:
    case RETRO_DEVICE_ID_JOYPAD_X: case RETRO_DEVICE_ID_JOYPAD_L: case RETRO_DEVICE_ID_JOYPAD_R:
      return (x >> (id * 3)) & 1;
    case RETRO_DEVICE_ID_JOYPAD_UP: return ((x >> 40) & 3) == 1;
    case RETRO_DEVICE_ID_JOYPAD_DOWN: return ((x >> 40) & 3) == 2;
    case RETRO_DEVICE_ID_JOYPAD_LEFT: return ((x >> 44) & 3) == 1;
    case RETRO_DEVICE_ID_JOYPAD_RIGHT: return ((x >> 44) & 3) == 2;
  }
  return 0;
}

// Diagnostics (PROBE_AREAS=1): FBNeo logs each state area as "state debug: name %s, len %d, total %d".
struct Area { std::string name; size_t len, end; };
std::vector<Area> g_areas;
bool g_collect_areas = false;

void log_cb(enum retro_log_level level, const char* fmt, ...) {
  if (g_collect_areas) {
    // HandleMessage passes the formatted text as log_cb(level, "%s", buf).
    va_list ap;
    va_start(ap, fmt);
    std::string msg = !strcmp(fmt, "%s") ? va_arg(ap, const char*) : fmt;
    va_end(ap);
    size_t p = msg.find("state debug: name "), q = msg.rfind(", len ");
    if (p != std::string::npos && q != std::string::npos) {
      unsigned long len = 0, total = 0;
      sscanf(msg.c_str() + q, ", len %lu, total %lu", &len, &total);
      g_areas.push_back({msg.substr(p + 18, q - p - 18), size_t(len), size_t(total)});
    }
    return;
  }
  if (level < RETRO_LOG_WARN) return;
  va_list ap;
  va_start(ap, fmt);
  fprintf(stderr, "[core] ");
  vfprintf(stderr, fmt, ap);
  va_end(ap);
}

bool environment(unsigned cmd, void* data) {
  switch (cmd) {
    case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY: *(const char**)data = g_system_dir.c_str(); return true;
    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY: *(const char**)data = g_save_dir.c_str(); return true;
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: g_pixfmt = *(retro_pixel_format*)data; return true;
    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: ((retro_log_callback*)data)->log = log_cb; return true;
    case RETRO_ENVIRONMENT_GET_SAVESTATE_CONTEXT:
      if (data) *(int*)data = g_context;
      return true;
    case RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE: if (data) *(int*)data = 3; return true;
    case RETRO_ENVIRONMENT_SET_ROTATION: g_rotation = *(const unsigned*)data; return true;
    case RETRO_ENVIRONMENT_GET_VARIABLE: {
      auto* v = (retro_variable*)data;
      // Hiscore injection reads hiscore.dat from the system dir: an outside input to the machine.
      if (v && v->key && !strcmp(v->key, "fbneo-hiscores")) { v->value = "disabled"; return true; }
      return false;
    }
    case RETRO_ENVIRONMENT_SET_GEOMETRY:
    case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
    case RETRO_ENVIRONMENT_SET_VARIABLES:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL:
    case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
    case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
    case RETRO_ENVIRONMENT_SET_MEMORY_MAPS:
    case RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL:
    case RETRO_ENVIRONMENT_SET_SUPPORT_ACHIEVEMENTS:
      return true;
  }
  return false;
}

void video_refresh(const void* data, unsigned w, unsigned h, size_t pitch) {
  if (getenv("PROBE_VIDEO_LOG") && g_frame < 3)
    fprintf(stderr, "video frame %llu data=%s %ux%u\n", (unsigned long long)g_frame, data ? "yes" : "NULL", w, h);
  g_width = w; g_height = h;
  g_video_hash = fnv(&w, sizeof w, fnv(&h, sizeof h));
  if (!data) return;  // dupe: keep last frame
  g_bpp = g_pixfmt == RETRO_PIXEL_FORMAT_XRGB8888 ? 4 : 2;
  g_last_frame.resize(size_t(w) * h * g_bpp);
  for (unsigned y = 0; y < h; y++)
    memcpy(&g_last_frame[size_t(y) * w * g_bpp], static_cast<const uint8_t*>(data) + y * pitch, size_t(w) * g_bpp);
  g_last_w = w; g_last_h = h;
  g_video_hash = fnv(g_last_frame.data(), g_last_frame.size(), g_video_hash);
}

size_t audio_batch(const int16_t* data, size_t frames) {
  g_audio_hash = fnv(data, frames * 4, g_audio_hash);
  g_audio_samples += frames;
  return frames;
}
void audio_sample(int16_t l, int16_t r) { int16_t s[2] = {l, r}; audio_batch(s, 1); }
void input_poll() {}
int16_t input_state(unsigned port, unsigned device, unsigned, unsigned id) {
  if (device != RETRO_DEVICE_JOYPAD) return 0;
  if (id == RETRO_DEVICE_ID_JOYPAD_MASK) {
    int16_t m = 0;
    for (unsigned i = 0; i < 16; i++) m |= scripted_input(port, i, g_frame) << i;
    return m;
  }
  return scripted_input(port, id, g_frame);
}

struct FrameRec { uint64_t video, audio; size_t samples; };

FrameRec step() {
  g_video_hash = 0; g_audio_hash = 0; g_audio_samples = 0;
  core.run();
  g_frame++;
  return {g_video_hash, g_audio_hash, g_audio_samples};
}

void write_ppm(const std::string& path) {
  FILE* f = fopen(path.c_str(), "wb");
  if (!f || g_last_frame.empty()) { if (f) fclose(f); return; }
  fprintf(f, "P6\n%u %u\n255\n", g_last_w, g_last_h);
  for (size_t i = 0; i < size_t(g_last_w) * g_last_h; i++) {
    uint8_t rgb[3];
    if (g_bpp == 4) {
      uint32_t p; memcpy(&p, &g_last_frame[i * 4], 4);
      rgb[0] = p >> 16; rgb[1] = p >> 8; rgb[2] = p;
    } else {
      uint16_t p; memcpy(&p, &g_last_frame[i * 2], 2);
      if (g_pixfmt == RETRO_PIXEL_FORMAT_RGB565) {
        rgb[0] = ((p >> 11) & 31) * 255 / 31; rgb[1] = ((p >> 5) & 63) * 255 / 63; rgb[2] = (p & 31) * 255 / 31;
      } else {
        rgb[0] = ((p >> 10) & 31) * 255 / 31; rgb[1] = ((p >> 5) & 31) * 255 / 31; rgb[2] = (p & 31) * 255 / 31;
      }
    }
    fwrite(rgb, 1, 3, f);
  }
  fclose(f);
}

double ms_since(std::chrono::steady_clock::time_point t) {
  return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t).count();
}

// Needs PROBE_AREAS-style area names: collected from a size pass of the debug core.
void print_area_diff(const char* label, const std::vector<uint8_t>& x, const std::vector<uint8_t>& y) {
  if (g_areas.empty()) {
    g_collect_areas = true;
    core.serialize_size();
    g_collect_areas = false;
  }
  // Area offsets come from the size pass; the write pass adds no headers (StateWriteAcb copies raw).
  for (auto& ar : g_areas) {
    size_t begin = ar.end - ar.len, n = 0;
    for (size_t i = begin; i < ar.end && i < x.size(); i++) n += x[i] != y[i];
    if (!n) continue;
    fprintf(stderr, "diff %s area %-32s off %8zu len %8zu differing %zu at", label, ar.name.c_str(), begin, ar.len, n);
    for (size_t i = begin, shown = 0; i < ar.end && i < x.size() && shown < 8; i++)
      if (x[i] != y[i]) { fprintf(stderr, " +%zu(%02x/%02x)", i - begin, x[i], y[i]); shown++; }
    fprintf(stderr, "\n");
  }
}

template <class T> bool sym(void* lib, const char* name, T& out) {
  out = reinterpret_cast<T>(dlsym(lib, name));
  if (!out) fprintf(stderr, "missing symbol %s\n", name);
  return out != nullptr;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 6) {
    fprintf(stderr, "usage: %s core.so rom.zip system_dir save_dir out_dir [warmup] [compare] [normal|runahead]\n", argv[0]);
    return 2;
  }
  const char* rom = argv[2];
  g_system_dir = argv[3];
  g_save_dir = argv[4];
  std::string out_dir = argv[5];
  uint64_t warmup = argc > 6 ? strtoull(argv[6], nullptr, 10) : 900;
  uint64_t compare = argc > 7 ? strtoull(argv[7], nullptr, 10) : 600;
  if (argc > 8 && !strcmp(argv[8], "runahead")) g_context = RETRO_SAVESTATE_CONTEXT_RUNAHEAD_SAME_INSTANCE;

  void* lib = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!lib) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 2; }
  bool ok = sym(lib, "retro_set_environment", core.set_environment) &&
            sym(lib, "retro_set_video_refresh", core.set_video_refresh) &&
            sym(lib, "retro_set_audio_sample", core.set_audio_sample) &&
            sym(lib, "retro_set_audio_sample_batch", core.set_audio_sample_batch) &&
            sym(lib, "retro_set_input_poll", core.set_input_poll) &&
            sym(lib, "retro_set_input_state", core.set_input_state) && sym(lib, "retro_init", core.init) &&
            sym(lib, "retro_deinit", core.deinit) && sym(lib, "retro_get_system_av_info", core.get_system_av_info) &&
            sym(lib, "retro_load_game", core.load_game) && sym(lib, "retro_run", core.run) &&
            sym(lib, "retro_serialize_size", core.serialize_size) && sym(lib, "retro_serialize", core.serialize) &&
            sym(lib, "retro_unserialize", core.unserialize);
  if (!ok) return 2;

  core.set_environment(environment);
  core.set_video_refresh(video_refresh);
  core.set_audio_sample(audio_sample);
  core.set_audio_sample_batch(audio_batch);
  core.set_input_poll(input_poll);
  core.set_input_state(input_state);
  core.init();

  retro_game_info gi{};
  gi.path = rom;
  if (!core.load_game(&gi)) {
    printf("{\"rom\":\"%s\",\"error\":\"load_game failed\"}\n", rom);
    return 2;
  }
  retro_system_av_info av{};
  core.get_system_av_info(&av);

  // PROBE_SEEK=<frames>: the way ReplayNES uses a core. One straight run from power-on records every
  // frame (video, audio, state hash) and a checkpoint every 300 frames; then checkpoints are loaded in
  // a scrambled order, each after unrelated history, and 300 frames are replayed and compared.
  if (const char* seek = getenv("PROBE_SEEK")) {
    const uint64_t total = strtoull(seek, nullptr, 10), interval = 300;
    size_t size = core.serialize_size();
    std::vector<FrameRec> rec;
    std::vector<uint64_t> state_hash;
    std::vector<std::vector<uint8_t>> checkpoints;
    std::vector<uint8_t> buf(size);
    // PROBE_SEEK_DUMP=<frame>: write that frame from the straight run and from its first replay.
    const char* dump = getenv("PROBE_SEEK_DUMP");
    uint64_t dump_frame = dump ? strtoull(dump, nullptr, 10) : UINT64_MAX;
    bool dumped_replay = false;
    for (uint64_t f = 0; f < total; f++) {
      if (f % interval == 0) { checkpoints.emplace_back(size); core.serialize(checkpoints.back().data(), size); }
      rec.push_back(step());
      core.serialize(buf.data(), size);
      state_hash.push_back(fnv(buf.data(), size));
      if (dump_frame == f) write_ppm(out_dir + "/seek_straight.ppm");
    }
    const uint64_t n = checkpoints.size();
    uint64_t loads = 0, bad_frames = 0, bad_states = 0, first_bad = UINT64_MAX;
    for (uint64_t k = 0; k < n; k++) {
      uint64_t c = (k * 7 + 3) % n;  // 7 is coprime with n unless n is a multiple of 7
      if (n % 7 == 0) c = (k * 11 + 3) % n;
      if (!core.unserialize(checkpoints[c].data(), size)) { bad_states++; continue; }
      loads++;
      g_frame = c * interval;
      for (uint64_t i = 0; i < interval && g_frame < total; i++) {
        uint64_t f = g_frame;
        FrameRec r = step();
        if (f == dump_frame && !dumped_replay) { write_ppm(out_dir + "/seek_replay.ppm"); dumped_replay = true; }
        core.serialize(buf.data(), size);
        bool ok = r.video == rec[f].video && r.audio == rec[f].audio && r.samples == rec[f].samples &&
                  fnv(buf.data(), size) == state_hash[f];
        if (!ok) {
          bad_frames++;
          if (first_bad == UINT64_MAX) first_bad = f;
          if (getenv("PROBE_SEEK_DETAIL"))
            fprintf(stderr, "seek bad: checkpoint %llu (order %llu) frame %llu video=%d audio=%d samples=%zu/%zu state=%d\n",
                    (unsigned long long)c, (unsigned long long)k, (unsigned long long)f, r.video != rec[f].video,
                    r.audio != rec[f].audio, r.samples, rec[f].samples, fnv(buf.data(), size) != state_hash[f]);
        }
      }
    }
    printf("{\"rom\":\"%s\",\"mode\":\"seek\",\"frames\":%llu,\"checkpoints\":%llu,\"loads\":%llu,"
           "\"bad_frames\":%llu,\"load_failures\":%llu,\"first_bad_frame\":%lld,\"deterministic\":%s}\n",
           rom, (unsigned long long)total, (unsigned long long)n, (unsigned long long)loads,
           (unsigned long long)bad_frames, (unsigned long long)bad_states,
           first_bad == UINT64_MAX ? -1LL : (long long)first_bad, bad_frames || bad_states ? "false" : "true");
    fflush(stdout);
    _Exit(bad_frames || bad_states ? 1 : 0);
  }

  // Power-on to the save point; hashes here identify the run for cross-process comparison.
  uint64_t boot_hash = 0;
  auto t_run = std::chrono::steady_clock::now();
  for (uint64_t i = 0; i < warmup; i++) {
    FrameRec r = step();
    boot_hash = fnv(&r, sizeof r, boot_hash);
  }
  double run_ms = ms_since(t_run) / double(warmup);
  write_ppm(out_dir + "/warmup.ppm");

  size_t size = core.serialize_size();
  std::vector<uint8_t> s0(size), s1(size), s2(size);
  auto t = std::chrono::steady_clock::now();
  bool saved = core.serialize(s0.data(), size);
  double save_ms = ms_since(t);
  uint64_t save_frame = g_frame;
  // PROBE_CANON=1: the first pass also starts from a load of the state just saved, so both passes
  // start from "loaded s0" and only the history before the load differs.
  if (getenv("PROBE_CANON")) core.unserialize(s0.data(), size);

  // PROBE_TRACE=1: keep the state after every frame of the first pass and report the first frame
  // whose state differs in the second pass (both passes serialize once per frame, symmetrically).
  bool trace = getenv("PROBE_TRACE") != nullptr;
  // Full states are kept only while they fit in 1 GiB; otherwise only per-frame hashes.
  bool keep_states = trace && size * compare <= (size_t(1) << 30);
  std::vector<std::vector<uint8_t>> states_a;
  std::vector<uint64_t> hashes_a;
  std::vector<uint8_t> trace_a, trace_b;
  uint64_t trace_first = UINT64_MAX;
  std::vector<FrameRec> a, b;
  for (uint64_t i = 0; i < compare; i++) {
    a.push_back(step());
    if (trace) {
      std::vector<uint8_t> sa(size);
      core.serialize(sa.data(), size);
      hashes_a.push_back(fnv(sa.data(), size));
      if (keep_states) states_a.push_back(std::move(sa));
    }
  }
  write_ppm(out_dir + "/compare_end.ppm");
  bool saved_end_a = core.serialize(s1.data(), size);

  t = std::chrono::steady_clock::now();
  bool loaded = core.unserialize(s0.data(), size);
  double load_ms = ms_since(t);
  g_frame = save_frame;
  // Round trip: a state saved right after loading must equal the state that was loaded.
  std::vector<uint8_t> rt(size);
  bool rt_ok = core.serialize(rt.data(), size) && rt == s0;
  for (uint64_t i = 0; i < compare; i++) {
    b.push_back(step());
    if (trace) {
      std::vector<uint8_t> sb(size);
      core.serialize(sb.data(), size);
      if (trace_first == UINT64_MAX && fnv(sb.data(), size) != hashes_a[i]) {
        trace_first = i;
        if (keep_states) { trace_a = states_a[i]; trace_b = sb; }
      }
    }
  }
  bool saved_end_b = core.serialize(s2.data(), size);

  uint64_t first_video = UINT64_MAX, first_audio = UINT64_MAX;
  uint64_t video_mismatch = 0, audio_mismatch = 0;
  for (uint64_t i = 0; i < compare; i++) {
    if (a[i].video != b[i].video) { video_mismatch++; if (first_video == UINT64_MAX) first_video = i; }
    if (a[i].audio != b[i].audio || a[i].samples != b[i].samples) {
      audio_mismatch++;
      if (first_audio == UINT64_MAX) first_audio = i;
    }
  }
  size_t state_diff = 0;
  for (size_t i = 0; i < size; i++) state_diff += s1[i] != s2[i];
  if (getenv("PROBE_DUMP_STATES")) {
    auto dump = [&](const char* name, const std::vector<uint8_t>& v) {
      if (FILE* f = fopen((out_dir + "/" + name).c_str(), "wb")) { fwrite(v.data(), 1, v.size(), f); fclose(f); }
    };
    dump("s0.state", s0); dump("s1_a_end.state", s1); dump("s2_b_end.state", s2); dump("rt.state", rt);
  }
  if (getenv("PROBE_AREAS")) print_area_diff("end", s1, s2);
  if (getenv("PROBE_AREAS") && !rt_ok) print_area_diff("roundtrip", s0, rt);
  if (trace_first != UINT64_MAX) {
    fprintf(stderr, "trace: state first differs after compare frame %llu\n", (unsigned long long)trace_first);
    if (!trace_a.empty()) print_area_diff("first", trace_a, trace_b);
  } else if (trace) {
    fprintf(stderr, "trace: states equal on every frame\n");
  }
  bool det = saved && loaded && saved_end_a && saved_end_b && video_mismatch == 0 && audio_mismatch == 0 && state_diff == 0;

  double total_samples = 0;
  for (auto& r : a) total_samples += r.samples;
  printf("{\"rom\":\"%s\",\"context\":\"%s\",\"fps\":%.6f,\"sample_rate\":%.1f,\"base\":\"%ux%u\",\"max\":\"%ux%u\","
         "\"aspect\":%.4f,\"rotation\":%u,\"pixfmt\":%d,\"last\":\"%ux%u\",\"state_bytes\":%zu,\"save_ms\":%.3f,"
         "\"load_ms\":%.3f,\"frame_ms\":%.3f,\"samples_per_frame\":%.2f,\"boot_hash\":\"%016llx\","
         "\"roundtrip_equal\":%s,\"video_mismatch\":%llu,\"audio_mismatch\":%llu,\"first_video_mismatch\":%lld,"
         "\"first_audio_mismatch\":%lld,\"end_state_diff_bytes\":%zu,\"deterministic\":%s}\n",
         rom, g_context == RETRO_SAVESTATE_CONTEXT_NORMAL ? "normal" : "runahead", av.timing.fps,
         av.timing.sample_rate, av.geometry.base_width, av.geometry.base_height, av.geometry.max_width,
         av.geometry.max_height, av.geometry.aspect_ratio, g_rotation, int(g_pixfmt), g_last_w, g_last_h, size,
         save_ms, load_ms, run_ms, total_samples / double(compare), (unsigned long long)boot_hash,
         rt_ok ? "true" : "false", (unsigned long long)video_mismatch, (unsigned long long)audio_mismatch,
         first_video == UINT64_MAX ? -1LL : (long long)first_video,
         first_audio == UINT64_MAX ? -1LL : (long long)first_audio, state_diff, det ? "true" : "false");
  // Exit without retro_unload_game: unloading writes NVRAM into save_dir, which the driver script inspects
  // separately; here the process just ends.
  fflush(stdout);
  _Exit(det ? 0 : 1);
}
