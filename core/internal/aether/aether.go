package aether

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/ClxybyCloner/ClxyProPc/core/internal/logx"
)

var peerRegex = regexp.MustCompile(`(?:\d{1,3}\.){3}\d{1,3}:\d{2,5}`)

// ServingMarker is the line aether prints once its SOCKS5 server accepts
// connections (matched as a substring: the line carries the bind address
// after it). Same marker as Android's AetherCore.
const ServingMarker = "socks5 server listening"

// ErrMissing is returned when aether.exe is not on disk: Quantum cannot
// run, and the caller must fail honestly instead of pretending to serve.
var ErrMissing = errors.New("aether.exe is not installed")

// Process manages the Quantum (Aether) native sidecar process. It is the
// Go port of Android's AetherCore runStage/pumpLogs: same CLI contract,
// same serving marker, same working-peer caching.
type Process struct {
	mu  sync.Mutex
	cmd *exec.Cmd
	// cancel ends the process's context (kills it when it outlives Stop).
	cancel  context.CancelFunc
	running bool
	serving bool
	// stage is the scan the process runs: "quick", "h2" or "h3".
	stage string
	// lastErr is why the process ended, or the last stage's timeout.
	lastErr error
	// terminal is set once the scan is over for good (serving, or an
	// error no restage can fix, such as a registration failure).
	terminal       bool
	discoveredPeer string
	socksPort      int
	workDir        string
	peerFile       string
	// servingCh closes when the SOCKS server starts listening; done closes
	// when the process exits. Both are recreated on every Start.
	servingCh chan struct{}
	done      chan struct{}
}

// NewProcess builds a sidecar whose identity lives in workDir
// (identity.toml) and whose working peer is cached in peerFile ("" to
// disable caching). The SOCKS port is picked free at Start.
func NewProcess(workDir, peerFile string) *Process {
	return &Process{workDir: workDir, peerFile: peerFile}
}

// Addr is the sidecar's SOCKS5 address ("" before Start).
func (p *Process) Addr() string {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.socksPort == 0 {
		return ""
	}
	return fmt.Sprintf("127.0.0.1:%d", p.socksPort)
}

// IsServing reports whether the sidecar's SOCKS server accepts connections.
func (p *Process) IsServing() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.serving
}

// DiscoveredPeer is the working relay endpoint found in the sidecar's logs
// ("" if none yet).
func (p *Process) DiscoveredPeer() string {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.discoveredPeer
}

// Stage is the scan the sidecar runs ("quick", "h2" or "h3").
func (p *Process) Stage() string {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.stage
}

// State reports the sidecar for the status view: "starting", "serving" or
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
	switch p.stage {
	case "quick":
		return "starting", "Reconnecting to the last working relay…"
	case "h3":
		return "starting", "Scanning for relays (HTTP/3)…"
	default:
		return "starting", "Scanning for relays (HTTP/2)…"
	}
}

// Start launches aether.exe with the exact Android CLI contract. useH3
// selects the HTTP/3 scan; cachedPeer ("" for none) selects the fast
// reconnect to the last working relay. A missing binary is an error:
// a Quantum engine without its binary must fail, never fake-serve.
func (p *Process) Start(ctx context.Context, useH3 bool, cachedPeer string) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.running {
		return nil
	}

	exePath, err := p.findExe()
	if err != nil {
		return err
	}
	port, err := freePort()
	if err != nil {
		return fmt.Errorf("no free loopback port for the Quantum engine: %w", err)
	}

	identityFile := filepath.Join(p.workDir, "identity.toml")
	args := []string{
		"--bind", fmt.Sprintf("127.0.0.1:%d", port),
		"--config", identityFile,
		"--log-level", "info",
		"--scan", "balanced",
		"--masque",
	}
	stage := "h2"
	if cachedPeer != "" {
		args = append(args, "--quick-reconnect", "--peer", cachedPeer, "--h2")
		stage = "quick"
	} else if useH3 {
		args = append(args, "--h3")
		stage = "h3"
	} else {
		args = append(args, "--h2")
	}

	runCtx, cancel := context.WithCancel(ctx)
	cmd := exec.CommandContext(runCtx, exePath, args...)
	cmd.Dir = p.workDir
	// On Windows the sidecar runs without a console window (see
	// hide_windows.go): without it every scan pops a black window.
	hideConsole(cmd)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		cancel()
		return err
	}
	cmd.Stderr = cmd.Stdout
	if err := cmd.Start(); err != nil {
		cancel()
		return fmt.Errorf("starting aether.exe failed: %w", err)
	}

	p.cmd = cmd
	p.cancel = cancel
	p.running = true
	p.serving = false
	p.stage = stage
	p.lastErr = nil
	p.terminal = false
	p.socksPort = port
	p.servingCh = make(chan struct{})
	p.done = make(chan struct{})
	logx.Info("quantum engine started stage=%s socks=127.0.0.1:%d", stage, port)

	go p.pumpLogs(stdout)
	return nil
}

// pumpLogs reads the sidecar's output until it ends, then reaps the
// process and records why it ended.
func (p *Process) pumpLogs(stdout io.Reader) {
	// Capture this start's channels and command up front: a restage
	// replaces them, and a late line from the old process must not close
	// the new stage's channels or mark the new process dead.
	p.mu.Lock()
	servingCh, done, cmd := p.servingCh, p.done, p.cmd
	p.mu.Unlock()
	scanner := bufio.NewScanner(stdout)
	for scanner.Scan() {
		line := scanner.Text()
		logx.Info("aether: %s", line)
		if strings.Contains(strings.ToLower(line), ServingMarker) {
			p.mu.Lock()
			if !p.serving {
				p.serving = true
				close(servingCh)
			}
			p.mu.Unlock()
		}
		if match := peerRegex.FindString(line); match != "" {
			if !strings.HasPrefix(match, "127.0.0.1") && !strings.HasPrefix(match, "0.0.0.0") {
				// Persist first, then publish: DiscoveredPeer
				// non-empty means the peer is already cached
				// for the next run's fast reconnect.
				p.savePeer(match)
				p.mu.Lock()
				p.discoveredPeer = match
				p.mu.Unlock()
			}
		}
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
			p.lastErr = fmt.Errorf("aether exited: %w", waitErr)
		}
		// An exit is terminal for this start: the supervisor decides
		// whether another stage is worth trying; a bare wait must not
		// hang.
		p.terminal = true
	}
	p.mu.Unlock()
	close(done)
}

// WaitServing waits until the sidecar serves, exits, or the timeout ends.
// A process exit returns the exit error at once (a registration failure,
// for example, will not heal by waiting).
func (p *Process) WaitServing(timeout time.Duration) error {
	p.mu.Lock()
	servingCh, done := p.servingCh, p.done
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
	case <-servingCh:
		return nil
	case <-done:
		return p.exitError()
	case <-timer.C:
		return fmt.Errorf("quantum scan timed out after %s", timeout.Round(time.Second))
	}
}

// MarkTimeout records a stage timeout as the last error (the process keeps
// running until the supervisor restages it).
func (p *Process) MarkTimeout(timeout time.Duration) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.lastErr = fmt.Errorf("quantum scan timed out after %s", timeout.Round(time.Second))
}

// MarkTerminal records a final error: no further stage will be tried.
func (p *Process) MarkTerminal(err error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.lastErr = err
	p.terminal = true
}

// Terminal reports whether the scan is over for good (serving, or a final
// error). The supervisor stops restaging then.
func (p *Process) Terminal() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.terminal || p.serving
}

func (p *Process) exitError() error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.lastErr != nil {
		return p.lastErr
	}
	return errors.New("aether exited before serving")
}

// Stop kills the sidecar (if any) and waits briefly for it to end.
func (p *Process) Stop() error {
	p.mu.Lock()
	cmd, cancel := p.cmd, p.cancel
	done := p.done
	p.cmd = nil
	p.cancel = nil
	p.running = false
	p.serving = false
	p.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	if cmd != nil && cmd.Process != nil {
		_ = cmd.Process.Kill()
	}
	if done != nil {
		select {
		case <-done:
		case <-time.After(3 * time.Second):
		}
	}
	return nil
}

func (p *Process) findExe() (string, error) {
	exePath := filepath.Join(p.workDir, "aether.exe")
	if _, err := os.Stat(exePath); err == nil {
		return exePath, nil
	}
	self, _ := os.Executable()
	exePath = filepath.Join(filepath.Dir(self), "aether.exe")
	if _, err := os.Stat(exePath); err == nil {
		return exePath, nil
	}
	return "", ErrMissing
}

// freePort reserves a loopback port by listening on :0 and closing it;
// aether binds it right after (a lost race surfaces as a bind error and a
// failed stage, not a silent wrong port).
func freePort() (int, error) {
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

func (p *Process) savePeer(peer string) {
	if p.peerFile == "" {
		return
	}
	if err := os.MkdirAll(filepath.Dir(p.peerFile), 0o700); err != nil {
		return
	}
	_ = os.WriteFile(p.peerFile, []byte(peer), 0o600)
}
