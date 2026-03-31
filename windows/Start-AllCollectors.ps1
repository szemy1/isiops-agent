<#
.SYNOPSIS
    Starts all OpCenter collectors in parallel.
.USAGE
    .\Start-AllCollectors.ps1
    .\Start-AllCollectors.ps1 -WebhookUrl "http://10.0.0.5:3001/webhook/telemetry"
#>

param(
    [string]$WebhookUrl = "http://localhost:3001/webhook/telemetry"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  OpCenter All-in-One Collector" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Starting collectors..." -ForegroundColor Green

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Start Windows Event Log collector
$eventJob = Start-Job -ScriptBlock {
    param($script, $url)
    & $script -WebhookUrl $url
} -ArgumentList "$scriptDir\Collect-WindowsLogs.ps1", $WebhookUrl

# Start Host Metrics collector
$metricsJob = Start-Job -ScriptBlock {
    param($script, $url)
    & $script -WebhookUrl $url
} -ArgumentList "$scriptDir\Collect-HostMetrics.ps1", $WebhookUrl

Write-Host ""
Write-Host "Running collectors:" -ForegroundColor Green
Write-Host "  [1] Windows Event Logs (System, Application, Security)"
Write-Host "  [2] Host Metrics (CPU, RAM, Disk, Network)"
Write-Host ""
Write-Host "Press Ctrl+C to stop all collectors." -ForegroundColor Yellow
Write-Host ""

try {
    while ($true) {
        # Show job status
        $jobs = @($eventJob, $metricsJob)
        $running = ($jobs | Where-Object { $_.State -eq 'Running' }).Count
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Collectors running: $running/2" -ForegroundColor DarkGray

        # Print any job output
        foreach ($job in $jobs) {
            Receive-Job -Job $job -ErrorAction SilentlyContinue | ForEach-Object {
                Write-Host "  $_" -ForegroundColor DarkCyan
            }
        }

        Start-Sleep -Seconds 10
    }
} finally {
    Write-Host ""
    Write-Host "Stopping all collectors..." -ForegroundColor Yellow
    Stop-Job -Job $eventJob, $metricsJob -ErrorAction SilentlyContinue
    Remove-Job -Job $eventJob, $metricsJob -Force -ErrorAction SilentlyContinue
    Write-Host "All collectors stopped." -ForegroundColor Green
}
