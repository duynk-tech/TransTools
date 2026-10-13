param(
    [Parameter(Mandatory = $true)][string]$PublishDirectory,
    [switch]$LoadNativeLibraries
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path $PublishDirectory).Path
$libraries = @('whisper.dll', 'ggml-whisper.dll', 'ggml-base-whisper.dll', 'ggml-cpu-whisper.dll')
$runtimeDirectories = @('runtimes/win-x64', 'runtimes/noavx/win-x64')
foreach ($directory in $runtimeDirectories) {
    foreach ($library in $libraries) {
        $path = Join-Path $root "$directory/$library"
        if (!(Test-Path $path -PathType Leaf) -or (Get-Item $path).Length -eq 0) {
            throw "Windows speech package is incomplete: $directory/$library is missing. Do not release this build."
        }
    }
}
if ($LoadNativeLibraries) {
    if (!$IsWindows) { throw 'Native Whisper loading must be tested on Windows.' }
    if (!('WhisperPackageNativeProbe' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WhisperPackageNativeProbe {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr LoadLibraryEx(string fileName, IntPtr reserved, uint flags);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool FreeLibrary(IntPtr handle);
    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, ExactSpelling = true)]
    public static extern IntPtr GetProcAddress(IntPtr handle, string name);
}
'@
    }
    foreach ($directory in $runtimeDirectories) {
        $path = Join-Path $root "$directory/whisper.dll"
        # Load dependencies from the same runtime directory plus trusted Windows search locations.
        $handle = [WhisperPackageNativeProbe]::LoadLibraryEx($path, [IntPtr]::Zero, 0x1100)
        if ($handle -eq [IntPtr]::Zero) {
            $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "Cannot load $directory/whisper.dll or its dependencies (Windows error $code)."
        }
        try {
            if ([WhisperPackageNativeProbe]::GetProcAddress($handle, 'whisper_init_from_file_with_params') -eq [IntPtr]::Zero) {
                throw "Whisper entry point missing in $directory/whisper.dll."
            }
        } finally { [void][WhisperPackageNativeProbe]::FreeLibrary($handle) }
    }
}
Write-Host 'PASS: Windows Whisper CPU and NoAVX libraries are present; requested load checks passed.'
