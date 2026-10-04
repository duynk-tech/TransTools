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
    if [ -d Resources/SpeechRuntime ]; then
        rm -rf build/TransTools.app/Contents/Resources/SpeechRuntime
        ditto Resources/SpeechRuntime build/TransTools.app/Contents/Resources/SpeechRuntime
    fi
    ditto Resources/SpeechNative build/TransTools.app/Contents/Resources/SpeechNative
    codesign --force --sign - build/TransTools.app/Contents/Resources/SpeechNative/libsea_g2p_rs.dylib
    ditto Resources/Licenses build/TransTools.app/Contents/Resources/Licenses
    if [ -d Resources/Pronunciation ]; then
        mkdir -p build/TransTools.app/Contents/Resources/Pronunciation
        cp -R Resources/Pronunciation/. build/TransTools.app/Contents/Resources/Pronunciation/
    fi
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
    if [ -d Resources/MascotModel ]; then
        mkdir -p build/TransTools.app/Contents/Resources/MascotModel
        cp -R Resources/MascotModel/. build/TransTools.app/Contents/Resources/MascotModel/
    fi
    if [ -d Resources/MascotActivities ]; then
        mkdir -p build/TransTools.app/Contents/Resources/MascotActivities
        cp -R Resources/MascotActivities/. build/TransTools.app/Contents/Resources/MascotActivities/
    fi
    if [ -d Resources/MascotSprites ]; then
        rm -rf build/TransTools.app/Contents/Resources/MascotSprites
        cp -R Resources/MascotSprites build/TransTools.app/Contents/Resources/MascotSprites
    fi
fi
for resource_bundle in .build/release/*.bundle(N); do
    ditto "$resource_bundle" "build/TransTools.app/Contents/Resources/$(basename "$resource_bundle")"
done
codesign --force --deep --sign - --identifier "local.mactools.transtools" -r='designated => identifier "local.mactools.transtools"' build/TransTools.app
rm -rf "build/Trans Tools.app"
ditto build/TransTools.app "build/Trans Tools.app"
codesign --force --deep --sign - --identifier "local.mactools.transtools" -r='designated => identifier "local.mactools.transtools"' "build/Trans Tools.app"

