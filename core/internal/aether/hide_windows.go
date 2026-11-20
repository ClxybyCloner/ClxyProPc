//go:build windows

package aether

import (
	"os/exec"
	"syscall"
)

// hideConsole runs a console binary without a console window: aether.exe
// is a console-subsystem binary, and the core itself has no console
// (built with -H windowsgui), so Windows would otherwise pop a visible
// black window for every scan — and again on every restage. The
// sidecar's logs still reach us through the stdout/stderr pipes.
func hideConsole(cmd *exec.Cmd) {
	const createNoWindow = 0x08000000 // CREATE_NO_WINDOW
	cmd.SysProcAttr = &syscall.SysProcAttr{
		HideWindow:    true,
		CreationFlags: createNoWindow,
	}
}
