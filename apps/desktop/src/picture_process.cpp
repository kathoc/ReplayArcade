// The library's picture process (docs/plans/2026-11-22-library-pictures-robust.md): a ROM's card picture is made
// by the app's own executable started with --rom-picture, so a core that crashes or hangs on an unknown ROM ends
// that process, not the app. Linux / Steam Deck and Windows; Android has its own (a service process).
// SPDX-License-Identifier: GPL-2.0-or-later
#include "picture_process.h"

#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>

#ifdef _WIN32
#include <windows.h>
#elif !defined(__ANDROID__)
#include <csignal>
#include <spawn.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>
#include <climits>
extern char** environ;
#endif

namespace rnl {

namespace {
// A picture runs a few thousand frames at most (RN_PRODUCT_LIBRARY_PICTURE_FRAME x 6): seconds. A process still
// running after this hangs.
constexpr auto kPictureTimeLimit = std::chrono::minutes(2);
constexpr int kExitNoPicture = 3;  // the process ran and made no picture (the engine refused the ROM ...)
}  // namespace

bool runPictureProcessArgs(int argc, char** argv, int* code) {
  if (argc != 4 || std::strcmp(argv[1], "--rom-picture") != 0) return false;
#if !defined(_WIN32) && !defined(__ANDROID__)
  setpriority(PRIO_PROCESS, 0, 19);  // below the app and its game
#elif defined(_WIN32)
  SetPriorityClass(GetCurrentProcess(), BELOW_NORMAL_PRIORITY_CLASS);
#endif
  std::string reason;
  const bool made = LibraryThumbs::makeRomPictureFile(argv[2], argv[3], &reason);
  if (!made) std::fprintf(stderr, "rom picture: %s: %s\n", argv[2], reason.c_str());
  *code = made ? 0 : kExitNoPicture;
  return true;
}

#ifdef _WIN32
namespace {
std::wstring wide(const std::string& s) {
  int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
  std::wstring w(size_t(n > 0 ? n - 1 : 0), L'\0');
  if (n > 1) MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, w.data(), n);
  return w;
}
// One argument for CreateProcess's command line (quotes, backslashes before a quote doubled).
std::wstring quoted(const std::wstring& a) {
  std::wstring out = L"\"";
  size_t slashes = 0;
  for (wchar_t c : a) {
    if (c == L'\\') { ++slashes; continue; }
    if (c == L'"') out.append(slashes * 2 + 1, L'\\');
    else out.append(slashes, L'\\');
    slashes = 0;
    out += c;
  }
  out.append(slashes * 2, L'\\');
  return out + L"\"";
}
}  // namespace

LibraryThumbs::PictureProcessRunner selfPictureProcess() {
  return [](const std::string& rom, const std::string& out, const std::function<bool()>& cancelled,
            std::string* reason) {
    using P = LibraryThumbs::PictureProcess;
    wchar_t exe[32768];
    DWORD n = GetModuleFileNameW(nullptr, exe, DWORD(sizeof exe / sizeof exe[0]));
    if (n == 0 || n >= sizeof exe / sizeof exe[0]) return P::unavailable;
    std::wstring cmd = quoted(exe) + L" --rom-picture " + quoted(wide(rom)) + L" " + quoted(wide(out));
    STARTUPINFOW si{};
    si.cb = sizeof si;
    PROCESS_INFORMATION pi{};
    if (!CreateProcessW(exe, cmd.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW | BELOW_NORMAL_PRIORITY_CLASS,
                        nullptr, nullptr, &si, &pi))
      return P::unavailable;
    CloseHandle(pi.hThread);
    const auto start = std::chrono::steady_clock::now();
    P result = P::crashed;
    for (;;) {
      if (WaitForSingleObject(pi.hProcess, 50) == WAIT_OBJECT_0) {
        DWORD code = 0;
        GetExitCodeProcess(pi.hProcess, &code);
        if (code == 0) result = P::made;
        else if (code == DWORD(kExitNoPicture)) { result = P::failed; *reason = "no picture"; }
        else { result = P::crashed; *reason = "the picture process ended with code " + std::to_string(code); }
        break;
      }
      if (cancelled()) { TerminateProcess(pi.hProcess, 1); WaitForSingleObject(pi.hProcess, INFINITE); result = P::cancelled; break; }
      if (std::chrono::steady_clock::now() - start > kPictureTimeLimit) {
        TerminateProcess(pi.hProcess, 1);
        WaitForSingleObject(pi.hProcess, INFINITE);
        *reason = "the picture process ran longer than 2 minutes";
        result = P::crashed;
        break;
      }
    }
    CloseHandle(pi.hProcess);
    return result;
  };
}
#elif !defined(__ANDROID__)
LibraryThumbs::PictureProcessRunner selfPictureProcess() {
  return [](const std::string& rom, const std::string& out, const std::function<bool()>& cancelled,
            std::string* reason) {
    using P = LibraryThumbs::PictureProcess;
    char exe[PATH_MAX];
    const ssize_t n = readlink("/proc/self/exe", exe, sizeof exe - 1);
    if (n <= 0) return P::unavailable;
    exe[n] = '\0';
    std::string a1 = "--rom-picture", a2 = rom, a3 = out;
    char* args[] = {exe, a1.data(), a2.data(), a3.data(), nullptr};
    pid_t pid = 0;
    if (posix_spawn(&pid, exe, nullptr, nullptr, args, environ) != 0) return P::unavailable;
    const auto start = std::chrono::steady_clock::now();
    for (;;) {
      int status = 0;
      const pid_t r = waitpid(pid, &status, WNOHANG);
      if (r == pid) {
        if (WIFEXITED(status) && WEXITSTATUS(status) == 0) return P::made;
        if (WIFEXITED(status) && WEXITSTATUS(status) == kExitNoPicture) { *reason = "no picture"; return P::failed; }
        *reason = WIFSIGNALED(status) ? "the picture process ended by signal " + std::to_string(WTERMSIG(status))
                                      : "the picture process ended with code " + std::to_string(WEXITSTATUS(status));
        return P::crashed;
      }
      if (r < 0) { *reason = "the picture process was lost"; return P::crashed; }
      if (cancelled()) { kill(pid, SIGKILL); waitpid(pid, &status, 0); return P::cancelled; }
      if (std::chrono::steady_clock::now() - start > kPictureTimeLimit) {
        kill(pid, SIGKILL);
        waitpid(pid, &status, 0);
        *reason = "the picture process ran longer than 2 minutes";
        return P::crashed;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
  };
}
#endif

}  // namespace rnl
