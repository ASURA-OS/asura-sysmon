package main

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"os/user"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type ProcessInfo struct {
	PID         int     `json:"pid"`
	PPID        int     `json:"ppid"`
	Name        string  `json:"name"`
	Cmdline     string  `json:"cmdline"`
	User        string  `json:"user"`
	UID         int     `json:"uid"`
	State       string  `json:"state"`
	CPUPercent  float64 `json:"cpuPercent"`
	MemoryBytes uint64  `json:"memoryBytes"`
	MemoryPct   float64 `json:"memoryPercent"`
	Threads     int     `json:"threads"`

	// cpuTicks is utime+stime from /proc/<pid>/stat, in clock ticks. It is
	// only the raw counter; CPUPercent is computed from two readings of it.
	cpuTicks uint64
}

var uidCache = make(map[int]string)

func usernameFromUID(uid int) string {
	if name, ok := uidCache[uid]; ok {
		return name
	}
	u, err := user.LookupId(strconv.Itoa(uid))
	if err == nil && u != nil && u.Username != "" {
		uidCache[uid] = u.Username
		return u.Username
	}
	name := strconv.Itoa(uid)
	uidCache[uid] = name
	return name
}

// resolveProcessName expands truncated names from /proc/[pid]/stat comm (TASK_COMM_LEN=16)
// and identifies generic runtimes (like quickshell or python) by their target argument.
func resolveProcessName(comm string, cmdline string) string {
	if cmdline == "" || strings.HasPrefix(cmdline, "[") {
		return comm
	}
	args := strings.Fields(cmdline)
	if len(args) == 0 {
		return comm
	}
	base0 := filepath.Base(args[0])

	// For quickshell instances, clarify what's running (e.g. desktop shell, sysmon, hub, wallpaper)
	if base0 == "quickshell" || comm == "quickshell" {
		for i, arg := range args {
			if (arg == "-p" || arg == "--path") && i+1 < len(args) {
				p := strings.TrimSuffix(args[i+1], ".qml")
				return fmt.Sprintf("quickshell (%s)", filepath.Base(p))
			}
			if strings.HasPrefix(arg, "--path=") {
				p := strings.TrimSuffix(strings.TrimPrefix(arg, "--path="), ".qml")
				return fmt.Sprintf("quickshell (%s)", filepath.Base(p))
			}
		}
		return "quickshell"
	}

	// For interpreters like python / node / ruby / perl
	if base0 == "python" || base0 == "python3" || base0 == "node" || base0 == "ruby" || base0 == "perl" {
		rest := args[1:]
		for i := 0; i < len(rest); i++ {
			arg := rest[i]
			switch {
			case arg == "-m" && i+1 < len(rest):
				// python3 -m http.server: the module is the program.
				return fmt.Sprintf("%s (%s)", base0, rest[i+1])
			case arg == "-c" || arg == "-e":
				// Inline code, not a script: there is no better name.
				return base0
			case !strings.HasPrefix(arg, "-"):
				return fmt.Sprintf("%s (%s)", base0, filepath.Base(arg))
			}
		}
	}

	// If comm was truncated to 15 chars (kernel TASK_COMM_LEN limit), use the untruncated base0
	if len(comm) >= 15 && len(base0) > len(comm) && strings.HasPrefix(base0, comm) {
		return base0
	}

	return comm
}

func readProcess(pid int, totalMem uint64) (*ProcessInfo, error) {
	procDir := fmt.Sprintf("/proc/%d", pid)

	// Stat file: pid (comm) state ppid ...
	statData, err := os.ReadFile(filepath.Join(procDir, "stat"))
	if err != nil {
		return nil, err
	}

	str := string(statData)
	openParen := strings.Index(str, "(")
	closeParen := strings.LastIndex(str, ")")
	if openParen == -1 || closeParen == -1 || closeParen <= openParen {
		return nil, fmt.Errorf("corrupt stat for %d", pid)
	}

	name := str[openParen+1 : closeParen]
	rest := strings.Fields(str[closeParen+1:])
	if len(rest) < 18 {
		return nil, fmt.Errorf("short stat for %d", pid)
	}

	state := rest[0]
	ppid, _ := strconv.Atoi(rest[1])
	// rest[0] is field 3 of proc(5)'s stat, so utime (14) and stime (15)
	// are rest[11] and rest[12].
	utime, _ := strconv.ParseUint(rest[11], 10, 64)
	stime, _ := strconv.ParseUint(rest[12], 10, 64)
	threads, _ := strconv.Atoi(rest[17])

	// Read status for UID and VmRSS
	statusData, err := os.ReadFile(filepath.Join(procDir, "status"))
	if err != nil {
		return nil, err
	}

	var uid int
	var rssBytes uint64
	sc := bufio.NewScanner(bytes.NewReader(statusData))
	for sc.Scan() {
		l := sc.Text()
		if strings.HasPrefix(l, "Uid:") {
			f := strings.Fields(l)
			if len(f) > 1 {
				uid, _ = strconv.Atoi(f[1])
			}
		} else if strings.HasPrefix(l, "VmRSS:") {
			f := strings.Fields(l)
			if len(f) > 1 {
				v, _ := strconv.ParseUint(f[1], 10, 64)
				rssBytes = v * 1024
			}
		}
	}

	// Read cmdline
	cmdData, _ := os.ReadFile(filepath.Join(procDir, "cmdline"))
	cmdline := strings.ReplaceAll(string(cmdData), "\x00", " ")
	cmdline = strings.TrimSpace(cmdline)
	if cmdline == "" {
		cmdline = "[" + name + "]"
	}

	var memPct float64
	if totalMem > 0 {
		memPct = float64(rssBytes) / float64(totalMem) * 100.0
	}

	return &ProcessInfo{
		PID:         pid,
		PPID:        ppid,
		Name:        resolveProcessName(name, cmdline),
		Cmdline:     cmdline,
		User:        usernameFromUID(uid),
		UID:         uid,
		State:       state,
		MemoryBytes: rssBytes,
		MemoryPct:   memPct,
		Threads:     threads,
		cpuTicks:    utime + stime,
	}, nil
}

// processCPUPercent is a process's share of the whole machine's CPU time
// between two readings: its own ticks over every CPU's ticks, so a process
// keeping one core of eight busy reads 12.5, and the sum over all processes
// never exceeds 100.
func processCPUPercent(procTicks1, procTicks2, totalTicks1, totalTicks2 uint64) float64 {
	if totalTicks2 <= totalTicks1 || procTicks2 < procTicks1 {
		return 0
	}
	pct := float64(procTicks2-procTicks1) / float64(totalTicks2-totalTicks1) * 100.0
	if pct > 100.0 {
		return 100.0
	}
	return pct
}

// processTicks reads utime+stime for every process, cheaply: only stat.
func processTicks() map[int]uint64 {
	ticks := make(map[int]uint64)
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return ticks
	}
	for _, e := range entries {
		pid, err := strconv.Atoi(e.Name())
		if err != nil || pid <= 0 {
			continue
		}
		data, err := os.ReadFile(filepath.Join("/proc", e.Name(), "stat"))
		if err != nil {
			continue
		}
		str := string(data)
		closeParen := strings.LastIndex(str, ")")
		if closeParen == -1 {
			continue
		}
		rest := strings.Fields(str[closeParen+1:])
		if len(rest) < 13 {
			continue
		}
		utime, _ := strconv.ParseUint(rest[11], 10, 64)
		stime, _ := strconv.ParseUint(rest[12], 10, 64)
		ticks[pid] = utime + stime
	}
	return ticks
}

// ListProcesses lists processes without measuring CPU usage (cpuPercent is 0).
func ListProcesses(sortBy string, limit int) ([]ProcessInfo, error) {
	return ListProcessesSampled(sortBy, limit, 0)
}

// ListProcessesSampled lists processes and, when interval > 0, measures each
// one's CPU usage over that interval. A process that started during the
// interval reads 0 for this sample.
func ListProcessesSampled(sortBy string, limit int, interval time.Duration) ([]ProcessInfo, error) {
	var before map[int]uint64
	var total1 cpuSample
	if interval > 0 {
		before = processTicks()
		total1, _, _ = readCPUSamples()
		time.Sleep(interval)
	}

	entries, err := os.ReadDir("/proc")
	if err != nil {
		return nil, err
	}

	mem, _, _ := CollectMemoryStats()
	totalMem := mem.TotalBytes

	var pids []int
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		pid, err := strconv.Atoi(e.Name())
		if err == nil && pid > 0 {
			pids = append(pids, pid)
		}
	}

	var total2 cpuSample
	if interval > 0 {
		total2, _, _ = readCPUSamples()
	}

	var procs []ProcessInfo
	for _, pid := range pids {
		pi, err := readProcess(pid, totalMem)
		if err == nil && pi != nil {
			if t1, ok := before[pid]; ok {
				pi.CPUPercent = processCPUPercent(t1, pi.cpuTicks, total1.total, total2.total)
			}
			procs = append(procs, *pi)
		}
	}

	switch strings.ToLower(sortBy) {
	case "cpu":
		sort.SliceStable(procs, func(i, j int) bool {
			if procs[i].CPUPercent != procs[j].CPUPercent {
				return procs[i].CPUPercent > procs[j].CPUPercent
			}
			return procs[i].MemoryBytes > procs[j].MemoryBytes
		})
	case "mem", "memory":
		sort.Slice(procs, func(i, j int) bool {
			return procs[i].MemoryBytes > procs[j].MemoryBytes
		})
	case "name":
		sort.Slice(procs, func(i, j int) bool {
			return strings.ToLower(procs[i].Name) < strings.ToLower(procs[j].Name)
		})
	case "pid":
		sort.Slice(procs, func(i, j int) bool {
			return procs[i].PID < procs[j].PID
		})
	default:
		// Default to memory or CPU
		sort.Slice(procs, func(i, j int) bool {
			return procs[i].MemoryBytes > procs[j].MemoryBytes
		})
	}

	if limit > 0 && len(procs) > limit {
		procs = procs[:limit]
	}

	return procs, nil
}

func KillProcess(pid int, force bool) error {
	if pid <= 1 {
		return fmt.Errorf("refusing to terminate PID %d", pid)
	}

	// Safety protection for core desktop compositor/system daemons
	proc, err := readProcess(pid, 0)
	if err == nil && proc != nil {
		lower := strings.ToLower(proc.Name)
		// runsvdir supervises every runit service: ending it stops them all.
		if lower == "systemd" || lower == "init" || lower == "runit" || lower == "runsvdir" {
			return fmt.Errorf("refusing to end %s, which the whole system depends on", proc.Name)
		}
	}

	sig := syscall.SIGTERM
	if force {
		sig = syscall.SIGKILL
	}

	switch err := syscall.Kill(pid, sig); err {
	case nil:
		return nil
	case syscall.EPERM:
		return fmt.Errorf("permission denied: process %d belongs to another user", pid)
	case syscall.ESRCH:
		return fmt.Errorf("process %d has already exited", pid)
	default:
		return err
	}
}
