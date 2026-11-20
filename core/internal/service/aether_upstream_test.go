package service

import (
	"context"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/ClxybyCloner/ClxyProPc/core/internal/aether"
)

// stubSocks5 serves no-auth SOCKS5 CONNECT to a fixed target: it stands
// in for the sidecar's SOCKS server.
func stubSocks5(t *testing.T, target string) string {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go handleStubSocks(c, target)
		}
	}()
	return ln.Addr().String()
}

func handleStubSocks(c net.Conn, target string) {
	defer c.Close()
	buf := make([]byte, 512)
	// Greeting: VER, NMETHODS, METHODS.
	if _, err := io.ReadFull(c, buf[:2]); err != nil {
		return
	}
	n := int(buf[1])
	if _, err := io.ReadFull(c, buf[:n]); err != nil {
		return
	}
	if _, err := c.Write([]byte{0x05, 0x00}); err != nil {
		return
	}
	// Request: VER, CMD, RSV, ATYP, DST.ADDR, DST.PORT. Accept any
	// CONNECT and open the fixed target instead.
	if _, err := io.ReadFull(c, buf[:4]); err != nil {
		return
	}
	if buf[1] != 0x01 {
		return
	}
	switch buf[3] {
	case 0x01: // IPv4
		if _, err := io.ReadFull(c, buf[:6]); err != nil {
			return
		}
	case 0x03: // domain
		if _, err := io.ReadFull(c, buf[:1]); err != nil {
			return
		}
		if _, err := io.ReadFull(c, buf[:int(buf[0])+2]); err != nil {
			return
		}
	case 0x04: // IPv6
		if _, err := io.ReadFull(c, buf[:18]); err != nil {
			return
		}
	default:
		return
	}
	up, err := net.Dial("tcp", target)
	if err != nil {
		c.Write([]byte{0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0})
		return
	}
	defer up.Close()
	if _, err := c.Write([]byte{0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0}); err != nil {
		return
	}
	go io.Copy(up, c)
	io.Copy(c, up)
}

func echoServer(t *testing.T) string {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go func() {
				defer c.Close()
				io.Copy(c, c)
			}()
		}
	}()
	return ln.Addr().String()
}

func TestDialThroughSocks(t *testing.T) {
	echo := echoServer(t)
	socks := stubSocks5(t, echo)
	conn, err := dialThroughSocks(socks, echo)
	if err != nil {
		t.Fatalf("dialThroughSocks: %v", err)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := conn.Write([]byte("hello")); err != nil {
		t.Fatalf("write: %v", err)
	}
	buf := make([]byte, 5)
	if _, err := io.ReadFull(conn, buf); err != nil {
		t.Fatalf("read: %v", err)
	}
	if string(buf) != "hello" {
		t.Fatalf("echo = %q, want hello", buf)
	}
}

func TestReadCachedPeer(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "aether-peer.txt")
	if got := readCachedPeer(path); got != "" {
		t.Fatalf("missing file: got %q, want empty", got)
	}
	os.WriteFile(path, []byte("not a peer"), 0o600)
	if got := readCachedPeer(path); got != "" {
		t.Fatalf("garbage file: got %q, want empty", got)
	}
	os.WriteFile(path, []byte("203.0.113.7:443\n"), 0o600)
	if got := readCachedPeer(path); got != "203.0.113.7:443" {
		t.Fatalf("got %q, want 203.0.113.7:443", got)
	}
}

func fakeAetherExe(t *testing.T, dir, script string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, "aether.exe"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
}

const supervisorServingScript = `#!/bin/sh
echo '[INFO] [+] socks5 server listening on 127.0.0.1:11819'
sleep 30
`

const supervisorExitingScript = `#!/bin/sh
echo 'Error: registration failed' >&2
exit 1
`

const supervisorSilentScript = `#!/bin/sh
sleep 30
`

func TestSuperviseAetherServing(t *testing.T) {
	dir := t.TempDir()
	fakeAetherExe(t, dir, supervisorServingScript)
	e := &proxyEngine{aether: aether.NewProcess(dir, "")}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	defer e.aether.Stop()
	go e.superviseAether(ctx, "")
	if err := e.aetherWait(10 * time.Second); err != nil {
		t.Fatalf("aetherWait: %v", err)
	}
	if st := e.aetherStatus(); st == nil || st.State != "serving" {
		t.Fatalf("aetherStatus = %+v, want serving", st)
	}
}

func TestSuperviseAetherExitIsTerminal(t *testing.T) {
	dir := t.TempDir()
	fakeAetherExe(t, dir, supervisorExitingScript)
	e := &proxyEngine{aether: aether.NewProcess(dir, "")}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	defer e.aether.Stop()
	go e.superviseAether(ctx, "")
	deadline := time.Now().Add(10 * time.Second)
	for {
		if st := e.aetherStatus(); st != nil && st.State == "error" {
			if !strings.Contains(st.Message, "aether exited") {
				t.Fatalf("message = %q, want it to report the exit", st.Message)
			}
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("no terminal error within 10s; status = %+v", e.aetherStatus())
		}
		time.Sleep(100 * time.Millisecond)
	}
}

func TestSuperviseAetherTimeoutRestages(t *testing.T) {
	// Shorten the budgets so the test runs in ~1s.
	oldH2, oldH3 := aetherH2Timeout, aetherH3Timeout
	aetherH2Timeout, aetherH3Timeout = 300*time.Millisecond, 300*time.Millisecond
	defer func() { aetherH2Timeout, aetherH3Timeout = oldH2, oldH3 }()

	dir := t.TempDir()
	fakeAetherExe(t, dir, supervisorSilentScript)
	e := &proxyEngine{aether: aether.NewProcess(dir, "")}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	defer e.aether.Stop()
	go e.superviseAether(ctx, "")
	deadline := time.Now().Add(10 * time.Second)
	for {
		if st := e.aetherStatus(); st != nil && st.State == "error" {
			if !strings.Contains(st.Message, "no working relay") {
				t.Fatalf("message = %q, want no-working-relay", st.Message)
			}
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("no terminal error within 10s; status = %+v", e.aetherStatus())
		}
		time.Sleep(100 * time.Millisecond)
	}
}
