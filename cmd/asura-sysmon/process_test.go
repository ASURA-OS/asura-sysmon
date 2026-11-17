package main

import (
	"os"
	"strings"
	"testing"
	"time"
)

func TestListProcesses(t *testing.T) {
	procs, err := ListProcesses("mem", 10)
	if err != nil {
		t.Fatalf("ListProcesses failed: %v", err)
	}
	if len(procs) == 0 {
		t.Fatalf("expected active processes, got 0")
	}

	myPID := os.Getpid()
	var foundMine bool
	for _, p := range procs {
		if p.PID == myPID {
			foundMine = true
			break
		}
	}

	// Also test without limit to find myPID
	allProcs, err := ListProcesses("pid", 0)
	if err != nil {
		t.Fatalf("ListProcesses all failed: %v", err)
	}
	for _, p := range allProcs {
		if p.PID == myPID {
			foundMine = true
			if p.User == "" {
				t.Errorf("expected non-empty user for PID %d", myPID)
			}
			break
		}
	}
	if !foundMine {
		t.Fatalf("current test process %d not found in /proc", myPID)
	}
}

func TestKillProcessSafety(t *testing.T) {
	if err := KillProcess(1, false); err == nil {
		t.Fatalf("expected error refusing to kill PID 1")
	}
	if err := KillProcess(0, false); err == nil {
		t.Fatalf("expected error refusing to kill PID 0")
	}
}

func TestProcessCPUPercent(t *testing.T) {
	cases := []struct {
		name           string
		p1, p2, t1, t2 uint64
		want           float64
	}{
		{"idle process", 50, 50, 1000, 1800, 0},
		{"one of eight cores busy", 0, 100, 0, 800, 12.5},
		{"whole machine", 0, 800, 0, 800, 100},
		{"total did not move", 0, 10, 500, 500, 0},
		{"counter went backwards (pid reused)", 90, 10, 0, 800, 0},
		{"clamped above 100", 0, 900, 0, 800, 100},
	}
	for _, c := range cases {
		if got := processCPUPercent(c.p1, c.p2, c.t1, c.t2); got != c.want {
			t.Errorf("%s: got %v, want %v", c.name, got, c.want)
		}
	}
}

// A process spinning on a CPU must show up with non-zero usage, and sorting
// by cpu must put it ahead of an idle one.
func TestListProcessesSampledMeasuresCPU(t *testing.T) {
	stop := make(chan struct{})
	go func() {
		x := 0
		for {
			select {
			case <-stop:
				return
			default:
				x++
			}
		}
	}()
	defer close(stop)

	procs, err := ListProcessesSampled("cpu", 0, 300*time.Millisecond)
	if err != nil {
		t.Fatalf("ListProcessesSampled: %v", err)
	}
	me := os.Getpid()
	for i, p := range procs {
		if p.PID != me {
			continue
		}
		if p.CPUPercent <= 0 {
			t.Fatalf("busy test process %d reported %v%% CPU", me, p.CPUPercent)
		}
		for _, q := range procs[:i] {
			if q.CPUPercent < p.CPUPercent {
				t.Fatalf("sort=cpu: %d (%v%%) is ahead of %d (%v%%)", q.PID, q.CPUPercent, me, p.CPUPercent)
			}
		}
		return
	}
	t.Fatalf("test process %d not listed", me)
}

func TestKillProcessExplainsMissingProcess(t *testing.T) {
	// PID values near the kernel maximum are almost never in use.
	err := KillProcess(4194301, false)
	if err == nil {
		t.Skip("PID 4194301 exists on this machine")
	}
	if !strings.Contains(err.Error(), "already exited") {
		t.Fatalf("got %q, want an 'already exited' explanation", err)
	}
}

func TestResolveProcessName(t *testing.T) {
	cases := []struct {
		comm     string
		cmdline  string
		expected string
	}{
		{"quickshell", "quickshell -p /usr/share/asura/shell --no-color", "quickshell (shell)"},
		{"quickshell", "quickshell -p /usr/share/asura/sysmon/sysmon.qml", "quickshell (sysmon)"},
		{"quickshell", "quickshell --path=/usr/share/asura/shell/hub.qml", "quickshell (hub)"},
		{"xdg-desktop-por", "/usr/libexec/xdg-desktop-portal-hyprland", "xdg-desktop-portal-hyprland"},
		{"xdg-desktop-por", "/usr/libexec/xdg-desktop-portal", "xdg-desktop-portal"},
		{"python3", "python3 /usr/bin/asura-doctor", "python3 (asura-doctor)"},
		{"python3", "python3 -m http.server 8000", "python3 (http.server)"},
		{"python3", "python3 -c import json, sys", "python3"},
		{"node", "node -e console.log(1)", "node"},
		{"node", "node --max-old-space-size=4096 /opt/app/server.js", "node (server.js)"},
		{"bash", "bash", "bash"},
		{"kthreadd", "", "kthreadd"},
	}

	for _, tc := range cases {
		got := resolveProcessName(tc.comm, tc.cmdline)
		if got != tc.expected {
			t.Errorf("resolveProcessName(%q, %q) = %q; want %q", tc.comm, tc.cmdline, got, tc.expected)
		}
	}
}
