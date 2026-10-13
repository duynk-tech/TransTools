$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$test = Join-Path $repo 'windows\tests\TranslationContractTests'
$reference = Get-Content (Join-Path $test 'reference.json') -Raw | ConvertFrom-Json
$folder = Join-Path $repo 'windows\test-models\marian-en-vi'
New-Item -ItemType Directory -Force (Join-Path $folder 'onnx') | Out-Null
foreach ($file in $reference.sha256.PSObject.Properties) {
    $target = Join-Path $folder $file.Name
    if (!(Test-Path $target) -or (Get-FileHash $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.Value) {
        $url = 'https://huggingface.co/' + $reference.repository + '/resolve/' + $reference.revision + '/' + $file.Name
        Invoke-WebRequest -Uri $url -OutFile $target -TimeoutSec 180
    }
    if ((Get-FileHash $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.Value) { throw "Model integrity failed: $($file.Name)" }
}
Copy-Item (Join-Path $test 'generation_config.json') $folder -Force
$output = Join-Path $repo 'windows\test-results'; New-Item -ItemType Directory -Force $output | Out-Null
$lines = @(dotnet run --project $test -c Release -- $folder 2>&1)
$exitCode = $LASTEXITCODE
$lines | Tee-Object -FilePath (Join-Path $output 'offline-translation.txt') | Write-Host
if ($exitCode -ne 0) { throw 'Native ONNX translation test failed.' }

# Exercise the same native extraction used by the shipped single-file application.
$published = Join-Path $repo 'windows\test-publish\translation'
dotnet publish $test -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -o $published
if ($LASTEXITCODE -ne 0) { throw 'Packaged offline translation publish failed.' }
$lines = @(& (Join-Path $published 'TranslationContractTests.exe') $folder 2>&1)
$exitCode = $LASTEXITCODE
$lines | Tee-Object -FilePath (Join-Path $output 'offline-translation-packaged.txt') | Write-Host
if ($exitCode -ne 0) { throw 'Packaged offline translation inference failed.' }

$lines = @(dotnet run --project (Join-Path $repo 'windows/tests/MeetingPipelineTests') -c Release -- $folder $output 2>&1)
$exitCode = $LASTEXITCODE
$lines | Tee-Object -FilePath (Join-Path $output 'meeting-pipeline.txt') | Write-Host
if ($exitCode -ne 0) { throw 'Actual meeting recognition/translation pipeline failed.' }
