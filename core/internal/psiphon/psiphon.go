// Package psiphon supervises the Psiphon exit sidecar behind Quantum
// (CLXY Quantum = MASQUE transport, Psiphon egress). It mirrors
// internal/aether's Process and Android's PsiphonExit: the wrapper binary
// (tools/psiphon, a Go program around psiphon-tunnel-core, GPLv3) takes a
// -config JSON file, serves a local SOCKS5 proxy, and prints one JSON
// object per line on stdout: {"event":"ready"} once the first tunnel is
// up, {"event":"error","message":...} on a fatal failure. It exits when
// its stdin closes.
//
// DNS needs no special handling here, unlike Android: the core already
// answers DNS with DNS-over-HTTPS through the tunnel opener (TCP), so
// once the opener switches to the exit SOCKS, DNS flows through the exit
// by TCP on its own. The wrapper's DNS listener is therefore left off
// (ClxyDnsListen is empty), and the exit's UDP (udpgw) is never used —
// it is dead on the public network (proven live 2026-11-27: TCP through
// the exit works, every UDP datagram vanishes).
package psiphon

import (
	"bufio"
	"context"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/ClxybyCloner/ClxyProPc/core/internal/logx"
)

// baseConfig is the public Psiphon config (BPB-VPN's public values,
// verbatim); the supervisor overrides the runtime fields at Start.
var (
	//go:embed psiphon_config.json
	baseConfig []byte
)

// StartTimeout bounds one exit start waiting for the wrapper's ready
// event (Android's PsiphonExit.START_TIMEOUT_MS).
const StartTimeout = 90 * time.Second

// grace bounds Stop waiting for the wrapper to exit after its stdin
// closes before it is killed.
const grace = 3 * time.Second

// PreferredSocksPort is the exit SOCKS port (Android's
// PREFERRED_EXIT_SOCKS); a busy port falls back to a free one.
const PreferredSocksPort = 10829

// ErrMissing is returned when no psiphon.exe is found.
var ErrMissing = errors.New("psiphon.exe not found")

// Process supervises one psiphon.exe run.
type Process struct {
	workDir string
	mu      sync.Mutex
	cmd     *exec.Cmd
	cancel  context.CancelFunc
	stdin   io.WriteCloser
	running bool
	serving bool
	// readyCh closes when the wrapper reports ready; done closes when
	// the process has been reaped.
	readyCh   chan struct{}
	done      chan struct{}
	socksPort int
	lastErr   error
	terminal  bool
	region    string
}

// NewProcess builds a supervisor whose config and data live under
// workDir/psiphon (workDir is the daemon's data directory).
func NewProcess(workDir string) *Process {
	return &Process{workDir: workDir}
}

// Addr is the exit's SOCKS5 address ("" before Start).
func (p *Process) Addr() string {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.socksPort == 0 {
		return ""
	}
	return fmt.Sprintf("127.0.0.1:%d", p.socksPort)
}

// IsRunning reports whether the exit reported ready and has not stopped.
func (p *Process) IsRunning() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.serving
}

// Region is the egress region this run was started with ("" = auto).
func (p *Process) Region() string {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.region
}

// State reports the exit for the status view: "starting", "serving" or
// "error", with a human message for the error case.
func (p *Process) State() (state, message string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.serving {
		return "serving", ""
	}
	if p.terminal && p.lastErr != nil {
		return "error", p.lastErr.Error()
	}
	return "starting", "Starting the Psiphon exit…"
}

// Start launches psiphon.exe with the runtime config. It returns once
// the process is up; WaitReady waits for the ready event. A missing
// binary is an error: a Quantum engine with the exit on and no binary
// must fail, never fake-serve.
func (p *Process) Start(ctx context.Context, upstreamSocks, region string) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.running {
		return nil
	}
	region = strings.ToUpper(strings.TrimSpace(region))
	if region != "" && (len(region) != 2 || !isLetters(region)) {
		return fmt.Errorf("psiphon region %q is not a two-letter country code", region)
	}

	exePath, err := p.findExe()
	if err != nil {
		return err
	}
	port, err := resolvePort(PreferredSocksPort)
	if err != nil {
		return fmt.Errorf("no free loopback port for the Psiphon exit: %w", err)
	}
	configFile, err := p.writeConfig(upstreamSocks, region, port)
	if err != nil {
		return err
	}

	runCtx, cancel := context.WithCancel(ctx)
	cmd := exec.CommandContext(runCtx, exePath, "-config", configFile)
	cmd.Dir = filepath.Join(p.workDir, "psiphon")
	// On Windows the sidecar runs without a console window (see
	// hide_windows.go): without it every connect pops a black window.
	hideConsole(cmd)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		cancel()
		return err
	}
	stdin, err := cmd.StdinPipe()
	if err != nil {
		cancel()
		return err
	}
	cmd.Stderr = cmd.Stdout
	if err := cmd.Start(); err != nil {
		cancel()
		return fmt.Errorf("starting psiphon.exe failed: %w", err)
	}

	p.cmd = cmd
	p.cancel = cancel
	p.stdin = stdin
	p.running = true
	p.serving = false
	p.region = region
	p.lastErr = nil
	p.terminal = false
	p.socksPort = port
	p.readyCh = make(chan struct{})
	p.done = make(chan struct{})
	logx.Info("psiphon exit started region=%s socks=127.0.0.1:%d", regionOrAuto(region), port)

	go p.pumpLogs(stdout)
	return nil
}

// WaitReady waits until the exit reports ready, exits, or the timeout
// ends. A process exit returns the exit error at once.
func (p *Process) WaitReady(timeout time.Duration) error {
	p.mu.Lock()
	readyCh, done := p.readyCh, p.done
	serving, running := p.serving, p.running
	p.mu.Unlock()
	if serving {
		return nil
	}
	if !running {
		return p.exitError()
	}
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	select {
	case <-readyCh:
		return nil
	case <-done:
		return p.exitError()
	case <-timer.C:
		return fmt.Errorf("psiphon exit did not come up in %s", timeout.Round(time.Second))
	}
}

// Stop stops the exit: close stdin (the wrapper exits on its own),
// wait for it briefly, then kill it if it lingers.
func (p *Process) Stop() error {
	p.mu.Lock()
	cmd, cancel, stdin := p.cmd, p.cancel, p.stdin
	done := p.done
	p.cmd = nil
	p.cancel = nil
	p.stdin = nil
	p.running = false
	p.serving = false
	p.mu.Unlock()
	if stdin != nil {
		_ = stdin.Close()
	}
	if done != nil {
		select {
		case <-done:
			if cancel != nil {
				cancel()
			}
			return nil
		case <-time.After(grace):
		}
	}
	if cancel != nil {
		cancel()
	}
	if cmd != nil && cmd.Process != nil {
		_ = cmd.Process.Kill()
	}
	if done != nil {
		select {
		case <-done:
		case <-time.After(grace):
		}
	}
	return nil
}

// pumpLogs reads the wrapper's output until it ends, then reaps the
// process and records why it ended. Only error-looking lines reach the
// log: Psiphon notices are chatty and routine.
func (p *Process) pumpLogs(stdout io.Reader) {
	p.mu.Lock()
	readyCh, done, cmd := p.readyCh, p.done, p.cmd
	p.mu.Unlock()
	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		p.handleLine(line, readyCh)
	}
	var waitErr error
	if cmd != nil {
		waitErr = cmd.Wait()
	}
	p.mu.Lock()
	if p.cmd == cmd {
		p.running = false
		p.serving = false
		if waitErr != nil && p.lastErr == nil {
			p.lastErr = fmt.Errorf("psiphon exited: %w", waitErr)
		}
		p.terminal = true
	}
	p.mu.Unlock()
	close(done)
}

// handleLine parses one wrapper output line: a ready event marks the
// exit serving, an error event records the failure, anything else is
// logged only when it looks like a failure.
func (p *Process) handleLine(line string, readyCh chan struct{}) {
	var event struct {
		Event   string `json:"event"`
		Message string `json:"message"`
	}
	if err := json.Unmarshal([]byte(line), &event); err == nil && event.Event != "" {
		switch event.Event {
		case "ready":
			p.mu.Lock()
			if !p.serving {
				p.serving = true
				close(readyCh)
			}
			p.mu.Unlock()
			logx.Info("psiphon: exit ready")
			return
		case "error":
			msg := strings.TrimSpace(event.Message)
			if msg == "" {
				msg = line
			}
			p.mu.Lock()
			if p.lastErr == nil {
				p.lastErr = fmt.Errorf("psiphon: %s", msg)
			}
			p.terminal = true
			p.mu.Unlock()
			logx.Info("psiphon: error: %s", msg)
			return
		}
		// Other JSON events are Psiphon notices; drop them.
		return
	}
	if strings.Contains(strings.ToLower(line), "error") ||
		strings.Contains(strings.ToLower(line), "failed") {
		logx.Info("psiphon: %s", line)
	}
}

// writeConfig writes the runtime config: the embedded public base with
// the runtime fields overridden. The DNS listener is left empty: the
// core answers DNS with DNS-over-HTTPS through the tunnel opener, so it
// never needs the wrapper's DNS.
func (p *Process) writeConfig(upstreamSocks, region string, port int) (string, error) {
	var cfg map[string]any
	if err := json.Unmarshal(baseConfig, &cfg); err != nil {
		return "", fmt.Errorf("psiphon base config: %w", err)
	}
	dir := filepath.Join(p.workDir, "psiphon")
	dataDir := filepath.Join(dir, "data")
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		return "", err
	}
	cfg["DataRootDirectory"] = dataDir
	cfg["EgressRegion"] = region
	cfg["UpstreamProxyURL"] = upstreamSocks
	cfg["ClxySocksListen"] = fmt.Sprintf("127.0.0.1:%d", port)
	cfg["ClxyDnsListen"] = ""
	cfg["ClientPlatform"] = "Windows_CLXY"
	cfg["NetworkID"] = "clxy"
	raw, err := json.Marshal(cfg)
	if err != nil {
		return "", err
	}
	file := filepath.Join(dir, "config.json")
	if err := os.WriteFile(file, raw, 0o600); err != nil {
		return "", err
	}
	return file, nil
}

func (p *Process) exitError() error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.lastErr != nil {
		return p.lastErr
	}
	return errors.New("psiphon exited before ready")
}

func (p *Process) findExe() (string, error) {
	exePath := filepath.Join(p.workDir, "psiphon.exe")
	if _, err := os.Stat(exePath); err == nil {
		return exePath, nil
	}
	self, _ := os.Executable()
	exePath = filepath.Join(filepath.Dir(self), "psiphon.exe")
	if _, err := os.Stat(exePath); err == nil {
		return exePath, nil
	}
	return "", ErrMissing
}

// resolvePort reserves the preferred loopback port, falling back to any
// free one when it is busy (a lost race surfaces as a bind error and a
// failed start, not a silent wrong port).
func resolvePort(preferred int) (int, error) {
	if ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", preferred)); err == nil {
		defer ln.Close()
		return preferred, nil
	}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	defer ln.Close()
	addr, ok := ln.Addr().(*net.TCPAddr)
	if !ok {
		return 0, errors.New("unexpected listener address")
	}
	return addr.Port, nil
}

func isLetters(s string) bool {
	for _, r := range s {
		if r < 'A' || r > 'Z' {
			return false
		}
	}
	return len(s) > 0
}

func regionOrAuto(region string) string {
	if region == "" {
		return "auto"
	}
	return region
}
