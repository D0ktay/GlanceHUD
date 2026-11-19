#!/usr/bin/env bash
# Builds build/GlanceHUD.app. Quiet on success; the full compiler log goes to build/logs/build.log.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/GlanceHUD.app
LOG=build/logs/build.log
mkdir -p build/logs

if ! swift build -c release --product GlanceHUD >"$LOG" 2>&1; then
  grep -E "error:" "$LOG" | head -40 || tail -40 "$LOG"
  echo "Build failed. Full log: $LOG"
  exit 1
fi
BIN="$(swift build -c release --show-bin-path)/GlanceHUD"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GlanceHUD"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# A stable signing identity keeps the Screen Recording grant across rebuilds; ad-hoc signing loses it.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -v CSSMERR | grep -E '"(Apple Development|Developer ID Application)' | awk '{print $2}' | head -1 || true)}"
if [[ -n "$IDENTITY" ]] && codesign --force --sign "$IDENTITY" "$APP" >>"$LOG" 2>&1; then
  SIGNED="identity $IDENTITY"
else
  codesign --force --sign - "$APP" >>"$LOG" 2>&1
  SIGNED="ad-hoc"
fi
echo "Built $APP (signed: $SIGNED)"
