#!/usr/bin/env bash
# Runs the built app's own checks and renders screenshots. Usage: tests/run_checks.sh
set -uo pipefail
cd "$(dirname "$0")/.."
APP="dist/Present Perfect.app"
BIN="$APP/Contents/MacOS/PresentPerfect"
OUT=tests/out
mkdir -p "$OUT"
fail=0
step() { echo; echo "== $*"; }
bad() { echo "FAIL $*"; fail=1; }

step "version"
"$BIN" --version || bad "version"

step "diagnostics (what the build machine sees)"
"$BIN" --diagnostics | tee "$OUT/diagnostics.txt" || bad "diagnostics"
grep -q "^SCREENS" "$OUT/diagnostics.txt" && grep -q "^SOUND DEVICES" "$OUT/diagnostics.txt" \
  && echo "OK   report has screens and sound devices" || bad "diagnostics incomplete"

step "translations inside the app"
plutil -lint "$APP"/Contents/Resources/*.lproj/Localizable.strings || bad "strings files"

step "screenshots"
"$BIN" --render-ui "$OUT/screenshots/en" -AppleLanguages "(en)" || bad "render English"
"$BIN" --render-ui "$OUT/screenshots/nl" -AppleLanguages "(nl)" || bad "render Dutch"
"$BIN" --render-ui "$OUT/screenshots/fr" -AppleLanguages "(fr)" || bad "render French"
for lang in en nl fr; do
  n=$(ls "$OUT/screenshots/$lang"/*.png 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -ge 20 ] && echo "OK   $n screenshots ($lang)" || bad "only $n screenshots ($lang)"
done

step "updates"
if codesign -dv "$APP" 2>&1 | grep -q "^TeamIdentifier=[A-Z0-9]\{10\}$"; then
  T="$OUT/update-test"
  rm -rf "$T"
  mkdir -p "$T/target"
  "$BIN" --verify-app "$APP" && echo "OK   the signed and notarized app is accepted as an update" || bad "own app refused"
  ditto "$APP" "$T/adhoc.app"
  codesign --force --deep --sign - "$T/adhoc.app" 2>/dev/null
  if "$BIN" --verify-app "$T/adhoc.app"; then bad "an ad-hoc signed app was accepted"; else echo "OK   an app without your Developer ID is refused"; fi
  ditto -c -k --keepParent "$APP" "$T/update.zip"
  ditto "$APP" "$T/target/Present Perfect.app"
  plutil -replace CFBundleShortVersionString -string 0.0.1 "$T/target/Present Perfect.app/Contents/Info.plist"
  "$BIN" --test-install "$T/update.zip" "$T/target/Present Perfect.app" || bad "install from zip"
  v=$(plutil -extract CFBundleShortVersionString raw "$T/target/Present Perfect.app/Contents/Info.plist")
  [ "$v" = "$(tr -d '[:space:]' < VERSION)" ] && echo "OK   installed version $v over 0.0.1" || bad "installed version is $v"
  codesign --verify --deep --strict "$T/target/Present Perfect.app" && echo "OK   installed app is intact" || bad "installed app signature"
else
  echo "SKIP the app is not signed with a Developer ID"
fi
"$BIN" --check-update && echo "OK   GitHub check works" || bad "update check"

echo
[ $fail -eq 0 ] && echo "All checks passed." || echo "Some checks failed."
exit $fail
