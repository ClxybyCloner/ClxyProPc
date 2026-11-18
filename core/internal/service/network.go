package service

import (
	"context"
	"net"
	"time"

	"github.com/ClxybyCloner/ClxyProPc/core/internal/config"
	"github.com/ClxybyCloner/ClxyProPc/core/internal/guardian"
	"github.com/ClxybyCloner/ClxyProPc/core/internal/hellosplit"
	"github.com/ClxybyCloner/ClxyProPc/core/internal/logx"
	"github.com/ClxybyCloner/ClxyProPc/core/internal/resolver"
)

// resolverDialer dials through the configured DNS servers with a timeout.
type resolverDialer struct{ timeout time.Duration }

func (d resolverDialer) DialContext(ctx context.Context, network, address string) (net.Conn, error) {
	ctx, cancel := context.WithTimeout(ctx, d.timeout)
	defer cancel()
	conn, err := resolver.Dial(ctx, network, address)
	if err != nil {
		return nil, err
	}
	return hellosplit.Wrap(conn), nil
}

func (d resolverDialer) Dial(network, address string) (net.Conn, error) {
	return d.DialContext(context.Background(), network, address)
}

// configureDNS installs the configured DNS servers for every connection
// this program opens itself.
func configureDNS(cfg config.DNS) error {
	r, err := resolver.New(cfg.Servers, cfg.FallbackToSystem)
	if err != nil {
		return err
	}
	if r.System() {
		resolver.Set(nil)
		logx.Info("DNS: system resolver")
		return nil
	}
	resolver.Set(r)
	logx.Info("DNS: servers=%s", r)
	return nil
}

// configureUpstreamProxy applies the TLS split and the upstream SOCKS5 proxy
// for the control-plane connections. ClxyPro connects directly to Mozilla;
// there is no relay transport.
func configureUpstreamProxy(n config.Network) error {
	hellosplit.Set(n.HelloSplit)
	proxyAddress := n.UpstreamProxyInUse()
	if err := resolver.SetUpstreamProxy(proxyAddress, n.UpstreamProxyUsername, n.UpstreamProxyPassword); err != nil {
		return err
	}
	if proxyAddress != "" {
		logx.Info("connections to Mozilla and the control plane go through the upstream proxy=%s", proxyAddress)
	}
	guardian.SetRegionRecovery(nil)
	return nil
}
