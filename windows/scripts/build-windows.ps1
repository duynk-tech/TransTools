# PowerShell Build Script for Trans Tools (Windows)
$ErrorActionPreference = "Stop"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "   Trans Tools Windows Build Script     " -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# 1. Check dotnet installation
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Error "Không tìm thấy .NET SDK! Vui lòng cài đặt .NET 9 SDK từ https://dotnet.microsoft.com/download"
    exit 1
}

$ProjectDir = Join-Path $PSScriptRoot "..\TransTools"
$OutputDir = Join-Path $PSScriptRoot "..\build"

Write-Host "Building project at: $ProjectDir" -ForegroundColor Yellow
Write-Host "Output destination:  $OutputDir" -ForegroundColor Yellow

# 2. Restore NuGet Packages
Write-Host "`n[1/3] Đang tải gói thư viện NuGet..." -ForegroundColor Green
dotnet restore "$ProjectDir\TransTools.csproj"

# 3. Publish Single-File Executable
Write-Host "`n[2/3] Đang biên dịch TransTools.exe (win-x64 Self-Contained)..." -ForegroundColor Green
dotnet publish "$ProjectDir\TransTools.csproj" `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:EnableCompressionInSingleFile=true `
    -o "$OutputDir"

# 4. Verification
$ExePath = Join-Path $OutputDir "TransTools.exe"
if (Test-Path $ExePath) {
    $Size = (Get-Item $ExePath).Length / 1MB
    Write-Host "`n[3/3] Build thành công!" -ForegroundColor Cyan
    Write-Host "File thực thi: $ExePath ($([Math]::Round($Size, 2)) MB)" -ForegroundColor Green
} else {
    Write-Error "Build thất bại, không tìm thấy TransTools.exe!"
    exit 1
}
