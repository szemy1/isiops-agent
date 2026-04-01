# IsiOps Insight Agent

Telemetry agent for collecting metrics and logs from Windows and Linux hosts, powered by [Fluent Bit](https://fluentbit.io/).

## Quick Install

### Linux (Fluent Bit)

```bash
curl -s "https://<opcenter>/api/public/setup/linux?agent=fluentbit&key=<API_KEY>" | sudo bash
```

### Windows (Fluent Bit)

```powershell
irm "https://<opcenter>/api/public/setup/windows?agent=fluentbit&key=<API_KEY>" | iex
```

### Legacy Script Agent (bash/PowerShell)

```bash
# Linux:
curl -s "https://<opcenter>/api/public/setup/linux?key=<API_KEY>" | sudo bash -s -- --url https://<opcenter>/webhook/telemetry --key <API_KEY>

# Windows:
irm "https://<opcenter>/api/public/setup/windows?persistent=true&key=<API_KEY>" | iex
```

## Supported Platforms

### Fluent Bit Agent (recommended)

| Platform | Versions | Status | Tested |
|----------|----------|--------|--------|
| Ubuntu | 20.04, 22.04, 24.04 | Supported | 2026-04-01 |
| Debian | 11 (Bullseye), 12 (Bookworm) | Supported | 2026-04-01 |
| Rocky Linux | 8, 9 | Supported | 2026-04-01 |
| AlmaLinux | 8, 9 | Supported | 2026-04-01 |
| Fedora | 39, 40 | Supported | 2026-04-01 |
| RHEL | 8, 9 | Supported (untested, same as Rocky) | - |
| Windows Server | 2019, 2022 | Supported | - |
| Windows | 10, 11 | Supported | 2026-04-01 |
| Amazon Linux 2023 | - | Not supported (no official FB package) | 2026-04-01 |
| CentOS 7 | - | Not supported (EOL) | 2026-04-01 |
| Arch Linux | - | Not supported (no official FB repo) | - |
| openSUSE/SLES | - | Not supported (no official FB repo) | - |

### Legacy Script Agent

| Platform | Versions | Status |
|----------|----------|--------|
| Any Linux with bash + curl | All | Supported |
| Windows with PowerShell 5.1+ | 10, 11, Server 2019+ | Supported |

## What It Collects

| Category | Linux | Windows |
|----------|-------|---------|
| CPU usage (%) | Fluent Bit `cpu` plugin | Fluent Bit `cpu` plugin |
| Memory usage (%) | Fluent Bit `mem` plugin | Fluent Bit `mem` plugin |
| Disk I/O | Fluent Bit `disk` plugin | Fluent Bit `disk` plugin |
| Network I/O | Fluent Bit `netif` plugin | Fluent Bit `netif` plugin |
| System logs | `tail` (syslog, auth.log, custom paths) | `winevtlog` (Event Log with Event ID) |
| Application logs | `tail` (configurable paths) | `tail` (configurable paths) |

## Architecture

```
Agent (Fluent Bit)
  → Lua transform (TelemetryEvent format)
    → HTTP POST /webhook/telemetry (with X-Intake-Key auth)
      → OpCenter Ingestion Worker
        → Kafka → Stream Processor → TimescaleDB + OpenSearch
```

## Configuration

Generated from the OpCenter dashboard: **Settings > Setup**

- Select metrics and log types to collect
- Configure log paths and Windows Event Log channels
- Set collection interval
- Choose agent type (Fluent Bit or Legacy Script)

Config files on the agent host:
- **Linux**: `/etc/fluent-bit/fluent-bit.conf`, `/etc/fluent-bit/transform.lua`
- **Windows**: `C:\fluent-bit\conf\fluent-bit.conf`, `C:\fluent-bit\conf\transform.lua`

## Requirements

### Fluent Bit Agent
- **Linux**: systemd, curl, package manager (apt/dnf/yum)
- **Windows**: PowerShell 5.1+, Administrator privileges

### Legacy Script Agent
- **Linux**: bash, curl, systemd, optional: jq, bc
- **Windows**: PowerShell 5.1+, Administrator privileges
