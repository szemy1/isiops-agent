<#
.SYNOPSIS
    OpCenter Windows Host Metrics Collector
    Sends CPU, memory, disk metrics to OpCenter.

.USAGE
    .\Collect-HostMetrics.ps1
    .\Collect-HostMetrics.ps1 -IntervalSeconds 10
#>

param(
    [string]$WebhookUrl = "http://localhost:3001/webhook/telemetry",
    [int]$IntervalSeconds = 10,
    [string]$SourceId = $env:COMPUTERNAME
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  OpCenter Host Metrics Collector" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Target:   $WebhookUrl"
Write-Host "  Interval: ${IntervalSeconds}s"
Write-Host "  Source:   $SourceId"
Write-Host "  Press Ctrl+C to stop"
Write-Host "========================================" -ForegroundColor Cyan

function Send-Metric {
    param([string]$Name, [double]$Value, [string]$Unit)

    $body = @{
        sourceId = $SourceId
        severity = "info"
        category = "metric"
        payload = @{
            name = $Name
            value = [math]::Round($Value, 2)
            unit = $Unit
        }
        tags = @{
            agent = "powershell-metrics"
            hostname = $SourceId
            metricType = "host"
        }
    } | ConvertTo-Json -Depth 4

    try {
        $null = Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $body -ContentType "application/json" -TimeoutSec 5
    } catch {}
}

$totalSent = 0

try {
    while ($true) {
        # CPU
        $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
        Send-Metric -Name "cpu_usage" -Value $cpu -Unit "percent"

        # Memory
        $os = Get-CimInstance Win32_OperatingSystem
        $memUsed = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100, 2)
        Send-Metric -Name "memory_usage" -Value $memUsed -Unit "percent"

        # Memory absolute (GB)
        $memUsedGB = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 2)
        Send-Metric -Name "memory_used_gb" -Value $memUsedGB -Unit "GB"

        # Disk (all drives)
        $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
        foreach ($disk in $disks) {
            $diskUsed = [math]::Round(($disk.Size - $disk.FreeSpace) / $disk.Size * 100, 2)
            Send-Metric -Name "disk_usage_$($disk.DeviceID.Replace(':',''))" -Value $diskUsed -Unit "percent"
        }

        # Network (bytes sent/received per interval)
        $net = Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface | Select-Object -First 1
        if ($net) {
            Send-Metric -Name "network_bytes_sent" -Value ($net.BytesSentPersec / 1MB) -Unit "MB/s"
            Send-Metric -Name "network_bytes_recv" -Value ($net.BytesReceivedPersec / 1MB) -Unit "MB/s"
        }

        # Process count
        $procCount = (Get-Process).Count
        Send-Metric -Name "process_count" -Value $procCount -Unit "count"

        # Uptime (hours)
        $uptime = [math]::Round((New-TimeSpan -Start $os.LastBootUpTime).TotalHours, 1)
        Send-Metric -Name "uptime" -Value $uptime -Unit "hours"

        $totalSent += 7 + $disks.Count
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] CPU: ${cpu}% | RAM: ${memUsed}% | Sent: $totalSent metrics" -ForegroundColor Green

        Start-Sleep -Seconds $IntervalSeconds
    }
} finally {
    Write-Host "Metrics collector stopped. Total: $totalSent" -ForegroundColor Yellow
}
