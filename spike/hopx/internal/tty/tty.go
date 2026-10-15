// Package tty finds the terminal when a caller hands hopx pipes, as a PSReadLine key handler does.
package tty

import (
	"os"
	"runtime"

	"golang.org/x/term"
)

// Name is the controlling terminal's device; CONOUT$ is the Windows console, unverified past cross-compile.
func Name() string {
	if runtime.GOOS == "windows" {
		return "CONOUT$"
	}
	return "/dev/tty"
}

// Open is the terminal for reading and writing, or nil when there is no controlling terminal.
func Open() *os.File {
	f, err := os.OpenFile(Name(), os.O_RDWR, 0)
	if err != nil {
		return nil
	}
	return f
}

// Available is _hop_tty_ok: a terminal is reachable, whatever stdin is.
// - fzf reads keys from /dev/tty, so `hopx < /dev/null` and `hopx | cat` still pick.
// - The failure is no controlling terminal at all (cron, CI), where fzf would block forever.
func Available() bool {
	f := Open()
	if f == nil {
		return false
	}
	f.Close()
	return true
}

// Is is isatty(3); /dev/null is a character device too, so a mode check would pass it.
func Is(f *os.File) bool { return term.IsTerminal(int(f.Fd())) }

// Attach points fds 0, 1 and 2 at the terminal when any of them isn't one, before an editor is exec'd.
// - It reports whether it changed anything; a caller with three terminals already is left alone.
func Attach() bool {
	if Is(os.Stdin) && Is(os.Stdout) && Is(os.Stderr) {
		return false
	}
	t := Open()
	if t == nil {
		return false
	}
	defer t.Close()
	for fd := 0; fd <= 2; fd++ {
		dupTo(int(t.Fd()), fd)
	}
	return true
}
