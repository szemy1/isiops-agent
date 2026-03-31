# IsiOps Insight Agent

Lightweight telemetry agents for collecting metrics and logs from Windows and Linux hosts, sending them to the [IsiOps Insight OpCenter](https://github.com/szemy1/VuejsApp1).

## Quick Install

### Windows (PowerShell as Administrator)

```powershell
# Via dashboard: Settings > Setup > Windows > Generate Persistent Script
# Or manual:
.\windows\Collect-WindowsLogs.ps1 -WebhookUrl "https://<opcenter>/webhook/telemetry"
```

### Linux (as root)

```bash
# Via dashboard: Settings > Setup > Linux > Generate Persistent Script
curl -s "https://<opcenter>/api/admin/setup/scripts/linux?persistent=true" -H "Authorization: Bearer <TOKEN>" | sudo bash
```

## What It Collects

| Category | Windows | Linux |
|----------|---------|-------|
| CPU usage (%) | Yes | Yes |
| Memory usage (%) | Yes | Yes |
| Disk usage (%) | Yes | Yes |
| Network I/O | Yes | Yes |
| Top processes | Yes | Yes |
| Event Logs / Journal | Yes (with Event ID) | Yes (journalctl + syslog) |
| Uptime | Yes | Yes |

## Structure

```
windows/
  Collect-WindowsLogs.ps1    -- Event Log collector (Event ID, Provider, Level)
  Collect-HostMetrics.ps1    -- CPU, memory, disk, network metrics
  Collect-IISLogs.ps1        -- IIS W3C access log collector
  Start-AllCollectors.ps1    -- Start all collectors in parallel

linux/
  install.sh                 -- Systemd agent installer
```

## Auth

API key via `X-Intake-Key` header. Generate from dashboard: Settings > Setup.

## Requirements

- **Windows**: PowerShell 5.1+, Admin for Scheduled Task
- **Linux**: bash, curl, systemd
