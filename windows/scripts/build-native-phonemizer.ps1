$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$source = Join-Path $repo 'windows\build\sea-g2p-native-source'
$revision = 'e825173f235d08ea19315b2b279fb11153b44cea'
if (!(Test-Path (Join-Path $source '.git'))) {
    git clone https://github.com/pnnbao97/sea-g2p.git $source
    if ($LASTEXITCODE -ne 0) { throw 'Could not clone pinned native phonemizer source.' }
}
git -C $source checkout --detach $revision
if ($LASTEXITCODE -ne 0) { throw 'Could not checkout pinned phonemizer revision.' }
if (!(Get-Command cargo -ErrorAction SilentlyContinue)) { throw 'Rust is required on the build machine only, not on user machines.' }
cargo build --manifest-path "$source\Cargo.toml" --release --locked --no-default-features --features capi --target x86_64-pc-windows-msvc
if ($LASTEXITCODE -ne 0) { throw 'Native Windows phonemizer build failed.' }
$destination = Join-Path $repo 'windows\TransTools\Resources\SpeechNative'
Copy-Item "$source\target\x86_64-pc-windows-msvc\release\sea_g2p_rs.dll" "$destination\sea_g2p_rs.dll" -Force
Copy-Item "$source\LICENSE" "$destination\SEA-G2P-Apache.txt" -Force
