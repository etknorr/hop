// Package rows is hop's 4-field row: <display> TAB <dir> TAB <preview> TAB <rel> (lib/providers.zsh:68-95).
package rows

import (
	"os"
	"strings"
	"sync/atomic"
	"unicode/utf8"
)

const (
	Off    = "\x1b[0m"
	CKind  = "\x1b[1;36m"
	CScope = "\x1b[34m"
	CReg   = "\x1b[36m"
	CName  = "\x1b[1m"
	CDim   = "\x1b[2m"

	WName  = 28
	WKind  = 5
	WScope = 22
	WEnv   = 9
)

// Row holds a target before rendering. File marks a file target, where Preview is the destination.
type Row struct {
	Kind, Scope, Env, Region, Name, Dir, Preview string
	File                                         bool
}

func dash(s string) string {
	if s == "" {
		return "-"
	}
	return s
}

// New is _hop_row's argument contract: an empty column is '-', and an empty preview is the dir.
func New(kind, scope, env, region, name, dir, preview string, file bool) Row {
	if preview == "" {
		preview = dir
	}
	return Row{dash(kind), dash(scope), dash(env), dash(region), dash(name), dir, preview, file}
}

// Fit is _hop_fit: clip to w characters with an ellipsis, keeping the end when tail is set.
func Fit(s string, w int, tail bool) string {
	n := utf8.RuneCountInString(s)
	if n <= w {
		return s
	}
	r := []rune(s)
	if tail {
		return "…" + string(r[n-w+1:])
	}
	return string(r[:w-1]) + "…"
}

// pad is zsh's printf %-Ns, which counts characters rather than bytes under a UTF-8 locale.
func pad(b *strings.Builder, s string, w int) {
	b.WriteString(s)
	for n := utf8.RuneCountInString(s); n < w; n++ {
		b.WriteByte(' ')
	}
}

// Tilde is zsh's ${(D)p} restricted to $HOME; hop's named directories are not modelled.
func Tilde(p string) string {
	home := os.Getenv("HOME")
	if home == "" || home == "/" {
		return p
	}
	if p == home {
		return "~"
	}
	if strings.HasPrefix(p, home+"/") {
		return "~" + p[len(home):]
	}
	return p
}

// Rel is _hop_rel: the target relative to root, with a trailing / on a dir target, else its ~ form.
func Rel(r Row, root string) string {
	p, tail := r.Dir, "/"
	if r.File {
		p, tail = r.Preview, ""
	}
	switch {
	case root != "" && p == root:
		return "./"
	case root != "" && strings.HasPrefix(p, root+"/"):
		return p[len(root)+1:] + tail
	}
	return Tilde(p) + tail
}

var classColour = map[string]string{"prod": "\x1b[31m", "staging": "\x1b[33m", "dev": "\x1b[34m"}

var envColours atomic.Pointer[map[string]string]

func init() {
	SetEnvColors(map[string][]string{"prod": {"prod"}, "staging": {"staging"}, "dev": {"dev"}})
}

// SetEnvColors maps each env word to its class's colour (prod red, staging yellow, dev blue); the last class naming a word wins.
func SetEnvColors(classes map[string][]string) {
	m := map[string]string{}
	for _, cls := range []string{"prod", "staging", "dev"} {
		for _, w := range classes[cls] {
			m[w] = classColour[cls]
		}
	}
	envColours.Store(&m)
}

func envColour(env string) string {
	if env == "-" {
		return CDim
	}
	if c, ok := (*envColours.Load())[env]; ok {
		return c
	}
	return "\x1b[35m"
}

// Render is _hop_row's output line, without the trailing newline.
func Render(r Row, root string) string {
	r = New(r.Kind, r.Scope, r.Env, r.Region, r.Name, r.Dir, r.Preview, r.File)
	cs, cr := CScope, CReg
	if r.Scope == "-" {
		cs = CDim
	}
	if r.Region == "-" {
		cr = CDim
	}
	var b strings.Builder
	b.Grow(160 + 2*len(r.Dir) + len(r.Preview))
	b.WriteString(CName)
	pad(&b, r.Name, WName)
	b.WriteString(Off + " " + CKind)
	pad(&b, Fit(r.Kind, WKind, false), WKind)
	b.WriteString(Off + " " + cs)
	pad(&b, Fit(r.Scope, WScope, true), WScope)
	b.WriteString(Off + " " + envColour(r.Env))
	pad(&b, Fit(r.Env, WEnv, false), WEnv)
	b.WriteString(Off + " " + cr + r.Region + Off)
	b.WriteString("\t" + r.Dir + "\t" + r.Preview + "\t" + CDim + Rel(r, root) + Off)
	return b.String()
}

// Split is _hop_row_split: TAB fields with empties kept; a legacy 3-field row gets an empty rel.
func Split(line string) []string {
	f := strings.Split(line, "\t")
	for len(f) < 4 {
		f = append(f, "")
	}
	return f
}

// StripANSI drops SGR sequences, which is how parity compares rows as plain text.
func StripANSI(s string) string {
	if !strings.Contains(s, "\x1b[") {
		return s
	}
	var b strings.Builder
	b.Grow(len(s))
	for i := 0; i < len(s); i++ {
		if s[i] == 0x1b && i+1 < len(s) && s[i+1] == '[' {
			j := i + 2
			for j < len(s) && (s[j] == ';' || s[j] >= '0' && s[j] <= '9') {
				j++
			}
			if j < len(s) && s[j] == 'm' {
				i = j
				continue
			}
		}
		b.WriteByte(s[i])
	}
	return b.String()
}
