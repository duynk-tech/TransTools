#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build -c release --disable-sandbox --cache-path .build/cache --scratch-path .build
mkdir -p build/TransTools.app/Contents/MacOS
mkdir -p build/TransTools.app/Contents/Resources
cp .build/release/TransTools build/TransTools.app/Contents/MacOS/TransTools
cp Info.plist build/TransTools.app/Contents/Info.plist
if [ -d Resources ]; then
    cp Resources/AppIcon.icns build/TransTools.app/Contents/Resources/AppIcon.icns 2>/dev/null || true
    cp Resources/AppIcon.png build/TransTools.app/Contents/Resources/AppIcon.png 2>/dev/null || true
    cp Resources/Mini.png build/TransTools.app/Contents/Resources/Mini.png 2>/dev/null || true
    cp Resources/Mascot3D.png build/TransTools.app/Contents/Resources/Mascot3D.png 2>/dev/null || true
    cp Resources/MascotWriting.png build/TransTools.app/Contents/Resources/MascotWriting.png 2>/dev/null || true
fi
codesign --force --deep --sign - --identifier "local.mactools.transtools" -r='designated => identifier "local.mactools.transtools"' build/TransTools.app

