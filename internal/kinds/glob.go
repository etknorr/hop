package kinds

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"

	"github.com/etknorr/hop/internal/collate"
)

var patCache sync.Map

// zshPattern compiles a pattern as [[ x == ${~pat} ]] sees it under emulate -L zsh, without extended_glob.
// - '*' crosses '/' there, unlike in a filename glob, which is the trap for exclude.
// - (a|b) grouping is core zsh, so it is honoured; <n-m> ranges are not supported and stay literal.
func zshPattern(p string, slashStar bool) *regexp.Regexp {
	key := fmt.Sprint(slashStar, "\x00", p)
	if r, ok := patCache.Load(key); ok {
		return r.(*regexp.Regexp)
	}
	var b strings.Builder
	b.WriteString(`(?s)^`)
	star := `.*`
	if !slashStar {
		star = `[^/]*`
	}
	depth := 0
	for i := 0; i < len(p); i++ {
		c := p[i]
		switch c {
		case '*':
			b.WriteString(star)
		case '?':
			b.WriteString(`.`)
		case '\\':
			if i+1 < len(p) {
				i++
				b.WriteString(regexp.QuoteMeta(p[i : i+1]))
			} else {
				b.WriteString(`\\`)
			}
		case '[':
			j := i + 1
			if j < len(p) && (p[j] == '!' || p[j] == '^') {
				j++
			}
			if j < len(p) && p[j] == ']' {
				j++
			}
			for j < len(p) && p[j] != ']' {
				j++
			}
			if j >= len(p) {
				b.WriteString(`\[`)
				continue
			}
			body := p[i+1 : j]
			neg := ""
			if strings.HasPrefix(body, "!") || strings.HasPrefix(body, "^") {
				neg, body = "^", body[1:]
			}
			b.WriteString("[" + neg + strings.ReplaceAll(body, `\`, `\\`) + "]")
			i = j
		case '(':
			depth++
			b.WriteString(`(?:`)
		case ')':
			if depth > 0 {
				depth--
				b.WriteString(`)`)
			} else {
				b.WriteString(`\)`)
			}
		case '|':
			if depth > 0 {
				b.WriteString(`|`)
			} else {
				b.WriteString(`\|`)
			}
		default:
			b.WriteString(regexp.QuoteMeta(string(c)))
		}
	}
	for ; depth > 0; depth-- {
		b.WriteString(`)`)
	}
	b.WriteString(`$`)
	r, err := regexp.Compile(b.String())
	if err != nil {
		r = regexp.MustCompile(`^` + regexp.QuoteMeta(p) + `$`)
	}
	patCache.Store(key, r)
	return r
}

// zglob expands a candidate under dir the way `$dir/${~c}(N.L+0)` does (dsl.zsh:175).
// - '*' never crosses '/' and never matches a leading dot, since hop does not set glob_dots.
// - `**` as a whole segment is zero or more directories, not following symlinks.
// - The final match must be a regular file by lstat, so a symlink is never chosen, with size > 0.
// - zsh sorts by the locale's collation, which collate approximates.
func zglob(dir, pat string) []string {
	segs := strings.Split(pat, "/")
	cur := []string{dir}
	for i, seg := range segs {
		last := i == len(segs)-1
		var next []string
		if seg == "**" && !last {
			for _, d := range cur {
				next = append(next, d)
				filepath.WalkDir(d, func(p string, de os.DirEntry, err error) error {
					if err != nil || p == d {
						return nil
					}
					if de.IsDir() {
						if strings.HasPrefix(de.Name(), ".") {
							return filepath.SkipDir
						}
						next = append(next, p)
					}
					return nil
				})
			}
			cur = next
			continue
		}
		if !strings.ContainsAny(seg, "*?[") {
			for _, d := range cur {
				next = append(next, d+"/"+seg)
			}
			cur = next
			continue
		}
		re := zshPattern(seg, false)
		for _, d := range cur {
			ents, err := os.ReadDir(d)
			if err != nil {
				continue
			}
			for _, e := range ents {
				n := e.Name()
				if strings.HasPrefix(n, ".") && !strings.HasPrefix(seg, ".") {
					continue
				}
				if re.MatchString(n) {
					next = append(next, d+"/"+n)
				}
			}
		}
		cur = next
	}
	var out []string
	for _, p := range cur {
		st, err := os.Lstat(p)
		if err == nil && st.Mode().IsRegular() && st.Size() > 0 {
			out = append(out, p)
		}
	}
	collate.Sort(out)
	return out
}
