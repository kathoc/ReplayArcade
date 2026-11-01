// How a game responds to one analog axis: from the same frame of a started game, the axis is held at
// v for a few frames and the machine state hashed. Prints, per direction, the smallest |v| the game
// tells from the centre (the dead zone end to end: frontend value -> FinalBurn Neo's libretro input ->
// the driver) and how many different states a sweep of 512 values gives (the steps the game sees).
//   analog_response <rom.zip> <axis id, e.g. p1.axis.x> [start frame] [frames held] [stick]
// "stick": the sweep is a controller stick's position, shaped as the desktop frontend shapes it with the
// layout's hints for the axis (stick_shape.h): the first response is then how far the stick is pushed.
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <set>
#include <string>

#include "core/FbneoCore.h"
#include "replaynes/replaynes.h"
#include "stick_shape.h"

namespace {

// "byte" / "bit" of the layout entry with this id (rn_session_input_layout_json); -1 when absent.
bool field(const std::string& json, const std::string& id, const char* key, int& out) {
  const size_t at = json.find("\"id\":\"" + id + "\"");
  if (at == std::string::npos) return false;
  const size_t end = json.find('}', at);
  const size_t k = json.find(std::string("\"") + key + "\":", at);
  if (k == std::string::npos || k > end) return false;
  out = std::atoi(json.c_str() + k + std::strlen(key) + 3);
  return true;
}

void setBit(rn_input_record& r, int byte, int bit) { r.bytes[byte] |= uint8_t(1u << bit); }

void setAxis(rn_input_record& r, int byte, float v) {
  const int16_t a = int16_t(std::lround(std::max(-1.f, std::min(1.f, v)) * 32767.f));
  r.bytes[byte] = uint8_t(uint16_t(a) & 0xFF);
  r.bytes[byte + 1] = uint8_t(uint16_t(a) >> 8);
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 3) {
    std::fprintf(stderr, "usage: %s <rom.zip> <axis id> [start frame] [frames held]\n", argv[0]);
    return 2;
  }
  const std::string axis = argv[2];
  const uint64_t start = argc > 3 ? std::strtoull(argv[3], nullptr, 10) : 1500;
  const int held = argc > 4 ? std::atoi(argv[4]) : 4;
  const bool stick = argc > 5 && std::strcmp(argv[5], "stick") == 0;
  rac::registerFbneoCore();
  rn_session_options opt;
  rn_session_options_init(&opt);
  opt.core = RN_CORE_EXTERNAL;
  rn_session* s = nullptr;
  if (rn_session_new(argv[1], nullptr, &opt, &s) != RN_OK) {
    std::fprintf(stderr, "%s: %s\n", argv[1], rn_last_error());
    return 1;
  }
  char* lj = rn_session_input_layout_json(s);
  const std::string layout = lj ? lj : "";
  rn_string_free(lj);
  int axisByte = -1, coinByte = -1, coinBit = -1, startByte = -1, startBit = -1;
  if (!field(layout, axis, "byte", axisByte)) {
    std::fprintf(stderr, "%s: no axis %s\n", argv[1], axis.c_str());
    return 1;
  }
  rnl::StickShape shape;  // the axis's hints, as the frontend reads them
  {
    const size_t at = layout.find("\"id\":\"" + axis + "\"");
    const std::string entry = layout.substr(at, layout.find('}', at) - at);
    const size_t dz = entry.find("\"deadzone\":");
    shape.deadzone = dz == std::string::npos ? 0.f : float(std::atof(entry.c_str() + dz + 11));
    shape.square = entry.find("\"square\":true") != std::string::npos;
    shape.active = shape.square || shape.deadzone > 0;
  }
  field(layout, "p1.coin", "byte", coinByte);
  field(layout, "p1.coin", "bit", coinBit);
  field(layout, "p1.start", "byte", startByte);
  field(layout, "p1.start", "bit", startBit);
  rn_set_mode(s, RN_MODE_RECORD);
  // A coin at 10 s, start at 12 s (boards boot for a while), then nothing until `start`.
  for (uint64_t f = 0; f < start; ++f) {
    rn_input_record r{};
    if (coinByte >= 0 && f >= 600 && f < 606) setBit(r, coinByte, coinBit);
    if (startByte >= 0 && f >= 720 && f < 726) setBit(r, startByte, startBit);
    if (rn_step_record(s, &r, nullptr) != RN_OK) {
      std::fprintf(stderr, "step %llu: %s\n", (unsigned long long)f, rn_last_error());
      return 1;
    }
  }
  auto stateAt = [&](float v) {
    rn_seek(s, start);
    for (int i = 0; i < held; ++i) {
      rn_input_record r{};
      setAxis(r, axisByte, stick ? shapeStick(v, 0.f, shape).first : v);
      rn_step_record(s, &r, nullptr);
    }
    return rn_state_hash(s);
  };
  const uint64_t centre = stateAt(0);
  std::printf("%s %s (from frame %llu, %d frames held%s)\n", argv[1], axis.c_str(), (unsigned long long)start, held,
              stick ? ", a controller stick's position through the frontend's shape" : "");
  for (int sign : {1, -1}) {
    float first = -1;
    std::set<uint64_t> states;
    for (int i = 1; i <= 512; ++i) {
      const float v = sign * float(i) / 512.f;
      const uint64_t h = stateAt(v);
      states.insert(h);
      if (first < 0 && h != centre) first = std::fabs(v);
    }
    std::printf("  %s: first response at |v| = %.3f, %zu different states over 512 values\n", sign > 0 ? "+" : "-", first,
                states.size());
  }
  rn_session_close(s);
  return 0;
}
