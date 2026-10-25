#!/bin/bash
# Gives the unsigned app an ad-hoc signature that carries its entitlements
# (the App Group shared with the widget). Signing services re-sign the app
# anyway; this only lets them see which entitlements it asks for.
set -euo pipefail
APP="$1"

# Inside out: frameworks and libraries, then the widget, then the app.
if [ -d "$APP/Frameworks" ]; then
  find "$APP/Frameworks" -depth \( -name "*.framework" -o -name "*.dylib" \) -print0 |
    while IFS= read -r -d '' item; do
      codesign --force --sign - --timestamp=none "$item"
    done
fi
for appex in "$APP"/PlugIns/*.appex; do
  [ -d "$appex" ] || continue
  codesign --force --sign - --timestamp=none --entitlements CinemaWidget/CinemaWidget.entitlements "$appex"
done
codesign --force --sign - --timestamp=none --entitlements Cinema/Resources/Cinema.entitlements "$APP"

echo "App entitlements:"
codesign -d --entitlements - "$APP" 2>/dev/null || true
