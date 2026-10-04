#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

echo "🔨 Building TransTools release binary..."
zsh scripts/build-app.sh

echo "📦 Packaging TransTools.zip with ditto (preserving code signatures & symlinks)..."
stage_dir=$(mktemp -d "${TMPDIR:-/tmp/}TransTools-ZIP.XXXXXX")
trap 'rm -rf "$stage_dir"' EXIT
ditto build/TransTools.app "$stage_dir/Trans Tools.app"
rm -f build/TransTools.zip build/TransTools.zip.sha256
ditto -c -k --keepParent "$stage_dir/Trans Tools.app" build/TransTools.zip
cd build
shasum -a 256 TransTools.zip > TransTools.zip.sha256
cd ..

zsh scripts/package-dmg.sh --skip-build

echo "✅ Created ZIP, DMG and SHA256 checksums successfully!"
ls -lh build/TransTools.zip build/TransTools.dmg
