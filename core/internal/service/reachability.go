package service

import (
	"bufio"
	"context"
	"crypto/tls"
	"fmt"
	"net"
	"net/http"
	"sync"
	"time"

	"github.com/ClxybyCloner/ClxyProPc/core/internal/logx"
)

// Reachability probes YouTube and Facebook through the local SOCKS5 proxy
// before declaring the connection ready, matching ClxyPro's Android Reachability.kt.
type Reachability struct {
	proxyAddr string
}

func NewReachability(proxyAddr string) *Reachability {
	return &Reachability{proxyAddr: proxyAddr}
}

// Verify probes YouTube and Facebook concurrently. Both must answer.
func (r *Reachability) Verify(ctx context.Context) (bool, string) {
	targets := []struct {
		host  string
		label string
	}{
		{"www.youtube.com", "YouTube"},
		{"www.facebook.com", "Facebook"},
	}

	var wg sync.WaitGroup
	results := make([]bool, len(targets))
	details := make([]string, len(targets))

	for i, t := range targets {
		wg.Add(1)
		go func(idx int, host, label string) {
			defer wg.Done()
			ok, detail := r.probe(ctx, host)
			results[idx] = ok
			details[idx] = detail
			if ok {
				logx.Info("reachability: %s answered through the tunnel", label)
			} else {
				logx.Warn("reachability: %s failed: %s", label, detail)
			}
		}(i, t.host, t.label)
	}

	wg.Wait()

	allOk := true
	for _, ok := range results {
		if !ok {
			allOk = false
			break
		}
	}

	if allOk {
		return true, "youtube and facebook answered"
	}
	return false, "traffic check failed"
}

// probe connects to the SOCKS5 proxy, issues a SOCKS5 CONNECT for host:443,
// performs a TLS handshake, and sends HEAD / HTTP/1.1.
func (r *Reachability) probe(ctx context.Context, host string) (bool, string) {
	if r.proxyAddr == "" {
		return true, "no proxy address configured"
	}

	dialer := net.Dialer{Timeout: 4 * time.Second}
	rawConn, err := dialer.DialContext(ctx, "tcp", r.proxyAddr)
	if err != nil {
		return false, fmt.Sprintf("proxy connect failed: %v", err)
	}
	defer rawConn.Close()

	_ = rawConn.SetDeadline(time.Now().Add(6 * time.Second))

	// 1. SOCKS5 greeting
	if _, err := rawConn.Write([]byte{0x05, 0x01, 0x00}); err != nil {
		return false, fmt.Sprintf("socks5 greeting failed: %v", err)
	}
	resp := make([]byte, 2)
	if _, err := bufio.NewReader(rawConn).Read(resp); err != nil || resp[0] != 0x05 || resp[1] != 0x00 {
		return false, "socks5 handshake rejected"
	}

	// 2. SOCKS5 CONNECT to domain name: host:443
	hostBytes := []byte(host)
	req := make([]byte, 0, 7+len(hostBytes))
	req = append(req, 0x05, 0x01, 0x00, 0x03, byte(len(hostBytes)))
	req = append(req, hostBytes...)
	req = append(req, 0x01, 0xBB) // port 443 big-endian

	if _, err := rawConn.Write(req); err != nil {
		return false, fmt.Sprintf("socks5 connect request failed: %v", err)
	}

	reader := bufio.NewReader(rawConn)
	replyHeader := make([]byte, 4)
	if _, err := reader.Read(replyHeader); err != nil || replyHeader[0] != 0x05 || replyHeader[1] != 0x00 {
		return false, "socks5 connect failed"
	}

	// Skip bound address
	switch replyHeader[3] {
	case 0x01: // IPv4
		skip := make([]byte, 4+2)
		_, _ = reader.Read(skip)
	case 0x03: // FQDN
		lenByte, _ := reader.ReadByte()
		skip := make([]byte, int(lenByte)+2)
		_, _ = reader.Read(skip)
	case 0x04: // IPv6
		skip := make([]byte, 16+2)
		_, _ = reader.Read(skip)
	default:
		return false, "unknown socks5 address type"
	}

	// 3. TLS Handshake
	tlsConn := tls.Client(rawConn, &tls.Config{
		ServerName:         host,
		InsecureSkipVerify: false,
		MinVersion:         tls.VersionTLS12,
	})
	defer tlsConn.Close()

	if err := tlsConn.HandshakeContext(ctx); err != nil {
		return false, fmt.Sprintf("tls handshake failed: %v", err)
	}

	// 4. Send HEAD / HTTP/1.1
	httpReq := fmt.Sprintf("HEAD / HTTP/1.1\r\nHost: %s\r\nUser-Agent: ClxyPro\r\nConnection: close\r\n\r\n", host)
	if _, err := tlsConn.Write([]byte(httpReq)); err != nil {
		return false, fmt.Sprintf("http head failed: %v", err)
	}

	httpResp, err := http.ReadResponse(bufio.NewReader(tlsConn), nil)
	if err != nil {
		return false, fmt.Sprintf("http read failed: %v", err)
	}
	_ = httpResp.Body.Close()

	return true, "ok"
}
