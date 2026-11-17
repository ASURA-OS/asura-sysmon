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
- **Process Manager**: Every process with its CPU and memory use, sortable by any column, searchable by name, PID, user or command line. Ending a process asks first (End or Force quit) and explains why when it can't.
- **Universal Hardware Support**: Automatically adapts across laptops, desktops, servers, and virtual machines without runtime failures.
- **Follows your theme**: Colours and fonts come from the ASURA shell's design tokens, so the monitor matches the colour scheme or wallpaper palette you picked in the Hub, light or dark.

## CLI Usage

```sh
# Full system vitals snapshot as JSON
asura-sysmon stats

# Sample with custom delta interval
asura-sysmon stats --interval 500

# Top running processes, by memory or by CPU (sampled over --interval ms)
asura-sysmon proc --limit 20 --sort mem
asura-sysmon proc --limit 20 --sort cpu --interval 250

# Terminate process safely
asura-sysmon kill <pid>
asura-sysmon kill <pid> --force

# Launch GUI showroom window
asura-sysmon
```

## Keyboard

| Keys | Does |
|---|---|
| Ctrl+1 … Ctrl+4 | Performance, Processes, Storage, System |
| Ctrl+Tab, Ctrl+Shift+Tab | Next or previous tab |
| Ctrl+F or `/` | Search processes |
| ↑ / ↓ | Select a process |
| Delete | End the selected process (asks first; Enter confirms) |
| Esc | Back out: cancel, clear the search, then deselect |
| Ctrl+Q, Ctrl+W | Close |

## Build & Test

On ASURA OS (or any Void Linux system):

```sh
sudo xbps-install -S go gcc make
```

The window is part of the ASURA shell: it imports the shell's design tokens
(`qs.Ui.Singletons`), so it runs from the shell tree (`shell/sysmon.qml` in ASURA OS),
not from a bare checkout.

```sh
# Run tests under race detector
make test

# Build executable
make build

# Install to system prefix
sudo make install
```

## License

GNU General Public License v3.0 only. See [LICENSE](LICENSE). The same code ships
inside [ASURA OS](https://github.com/mohitjoer/ASURA-OS) under the same licence.
