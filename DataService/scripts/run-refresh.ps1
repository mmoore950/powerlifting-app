param(
    [string]$Root = '',
    [switch]$Force,
    [int]$TimeoutSeconds = 1200
)
$ErrorActionPreference = 'Stop'
if ($TimeoutSeconds -lt 1 -or $TimeoutSeconds -gt 1200) { throw 'TimeoutSeconds must be 1–1200.' }
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $Root) { $Root = Join-Path $projectRoot 'artifacts/opl-service' }
$Root = [System.IO.Path]::GetFullPath($Root)
$nodeExecutable = (Get-Command node -ErrorAction Stop).Source
$cliPath = Join-Path $projectRoot 'DataService/src/cli.mjs'
New-Item -ItemType Directory -Path (Join-Path $Root 'logs') -Force | Out-Null
$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$outputPath = Join-Path $Root ('logs/' + $stamp + '.stdout.log')
$errorPath = Join-Path $Root ('logs/' + $stamp + '.stderr.log')
$info = [System.Diagnostics.ProcessStartInfo]::new()
$info.FileName = $nodeExecutable
$info.WorkingDirectory = $projectRoot
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
foreach ($argument in @($cliPath, 'refresh', '--root', $Root, '--due', 'true')) { $info.ArgumentList.Add($argument) }
if ($Force) { foreach ($argument in @('--force', 'true')) { $info.ArgumentList.Add($argument) } }
$child = [System.Diagnostics.Process]::Start($info)
$stdout = $child.StandardOutput.ReadToEndAsync()
$stderr = $child.StandardError.ReadToEndAsync()
$finished = $child.WaitForExit($TimeoutSeconds * 1000)
if (-not $finished) { $child.Kill($true); $child.WaitForExit() }
$stdout.GetAwaiter().GetResult() | Set-Content -LiteralPath $outputPath -Encoding utf8
$stderr.GetAwaiter().GetResult() | Set-Content -LiteralPath $errorPath -Encoding utf8
if (-not $finished) {
    $lockPath = Join-Path $Root 'refresh.lock'
    if (Test-Path -LiteralPath $lockPath) {
        $owner = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
        if ($owner.pid -eq $child.Id) { & $nodeExecutable $cliPath recover-lock --root $Root --pid $child.Id }
    }
    throw ('Refresh exceeded hard wall-clock limit of ' + $TimeoutSeconds + ' seconds; child terminated. Logs: ' + $errorPath)
}
[pscustomobject]@{ exitCode = $child.ExitCode; stdout = $outputPath; stderr = $errorPath } | ConvertTo-Json
if ($child.ExitCode -ne 0) { throw ('Refresh failed. See ' + $errorPath) }
