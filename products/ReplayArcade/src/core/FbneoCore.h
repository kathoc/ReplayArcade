// FinalBurn Neo (libretro, statically linked, patched for determinism: patches/fbneo) behind
// ReplayNES's ICore, registered as the product's external core (RN_CORE_EXTERNAL).
//
// FBNeo keeps its machine in process-wide globals, so there is one real machine. Every FbneoCore
// instance is a virtual machine: it owns its machine state while another instance uses the real
// one, and takes the real one by saving the current owner's state and loading its own (both are
// exact: docs/LOG.md, Phase 0). All calls lock one mutex, so the session's core and the offline
// renderer's core may run on different threads.
#pragma once
#include <map>
#include <string>

namespace rac {

struct FbneoSettings {
  // Core options passed to FBNeo (the values ReplayArcade fixes are applied on top: hiscore
  // injection off, no diagnostic-input hold, 48 kHz, 32-bit colour). DIP switches go here too:
  // "fbneo-dipswitch-<set>-<name>" = value.
  std::map<std::string, std::string> options;
};

// Registers the core with ReplayNES's engine (rn::registerExternalCore). Call once at start-up.
void registerFbneoCore(const FbneoSettings& settings = {});

}  // namespace rac
