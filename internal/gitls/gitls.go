// Package gitls lists a repo's index once per run and answers every pathspec from memory.
// - hop's _hop_ls forks `git ls-files` per kind (lib/providers.zsh:121); one listing is the same bytes.
// - Matching ports git's rules for :(glob) pathspecs (dir.c match_pathspec_item, wildmatch.c).
// - Any pattern first matches literally, exactly or as a leading directory, so `brack[1]` finds itself.
// - Then wildmatch with WM_PATHNAME runs on what follows the literal prefix, which git strips first.
package gitls

import (
	"bytes"
	"fmt"
	"os/exec"
	"regexp"
	"strings"
	"sync"
)

type Index struct {
	Root  string
	Paths []string
}

// List is `git -C root ls-files -z --cached`, NUL-split so no path is ever C-quoted.
func List(root string) (*Index, error) {
	var stderr bytes.Buffer
	cmd := exec.Command("git", "-C", root, "ls-files", "-z", "--cached")
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		msg := strings.SplitN(strings.TrimSpace(stderr.String()), "\n", 2)[0]
		if msg == "" {
			msg = err.Error()
		}
		return nil, fmt.Errorf("git ls-files failed in %s: %s", root, msg)
	}
	ix := &Index{Root: root}
	for _, p := range bytes.Split(out, []byte{0}) {
		if len(p) > 0 {
			ix.Paths = append(ix.Paths, string(p))
		}
	}
	return ix, nil
}

// Matcher is one compiled pathspec.
type Matcher struct {
	literal string
	re      *regexp.Regexp
}

var cache sync.Map

// Compile takes a pathspec as hop writes it: bare means :(glob), and an explicit :(glob) is accepted.
func Compile(spec string) (*Matcher, error) {
	if m, ok := cache.Load(spec); ok {
		return m.(*Matcher), nil
	}
	pat := spec
	if strings.HasPrefix(pat, ":(glob)") {
		pat = pat[len(":(glob)"):]
	} else if strings.HasPrefix(pat, ":") {
		return nil, fmt.Errorf("pathspec magic other than :(glob) is not supported: %s", spec)
	}
	m := &Matcher{literal: pat}
	if strings.ContainsAny(pat, `*?[\`) {
		re, err := regexp.Compile(globRegexp(pat))
		if err != nil {
			return nil, fmt.Errorf("pathspec %s: %w", spec, err)
		}
		m.re = re
	}
	cache.Store(spec, m)
	return m, nil
}

func (m *Matcher) Match(p string) bool {
	l := m.literal
	if l == "" || p == l {
		return true
	}
	if strings.HasPrefix(p, l) && (l[len(l)-1] == '/' || p[len(l)] == '/') {
		return true
	}
	return m.re != nil && m.re.MatchString(p)
}

// Match is `git ls-files -- specs...`: the matching paths in index order, or every path with no spec.
func (ix *Index) Match(specs ...string) ([]string, error) {
	if len(specs) == 0 {
		return ix.Paths, nil
	}
	ms := make([]*Matcher, 0, len(specs))
	for _, s := range specs {
		m, err := Compile(s)
		if err != nil {
			return nil, err
		}
		ms = append(ms, m)
	}
	var out []string
	for _, p := range ix.Paths {
		for _, m := range ms {
			if m.Match(p) {
				out = append(out, p)
				break
			}
		}
	}
	return out, nil
}

// globRegexp translates a wildmatch WM_PATHNAME pattern.
// - `**` is recursive only as a whole segment: leading `**/`, inner `/**/`, trailing `/**`, or alone.
// - "Leading" counts from the end of the literal prefix, so `a**` and `a/b**/f` cross '/' in git too.
// - Any other `*` or `**` and every `?` and bracket stop at '/'.
func globRegexp(p string) string {
	var b strings.Builder
	b.WriteString(`(?s)^`)
	lit := strings.IndexAny(p, `*?[\`)
	if lit < 0 {
		lit = len(p)
	}
	b.WriteString(regexp.QuoteMeta(p[:lit]))
	for i := lit; i < len(p); i++ {
		c := p[i]
		switch c {
		case '*':
			j := i
			for j < len(p) && p[j] == '*' {
				j++
			}
			wholeSeg := j-i >= 2 && (i == lit || p[i-1] == '/') && (j == len(p) || p[j] == '/')
			switch {
			case wholeSeg && j == len(p):
				b.WriteString(`.*`)
				i = j - 1
			case wholeSeg:
				b.WriteString(`(?:.*/)?`)
				i = j
			default:
				b.WriteString(`[^/]*`)
				i = j - 1
			}
		case '?':
			b.WriteString(`[^/]`)
		case '\\':
			if i+1 < len(p) {
				i++
				b.WriteString(regexp.QuoteMeta(p[i : i+1]))
			} else {
				b.WriteString(`\\`)
			}
		case '[':
			cls, n, ok := bracket(p[i:])
			if !ok {
				b.WriteString(`\[`)
				continue
			}
			b.WriteString(cls)
			i += n - 1
		default:
			b.WriteString(regexp.QuoteMeta(string(c)))
		}
	}
	b.WriteString(`$`)
	return b.String()
}

// bracket translates a [...] class, returning the regexp class and the bytes consumed.
func bracket(s string) (string, int, bool) {
	j := 1
	neg := false
	if j < len(s) && (s[j] == '!' || s[j] == '^') {
		neg = true
		j++
	}
	var body strings.Builder
	first := true
	for j < len(s) {
		c := s[j]
		if c == ']' && !first {
			if neg {
				return "[^/" + body.String() + "]", j + 1, true
			}
			return "[" + body.String() + "]", j + 1, true
		}
		first = false
		switch {
		case c == '[' && j+1 < len(s) && s[j+1] == ':':
			end := strings.Index(s[j:], ":]")
			if end < 0 {
				return "", 0, false
			}
			body.WriteString(s[j : j+end+2])
			j += end + 2
			continue
		case c == '\\' && j+1 < len(s):
			body.WriteString(regexp.QuoteMeta(s[j+1 : j+2]))
			j += 2
			continue
		case c == '\\' || c == ']' || c == '^' || c == '[':
			body.WriteByte('\\')
		}
		body.WriteByte(c)
		j++
	}
	return "", 0, false
}
