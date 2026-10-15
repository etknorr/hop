package resolve

import (
	"os"
	"os/user"
	"path/filepath"
	"regexp"
	"slices"
	"strings"

	"github.com/etknorr/hop/spike/hopx/internal/collate"
	"github.com/etknorr/hop/spike/hopx/internal/rows"
)

var userName = regexp.MustCompile(`^~[[:alnum:]_.-]+$`)

func exists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

func isDir(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.IsDir()
}

func joinPath(base, seg string) string {
	if base == "/" {
		return "/" + seg
	}
	return base + "/" + seg
}

// ciGlob is "${base%/}"/(#i)${rest}(N): every existing path under base whose segments equal rest's without case.
// - The segments are literal text, so only case is relaxed; a dot-file still needs its typed dot.
func ciGlob(base, rest string) []string {
	cur := []string{base}
	segs := strings.Split(rest, "/")
	for i, seg := range segs {
		var next []string
		for _, c := range cur {
			ents, err := os.ReadDir(c)
			if err != nil {
				continue
			}
			for _, e := range ents {
				if !strings.EqualFold(e.Name(), seg) {
					continue
				}
				p := joinPath(c, e.Name())
				if i < len(segs)-1 && !isDir(p) {
					continue
				}
				next = append(next, p)
			}
		}
		cur = next
	}
	collate.Sort(cur)
	return cur
}

func realpath(p string) string {
	if r, err := filepath.EvalSymlinks(p); err == nil {
		return r
	}
	return p
}

// Literal is _hop_literal_target, T0: the word names a real path, so it jumps before any row is enumerated.
// - Only a word holding a / or starting with ~, or a bare . or .., qualifies.
// - ./x and ../x are pwd-relative only; /x is the repo root first, then the absolute path; anything else pwd, then root.
// - hop's named directories (hash -d) aren't modelled; ~user reads the passwd entry, as zsh's userdirs does.
func Literal(w, root, pwd string) (Target, bool) {
	if !strings.Contains(w, "/") && !strings.HasPrefix(w, "~") && w != "." && w != ".." {
		return Target{}, false
	}
	p := w
	if len(p) >= 2 && strings.HasSuffix(p, "/") {
		p = strings.TrimRight(p, "/")
	}
	var anchors, rests []string
	switch {
	case p == "." || p == ".." || strings.HasPrefix(p, "./") || strings.HasPrefix(p, "../"):
		anchors, rests = []string{pwd}, []string{p}
	case strings.HasPrefix(p, "/"):
		if root != "" {
			anchors, rests = append(anchors, root), append(rests, p[1:])
		}
		anchors, rests = append(anchors, "/"), append(rests, p[1:])
	case strings.HasPrefix(p, "~"):
		head, tail, _ := strings.Cut(p, "/")
		home := ""
		if head == "~" {
			home = os.Getenv("HOME")
		} else if userName.MatchString(head) {
			if u, err := user.Lookup(head[1:]); err == nil {
				home = u.HomeDir
			}
		}
		if home == "" {
			return Target{}, false
		}
		anchors, rests = []string{home}, []string{tail}
	default:
		anchors, rests = []string{pwd}, []string{p}
		if root != "" {
			anchors, rests = append(anchors, root), append(rests, p)
		}
	}

	hit := ""
	for i := range anchors {
		if h, ok := pathUnder(anchors[i], rests[i]); ok {
			hit = h
			break
		}
	}
	if hit == "" {
		return Target{}, false
	}
	return literalFields(hit, root), true
}

// pathUnder is _hop_path_under: the path rest names under anchor, spelled as the disk spells it.
// - An exact-case hit wins outright; otherwise exactly one case-insensitive match is required, never a guess.
func pathUnder(anchor, rest string) (string, bool) {
	a := filepath.Clean(anchor)
	f := filepath.Clean(strings.TrimSuffix(a, "/") + "/" + rest)
	// ../ can climb above the anchor, so the literal part is what the typed path still shares with it.
	base := a
	for base != "/" && f != base && !strings.HasPrefix(f, base+"/") {
		base = filepath.Dir(base)
	}
	r := strings.TrimPrefix(strings.TrimPrefix(f, base), "/")
	if r == "" {
		return f, exists(f)
	}
	g := ciGlob(base, r)
	if slices.Contains(g, f) {
		return f, true
	}
	if len(g) == 1 {
		return g[0], true
	}
	return "", false
}

// literalFields is _hop_literal_fields: the target for a path T0 found, where a file cds to its parent.
func literalFields(hit, root string) Target {
	groot := ""
	if root != "" {
		groot = realpath(root)
	}
	ha := realpath(hit)
	if isDir(hit) {
		return Target{hit, hit, rows.Rel(rows.Row{Dir: ha, Preview: ha}, groot)}
	}
	return Target{filepath.Dir(hit), hit, rows.Rel(rows.Row{Dir: filepath.Dir(ha), Preview: ha, File: true}, groot)}
}
