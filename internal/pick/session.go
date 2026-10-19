package pick

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"time"

	"github.com/etknorr/hop/internal/keymap"
)

// Session is what every callback reads, written once per picker, so no bind string carries a root or a query.
// - hop's reload strings embed the root, so a root holding `)` ended reload(...) early; here it never enters a bind.
// - View is the kinds on screen after the menu switched them, which r and esc out of the menu reload; empty is Kinds.
type Session struct {
	Root  string     `json:"root"`
	Under string     `json:"under,omitempty"`
	Kinds []string   `json:"kinds"`
	All   []string   `json:"all"`
	View  []string   `json:"view,omitempty"`
	Keys  keymap.Map `json:"keys"`
}

// Current is the view r reloads.
func (s *Session) Current() []string {
	if len(s.View) > 0 {
		return s.View
	}
	return s.Kinds
}

// Write puts the session in a fresh private directory and returns its path; the caller removes the directory.
// - SIGKILL leaves a directory behind, so ones a day old are reaped first; a day, because a picker can sit open over lunch.
func (s *Session) Write() (dir, path string, err error) {
	reap(os.TempDir(), 24*time.Hour)
	dir, err = os.MkdirTemp("", "hop-pick-")
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

// Load reads $HOP_SESSION, which only a picker's callbacks have.
func Load() (*Session, error) {
	p := os.Getenv("HOP_SESSION")
	if p == "" {
		return nil, errors.New("HOP_SESSION is not set; this is a picker callback")
	}
	b, err := os.ReadFile(p)
	if err != nil {
		return nil, err
	}
	s := &Session{}
	return s, json.Unmarshal(b, s)
}

// Path is the session file a callback reads; the guard's mark sits beside it, in the picker's private directory.
func Path() string { return os.Getenv("HOP_SESSION") }

// Save rewrites the session for the callbacks after this one, by rename so a reader never sees half a file.
func (s *Session) Save() error {
	p := Path()
	b, _ := json.Marshal(s)
	tmp := p + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, p)
}

func reap(root string, age time.Duration) {
	old, _ := filepath.Glob(filepath.Join(root, "hop-pick-*"))
	for _, d := range old {
		if st, err := os.Lstat(d); err == nil && st.IsDir() && time.Since(st.ModTime()) > age {
			os.RemoveAll(d)
		}
	}
}
