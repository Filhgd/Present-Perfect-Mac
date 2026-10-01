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
  [ "$n" -ge 18 ] && echo "OK   $n screenshots ($lang)" || bad "only $n screenshots ($lang)"
done

echo
[ $fail -eq 0 ] && echo "All checks passed." || echo "Some checks failed."
exit $fail
