# OpCenter Windows Log Collectors

PowerShell-based collectors that send Windows logs and metrics to the OpCenter pipeline.

## Prerequisites

- PowerShell 5.1+ (built into Windows)
- OpCenter REST Ingestion Worker running on port 3001

## Quick Start

### All collectors at once:
```powershell
.\Start-AllCollectors.ps1
```

### Individual collectors:

**Windows Event Logs** (System, Application, Security):
```powershell
.\Collect-WindowsLogs.ps1
```

**Host Metrics** (CPU, RAM, Disk, Network):
```powershell
.\Collect-HostMetrics.ps1
```

**IIS Logs** (if IIS is installed):
```powershell
.\Collect-IISLogs.ps1
```

## Custom Configuration

```powershell
# Point to a remote OpCenter instance:
.\Collect-WindowsLogs.ps1 -WebhookUrl "http://10.0.0.5:3001/webhook/telemetry"

# Collect only Security logs, every 2 seconds:
.\Collect-WindowsLogs.ps1 -Logs "Security" -IntervalSeconds 2

# Metrics every 30 seconds:
.\Collect-HostMetrics.ps1 -IntervalSeconds 30

# Custom source name:
.\Collect-WindowsLogs.ps1 -SourceId "PROD-WEB-01"
```

## What gets collected

| Collector | Data | Category |
|---|---|---|
| WindowsLogs | Event Log entries (System, Application, Security) | log |
| HostMetrics | CPU %, RAM %, Disk %, Network MB/s, Process count, Uptime | metric |
| IISLogs | IIS W3C access logs | log |

## Data Flow

```
PowerShell Script -> HTTP POST -> REST Worker (:3001) -> Kafka -> Stream Processor -> Dashboard
```
