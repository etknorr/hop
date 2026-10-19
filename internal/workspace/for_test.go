package workspace

import "testing"

func TestFor(t *testing.T) {
	wss := []Workspace{{Name: "w", Path: "/w"}, {Name: "code", Path: "/w/code"}, {Name: "x", Path: "/x/"}}
	for dir, want := range map[string]string{"/w/code/repo": "/w/code", "/w/codex": "/w", "/w": "/w", "/x/y": "/x", "/y": ""} {
		if got, ok := For(dir, wss); got != want || ok != (want != "") {
			t.Errorf("For(%s) = %q %v, want %q", dir, got, ok, want)
		}
	}
}
