<#
.SYNOPSIS
    OpCenter IIS Log Collector
    Tails IIS W3C log files and sends entries to OpCenter.

.USAGE
    .\Collect-IISLogs.ps1
    .\Collect-IISLogs.ps1 -LogPath "C:\inetpub\logs\LogFiles\W3SVC1"
#>

param(
    [string]$WebhookUrl = "http://localhost:3001/webhook/telemetry",
    [string]$LogPath = "C:\inetpub\logs\LogFiles",
    [int]$IntervalSeconds = 5,
    [string]$SourceId = "$($env:COMPUTERNAME)-iis"
)

$ErrorActionPreference = "Continue"
$lastPosition = @{}

function Parse-IISLogLine {
    param([string]$Line)

    if ($Line.StartsWith("#")) { return $null }

    $parts = $Line -split " "
    if ($parts.Count -lt 10) { return $null }

    $statusCode = if ($parts.Count -gt 10) { $parts[10] } else { "0" }
    $statusInt = [int]$statusCode
    $severity = if ($statusInt -ge 500) { "error" } elseif ($statusInt -ge 400) { "warning" } else { "info" }

    return @{
        sourceId = $SourceId
        severity = $severity
        category = "log"
        payload = @{
            message = "IIS: $($parts[3]) $($parts[4]) -> $statusCode ($($parts[6]))"
            level = "iis-access"
            source = $SourceId
        }
        tags = @{
            agent = "powershell-iis-collector"
            method = $parts[3]
            uri = $parts[4]
            statusCode = $statusCode
            clientIp = if ($parts.Count -gt 8) { $parts[8] } else { "" }
            hostname = $SourceId
        }
    }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  OpCenter IIS Log Collector" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Target:   $WebhookUrl"
Write-Host "  LogPath:  $LogPath"
Write-Host "  Source:   $SourceId"
Write-Host "  Press Ctrl+C to stop"
Write-Host "========================================" -ForegroundColor Cyan

$totalSent = 0

try {
    while ($true) {
        $logFiles = Get-ChildItem -Path $LogPath -Filter "*.log" -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 5

        foreach ($file in $logFiles) {
            $key = $file.FullName
            if (-not $lastPosition.ContainsKey($key)) {
                # Start from end of file
                $lastPosition[$key] = (Get-Content $file.FullName -ErrorAction SilentlyContinue).Count
            }

            $lines = Get-Content $file.FullName -ErrorAction SilentlyContinue
            if ($lines.Count -gt $lastPosition[$key]) {
                $newLines = $lines[$lastPosition[$key]..($lines.Count - 1)]
                $lastPosition[$key] = $lines.Count

                foreach ($line in $newLines) {
                    $parsed = Parse-IISLogLine -Line $line
                    if ($parsed) {
                        try {
                            $body = $parsed | ConvertTo-Json -Depth 4
                            $null = Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $body -ContentType "application/json" -TimeoutSec 5
                            $totalSent++
                        } catch {}
                    }
                }
            }
        }

        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Checked $(($logFiles).Count) files, sent: $totalSent" -ForegroundColor DarkGray
        Start-Sleep -Seconds $IntervalSeconds
    }
} finally {
    Write-Host "IIS collector stopped. Total: $totalSent" -ForegroundColor Yellow
}
