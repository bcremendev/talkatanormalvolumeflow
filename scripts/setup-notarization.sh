#!/bin/bash
# One-time: store Apple notarization credentials in your keychain so releases notarize automatically.
# You type the password directly into Apple's tool; it is never written to disk by this script.
set -euo pipefail
PROFILE="tanvf"
TEAM_ID="${TEAM_ID:-8D929LM592}"

cat <<MSG

  Notarization setup (one time, ~2 minutes)
  ------------------------------------------
  1. Open https://account.apple.com/account/manage  (sign in with the Apple ID on your developer account)
  2. Under "Sign-In and Security" click "App-Specific Passwords" → "+" → name it "talkatanormalvolumeflow"
  3. Copy the password it shows (looks like xxxx-xxxx-xxxx-xxxx)

MSG
open "https://account.apple.com/account/manage" 2>/dev/null || true
read -rp "  Apple ID email: " APPLE_ID
echo "  Now paste the app-specific password when Apple's tool asks (it won't show as you type)."
xcrun notarytool store-credentials "$PROFILE" --apple-id "$APPLE_ID" --team-id "$TEAM_ID"
echo
echo "  ✔ Saved. Every future ./scripts/release.sh will notarize automatically."
