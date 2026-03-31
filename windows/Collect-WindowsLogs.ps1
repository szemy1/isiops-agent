<#
.SYNOPSIS
    OpCenter Windows Event Log Collector
    Reads Windows Event Logs and sends them to the OpCenter ingestion pipeline.

.USAGE
    .\Collect-WindowsLogs.ps1
    .\Collect-WindowsLogs.ps1 -WebhookUrl "http://192.168.1.100:3001/webhook/telemetry"
    .\Collect-WindowsLogs.ps1 -Logs "System","Application","Security" -IntervalSeconds 10
#>

param(
    [string]$WebhookUrl = "http://localhost:3001/webhook/telemetry",
    [string[]]$Logs = @("System", "Application", "Security"),
    [int]$IntervalSeconds = 5,
    [int]$MaxEventsPerBatch = 50,
    [string]$SourceId = $env:COMPUTERNAME
)

$ErrorActionPreference = "Continue"

# Track last read time per log
$lastRead = @{}
foreach ($log in $Logs) {
    $lastRead[$log] = (Get-Date).AddSeconds(-$IntervalSeconds)
}

function Convert-SeverityLevel {
    param([int]$Level)
    switch ($Level) {
        1 { return "critical" }   # Critical
        2 { return "error" }      # Error
        3 { return "warning" }    # Warning
        4 { return "info" }       # Information
        5 { return "debug" }      # Verbose
        default { return "info" }
    }
}

function Send-ToOpCenter {
    param(
        [object]$Event,
        [string]$LogName
    )

    $severity = Convert-SeverityLevel -Level $Event.Level

    $body = @{
        sourceId = "$SourceId"
        protocol = "webhook"
        severity = $severity
        category = "log"
        payload = @{
            message = $Event.Message
            level = $Event.LevelDisplayName
            source = "$LogName/$($Event.ProviderName)"
            metadata = @{
                hostname = $SourceId
                ip = ""
                eventId = "$($Event.Id)"
                logName = $LogName
                providerName = "$($Event.ProviderName)"
            }
        }
        tags = @{
            agent = "powershell-collector"
            hostname = $SourceId
            logName = $LogName
            eventId = "$($Event.Id)"
            providerName = "$($Event.ProviderName)"
        }
    } | ConvertTo-Json -Depth 5

    try {
        $null = Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $body -ContentType "application/json" -TimeoutSec 5
    } catch {
        # Silently count errors
        $script:errorCount++
    }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  OpCenter Windows Log Collector" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Target:   $WebhookUrl"
Write-Host "  Logs:     $($Logs -join ', ')"
Write-Host "  Interval: ${IntervalSeconds}s"
Write-Host "  Source:   $SourceId"
Write-Host "  Press Ctrl+C to stop"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$totalSent = 0
$script:errorCount = 0
$startTime = Get-Date

try {
    while ($true) {
        $batchCount = 0

        foreach ($logName in $Logs) {
            try {
                $events = Get-WinEvent -LogName $logName -MaxEvents $MaxEventsPerBatch -ErrorAction SilentlyContinue |
                    Where-Object { $_.TimeCreated -gt $lastRead[$logName] }

                if ($events) {
                    $lastRead[$logName] = ($events | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated

                    foreach ($event in $events) {
                        Send-ToOpCenter -Event $event -LogName $logName
                        $batchCount++
                    }
                }
            } catch {
                # Log source may not exist or access denied
            }
        }

        $totalSent += $batchCount
        $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)

        if ($batchCount -gt 0) {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Sent $batchCount events (total: $totalSent, errors: $script:errorCount, uptime: ${elapsed}s)" -ForegroundColor Green
        } else {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] No new events (total: $totalSent, uptime: ${elapsed}s)" -ForegroundColor DarkGray
        }

        Start-Sleep -Seconds $IntervalSeconds
    }
} finally {
    Write-Host ""
    Write-Host "Collector stopped. Total events sent: $totalSent, Errors: $script:errorCount" -ForegroundColor Yellow
}
