package psiphon

import (
	"context"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"testing"
)

func TestWriteConfigOverrides(t *testing.T) {
	dir := t.TempDir()
	p := NewProcess(dir)
	file, err := p.writeConfig("socks5://127.0.0.1:1080", "DE", 10829)
	if err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(file)
	if err != nil {
		t.Fatal(err)
	}
	var cfg map[string]any
	if err := json.Unmarshal(raw, &cfg); err != nil {
		t.Fatal(err)
	}
	want := map[string]string{
		"EgressRegion":      "DE",
		"UpstreamProxyURL":  "socks5://127.0.0.1:1080",
		"ClxySocksListen":   "127.0.0.1:10829",
		"ClxyDnsListen":     "",
		"ClientPlatform":    "Windows_CLXY",
		"NetworkID":         "clxy",
		"DataRootDirectory": filepath.Join(dir, "psiphon", "data"),
	}
	for k, v := range want {
		if cfg[k] != v {
			t.Errorf("config %s = %v, want %v", k, cfg[k], v)
		}
	}
	// The public base survives the overrides.
	if cfg["RemoteServerListUrl"] == nil || cfg["PropagationChannelId"] != "FFFFFFFFFFFFFFFF" {
		t.Errorf("base config lost: %+v", cfg)
	}
	if st, err := os.Stat(filepath.Join(dir, "psiphon", "data")); err != nil || !st.IsDir() {
		t.Errorf("data dir not created: %v", err)
	}
	if st, err := os.Stat(file); err != nil || st.Mode().Perm() != 0o600 {
		t.Errorf("config file perms = %v, want 0600", st.Mode())
	}
}

func TestStartRejectsBadRegion(t *testing.T) {
	p := NewProcess(t.TempDir())
	for _, region := range []string{"USA", "U1", "D-E"} {
		if err := p.Start(context.Background(), "socks5://127.0.0.1:1080", region); err == nil {
			t.Errorf("Start(region %q) accepted a bad region", region)
		}
	}
}

func TestHandleLineReadyAndError(t *testing.T) {
	p := &Process{readyCh: make(chan struct{})}
	p.handleLine(`{"event":"ready"}`, p.readyCh)
	if !p.IsRunning() {
		t.Error("ready event did not mark the exit serving")
	}
	select {
	case <-p.readyCh:
	default:
		t.Error("ready event did not close readyCh")
	}

	p2 := &Process{readyCh: make(chan struct{})}
	p2.handleLine(`{"event":"error","message":"tunnel failed"}`, p2.readyCh)
	if p2.lastErr == nil || p2.lastErr.Error() != "psiphon: tunnel failed" {
		t.Errorf("error event: lastErr = %v", p2.lastErr)
	}
	if !p2.terminal {
		t.Error("error event did not mark the exit terminal")
	}

	// A Psiphon notice is dropped, not treated as an error.
	p3 := &Process{readyCh: make(chan struct{})}
	p3.handleLine(`{"noticeType":"TunnelConnected"}`, p3.readyCh)
	if p3.IsRunning() || p3.lastErr != nil {
		t.Error("notice changed the exit state")
	}
}

func TestResolvePortPrefersAndFallsBack(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	free := ln.Addr().(*net.TCPAddr).Port
	ln.Close()
	if got, err := resolvePort(free); err != nil || got != free {
		t.Errorf("resolvePort(free) = %d, %v, want %d", got, err, free)
	}

	// Hold the preferred port: the resolver must pick another free one.
	ln, err = net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	busy := ln.Addr().(*net.TCPAddr).Port
	got, err := resolvePort(busy)
	if err != nil {
		t.Fatal(err)
	}
	if got == busy {
		t.Errorf("resolvePort(busy %d) returned the busy port", busy)
	}
	if c, err := net.Dial("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(got))); err == nil {
		c.Close()
		t.Errorf("resolvePort returned %d, which is already listening", got)
	}
}
