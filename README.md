# asura-sysmon

**Asura OS Resource Monitor** — High-performance real-time system telemetry and process manager.

Designed natively for [Asura OS](https://github.com/mohitjoer/ASURA-OS) with a pure monochrome cyberpunk UI, fast Go telemetry data plane, and Quickshell Wayland interface.

## Features

- **Live Telemetry**: Real-time CPU % (overall and per-core distribution), load averages, temperature.
- **Memory & Swap**: Physical RAM utilization, available, cached, buffers, and swap breakdown.
- **Graphics (GPU)**: Multi-vendor GPU monitoring supporting NVIDIA (`nvidia-smi`), AMD (`amdgpu` sysfs), Intel Iris/UHD, and virtualized GPUs (VirtIO, VMware, VirtualBox).
- **Power & Battery**: Real-time battery %, charging/discharging wattage, voltage, and health status for laptops and portables.
- **Storage & Disk I/O**: Real-time read/write speeds (bytes/sec) and IOPS, top-level block device enumeration, and filesystem filtering (excluding pseudo-filesystems like `efivarfs`).
- **Network I/O**: Live upload and download throughput rates per second, total bandwidth, interface monitoring.
- **Process Manager**: Searchable task list sorted by memory or CPU, thread counts, process status, and safe process termination ("End Task").
- **Universal Hardware Support**: Automatically adapts across laptops, desktops, servers, and virtual machines without runtime failures.
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
