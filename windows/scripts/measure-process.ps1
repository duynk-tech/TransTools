param(
  [Parameter(Mandatory=$true)][int]$TargetProcessId,
  [ValidateRange(10,86400)][int]$DurationSeconds = 120,
  [ValidateRange(1,60)][int]$IntervalSeconds = 2,
  [string]$OutputPath = "windows/test-results/process-metrics.csv"
)
$ErrorActionPreference = 'Stop'
# Observe an existing user-started app; never starts audio, changes settings or kills it.
$target = Get-Process -Id $TargetProcessId
$startedAt = $target.StartTime
$previousCpu = $target.TotalProcessorTime.TotalSeconds
$clock = [System.Diagnostics.Stopwatch]::StartNew()
$previousTime = $clock.Elapsed.TotalSeconds
$deadline = $DurationSeconds
$rows = [System.Collections.Generic.List[object]]::new()
while ($clock.Elapsed.TotalSeconds -lt $deadline) {
  Start-Sleep -Seconds $IntervalSeconds
  try { $target = Get-Process -Id $TargetProcessId -ErrorAction Stop } catch { break }
  if ($target.StartTime -ne $startedAt) { break } # PID reuse must not mix different apps.
  $now = $clock.Elapsed.TotalSeconds
  $cpu = $target.TotalProcessorTime.TotalSeconds
  $elapsed = $now - $previousTime
  $rows.Add([pscustomobject]@{
    TimestampUtc = [DateTime]::UtcNow.ToString('o')
    ProcessId = $TargetProcessId
    ElapsedSeconds = [Math]::Round($now,3)
    CpuPercentOneCore = [Math]::Round(100 * ($cpu - $previousCpu) / $elapsed,2)
    CpuPercentMachine = [Math]::Round(100 * ($cpu - $previousCpu) / $elapsed / [Environment]::ProcessorCount,2)
    WorkingSetMB = [Math]::Round($target.WorkingSet64 / 1MB,2)
    PrivateMemoryMB = [Math]::Round($target.PrivateMemorySize64 / 1MB,2)
    Handles = $target.HandleCount
    Threads = $target.Threads.Count
  })
  $previousCpu = $cpu; $previousTime = $now
}
$folder = Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
[IO.Directory]::CreateDirectory($folder) | Out-Null
$rows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
Write-Output "Saved $($rows.Count) samples to $OutputPath"
