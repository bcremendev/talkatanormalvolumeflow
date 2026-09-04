#!/bin/bash
# Build, package and publish a new version to GitHub Releases.
#   ./scripts/release.sh 1.1.0            # NOTARY_PROFILE=tanvf ./scripts/release.sh 1.1.0 to notarize too
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: release.sh <version>}"
# Notarize automatically if credentials were saved with scripts/setup-notarization.sh
if [[ -z "${NOTARY_PROFILE:-}" ]] && xcrun notarytool history --keychain-profile tanvf >/dev/null 2>&1; then
  export NOTARY_PROFILE=tanvf
fi
[[ -n "${NOTARY_PROFILE:-}" ]] && echo "▸ will notarize with profile $NOTARY_PROFILE" || echo "▸ NOT notarizing (run ./scripts/setup-notarization.sh once to fix)"
VERSION="$VERSION" ./scripts/build.sh
git add -A && git -c user.name="Brent Cremen" -c user.email="brent@zenmaid.com" commit -qm "Release $VERSION" || true
git push -q
gh release create "v$VERSION" "dist/talkatanormalvolumeflow-$VERSION.dmg" "dist/talkatanormalvolumeflow-$VERSION.zip" \
  --title "talkatanormalvolumeflow $VERSION" --generate-notes
# Don't leave a second copy of the app lying around: Spotlight/Launchpad would list it next to the installed one.
rm -rf dist/talkatanormalvolumeflow.app
echo "Download link: https://github.com/bcremendev/talkatanormalvolumeflow/releases/latest"
