#!/usr/bin/env bash
# The Windows test VM on macsrv (Parallels "Windows 11", ARM64, Parallels Display Adapter = D3D11 on the Mac's GPU),
# driven over ssh. Parallels on macsrv is not Pro/Business: `prlctl exec` / `prlctl resume` are refused, so the
# guest runs OpenSSH Server (key login, set up once by scripts/winvm/ssh-setup.ps1) and GUI programs are started
# in the logged-in desktop session through a scheduled task (an ssh session has no desktop).
#
#   scripts/winvm/winvm.sh ps '<PowerShell>'           run PowerShell in the guest (ssh session, no desktop)
#   scripts/winvm/winvm.sh put <local> <guest path>    copy a file into the guest
#   scripts/winvm/winvm.sh get <guest path> <local>    copy a file out of the guest
#   scripts/winvm/winvm.sh app <zip>                   unpack a ReplayNES / ReplayArcade Windows zip to C:\rn-test\app
#   scripts/winvm/winvm.sh gui <seconds> <exe> [args]  start <exe> on the guest's desktop, wait until it exits
#                                                      (at most <seconds>, then it is stopped); prints its exit code
#   scripts/winvm/winvm.sh shot <local.png>            the guest's screen as the Mac shows it (the VM window)
#
# Env: WINVM_HOST (default 10.211.55.3), WINVM_USER (default: the Mac user), WINVM_KEY (~/.ssh/winvm_ed25519).
# The VM must be running (open "~/Parallels/Windows 11.pvm" resumes it); the Mac's screen must be unlocked for shot.
set -euo pipefail
HOST="${WINVM_HOST:-10.211.55.3}"
USER_="${WINVM_USER:-$USER}"
KEY="${WINVM_KEY:-$HOME/.ssh/winvm_ed25519}"
SSH=(ssh -i "$KEY" -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$USER_@$HOST")
SCP=(scp -q -i "$KEY" -o ConnectTimeout=10 -o BatchMode=yes)

ps_run() { "${SSH[@]}" "$1"; }
ps_file() {  # <local .ps1>: copied and run (no quoting of the script through ssh)
  "${SCP[@]}" "$1" "$USER_@$HOST:C:/rn-test/.winvm-cmd.ps1"
  "${SSH[@]}" 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\rn-test\.winvm-cmd.ps1'
}

cmd="${1:-}"; shift || true
case "$cmd" in
  ps) ps_run "$1" ;;
  put) ps_run "New-Item -ItemType Directory -Force (Split-Path -Parent '$2') | Out-Null"; "${SCP[@]}" "$1" "$USER_@$HOST:$(printf '%s' "$2" | tr '\\' '/')" ;;
  get) "${SCP[@]}" "$USER_@$HOST:$(printf '%s' "$1" | tr '\\' '/')" "$2" ;;
  app)
    ps_run "New-Item -ItemType Directory -Force C:\\rn-test | Out-Null"
    "${SCP[@]}" "$1" "$USER_@$HOST:C:/rn-test/app.zip"
    ps_run "Get-Process ReplayNES,ReplayArcade -ErrorAction SilentlyContinue | Stop-Process -Force; Remove-Item -Recurse -Force C:\\rn-test\\app -ErrorAction SilentlyContinue; Expand-Archive -Force C:\\rn-test\\app.zip C:\\rn-test\\app-x; \$d = Get-ChildItem C:\\rn-test\\app-x | Select-Object -First 1; Move-Item \$d.FullName C:\\rn-test\\app; Remove-Item -Recurse -Force C:\\rn-test\\app-x; Get-ChildItem C:\\rn-test\\app | Select-Object -ExpandProperty Name"
    ;;
  gui)
    secs="$1"; exe="$2"; shift 2
    args=""
    for a in "$@"; do args+=" \"${a//\"/\\\"}\""; done
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    # A .cmd holds the command line (quotes, semicolons and backslashes stay as written); the task runs it in the
    # interactive session of the logged-in user and the script waits for the program to end.
    printf '@echo off\r\n"%s"%s\r\necho %%ERRORLEVEL%% > C:\\rn-test\\.winvm-exit.txt\r\n' "$exe" "$args" > "$tmp/run.cmd"
    cat > "$tmp/start.ps1" <<EOF
\$ErrorActionPreference = 'Stop'
Remove-Item C:\\rn-test\\.winvm-exit.txt -ErrorAction SilentlyContinue
\$a = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c C:\\rn-test\\.winvm-run.cmd'
\$p = New-ScheduledTaskPrincipal -UserId '$USER_' -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName 'winvm-gui' -Action \$a -Principal \$p -Force | Out-Null
Start-ScheduledTask -TaskName 'winvm-gui'
\$deadline = (Get-Date).AddSeconds($secs)
Start-Sleep -Seconds 2
while ((Get-Date) -lt \$deadline -and -not (Test-Path C:\\rn-test\\.winvm-exit.txt)) { Start-Sleep -Milliseconds 500 }
if (Test-Path C:\\rn-test\\.winvm-exit.txt) { "exit " + (Get-Content C:\\rn-test\\.winvm-exit.txt).Trim() }
else { Stop-ScheduledTask -TaskName 'winvm-gui'; Get-Process (Split-Path -LeafBase '$exe') -ErrorAction SilentlyContinue | Stop-Process -Force; "timeout after $secs s: stopped" }
Unregister-ScheduledTask -TaskName 'winvm-gui' -Confirm:\$false
EOF
    "${SCP[@]}" "$tmp/run.cmd" "$USER_@$HOST:C:/rn-test/.winvm-run.cmd"
    ps_file "$tmp/start.ps1"
    ;;
  shot)
    # The VM window's bounds from the Mac; the capture is of the Mac's screen, so the window must be visible.
    osascript -e 'tell application "Parallels Desktop" to activate' >/dev/null 2>&1 || true
    sleep 1
    b="$(osascript -e 'tell application "System Events" to tell (first process whose name is "prl_client_app") to get {position, size} of (first window whose name contains "Windows 11")' | tr -d ' ')"
    IFS=, read -r x y w h <<< "$b"
    screencapture -x -R "$x,$y,$w,$h" "$1"
    echo "$1 (${w}x${h} at $x,$y)"
    ;;
  *) sed -n '2,20p' "$0"; exit 2 ;;
esac
