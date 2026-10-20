// Package guard is bin/hop-guard: it tells a forged keystroke from a real one by when it arrived.
// - fzf passes an escape sequence it can't parse on as keystrokes, so `\e]11;rgb:1e1e/1e1e/1e1e\e\\` types `11;rgb:...`.
// - In NORMAL those letters are verbs, and `b` in that payload ran `gh browse` with no keypress.
// - fzf turns the unparsed introducer into a bindable alt-<char>, so the payload always follows one nobody would press.
// - Mark records that moment, and Check refuses a verb that lands too soon after it.
// - It never fails closed: no mark, a malformed one, a backwards clock or a window of 0 lets the verb run.
package guard

import (
	"os"
	"regexp"
	"strconv"
	"time"
)

// DefaultWindow was sized for zsh's 15 to 22 ms hop-guard fork.
// - `hop __guard` measured no slower on macOS arm64 (median 8 ms, p90 11 ms at load 5; p90 26 ms at load 18), so it stays.
const DefaultWindow = 0.15

var number = regexp.MustCompile(`^([0-9]+|[0-9]+\.[0-9]+|\.[0-9]+)$`)

// Window is HOP_GUARD_WINDOW in seconds; a malformed value falls back rather than failing the bind.
func Window(raw string) float64 {
	if raw == "" || !number.MatchString(raw) {
		return DefaultWindow
	}
	w, err := strconv.ParseFloat(raw, 64)
	if err != nil {
		return DefaultWindow
	}
	return w
}

func now() string { return strconv.FormatFloat(float64(time.Now().UnixMicro())/1e6, 'f', 6, 64) }

// Mark records an unparsed escape introducer's arrival; a write failure only drops the protection.
func Mark(path string) {
	if path != "" {
		os.WriteFile(path, []byte(now()), 0o600)
	}
}

// Check reports whether a verb may run now.
// - A refused key re-arms the window, so one mark covers a payload of any length: payload letters arrive about 19 ms apart.
// - It can't lock the picker out, since a key that passes never re-arms.
func Check(path string, window float64) bool {
	if path == "" || window <= 0 {
		return true
	}
	b, err := os.ReadFile(path)
	if err != nil || !number.MatchString(string(b)) {
		return true
	}
	mark, err := strconv.ParseFloat(string(b), 64)
	if err != nil {
		return true
	}
	age := float64(time.Now().UnixMicro())/1e6 - mark
	if age < 0 || age >= window {
		return true
	}
	Mark(path)
	return false
}
