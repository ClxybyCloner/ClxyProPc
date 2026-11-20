// fakeaether stands in for aether.exe in the aether and service tests.
// It accepts the real aether CLI flags and behaves by FAKE_AETHER_MODE:
//
//	serving: prints the serving marker and a peer line, then sleeps.
//	exiting: prints an error to stderr and exits 1.
//	silent:  sleeps without printing anything.
//
// A Go binary (not a shell script) so the tests run on Windows CI too.
package main

import (
	"flag"
	"fmt"
	"os"
	"time"
)

func main() {
	flag.String("bind", "127.0.0.1:11819", "SOCKS bind address")
	flag.String("config", "", "identity file (ignored)")
	flag.String("log-level", "", "log level (ignored)")
	flag.String("scan", "", "scan mode (ignored)")
	flag.Bool("masque", false, "MASQUE mode (ignored)")
	flag.Bool("h2", false, "HTTP/2 (ignored)")
	flag.Bool("h3", false, "HTTP/3 (ignored)")
	flag.Bool("quick-reconnect", false, "fast reconnect (ignored)")
	flag.String("peer", "", "cached peer (ignored)")
	flag.Parse()

	switch os.Getenv("FAKE_AETHER_MODE") {
	case "serving":
		fmt.Println("[2026-11-20T10:30:57Z INFO  aether] [+] socks5 server listening on 127.0.0.1:11819")
		fmt.Println("[2026-11-20T10:30:58Z INFO  aether] relay 203.0.113.7:443 selected")
		time.Sleep(30 * time.Second)
	case "exiting":
		fmt.Fprintln(os.Stderr, "Error: registration failed")
		os.Exit(1)
	default: // silent
		time.Sleep(30 * time.Second)
	}
}
