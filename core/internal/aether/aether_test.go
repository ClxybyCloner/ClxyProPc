package aether

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// fakeExe writes an executable script named aether.exe into dir.
func fakeExe(t *testing.T, dir, script string) {
	t.Helper()
	path := filepath.Join(dir, "aether.exe")
	if err := os.WriteFile(path, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
}

const servingScript = `#!/bin/sh
echo '[2026-11-20T10:30:57Z INFO  aether] [+] socks5 server listening on 127.0.0.1:11819'
echo '[2026-11-20T10:30:58Z INFO  aether] relay 203.0.113.7:443 selected'
sleep 30
`

const exitingScript = `#!/bin/sh
echo 'Error: registration failed' >&2
exit 1
`

const silentScript = `#!/bin/sh
sleep 30
`

func TestStartMissingExe(t *testing.T) {
	dir := t.TempDir()
	p := NewProcess(dir, "")
	if err := p.Start(context.Background(), false, ""); err != ErrMissing {
		t.Fatalf("Start with no binary: got %v, want ErrMissing", err)
	}
	if p.IsServing() {
		t.Fatal("a missing binary must not report serving")
	}
}

func TestStartServingAndPeer(t *testing.T) {
	dir := t.TempDir()
	fakeExe(t, dir, servingScript)
	peerFile := filepath.Join(dir, "aether-peer.txt")
	p := NewProcess(dir, peerFile)
	if err := p.Start(context.Background(), false, ""); err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer p.Stop()
	if err := p.WaitServing(5 * time.Second); err != nil {
		t.Fatalf("WaitServing: %v", err)
	}
	if !p.IsServing() {
		t.Fatal("expected serving after the marker")
	}
	if addr := p.Addr(); !strings.HasPrefix(addr, "127.0.0.1:") {
		t.Fatalf("Addr = %q, want a loopback address", addr)
	}
	// The peer line follows the marker; the pump reads it a moment later.
	peerDeadline := time.Now().Add(2 * time.Second)
	for p.DiscoveredPeer() == "" && time.Now().Before(peerDeadline) {
		time.Sleep(50 * time.Millisecond)
	}
	if got := p.DiscoveredPeer(); got != "203.0.113.7:443" {
		t.Fatalf("DiscoveredPeer = %q, want 203.0.113.7:443", got)
	}
	// The peer is cached for the next run's fast reconnect.
	raw, err := os.ReadFile(peerFile)
	if err != nil {
		t.Fatalf("peer file not written: %v", err)
	}
	if strings.TrimSpace(string(raw)) != "203.0.113.7:443" {
		t.Fatalf("peer file = %q, want 203.0.113.7:443", raw)
	}
	if state, _ := p.State(); state != "serving" {
		t.Fatalf("State = %q, want serving", state)
	}
}

func TestExitFailsFast(t *testing.T) {
	dir := t.TempDir()
	fakeExe(t, dir, exitingScript)
	p := NewProcess(dir, "")
	if err := p.Start(context.Background(), false, ""); err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer p.Stop()
	start := time.Now()
	err := p.WaitServing(30 * time.Second)
	if err == nil {
		t.Fatal("WaitServing on an exited process: got nil, want an error")
	}
	if took := time.Since(start); took > 10*time.Second {
		t.Fatalf("WaitServing took %s for an exited process; it must fail fast", took)
	}
	if !strings.Contains(err.Error(), "aether exited") {
		t.Fatalf("error = %q, want it to report the exit", err)
	}
	if state, _ := p.State(); state != "error" {
		t.Fatalf("State = %q, want error", state)
	}
}

func TestWaitServingTimeout(t *testing.T) {
	dir := t.TempDir()
	fakeExe(t, dir, silentScript)
	p := NewProcess(dir, "")
	if err := p.Start(context.Background(), false, ""); err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer p.Stop()
	start := time.Now()
	err := p.WaitServing(500 * time.Millisecond)
	if err == nil || !strings.Contains(err.Error(), "timed out") {
		t.Fatalf("WaitServing on a silent process: got %v, want a timeout", err)
	}
	if took := time.Since(start); took > 5*time.Second {
		t.Fatalf("WaitServing took %s, want ~500ms", took)
	}
	if p.Terminal() {
		t.Fatal("a timeout must not mark the scan terminal: the supervisor may restage")
	}
}
