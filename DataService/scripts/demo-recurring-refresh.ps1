param(
    [string]$Root = '',
    [ValidateRange(1,12)][int]$Ticks = 3,
    [ValidateRange(1,30)][int]$IntervalSeconds = 5,
    [ValidateRange(1,1200)][int]$TickTimeoutSeconds = 1200
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $Root) { $Root = Join-Path $projectRoot 'artifacts/opl-service' }
$Root = [IO.Path]::GetFullPath($Root)
$demoRoot = Join-Path $projectRoot 'artifacts/refresh-demo'
New-Item -ItemType Directory -Force -Path $demoRoot | Out-Null
$reportPath = Join-Path $demoRoot ('official-due-loop-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff') + '.json')
$events = [Collections.Generic.List[object]]::new()
$watch = [Diagnostics.Stopwatch]::StartNew()
for ($tick = 1; $tick -le $Ticks; $tick++) {
    try {
        $result = & (Join-Path $PSScriptRoot 'run-refresh.ps1') -Root $Root -TimeoutSeconds $TickTimeoutSeconds | ConvertFrom-Json
    } catch {
        $events.Add([pscustomobject]@{ tick=$tick; at=[DateTime]::UtcNow.ToString('o'); error=$_.Exception.Message })
        [pscustomobject]@{ kind='finite due-only official wrapper loop'; scheduledInstallation=$false; events=$events; elapsedSeconds=$watch.Elapsed.TotalSeconds } |
            ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $reportPath -Encoding utf8
        throw
    }
    $outcome = Get-Content -LiteralPath $result.stdout -Raw | ConvertFrom-Json
    $events.Add([pscustomobject]@{ tick=$tick; at=[DateTime]::UtcNow.ToString('o'); result=$result; outcome=$outcome })
    [pscustomobject]@{ kind='finite due-only official wrapper loop'; scheduledInstallation=$false; events=$events; elapsedSeconds=$watch.Elapsed.TotalSeconds } |
        ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $reportPath -Encoding utf8
    Write-Output ('Tick ' + $tick + '/' + $Ticks + ': ' + $(if($outcome.skipped){'not due; no upstream check'}else{'upstream refresh command completed'}) + '; evidence ' + $reportPath)
    if ($tick -lt $Ticks) { Start-Sleep -Seconds $IntervalSeconds }
}
Write-Output ('Finite loop finished after ' + [Math]::Round($watch.Elapsed.TotalSeconds,2) + ' seconds. No background service/task remains.')
