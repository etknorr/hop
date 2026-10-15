// Package workspace is lib/workspaces.zsh: the directories that hold repos, and the repos inside them.
package workspace

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/etknorr/hop/spike/hopx/internal/collate"
)

// Expand is _hop_ws_expand: a leading ~, then $VAR and ${VAR}, and never eval.
// - A '$' not followed by a name is dropped, and an unclosed ${ keeps its text, both as zsh does.
func Expand(s string) string {
	home := os.Getenv("HOME")
	if s == "~" {
		s = home
	} else if strings.HasPrefix(s, "~/") {
		s = home + "/" + s[2:]
	}
	var out strings.Builder
	rest := s
	for {
		i := strings.IndexByte(rest, '$')
		if i < 0 {
			break
		}
		out.WriteString(rest[:i])
		rest = rest[i+1:]
		var name string
		if strings.HasPrefix(rest, "{") {
			if j := strings.IndexByte(rest, '}'); j >= 0 {
				name, rest = rest[1:j], rest[j+1:]
			} else {
				name = rest[1:]
			}
		} else {
			j := 0
			for j < len(rest) && isIdent(rest[j]) {
				j++
			}
			name, rest = rest[:j], rest[j:]
		}
		if name != "" {
			out.WriteString(os.Getenv(name))
		}
	}
	return out.String() + rest
}

func isIdent(c byte) bool {
	return c == '_' || c >= '0' && c <= '9' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z'
}

var trailingComment = regexp.MustCompile(`[ \t\v\f\r\n]+#.*$`)

const space = " \t\v\f\r\n"

type Workspace struct{ Name, Path string }

// Parse is _hop_ws_parse: an explicit list beats the file, and the file beats the guessed defaults.
// - A missing or unsearchable path is skipped silently, and the first occurrence of a name wins.
func Parse(list []string, file string) []Workspace {
	raw := list
	if len(raw) == 0 {
		if b, err := os.ReadFile(file); err == nil {
			raw = strings.Split(strings.TrimRight(string(b), "\n"), "\n")
		} else {
			h := os.Getenv("HOME")
			raw = []string{h + "/src", h + "/code", h + "/projects", h + "/dev", h + "/work"}
		}
	}
	seen := map[string]bool{}
	var out []Workspace
	for _, line := range raw {
		line = strings.TrimSuffix(line, "\r")
		line = strings.TrimLeft(line, space)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if loc := trailingComment.FindStringIndex(line); loc != nil {
			line = line[:loc[0]]
		}
		line = strings.TrimRight(line, space)
		if line == "" {
			continue
		}
		name, p := "", line
		if i := strings.IndexByte(line, '='); i >= 0 {
			name, p = line[:i], line[i+1:]
		}
		name = strings.Trim(name, space)
		p = strings.Trim(p, space)
		if p == "" {
			continue
		}
		p = Canon(Expand(p))
		if !searchableDir(p) {
			continue
		}
		if name == "" {
			name = filepath.Base(p)
		}
		if seen[name] {
			continue
		}
		seen[name] = true
		out = append(out, Workspace{name, p})
	}
	return out
}

// Canon is zsh's :A: absolute, with symlinks resolved when the path exists.
func Canon(p string) string {
	p, _ = filepath.Abs(p)
	if r, err := filepath.EvalSymlinks(p); err == nil {
		p = r
	}
	return p
}

// searchableDir approximates [[ -d p && -x p ]] from the mode bits rather than access(2).
func searchableDir(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.IsDir() && st.Mode().Perm()&0o111 != 0
}

// Repos is _hop_ws_repos: the git repos directly inside ws, sorted, where a worktree's .git is a file.
func Repos(ws string) []string {
	ents, err := os.ReadDir(ws)
	if err != nil {
		return nil
	}
	var out []string
	for _, e := range ents {
		if strings.HasPrefix(e.Name(), ".") {
			continue
		}
		d := filepath.Join(ws, e.Name())
		if _, err := os.Lstat(filepath.Join(d, ".git")); err == nil {
			out = append(out, d)
		}
	}
	collate.Sort(out)
	return out
}

// RepoList is _hop_repos: the explicit list when set, else every repo of every workspace, deduped.
func RepoList(repos []string, wss []Workspace) []string {
	var all []string
	if len(repos) > 0 {
		all = repos
	} else {
		for _, w := range wss {
			all = append(all, Repos(w.Path)...)
		}
	}
	seen := map[string]bool{}
	var out []string
	for _, r := range all {
		if r == "" || seen[r] {
			continue
		}
		seen[r] = true
		out = append(out, r)
	}
	return out
}
