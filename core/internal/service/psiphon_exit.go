package service

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/ClxybyCloner/ClxyProPc/core/internal/logx"
	"github.com/ClxybyCloner/ClxyProPc/core/internal/psiphon"
)

// PsiphonStatus is the Psiphon exit's state in /api/status.
type PsiphonStatus struct {
	// Enabled is what the app asked for; Running is whether the exit
	// actually serves. Region is the egress region ("" = auto).
	Enabled bool   `json:"enabled"`
	Region  string `json:"region"`
	Running bool   `json:"running"`
	// Socks is the exit's SOCKS5 address while it runs.
	Socks string `json:"socks,omitempty"`
	// EgressIP/Place/Code are the exit's public address and place, probed
	// through the exit SOCKS ("" until the probe answers).
	EgressIP    string `json:"egress_ip,omitempty"`
	EgressPlace string `json:"egress_place,omitempty"`
	EgressCode  string `json:"egress_code,omitempty"`
	// Error is the exit's terminal failure, in English.
	Error string `json:"error,omitempty"`
}

// psiphonSettings returns the exit the app asked for ("" region = auto).
// The settings live on the daemon so they survive engine restarts; the
// engine snapshots them at creation.
func (d *Daemon) psiphonSettings() (enabled bool, region string) {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.psiphonEnabled, d.psiphonRegion
}

// setPsiphonSettings stores the exit the app asked for. A bad region is
// rejected; the previous settings stay.
func (d *Daemon) setPsiphonSettings(enabled bool, region string) error {
	region = strings.ToUpper(strings.TrimSpace(region))
	if region != "" && len(region) != 2 {
		return fmt.Errorf("psiphon region %q is not a two-letter country code", region)
	}
	d.mu.Lock()
	d.psiphonEnabled, d.psiphonRegion = enabled, region
	d.mu.Unlock()
	return nil
}

// psiphonStatus reports the Psiphon exit for the status view.
func (e *proxyEngine) psiphonStatus() *PsiphonStatus {
	if e.psiphon == nil {
		return nil
	}
	e.psiphonMu.Lock()
	err := e.psiphonErr
	e.psiphonMu.Unlock()
	st := &PsiphonStatus{Enabled: e.psiphonEnabled, Region: e.psiphonRegion, Running: e.psiphon.IsRunning(), Socks: e.psiphon.Addr()}
	if err != nil {
		st.Error = err.Error()
	}
	e.egressMu.Lock()
	st.EgressIP, st.EgressPlace, st.EgressCode = e.egressIP, e.egressPlace, e.egressCode
	e.egressMu.Unlock()
	return st
}

// psiphonReady reports whether the exit is up to the point the connect
// needs: disabled, or running.
func (e *proxyEngine) psiphonReady() bool {
	if e.psiphon == nil || !e.psiphonEnabled {
		return true
	}
	return e.psiphon.IsRunning()
}

// psiphonError returns the exit's terminal failure, if any.
func (e *proxyEngine) psiphonError() error {
	e.psiphonMu.Lock()
	defer e.psiphonMu.Unlock()
	return e.psiphonErr
}

func (e *proxyEngine) setPsiphonErr(err error) {
	e.psiphonMu.Lock()
	defer e.psiphonMu.Unlock()
	if e.psiphonErr == nil {
		e.psiphonErr = err
	}
}

// startPsiphon brings the exit up after a MASQUE stage succeeded (the
// Android finishConnect step): the sidecar dials through aether's SOCKS
// and serves the exit SOCKS. It blocks up to the wrapper's start timeout.
// A failure is terminal for this connect: silently falling back to plain
// Quantum would hand the user the Tehran IP they turned the exit on to
// avoid.
func (e *proxyEngine) startPsiphon(ctx context.Context) error {
	if e.psiphon == nil || !e.psiphonEnabled {
		return nil
	}
	upstream := e.aether.Addr()
	if upstream == "" {
		return fmt.Errorf("psiphon: quantum engine has no SOCKS address")
	}
	if err := e.psiphon.Start(ctx, "socks5://"+upstream, e.psiphonRegion); err != nil {
		e.setPsiphonErr(err)
		return err
	}
	if err := e.psiphon.WaitReady(psiphon.StartTimeout); err != nil {
		e.setPsiphonErr(err)
		return err
	}
	logx.Info("psiphon exit ready on %s (region %s)", e.psiphon.Addr(), regionOrAuto(e.psiphonRegion))
	e.egressMu.Lock()
	e.egressGen++
	e.egressIP, e.egressPlace, e.egressCode = "", "", ""
	e.egressMu.Unlock()
	go e.probePsiphonEgress()
	return nil
}

// probePsiphonEgress asks ip-api which address the exit hands to the
// outside world and where it lives. The request goes through the exit
// SOCKS — never aether's: probing aether's SOCKS would measure the
// MASQUE egress, a Cloudflare WARP IP ip-api reads as "Tehran, Iran".
// The hostname travels unresolved, so DNS happens on the far side too.
func (e *proxyEngine) probePsiphonEgress() {
	e.egressMu.Lock()
	gen := e.egressGen
	e.egressMu.Unlock()
	addr := e.psiphon.Addr()
	for attempt := 0; attempt < 3; attempt++ {
		if attempt > 0 {
			time.Sleep(4 * time.Second)
		}
		e.egressMu.Lock()
		if gen != e.egressGen {
			e.egressMu.Unlock()
			return
		}
		e.egressMu.Unlock()
		ip, place, code, err := fetchEgress(addr)
		if err != nil {
			logx.Debug("psiphon egress probe failed: %s", logx.Err(err))
			continue
		}
		e.egressMu.Lock()
		if gen == e.egressGen {
			e.egressIP, e.egressPlace, e.egressCode = ip, place, code
		}
		e.egressMu.Unlock()
		logx.Info("psiphon egress %s (%s)", ip, place)
		return
	}
}

// fetchEgress is one probe attempt: a plain HTTP GET through the exit
// SOCKS, 10s timeout. The hostname travels unresolved, so the exit
// resolves it on the far side.
func fetchEgress(exitAddr string) (ip, place, code string, err error) {
	client := &http.Client{
		Timeout: 10 * time.Second,
		Transport: &http.Transport{
			Proxy: nil,
			DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
				return dialThroughSocks(exitAddr, "ip-api.com:80")
			},
		},
	}
	resp, err := client.Get("http://ip-api.com/json/?fields=status,query,country,countryCode,city")
	if err != nil {
		return "", "", "", err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 64*1024))
	if err != nil {
		return "", "", "", err
	}
	return parseEgress(raw)
}

// parseEgress reads ip-api's answer: the exit's public IP, its place
// ("city, country") and its country code.
func parseEgress(raw []byte) (ip, place, code string, err error) {
	var answer struct {
		Status      string `json:"status"`
		Query       string `json:"query"`
		Country     string `json:"country"`
		CountryCode string `json:"countryCode"`
		City        string `json:"city"`
	}
	if err := json.Unmarshal(raw, &answer); err != nil {
		return "", "", "", err
	}
	if answer.Status != "success" || answer.Query == "" {
		return "", "", "", fmt.Errorf("ip-api: status %q", answer.Status)
	}
	place = strings.TrimSpace(answer.City)
	if answer.Country != "" {
		if place != "" {
			place += ", "
		}
		place += strings.TrimSpace(answer.Country)
	}
	return answer.Query, place, strings.ToUpper(strings.TrimSpace(answer.CountryCode)), nil
}

func regionOrAuto(region string) string {
	if region == "" {
		return "auto"
	}
	return region
}
