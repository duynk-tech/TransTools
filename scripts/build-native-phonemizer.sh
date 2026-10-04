#!/bin/zsh
# Development-only. Released apps contain the universal native library; users
# never install Rust, Python or SEA-G2P packages to run VieNeu.
set -euo pipefail
cd "${0:A:h:h}"
revision=e825173f235d08ea19315b2b279fb11153b44cea
source_dir="$PWD/build/sea-g2p-native-source"
if [[ ! -d "$source_dir/.git" ]]; then
    git clone https://github.com/pnnbao97/sea-g2p.git "$source_dir"
fi
git -C "$source_dir" checkout --detach "$revision"
command -v cargo >/dev/null || { print -u2 "Rust toolchain required on the build machine only."; exit 1; }
rustup target add aarch64-apple-darwin x86_64-apple-darwin
for target in aarch64-apple-darwin x86_64-apple-darwin; do
    MACOSX_DEPLOYMENT_TARGET=14.0 cargo build --manifest-path "$source_dir/Cargo.toml" --release --locked --no-default-features --features capi --target "$target"
done
mkdir -p Resources/SpeechNative
lipo -create "$source_dir/target/aarch64-apple-darwin/release/libsea_g2p_rs.dylib" "$source_dir/target/x86_64-apple-darwin/release/libsea_g2p_rs.dylib" -output Resources/SpeechNative/libsea_g2p_rs.dylib
cp "$source_dir/LICENSE" Resources/Licenses/SEA-G2P-Apache.txt
