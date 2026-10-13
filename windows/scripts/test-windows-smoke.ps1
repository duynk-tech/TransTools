param(
    [Parameter(Mandatory=$true)][string]$AppPath,
    [ValidateRange(1,1440)][int]$Minutes = 10,
    [string]$OutputDirectory = "$env:USERPROFILE\Desktop\TransTools-test"
)
$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath $AppPath)) { throw "Executable not found: $AppPath" }
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$metadata = [ordered]@{
    OS = $os.Caption; Build = $os.BuildNumber; Architecture = $os.OSArchitecture
    CPU = $cpu.Name; LogicalProcessors = [Environment]::ProcessorCount
    TotalRAMBytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
    App = (Resolve-Path -LiteralPath $AppPath).Path
    SHA256 = (Get-FileHash -LiteralPath $AppPath -Algorithm SHA256).Hash
    StartedAt = (Get-Date).ToString('o')
}
$metadata | ConvertTo-Json | Set-Content "$OutputDirectory\environment.json"
$process = Start-Process -FilePath $AppPath -PassThru
$rows = [System.Collections.Generic.List[object]]::new()
Write-Host 'Test microphone/loopback, captions, conversation, TTS/export and board while metrics are recorded. This does not automatically validate those functions.'
$process.Refresh()
$previousCPU = $process.TotalProcessorTime.TotalSeconds; $previousTime = Get-Date
try {
    for ($i = 0; $i -lt ($Minutes * 12); $i++) {
        Start-Sleep -Seconds 5
        $process.Refresh()
        if ($process.HasExited) { Write-Warning "App exited with code $($process.ExitCode)"; break }
        $now = Get-Date; $cpuSeconds = $process.TotalProcessorTime.TotalSeconds
        $elapsed = ($now - $previousTime).TotalSeconds
        $rows.Add([pscustomobject]@{
            Timestamp = $now.ToString('o')
            CPUPercentOfMachine = [Math]::Round(100 * ($cpuSeconds - $previousCPU) / $elapsed / [Environment]::ProcessorCount, 2)
            WorkingSetMB = [Math]::Round($process.WorkingSet64 / 1MB, 2)
            PrivateMemoryMB = [Math]::Round($process.PrivateMemorySize64 / 1MB, 2)
            Handles = $process.HandleCount; Threads = $process.Threads.Count
            Responding = $process.Responding
        })
        $previousCPU = $cpuSeconds; $previousTime = $now
    }
} finally {
    $rows | Export-Csv -Path "$OutputDirectory\metrics.csv" -NoTypeInformation
    $process.Refresh()
    [ordered]@{
        FinishedAt = (Get-Date).ToString('o')
        Samples = $rows.Count
        Exited = $process.HasExited
        ExitCode = $(if ($process.HasExited) { $process.ExitCode } else { $null })
        PeakWorkingSetMB = $(if ($rows.Count) { ($rows | Measure-Object WorkingSetMB -Maximum).Maximum } else { $null })
        AverageCPUPercentOfMachine = $(if ($rows.Count) { ($rows | Measure-Object CPUPercentOfMachine -Average).Average } else { $null })
        FunctionalTests = 'Manual checks required; metrics alone do not prove functionality.'
    } | ConvertTo-Json | Set-Content "$OutputDirectory\summary.json"
    Write-Host "Saved evidence to $OutputDirectory. App remains open."
}
