# Asura Resource Monitor (`asura-sysmon`)

This repository is the standalone home of ASURA's system resource monitor: the Quickshell
Wayland window (`ui/`), the telemetry data plane (`cmd/asura-sysmon/`), and the desktop launcher.

In the distribution itself the trees are byte-identical mirrors of this one:
- `cmd/asura-sysmon/` mirrors `desktop/cmd/asura-sysmon/`
- `ui/` mirrors `shell/sysmon/` and `shell/sysmon.qml`
- `asura-sysmon.desktop` mirrors `session/applications/asura-sysmon.desktop`

Parity is automatically validated on every push and PR via `.github/workflows/sysmon-sync.yml`.

---

## Architecture

| Component | Path | Function |
|---|---|---|
| `asura-sysmon` | `cmd/asura-sysmon` (binary `/usr/bin/asura-sysmon`) | High-performance Go telemetry data plane and single-instance window launcher. |
| Window UI | `ui/sysmon.qml` and `ui/` (`/usr/share/asura/sysmon/`) | Quickshell showroom window: gauges, process table, storage, and telemetry cards. |
| Desktop Entry | `asura-sysmon.desktop` (`/usr/share/applications/`) | Application launcher and system menu integration. |

---

## CLI Commands

```text
asura-sysmon stats [--interval MS]     JSON: live CPU %, RAM, Swap, Disks, Network I/O
asura-sysmon proc [--sort FIELD]       JSON: active process list with memory, PID, threads
asura-sysmon kill <PID> [--force]      Terminates target PID (SIGTERM or SIGKILL)
asura-sysmon                           Launches the Resource Monitor GUI window
```

---

## Telemetry Sources

- **CPU & Thermal**: Instantaneous sampling from `/proc/stat` and `/proc/loadavg`; core temps from `/sys/class/thermal/` and `/sys/class/hwmon/`.
- **Memory & Swap**: Detailed breakdown from `/proc/meminfo` (RAM used, available, buffers, cache, swap).
- **Disk & Storage**: Read/write speeds and IOPS from `/proc/diskstats`, block devices from `/sys/block/`, and mounted filesystem capacity from `/proc/mounts`.
- **GPU**: Multi-vendor hardware monitoring: NVIDIA via `nvidia-smi`, AMD via `amdgpu` sysfs/hwmon, and Intel via DRM frequency scaling.
- **Power & Battery**: Charge levels, discharge wattage, voltage, and health metrics via `/sys/class/power_supply/`.
- **Network**: Interface throughput counters from `/proc/net/dev`.
