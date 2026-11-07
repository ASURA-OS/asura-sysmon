# asura-sysmon

**Asura OS Resource Monitor** — High-performance real-time system telemetry and process manager.

Designed natively for [Asura OS](https://github.com/mohitjoer/ASURA-OS) with a pure monochrome cyberpunk UI, fast Go telemetry data plane, and Quickshell Wayland interface.

## Features

- **Live Telemetry**: Real-time CPU % (overall and per-core distribution), load averages, temperature.
- **Memory & Swap**: Physical RAM utilization, available, cached, buffers, and swap breakdown.
- **Storage Partitions**: Root mount and storage disk usages, filesystem types, read/write metrics.
- **Network I/O**: Live upload and download throughput rates per second, total bandwidth, interface monitoring.
- **Process Manager**: Searchable task list sorted by memory or CPU, thread counts, process status, and safe process termination ("End Task").
- **Pure Monochrome**: Official Asura OS dark visual register with zero external styling dependencies.

## CLI Usage

```sh
# Full system vitals snapshot as JSON
asura-sysmon stats

# Sample with custom delta interval
asura-sysmon stats --interval 500

# Top running processes
asura-sysmon proc --limit 20 --sort mem

# Terminate process safely
asura-sysmon kill <pid>
asura-sysmon kill <pid> --force

# Launch GUI showroom window
asura-sysmon
```

## Build & Test

```sh
# Run tests under race detector
make test

# Build executable
make build

# Install to system prefix
sudo make install
```
