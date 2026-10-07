$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$root = Join-Path $repo 'windows\test-models'
foreach ($name in @('supertonic','vieneu')) {
    $manifestFile = if ($name -eq 'supertonic') { 'windows\TransTools\Resources\Models\supertonic.json' } else { 'windows\TransTools\Resources\SpeechNative\vieneu-native-manifest.json' }
    $manifest = Get-Content (Join-Path $repo $manifestFile) -Raw | ConvertFrom-Json
    $folder = [IO.Path]::GetFullPath((Join-Path $root $name))
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    foreach ($file in $manifest.files) {
        $destination = [IO.Path]::GetFullPath((Join-Path $folder $file.path))
        if (!$destination.StartsWith($folder + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe model path.' }
        $url = if ($name -eq 'supertonic') { "https://huggingface.co/supertone-oss-archive/supertonic-3/resolve/$($manifest.revision)/$($file.path)" } else { $file.url }
        $uri = [Uri]$url
        if ($uri.Scheme -ne 'https' -or $uri.Host -notin @('huggingface.co','raw.githubusercontent.com')) { throw 'Untrusted model host.' }
        if ((Test-Path -LiteralPath $destination) -and ((Get-Item -LiteralPath $destination).Length -eq $file.size) -and ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -eq $file.sha256)) { continue }
        New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
        Write-Host "Downloading $name/$($file.path)"
        $temporary = $destination + '.partial'
        try {
            Invoke-WebRequest -Uri $url -OutFile $temporary -TimeoutSec 600
            if ((Get-Item -LiteralPath $temporary).Length -ne $file.size -or (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ne $file.sha256) { throw "Model checksum or size mismatch: $($file.path)" }
            Move-Item -LiteralPath $temporary -Destination $destination -Force
        } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
    }
}
