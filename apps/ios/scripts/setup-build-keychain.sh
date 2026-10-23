#!/bin/bash
# One-time setup on the Mac (run it in the Mac's Terminal, not over ssh): a build-only keychain
# holding just this team's "Apple Development" identity, so build-device.sh can sign over ssh
# (the login keychain is locked in an ssh session: errSecInternalComponent).
#
#   apps/ios/scripts/setup-build-keychain.sh            # team from Config/Signing.local.xcconfig
#   apps/ios/scripts/setup-build-keychain.sh --remove   # delete the build keychain and its password
#
# Creates ~/Library/Keychains/replaynes-build.keychain-db (no auto-lock) with a random password
# stored in ~/.config/replaynes/build-keychain.pass (mode 600), copies the identity from the login
# keychain (macOS asks for the login password / "Allow" once), lets codesign use its key without
# a prompt (set-key-partition-list), and adds the keychain to the user's search list.
# Trade-off: anyone who can read the password file can sign apps as this developer team.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
KC="$HOME/Library/Keychains/replaynes-build.keychain-db"
PASSFILE="$HOME/.config/replaynes/build-keychain.pass"
LOGIN="$HOME/Library/Keychains/login.keychain-db"

searchlist() { security list-keychains -d user | sed 's/^ *"//; s/"$//'; }

if [ "${1:-}" = "--remove" ]; then
  keep=(); while IFS= read -r k; do [ "$k" = "$KC" ] || keep+=("$k"); done < <(searchlist)
  security list-keychains -d user -s "${keep[@]}"
  [ -f "$KC" ] && security delete-keychain "$KC"
  rm -f "$PASSFILE"
  echo "removed the build keychain and its password"
  exit 0
fi

[ -z "${SSH_CONNECTION:-}" ] || { echo "run this in the Mac's Terminal (it needs the login keychain's dialogs)"; exit 1; }
TEAM="$(sed -n 's/^ *DEVELOPMENT_TEAM *= *\([A-Z0-9]*\).*/\1/p' "$HERE/Config/Signing.local.xcconfig" 2>/dev/null | head -1)"
[ -n "$TEAM" ] || { echo "no DEVELOPMENT_TEAM in Config/Signing.local.xcconfig (run build-device.sh --team ... once)"; exit 1; }

# The login keychain's Apple Development identities of this team (OU = team id).
IDS=()
while read -r sha; do
  pem="$(security find-certificate -Z -a -p "$LOGIN" | awk -v s="$sha" '/^SHA-1 hash:/{keep=($3==s)} keep')"
  ou="$(printf '%s\n' "$pem" | sed -n '/BEGIN CERT/,/END CERT/p' | openssl x509 -noout -subject -nameopt multiline 2>/dev/null | sed -n 's/^ *organizationalUnitName *= *//p')"
  [ "$ou" = "$TEAM" ] && IDS+=("$sha")
done < <(security find-identity -v -p codesigning "$LOGIN" | sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\) "Apple Development: .*/\1/p')
[ "${#IDS[@]}" -gt 0 ] || { echo "no valid Apple Development identity of team $TEAM in the login keychain"; exit 1; }
echo "==> team $TEAM: ${#IDS[@]} identity(ies): ${IDS[*]}"

umask 077
mkdir -p "$(dirname "$PASSFILE")"
[ -f "$PASSFILE" ] || openssl rand -base64 24 > "$PASSFILE"
chmod 600 "$PASSFILE"
PASS="$(cat "$PASSFILE")"
[ -f "$KC" ] || security create-keychain -p "$PASS" "$KC"
security set-keychain-settings "$KC"   # no timeout, no lock on sleep
security unlock-keychain -p "$PASS" "$KC"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
P12PASS="$(openssl rand -base64 18)"
# security export cannot pick one identity: export all, import all, then drop the others.
security export -k "$LOGIN" -t identities -f pkcs12 -P "$P12PASS" -o "$TMP/ids.p12"
security import "$TMP/ids.p12" -k "$KC" -P "$P12PASS" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
rm -f "$TMP/ids.p12"
while read -r sha; do
  keepit=0; for k in "${IDS[@]}"; do [ "$k" = "$sha" ] && keepit=1; done
  [ "$keepit" = 1 ] || security delete-identity -Z "$sha" "$KC" >/dev/null 2>&1 || true
done < <(security find-identity "$KC" | sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\) .*/\1/p' | sort -u)
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KC" >/dev/null

# Search list: login first, then the build keychain (once).
list=(); while IFS= read -r k; do list+=("$k"); done < <(searchlist)
case " ${list[*]} " in *" $KC "*) ;; *) security list-keychains -d user -s "${list[@]}" "$KC" ;; esac

echo "==> build keychain: $KC"
security find-identity -v -p codesigning "$KC"
