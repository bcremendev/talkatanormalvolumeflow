#!/bin/bash
# Builds, bundles, signs, (optionally) notarizes and packages talkatanormalvolumeflow.app
#
#   ./scripts/build.sh                 # build + sign with Developer ID (if present) + zip + dmg
#   NOTARY_PROFILE=myprofile ./scripts/build.sh   # also notarize + staple
#   SKIP_OLLAMA=1 ./scripts/build.sh   # smaller build without bundled Ollama
#   BUNDLE_MLX=1 ./scripts/build.sh    # include Ollama's MLX libs (+350 MB) for MLX-only models
#
# Env:
#   SIGN_IDENTITY   codesign identity (default: first "Developer ID Application" in keychain, else ad-hoc "-")
#   NOTARY_PROFILE  notarytool keychain profile name (create once with:
#                     xcrun notarytool store-credentials myprofile --apple-id you@x.com --team-id TEAMID --password app-specific-pw)
#   BUNDLE_ID       default com.talkatanormalvolumeflow.app
#   VERSION         default 1.0.0
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
APP_NAME="talkatanormalvolumeflow"
VERSION="${VERSION:-1.0.0}"
BUILD_NUM="$(date +%Y%m%d%H%M)"
BUNDLE_ID="${BUNDLE_ID:-com.talkatanormalvolumeflow.app}"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

# ---- dependencies -----------------------------------------------------------
"$ROOT/scripts/fetch-deps.sh"

# ---- compile ----------------------------------------------------------------
echo "▸ swift build (release, arm64)"
swift build -c release --arch arm64 2>&1 | grep -v "warning:" | tail -3
BIN="$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME"

# ---- bundle -----------------------------------------------------------------
echo "▸ assembling $APP"
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/" -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUM/" \
    Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R vendor/build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework "$APP/Contents/Frameworks/"
# Strip Intel slice from the framework to save space (app is arm64-only).
lipo -thin arm64 "$APP/Contents/Frameworks/whisper.framework/Versions/A/whisper" -output /tmp/whisper.thin 2>/dev/null \
  && mv /tmp/whisper.thin "$APP/Contents/Frameworks/whisper.framework/Versions/A/whisper" || true

if [[ -z "${SKIP_OLLAMA:-}" && -x vendor/ollama/ollama ]]; then
  echo "▸ bundling Ollama"
  H="$APP/Contents/Helpers/ollama"
  mkdir -p "$H"
  # Copy everything except Intel-only CPU variants and unneeded tools.
  # Skip Intel-only CPU variants, the quantize tool, and (unless BUNDLE_MLX=1) the 350 MB MLX libs that
  # only newer MLX-format models use; GGUF models like qwen2.5 run on the ggml/Metal runner.
  (cd vendor/ollama && find . -maxdepth 1 -mindepth 1 ! -name '*.so' ! -name 'llama-quantize' ${BUNDLE_MLX:+-o -false} ! -name 'mlx_metal_*' -exec cp -R {} "$H/" \;)
  [[ -n "${BUNDLE_MLX:-}" ]] && cp -R vendor/ollama/mlx_metal_* "$H/" || true
  for f in "$H"/ollama "$H"/*.dylib "$H"/llama-server "$H"/mlx_metal_*/*.dylib; do
    [[ -f "$f" && ! -L "$f" ]] || continue
    if lipo -info "$f" 2>/dev/null | grep -q x86_64; then
      lipo -thin arm64 "$f" -output "$f.thin" 2>/dev/null && mv "$f.thin" "$f" || true
    fi
  done
  # Licenses live in Resources, not next to executables.
  mkdir -p "$APP/Contents/Resources/ollama-licenses" && mv "$H"/*LICENSE* "$H"/*NOTICE* "$APP/Contents/Resources/ollama-licenses/" 2>/dev/null || true
fi

# ---- sign -------------------------------------------------------------------
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning | grep -m1 'Developer ID Application' | sed -E 's/.*"(.*)"/\1/' || true)"
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
echo "▸ signing with: $SIGN_IDENTITY"
SIGN=(codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY")
[[ "$SIGN_IDENTITY" == "-" ]] && SIGN=(codesign --force --sign -)

if [[ -d "$APP/Contents/Helpers/ollama" ]]; then
  find "$APP/Contents/Helpers/ollama" -type f \( -name '*.dylib' -o -name '*.metallib' \) -exec "${SIGN[@]}" {} \;
  for exe in "$APP/Contents/Helpers/ollama/ollama" "$APP/Contents/Helpers/ollama/llama-server"; do
    [[ -f "$exe" ]] && "${SIGN[@]}" --entitlements Resources/helper.entitlements "$exe"
  done
fi
"${SIGN[@]}" "$APP/Contents/Frameworks/whisper.framework/Versions/A"
"${SIGN[@]}" --entitlements Resources/app.entitlements "$APP"
codesign --verify --deep --strict "$APP" && echo "  signature OK"

# ---- notarize ---------------------------------------------------------------
ZIP="$DIST/$APP_NAME-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
if [[ -n "${NOTARY_PROFILE:-}" && "$SIGN_IDENTITY" != "-" ]]; then
  echo "▸ notarizing (this takes a few minutes)…"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP"
else
  echo "  (skipping notarization: set NOTARY_PROFILE to notarize)"
fi

# ---- dmg --------------------------------------------------------------------
DMG="$DIST/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
cp COWORKERS.md "$STAGE/READ ME FIRST.md" 2>/dev/null || true
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
if [[ -n "${NOTARY_PROFILE:-}" && "$SIGN_IDENTITY" != "-" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait >/dev/null && xcrun stapler staple "$DMG"
fi

echo
echo "✔ Done"
du -sh "$APP" "$ZIP" "$DMG" | sed 's/^/  /'
