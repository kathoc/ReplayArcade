// ReplayNES for Android: the shared desktop frontend (apps/desktop/src/app.h) with the Vulkan presenter
// of apps/linux (vk_renderer.h), full screen. SDLActivity calls SDL_main in libmain.so.
// SPDX-License-Identifier: GPL-2.0-or-later
#include <jni.h>
#include "replaynes/product.h"
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>

#include <android/log.h>
#include <sys/stat.h>
#include <sys/system_properties.h>
#include <sys/time.h>
#include <unistd.h>

#include <chrono>
#include <cstdio>
#include <cstring>
#include <functional>
#include <ctime>
#include <memory>
#include <string>
#include <thread>

#include "app.h"
#include "vk_renderer.h"

#ifdef RN_PRODUCT_HAS_STARTUP
extern "C" void rn_product_startup(void);
#endif

namespace {
std::string property(const char* name) {
  char v[PROP_VALUE_MAX] = {0};
  __system_property_get(name, v);
  return v;
}

// The log a user can send from Settings (docs/design/ANDROID.md, "Logs"): <external files>/Logs/<product>.log,
// the previous one kept as <product>.1.log once it passes 1 MB. Opened before anything is logged.
std::FILE* openLogFile(std::string* path) {
  const char* ext = SDL_GetAndroidExternalStoragePath();
  if (!ext) return nullptr;
  const std::string dir = std::string(ext) + "/Logs";
  mkdir(dir.c_str(), 0775);
  *path = dir + "/" RN_PRODUCT_NAME ".log";
  struct stat st{};
  if (stat(path->c_str(), &st) == 0 && st.st_size > (1 << 20))
    rename(path->c_str(), (dir + "/" RN_PRODUCT_NAME ".1.log").c_str());
  return std::fopen(path->c_str(), "a");
}

// stdout / stderr into logcat (tag = the product) and the log file, each line with the local time: the app
// logs with fprintf(stderr), as on the desktop, and Android drops both streams. `adb logcat -s ReplayArcade`.
void logToLogcat() {
  static int fds[2];
  if (pipe(fds) != 0) return;
  std::string path;
  std::FILE* file = openLogFile(&path);
  if (file) {
    setvbuf(file, nullptr, _IOLBF, 0);
    std::fprintf(file, "\n==== %s %s on %s %s (%s), Android %s (SDK %s), %s\n", RN_PRODUCT_NAME, RNL_APP_VERSION,
                 property("ro.product.manufacturer").c_str(), property("ro.product.model").c_str(),
                 property("ro.product.device").c_str(), property("ro.build.version.release").c_str(),
                 property("ro.build.version.sdk").c_str(), property("ro.soc.model").c_str());
  }
  dup2(fds[1], STDOUT_FILENO);
  dup2(fds[1], STDERR_FILENO);
  setvbuf(stdout, nullptr, _IOLBF, 0);
  setvbuf(stderr, nullptr, _IONBF, 0);
  std::thread([file] {
    std::string line;
    char buf[512];
    for (ssize_t n; (n = read(fds[0], buf, sizeof buf)) > 0;)
      for (ssize_t i = 0; i < n; ++i) {
        if (buf[i] != '\n') { line += buf[i]; continue; }
        __android_log_write(ANDROID_LOG_INFO, RN_PRODUCT_NAME, line.c_str());
        if (file) {
          timeval tv{};
          gettimeofday(&tv, nullptr);
          std::tm tm{};
          localtime_r(&tv.tv_sec, &tm);
          char stamp[32];
          std::strftime(stamp, sizeof stamp, "%m-%d %H:%M:%S", &tm);
          std::fprintf(file, "%s.%03d %s\n", stamp, int(tv.tv_usec / 1000), line.c_str());
        }
        line.clear();
      }
  }).detach();
}
}  // namespace

// A touch control's press (TouchControls): MainActivity.haptic() on the UI thread (the view's haptic feedback).
void androidHaptic() {
  auto* env = static_cast<JNIEnv*>(SDL_GetAndroidJNIEnv());
  auto activity = static_cast<jobject>(SDL_GetAndroidActivity());
  if (!env || !activity) return;
  jclass cls = env->GetObjectClass(activity);
  static jmethodID haptic = env->GetMethodID(cls, "haptic", "()V");
  if (haptic) env->CallVoidMethod(activity, haptic);
  if (env->ExceptionCheck()) env->ExceptionClear();
  env->DeleteLocalRef(cls);
  env->DeleteLocalRef(activity);
}

// MainActivity's surface callbacks (docs/design/ANDROID.md, "Black screen"): before the window's surface goes,
// the renderer stops drawing to it; once a new one is there, it draws again.
extern "C" JNIEXPORT void JNICALL Java_io_github_replaynes_android_MainActivity_nativeSurfaceGoing(JNIEnv*, jclass) {
  rnl::androidSurfaceGoing();
}
extern "C" JNIEXPORT void JNICALL Java_io_github_replaynes_android_MainActivity_nativeSurfaceBack(JNIEnv*, jclass) {
  rnl::androidSurfaceBack();
}

// The library's picture process (PictureService, android:process=":pictures"; docs/plans/2026-11-22-library-pictures-robust.md):
// the same native code makes one ROM's picture there, so a core crash ends that process, not the app.
extern "C" JNIEXPORT jboolean JNICALL Java_io_github_replaynes_android_PictureService_nativeMakeRomPicture(JNIEnv* env, jclass,
                                                                                                     jstring jrom, jstring jout) {
  static bool started = false;
  if (!started) {
#ifdef RN_PRODUCT_HAS_STARTUP
    rn_product_startup();
#endif
    started = true;
  }
  const char* r = env->GetStringUTFChars(jrom, nullptr);
  const char* o = env->GetStringUTFChars(jout, nullptr);
  std::string rom = r, out = o, reason;
  env->ReleaseStringUTFChars(jrom, r);
  env->ReleaseStringUTFChars(jout, o);
  const bool made = rnl::LibraryThumbs::makeRomPictureFile(rom, out, &reason);
  if (!made) __android_log_print(ANDROID_LOG_INFO, "ReplayNES", "pictures: %s: %s", rom.c_str(), reason.c_str());
  return made ? JNI_TRUE : JNI_FALSE;
}

namespace {
// MainActivity's picture-process methods (PictureClient), from the picture worker thread.
int activityPictureCall(const char* method, const char* sig, const std::string& a = "", const std::string& b = "") {
  auto* env = static_cast<JNIEnv*>(SDL_GetAndroidJNIEnv());
  auto activity = static_cast<jobject>(SDL_GetAndroidActivity());
  if (!env || !activity) return -1;
  int result = -1;
  jclass cls = env->GetObjectClass(activity);
  jmethodID m = env->GetMethodID(cls, method, sig);
  if (m) {
    if (std::strcmp(sig, "(Ljava/lang/String;Ljava/lang/String;)Z") == 0) {
      jstring ja = env->NewStringUTF(a.c_str()), jb = env->NewStringUTF(b.c_str());
      result = env->CallBooleanMethod(activity, m, ja, jb) ? 1 : 0;
      env->DeleteLocalRef(ja);
      env->DeleteLocalRef(jb);
    } else if (std::strcmp(sig, "()I") == 0) {
      result = env->CallIntMethod(activity, m);
    } else {
      env->CallVoidMethod(activity, m);
      result = 0;
    }
  }
  if (env->ExceptionCheck()) {
    env->ExceptionClear();
    result = -1;
  }
  env->DeleteLocalRef(cls);
  env->DeleteLocalRef(activity);
  return result;
}

rnl::LibraryThumbs::PictureProcessRunner androidPictureProcess() {
  return [](const std::string& rom, const std::string& out, const std::function<bool()>& cancelled, std::string* reason) {
    using P = rnl::LibraryThumbs::PictureProcess;
    if (activityPictureCall("startRomPicture", "(Ljava/lang/String;Ljava/lang/String;)Z", rom, out) != 1) return P::unavailable;
    const auto start = std::chrono::steady_clock::now();
    for (;;) {
      std::this_thread::sleep_for(std::chrono::milliseconds(50));
      const int st = activityPictureCall("romPictureState", "()I");  // PictureClient: 0 running 1 made 2 failed 3 crashed
      if (st == 1) return P::made;
      if (st == 2) { *reason = "no picture"; return P::failed; }
      if (st == 3) { *reason = "the picture process ended"; return P::crashed; }
      if (st < 0) { *reason = "the picture process cannot be reached"; return P::crashed; }
      if (cancelled()) { activityPictureCall("cancelRomPicture", "()V"); return P::cancelled; }
      if (std::chrono::steady_clock::now() - start > std::chrono::minutes(2)) {
        activityPictureCall("cancelRomPicture", "()V");
        *reason = "the picture process ran longer than 2 minutes";
        return P::crashed;
      }
    }
  };
}
}  // namespace

int main(int argc, char** argv) {
  using namespace rnl;
  logToLogcat();
#ifdef RN_PRODUCT_HAS_STARTUP
  rn_product_startup();
#endif
  PlatformHooks platform;
  platform.version = RNL_APP_VERSION;
  platform.executable = RN_PRODUCT_EXECUTABLE;
  platform.windowFlags = SDL_WINDOW_VULKAN | SDL_WINDOW_FULLSCREEN;
  platform.makeRenderer = [](const AppOptions&) { return std::unique_ptr<Renderer>(new VkRenderer()); };
  platform.sessionMode = [] { return std::string("android"); };
  platform.touchControls = true;  // docs/design/TOUCH_ANDROID.md
  platform.haptic = androidHaptic;
  platform.romPictureProcess = androidPictureProcess();
  AppOptions opt;
  if (!parseAppArgs(argc, argv, platform, &opt)) return 2;
  return runApp(opt, platform);
}
