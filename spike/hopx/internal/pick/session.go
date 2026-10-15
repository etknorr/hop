package pick

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
)

// Session is what every callback reads, written once per picker, so no bind string carries a root or a query.
// - hop's reload strings embed the root, so a root holding `)` ended reload(...) early; here it never enters a bind.
type Session struct {
	Root   string   `json:"root"`
	Under  string   `json:"under,omitempty"`
	Kinds  []string `json:"kinds"`
	All    []string `json:"all"`
	Header string   `json:"header"`
}

// Write puts the session in a fresh private directory and returns its path; the caller removes the directory.
func (s *Session) Write() (dir, path string, err error) {
	dir, err = os.MkdirTemp("", "hopx-pick-")
	if err != nil {
		return "", "", err
	}
	b, _ := json.Marshal(s)
	path = filepath.Join(dir, "session.json")
	if err := os.WriteFile(path, b, 0o600); err != nil {
		os.RemoveAll(dir)
		return "", "", err
	}
	return dir, path, nil
}

// Load reads $HOPX_SESSION, which only a picker's callbacks have.
func Load() (*Session, error) {
	p := os.Getenv("HOPX_SESSION")
	if p == "" {
		return nil, errors.New("HOPX_SESSION is not set; this is a picker callback")
	}
	b, err := os.ReadFile(p)
	if err != nil {
		return nil, err
	}
	s := &Session{}
	return s, json.Unmarshal(b, s)
}

func inMenu() bool { return strings.HasPrefix(os.Getenv("FZF_PROMPT"), MenuPrompt) }

// back leaves the menu for these kinds' rows, under the picker's own prompt and header; the query filtered kinds, so it goes.
func back(kinds []string) string {
	return "clear-query+reload(hopx __rows " + strings.Join(kinds, " ") + ")+change-prompt(" + Prompt + ")+transform-header(hopx __header)+first"
}

// Key is `hopx __key`, the one decision fzf can't make: whether the list on screen holds kinds or targets.
// - It replaces hop's POSIX `case "$FZF_PROMPT"` transform bodies, which break under fish and pwsh.
// - FZF_PROMPT is the state, as in hop, since fzf exports it to every callback.
func Key(s *Session, key, arg string) string {
	switch key {
	case "enter":
		if !inMenu() {
			return "accept"
		}
		if !slices.Contains(s.All, arg) {
			return "ignore"
		}
		return back([]string{arg})
	case "esc":
		if inMenu() {
			return back(s.Kinds)
		}
		return "abort"
	case "alt-enter":
		if inMenu() {
			return "ignore"
		}
		return "print(alt-enter)+accept"
	}
	return "ignore"
}
