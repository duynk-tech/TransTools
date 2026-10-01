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
    cp Resources/MascotBack.png build/TransTools.app/Contents/Resources/MascotBack.png 2>/dev/null || true
    cp Resources/MascotSleeping.png build/TransTools.app/Contents/Resources/MascotSleeping.png 2>/dev/null || true
    cp Resources/MascotWalking.png build/TransTools.app/Contents/Resources/MascotWalking.png 2>/dev/null || true
    cp Resources/MascotBody.png build/TransTools.app/Contents/Resources/MascotBody.png 2>/dev/null || true
    cp Resources/MascotLegLeft.png build/TransTools.app/Contents/Resources/MascotLegLeft.png 2>/dev/null || true
    cp Resources/MascotLegRight.png build/TransTools.app/Contents/Resources/MascotLegRight.png 2>/dev/null || true
    if [ -d Resources/MascotSprites ]; then
        rm -rf build/TransTools.app/Contents/Resources/MascotSprites
        cp -R Resources/MascotSprites build/TransTools.app/Contents/Resources/MascotSprites
    fi
fi
codesign --force --deep --sign - --identifier "local.mactools.transtools" -r='designated => identifier "local.mactools.transtools"' build/TransTools.app

