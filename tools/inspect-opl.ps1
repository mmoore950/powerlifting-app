param([switch]$Download)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$landingUrl = 'https://openpowerlifting.gitlab.io/opl-csv/bulk-csv.html'
$zipUrl = 'https://openpowerlifting.gitlab.io/opl-csv/files/openpowerlifting-latest.zip'
$landing = (Invoke-WebRequest -Uri $landingUrl -TimeoutSec 20).Content
$sourceDate = [regex]::Match($landing, 'Updated: (\d{4}-\d{2}-\d{2})').Groups[1].Value
$revision = [regex]::Match($landing, '>([a-f0-9]{8,40})</a>').Groups[1].Value
$observation = [ordered]@{
    checkedAtUTC = [DateTime]::UtcNow.ToString('o')
    landingUrl = $landingUrl
    archiveUrl = $zipUrl
    sourceDate = $sourceDate
    revision = $revision
    archiveDownloaded = $false
}
if ($Download) {
    $artifactDirectory = Join-Path $taskRoot 'artifacts'
    New-Item -ItemType Directory -Path $artifactDirectory -Force | Out-Null
    $archivePath = Join-Path $artifactDirectory 'openpowerlifting-latest.zip'
    $client = [System.Net.Http.HttpClient]::new()
    $timeout = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(60))
    $response = $null
    $inputStream = $null
    $outputStream = $null
    try {
        $response = $client.GetAsync($zipUrl, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead, $timeout.Token).GetAwaiter().GetResult()
        $response.EnsureSuccessStatusCode() | Out-Null
        $limit = 200MB
        if ($response.Content.Headers.ContentLength -gt $limit) { throw 'Archive exceeds 200 MiB inspection limit.' }
        $inputStream = $response.Content.ReadAsStreamAsync($timeout.Token).GetAwaiter().GetResult()
        $outputStream = [System.IO.File]::Create($archivePath)
        $buffer = [byte[]]::new(65536)
        $received = 0L
        while (($read = $inputStream.ReadAsync($buffer, 0, $buffer.Length, $timeout.Token).GetAwaiter().GetResult()) -gt 0) {
            $received += $read
            if ($received -gt $limit) { throw 'Archive exceeds 200 MiB inspection limit.' }
            $outputStream.Write($buffer, 0, $read)
        }
        $observation.archiveBytes = $received
        $observation.lastModified = [string]$response.Content.Headers.LastModified
        $observation.etag = [string]$response.Headers.ETag
    } finally {
        if ($outputStream) { $outputStream.Dispose() }
        if ($inputStream) { $inputStream.Dispose() }
        if ($response) { $response.Dispose() }
        $client.Dispose()
        $timeout.Dispose()
    }
    $zip = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $csvEntries = @($zip.Entries | Where-Object { $_.FullName.EndsWith('.csv') })
        if ($csvEntries.Count -ne 1) { throw 'Expected exactly one CSV in the upstream archive.' }
        $reader = [System.IO.StreamReader]::new($csvEntries[0].Open())
        try {
            $header = $reader.ReadLine()
            if ($header.Length -gt 20000) { throw 'Unexpectedly large CSV header.' }
            $observation.csvEntry = $csvEntries[0].FullName
            $observation.uncompressedBytes = $csvEntries[0].Length
            $observation.columns = @($header.Split(','))
        } finally { $reader.Dispose() }
    } finally { $zip.Dispose() }
    $observation.archiveDownloaded = $true
    $observation.sha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $observation | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $artifactDirectory 'opl-inspection.json') -Encoding utf8
}
$observation | ConvertTo-Json -Depth 5
