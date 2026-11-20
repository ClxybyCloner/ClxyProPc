package service

import (
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"strings"
	"time"

	"github.com/ClxybyCloner/ClxyProPc/core/internal/logx"
	"github.com/ClxybyCloner/ClxyProPc/core/internal/tun"
)

// Scan budgets for the Quantum engine's stages, in the order Android's
// AetherCore runs them: fast reconnect to the last working relay, then a
// full HTTP/2 scan, then HTTP/3. The whole scan (12 + 75 + 75 = 162s)
// fits the app's 180s wait and the daemon's 4-minute Quantum connect
// window.
var (
	aetherQuickTimeout = 12 * time.Second
	aetherH2Timeout    = 75 * time.Second
	aetherH3Timeout    = 75 * time.Second
	// aetherOpenTimeout bounds one tunnel open waiting for the sidecar
	// to serve. The app waits for serving before probing, so this is a
	// backstop for other traffic, not the connect path.
	aetherOpenTimeout = 120 * time.Second
)

// aetherUpstream opens tunnels through the Quantum sidecar's SOCKS5 proxy
// instead of Mozilla sessions. It implements proxy's tunnelOpener
// (OpenTunnel only). UDP is not carried: the opener does not implement
// udpTunnelOpener, so UDP fails fast with ErrUDPPort and clients fall
// back to TCP (browsers fall back from QUIC; DNS goes over the DoH
// exchange, which uses OpenTunnel).
type aetherUpstream struct {
	engine *proxyEngine
}

func (u *aetherUpstream) OpenTunnel(authority string) (net.Conn, error) {
	if err := u.engine.aetherWait(aetherOpenTimeout); err != nil {
		return nil, err
	}
	addr := u.engine.aether.Addr()
	if addr == "" {
		return nil, errors.New("quantum engine has no SOCKS address")
	}
	// The address is read now, not cached at engine start: a restage
	// rebinds the sidecar on a new port.
	return dialThroughSocks(addr, authority)
}

// dialThroughSocks opens authority through the SOCKS5 proxy at addr
// (no login: the sidecar listens on loopback only).
func dialThroughSocks(addr, authority string) (net.Conn, error) {
	dial, err := tun.SOCKS5Dialer(addr, "", "")
	if err != nil {
		return nil, err
	}
	return dial(context.Background(), authority)
}

// aetherWait waits until the sidecar serves, the scan fails for good, or
// the timeout ends.
func (e *proxyEngine) aetherWait(timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for {
		if e.aether == nil {
			return errors.New("no quantum engine")
		}
		if e.aether.IsServing() {
			return nil
		}
		e.aetherMu.Lock()
		err := e.aetherErr
		e.aetherMu.Unlock()
		if err != nil {
			return err
		}
		if time.Now().After(deadline) {
			return errors.New("quantum engine did not start in time")
		}
		time.Sleep(200 * time.Millisecond)
	}
}

// aetherStatus reports the Quantum engine for the status view.
func (e *proxyEngine) aetherStatus() *AetherStatus {
	if e.aether == nil {
		return nil
	}
	e.aetherMu.Lock()
	err := e.aetherErr
	e.aetherMu.Unlock()
	if err != nil {
		return &AetherStatus{State: "error", Message: err.Error()}
	}
	state, message := e.aether.State()
	return &AetherStatus{State: state, Message: message}
}

func (e *proxyEngine) setAetherErr(err error) {
	e.aetherMu.Lock()
	defer e.aetherMu.Unlock()
	if e.aetherErr == nil {
		e.aetherErr = err
	}
}

// superviseAether runs the sidecar's scan stages for the engine's life:
// fast reconnect to the cached peer, then HTTP/2, then HTTP/3. A stage
// that times out restages with the next scan; a stage whose process exits
// (registration failure, bind error, crash) ends the scan — the same
// binary would fail the same way again.
func (e *proxyEngine) superviseAether(ctx context.Context, cachedPeer string) {
	proc := e.aether
	type stage struct {
		useH3  bool
		peer   string
		budget time.Duration
	}
	stages := []stage{{budget: aetherH2Timeout}}
	if cachedPeer != "" {
		stages = []stage{
			{peer: cachedPeer, budget: aetherQuickTimeout},
			{budget: aetherH2Timeout},
			{useH3: true, budget: aetherH3Timeout},
		}
	} else {
		stages = append(stages, stage{useH3: true, budget: aetherH3Timeout})
	}

	for i, st := range stages {
		select {
		case <-ctx.Done():
			return
		default:
		}
		if err := proc.Start(ctx, st.useH3, st.peer); err != nil {
			e.setAetherErr(err)
			return
		}
		err := proc.WaitServing(st.budget)
		if err == nil || proc.IsServing() {
			logx.Info("quantum engine serving stage=%s", proc.Stage())
			return
		}
		if proc.Terminal() {
			// The process exited: registration refused, bind failed,
			// or a crash. Restaging will not help.
			e.setAetherErr(err)
			return
		}
		// The scan found nothing in budget. Restage unless this was the
		// last stage.
		proc.MarkTimeout(st.budget)
		logx.Info("quantum stage timed out stage=%s budget=%s", proc.Stage(), st.budget)
		_ = proc.Stop()
		if i == len(stages)-1 {
			e.setAetherErr(fmt.Errorf("quantum found no working relay"))
			return
		}
	}
}

// readCachedPeer reads the working relay the last run found ("" if none).
func readCachedPeer(path string) string {
	raw, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	peer := strings.TrimSpace(string(raw))
	if _, _, err := net.SplitHostPort(peer); err != nil {
		return ""
	}
	return peer
}

// aetherPeerFile is where the working relay is cached, next to the
// identity.
func aetherPeerFile(dataDir string) string {
	return dataDir + string(os.PathSeparator) + "aether-peer.txt"
}
