#!/bin/bash
# Build, package and publish a new version to GitHub Releases.
#   ./scripts/release.sh 1.1.0            # NOTARY_PROFILE=tanvf ./scripts/release.sh 1.1.0 to notarize too
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: release.sh <version>}"
VERSION="$VERSION" ./scripts/build.sh
git add -A && git commit -qm "Release $VERSION" || true
git push -q
gh release create "v$VERSION" "dist/talkatanormalvolumeflow-$VERSION.dmg" "dist/talkatanormalvolumeflow-$VERSION.zip" \
  --title "talkatanormalvolumeflow $VERSION" --generate-notes
echo "Download link: https://github.com/bcremendev/talkatanormalvolumeflow/releases/latest"
