#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

if [[ "${1:-}" != "--skip-build" ]]; then
  zsh scripts/build-app.sh
fi
/usr/bin/codesign --verify --deep --strict build/TransTools.app

stage_dir=$(mktemp -d "${TMPDIR:-/tmp/}TransTools-DMG.XXXXXX")
trap 'rm -rf "$stage_dir"' EXIT
/usr/bin/ditto build/TransTools.app "$stage_dir/Trans Tools.app"
ln -s /Applications "$stage_dir/Applications"

/usr/bin/hdiutil create -ov -volname "Trans Tools" -srcfolder "$stage_dir" \
  -format UDZO -imagekey zlib-level=9 build/TransTools.dmg
/usr/bin/hdiutil verify build/TransTools.dmg
(cd build && shasum -a 256 TransTools.dmg > TransTools.dmg.sha256)
echo "Created build/TransTools.dmg and build/TransTools.dmg.sha256"
