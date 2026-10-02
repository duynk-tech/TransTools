#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/module-cache .build/tests
swiftc -module-cache-path .build/module-cache Sources/TransTools/UpdateManifest.swift Tests/UpdateManifestTests/main.swift -o .build/tests/update-manifest
.build/tests/update-manifest
