//go:build live

package psiphon

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// TestLiveExit is an end-to-end test of the supervisor against the real
// wrapper binary (built for the host OS) and a working SOCKS5 upstream.
// It is NOT run by CI: it needs the network and a forwarder on
// 127.0.0.1:11080 (see /tmp/socks_fwd.py). Run it with:
//   go test ./internal/psiphon/ -tags live -run TestLiveExit -v -timeout 5m
// The wrapper binary must be at ../../../../tools-built/psiphon-linux
// (built with: go build -o <that path> . in tools/psiphon).
func TestLiveExit(t *testing.T) {
	bin := filepath.Join("..", "..", "..", "tools-built", "psiphon-linux")
	raw, err := os.ReadFile(bin)
	if err != nil {
		t.Skipf("live wrapper binary missing at %s (build it first): %v", bin, err)
	}
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "psiphon.exe"), raw, 0o700); err != nil {
		t.Fatal(err)
	}
	p := NewProcess(dir)
	ctx := context.Background()
	if err := p.Start(ctx, "socks5://127.0.0.1:11080", ""); err != nil {
		t.Fatalf("Start: %v", err)
	}
	t.Cleanup(func() { _ = p.Stop() })
	if err := p.WaitReady(150 * time.Second); err != nil {
		t.Fatalf("exit never became ready: %v", err)
	}
	if addr := p.Addr(); addr == "" || !p.IsRunning() {
		t.Fatalf("exit ready but Addr=%q IsRunning=%v", addr, p.IsRunning())
	}
	t.Logf("exit serving on %s", p.Addr())
}
