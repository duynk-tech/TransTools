param([Parameter(Mandatory = $true)][string]$PublishDirectory)
$ErrorActionPreference = 'Stop'
if (!$IsWindows) { throw 'Prepare Microsoft runtime files on Windows.' }
$root = (Resolve-Path $PublishDirectory).Path
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (!(Test-Path $vswhere)) { throw 'Visual Studio redistributable tools are required for packaging.' }
$installations = @(& $vswhere -products '*' -property installationPath)
$directories = @($installations | ForEach-Object { Get-ChildItem (Join-Path $_ 'VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT') -Directory -ErrorAction SilentlyContinue })
$crt = $directories | Sort-Object FullName -Descending | Select-Object -First 1
if (!$crt) { throw 'Microsoft x64 CRT redistributable directory was not found. Do not package an incomplete app.' }
# Use only the licensed redistribution directory; never copy DLLs out of System32.
foreach ($file in Get-ChildItem $crt.FullName -Filter '*.dll') {
    $signature = Get-AuthenticodeSignature $file.FullName
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft') { throw "Unverified Microsoft runtime: $($file.Name)" }
    Copy-Item $file.FullName $root -Force
}
foreach ($name in @('msvcp140.dll', 'msvcp140_1.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if (!(Test-Path (Join-Path $root $name))) { throw "Missing runtime dependency: $name" }
}
@'
Microsoft Visual C++ Runtime files are redistributed from the Visual Studio x64 CRT redistribution directory.
Copyright Microsoft Corporation. Redistribution is subject to Microsoft Software License Terms.
https://learn.microsoft.com/cpp/windows/redistributing-visual-cpp-files
'@ | Set-Content (Join-Path $root 'Microsoft-runtime-notice.txt')
Write-Host "PASS: verified Microsoft runtime bundled from $($crt.FullName)"
