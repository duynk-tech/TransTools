#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

echo "🔨 Building TransTools release binary..."
./scripts/build-app.sh

echo "📦 Packaging TransTools.zip with ditto (preserving code signatures & symlinks)..."
cd build
rm -f TransTools.zip TransTools.zip.sha256
ditto -c -k --keepParent TransTools.app TransTools.zip
shasum -a 256 TransTools.zip > TransTools.zip.sha256
cd ..

echo "✅ Created build/TransTools.zip and build/TransTools.zip.sha256 successfully!"
ls -lh build/TransTools.zip
