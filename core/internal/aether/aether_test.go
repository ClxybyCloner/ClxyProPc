package aether

import (
	"context"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// fakeExeOnce builds testdata/fakeaether once per package run (a Go
// binary, so the tests run on Windows CI too — a shell script named
// aether.exe does not execute there).
var (
	fakeExeOnce sync.Once
	fakeExePath string
	fakeExeErr  error
)

func builtFakeExe(t *testing.T) string {
	t.Helper()
	fakeExeOnce.Do(func() {
		dir, err := os.MkdirTemp("", "fakeaether")
		if err != nil {
			fakeExeErr = err
			return
		}
		fakeExePath = filepath.Join(dir, "fakeaether.exe")
		cmd := exec.Command("go", "build", "-o", fakeExePath, ".")
		cmd.Dir = filepath.Join("testdata", "fakeaether")
		if out, err := cmd.CombinedOutput(); err != nil {
			fakeExeErr = err
			fakeExePath = ""
			_ = out
		}
	})
	if fakeExeErr != nil {
		t.Fatalf("building the fake aether.exe: %v", fakeExeErr)
	}
	return fakeExePath
}

// fakeExe places the fake aether.exe into dir and selects its mode
// (serving, exiting, silent) for this test via the environment.
func fakeExe(t *testing.T, dir, mode string) {
	t.Helper()
	t.Setenv("FAKE_AETHER_MODE", mode)
	src, err := os.Open(builtFakeExe(t))
	if err != nil {
		t.Fatal(err)
	}
	defer src.Close()
	dst, err := os.OpenFile(filepath.Join(dir, "aether.exe"), os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o755)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := io.Copy(dst, src); err != nil {
		dst.Close()
		t.Fatal(err)
	}
	if err := dst.Close(); err != nil {
		t.Fatal(err)
	}
}

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
	fakeExe(t, dir, "serving")
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
	// The peer is cached for the next run's fast reconnect. Poll the
	// file: the pump writes it from its own goroutine, and a read
	// racing the write sees an empty file.
	raw := []byte(nil)
	fileDeadline := time.Now().Add(2 * time.Second)
	for {
		var err error
		raw, err = os.ReadFile(peerFile)
		if err == nil && strings.TrimSpace(string(raw)) == "203.0.113.7:443" {
			break
		}
		if time.Now().After(fileDeadline) {
			t.Fatalf("peer file = %q, want 203.0.113.7:443", raw)
		}
		time.Sleep(50 * time.Millisecond)
	}
	if state, _ := p.State(); state != "serving" {
		t.Fatalf("State = %q, want serving", state)
	}
}

func TestExitFailsFast(t *testing.T) {
	dir := t.TempDir()
	fakeExe(t, dir, "exiting")
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
	fakeExe(t, dir, "silent")
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
