package aether

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sync"
	"time"

	"github.com/ClxybyCloner/ClxyProPc/core/internal/logx"
)

var peerRegex = regexp.MustCompile(`(?:\d{1,3}\.){3}\d{1,3}:\d{2,5}`)

const (
	ServingMarker = "socks5 server listening"
)

// Process manages the Quantum (Aether) native sidecar process.
type Process struct {
	mu            sync.Mutex
	cmd           *exec.Cmd
	running       bool
	serving       bool
	discoveredPeer string
	socksPort     int
	workDir       string
}

func NewProcess(workDir string, socksPort int) *Process {
	return &Process{
		workDir:   workDir,
		socksPort: socksPort,
	}
}

// Start launches aether.exe if found with the exact Android CLI contract.
func (p *Process) Start(ctx context.Context, useH3 bool, cachedPeer string) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.running {
		return nil
	}

	exePath := filepath.Join(p.workDir, "aether.exe")
	if _, err := os.Stat(exePath); os.IsNotExist(err) {
		// Also check core/aether.exe or beside executable
		self, _ := os.Executable()
		exePath = filepath.Join(filepath.Dir(self), "aether.exe")
		if _, err := os.Stat(exePath); os.IsNotExist(err) {
			logx.Info("aether.exe not found on disk; Quantum core will run in direct anycast mode")
			p.serving = true
			p.running = true
			return nil
		}
	}

	identityFile := filepath.Join(p.workDir, "identity.toml")
	args := []string{
		"--bind", fmt.Sprintf("127.0.0.1:%d", p.socksPort),
		"--config", identityFile,
		"--log-level", "info",
		"--scan", "balanced",
		"--masque",
	}

	if cachedPeer != "" {
		args = append(args, "--quick-reconnect", "--peer", cachedPeer, "--h2")
	} else if useH3 {
		args = append(args, "--h3")
	} else {
		args = append(args, "--h2")
	}

	cmd := exec.CommandContext(ctx, exePath, args...)
	cmd.Dir = p.workDir

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	cmd.Stderr = cmd.Stdout

	if err := cmd.Start(); err != nil {
		return err
	}

	p.cmd = cmd
	p.running = true
	p.serving = false

	go func() {
		scanner := bufio.NewScanner(stdout)
		for scanner.Scan() {
			line := scanner.Text()
			logx.Info("aether: %s", line)
			if peerRegex.MatchString(line) {
				match := peerRegex.FindString(line)
				p.mu.Lock()
				p.discoveredPeer = match
				p.mu.Unlock()
			}
			if line != "" && (line == ServingMarker || len(line) > 10) {
				p.mu.Lock()
				p.serving = true
				p.mu.Unlock()
			}
		}
		p.mu.Lock()
		p.running = false
		p.serving = false
		p.mu.Unlock()
	}()

	return nil
}

func (p *Process) Stop() error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.cmd != nil && p.cmd.Process != nil {
		_ = p.cmd.Process.Kill()
		p.cmd = nil
	}
	p.running = false
	p.serving = false
	return nil
}

func (p *Process) IsServing() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.serving
}

func (p *Process) DiscoveredPeer() string {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.discoveredPeer
}
