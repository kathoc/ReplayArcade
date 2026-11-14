# The Windows test VM (scripts/winvm/winvm.sh): OpenSSH Server with key login from the Mac. Run once in the
# guest, as administrator, with the Mac's public key (~/.ssh/winvm_ed25519.pub) in winvm_ed25519.pub next to
# this script (the Mac's Desktop is the guest's Desktop through Parallels' shared profile):
#   right-click ssh-setup.cmd > Run as administrator
$ErrorActionPreference = 'Stop'
Start-Transcript -Path "$env:PUBLIC\replaynes-ssh-setup.log" -Force
$key = (Get-Content -Raw (Join-Path $PSScriptRoot 'winvm_ed25519.pub')).Trim()
$cap = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
if ($cap.State -ne 'Installed') { Add-WindowsCapability -Online -Name $cap.Name }
Set-Service sshd -StartupType Automatic
Start-Service sshd
if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
}
$f = "$env:ProgramData\ssh\administrators_authorized_keys"   # an administrator's keys live here, not in ~/.ssh
Set-Content -Path $f -Value $key -Encoding ascii
icacls $f /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F'
$u = Join-Path $env:USERPROFILE '.ssh'
New-Item -ItemType Directory -Force $u | Out-Null
Set-Content -Path (Join-Path $u 'authorized_keys') -Value $key -Encoding ascii
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PropertyType String -Force | Out-Null
Restart-Service sshd
Write-Host "done: sshd $((Get-Service sshd).Status), user $env:USERNAME"
Stop-Transcript
