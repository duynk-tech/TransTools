#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc Sources/TransTools/SpeechTextReconciler.swift Tests/SpeechTextReconcilerTests/main.swift -o "$test_dir/speech-check"
"$test_dir/speech-check"
