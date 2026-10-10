param(
    [string]$SupertonicModel,
    [string]$VieNeuModel,
    [switch]$RequireModels,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\test-results')
)
$ErrorActionPreference = 'Stop'
if (![OperatingSystem]::IsWindows()) { throw 'Run this test suite on Windows.' }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $output | Out-Null
$names = @('SUPERtonic_TEST_MODEL','VIENEU_TEST_MODEL','VIENEU_TEST_RESOURCES','VIENEU_TEST_GOLDEN')
$previous = @{}
foreach ($name in $names) { $previous[$name] = [Environment]::GetEnvironmentVariable($name) }
try {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $null) }
    if ($RequireModels -and (!$SupertonicModel -or !$VieNeuModel)) { throw 'Both model paths are required for release validation.' }
    if ($SupertonicModel) { $env:SUPERtonic_TEST_MODEL = (Resolve-Path -LiteralPath $SupertonicModel).Path }
    if ($VieNeuModel) {
        $env:VIENEU_TEST_MODEL = (Resolve-Path -LiteralPath $VieNeuModel).Path
        $env:VIENEU_TEST_RESOURCES = Join-Path $repo 'windows\TransTools\Resources\SpeechNative'
        $env:VIENEU_TEST_GOLDEN = Join-Path $repo 'Tests\LocalTTSTests\vieneu-sdk-golden.json'
        if (!(Test-Path "$env:VIENEU_TEST_RESOURCES\sea_g2p_rs.dll")) { throw 'Build the native Windows phonemizer first.' }
    }
    $lines = @(dotnet run --project "$repo\windows\tests\AudioContractTests" -c Release 2>&1)
    $exitCode = $LASTEXITCODE
    $lines | Tee-Object -FilePath "$output\contracts.txt" | Write-Host
    $skips = @($lines | Where-Object { "$_" -match '^SKIP:' })
    [ordered]@{
        Platform = [Environment]::OSVersion.VersionString
        Architecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
        CompletedAt = (Get-Date).ToString('o')
        ExitCode = $exitCode
        Passed = @($lines | Where-Object { "$_" -match '^PASS:' }).Count
        Skipped = $skips.Count
        ModelTestsRequired = [bool]$RequireModels
        InteractiveTestsComplete = $false
    } | ConvertTo-Json | Set-Content "$output\contracts.json"
    if ($exitCode -ne 0) { throw "Contract tests failed ($exitCode)." }
    if ($RequireModels -and $skips.Count) { throw 'Model tests were skipped; release validation failed.' }
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $previous[$name]) }
}
