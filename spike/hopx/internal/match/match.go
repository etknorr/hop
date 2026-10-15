// Package match is hop's one matcher: fzf in --filter mode with _HOP_MATCHER_FLAGS (lib/ui.zsh:384).
package match

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
)

// Flags is _HOP_MATCHER_FLAGS, read from lib/ui.zsh at the start of phase 2.
// - --accept-nth and --no-sort never reach --filter: fzf versions disagree on both there.
var Flags = []string{
	"--ansi",
	"--delimiter=\t",
	"--with-nth=1,4",
	"--exact",
	"-i",
	"--nth=..",
	"--no-tac",
	"--scheme=default",
	"--tiebreak=begin,chunk",
}

// Floor is the oldest fzf hop supports (_hop_fzf_ok).
const Floor = "0.60.3"

// Matcher filters rows by a query, best first, the way the picker would rank them.
type Matcher interface {
	Filter(query string, rows []string, extra ...string) ([]string, error)
}

// FZF forks the external fzf once per Filter call, as _hop_filter does.
type FZF struct {
	Bin    string
	Stderr io.Writer
	Calls  int
}

// New finds fzf on PATH.
func New(stderr io.Writer) (*FZF, error) {
	bin, err := exec.LookPath("fzf")
	if err != nil {
		return nil, errors.New("fzf is not installed")
	}
	return &FZF{Bin: bin, Stderr: stderr}, nil
}

func (f *FZF) env() []string {
	env := make([]string, 0, len(os.Environ())+2)
	for _, e := range os.Environ() {
		if strings.HasPrefix(e, "FZF_DEFAULT_OPTS=") || strings.HasPrefix(e, "FZF_DEFAULT_OPTS_FILE=") {
			continue
		}
		env = append(env, e)
	}
	// Set empty rather than only unset, which is exactly what _hop_filter's prefix assignment does.
	return append(env, "FZF_DEFAULT_OPTS=", "FZF_DEFAULT_OPTS_FILE=")
}

// Filter is _hop_match: the matching rows, SGR stripped by --ansi, or none. fzf's status 1 is "no match".
func (f *FZF) Filter(query string, rows []string, extra ...string) ([]string, error) {
	if len(rows) == 0 {
		return nil, nil
	}
	f.Calls++
	args := append([]string{"--filter=" + query}, Flags...)
	args = append(args, extra...)
	cmd := exec.Command(f.Bin, args...)
	cmd.Env = f.env()
	var in bytes.Buffer
	for _, r := range rows {
		in.WriteString(r)
		in.WriteByte('\n')
	}
	cmd.Stdin = &in
	cmd.Stderr = f.Stderr
	out, err := cmd.Output()
	if err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) && ee.ExitCode() == 1 {
			return nil, nil
		}
		return nil, fmt.Errorf("fzf --filter: %w", err)
	}
	return Lines(string(out)), nil
}

// Lines splits text on newlines and drops empty lines, as ${(@f)...} then ${x:#} does.
func Lines(s string) []string {
	var out []string
	for l := range strings.SplitSeq(s, "\n") {
		if l != "" {
			out = append(out, l)
		}
	}
	return out
}

var verRe = regexp.MustCompile(`^[0-9]+\.[0-9]+(\.[0-9]+)?`)

// Version is _hop_fzf_ver: the leading dotted number of `fzf --version`, or "" when it can't tell.
func (f *FZF) Version() string {
	out, err := exec.Command(f.Bin, "--version").Output()
	if err != nil {
		return ""
	}
	v := strings.TrimSpace(string(out))
	if i := strings.IndexFunc(v, func(r rune) bool { return (r < '0' || r > '9') && r != '.' }); i >= 0 {
		v = v[:i]
	}
	if verRe.FindString(v) != v {
		return ""
	}
	return v
}

// CheckVersion is _hop_fzf_ok: an fzf below Floor is refused, and one it can't read is allowed.
func (f *FZF) CheckVersion() error {
	v := f.Version()
	if v == "" || !Less(v, Floor) {
		return nil
	}
	return fmt.Errorf("fzf %s is too old; hopx needs %s or newer", v, Floor)
}

// Less is _hop_ver_lt: three dotted fields, non-digits stripped, a missing field counting as 0.
func Less(a, b string) bool {
	field := func(s string, i int) int {
		parts := strings.Split(s, ".")
		if i >= len(parts) {
			return 0
		}
		n, _ := strconv.Atoi(strings.Map(func(r rune) rune {
			if r < '0' || r > '9' {
				return -1
			}
			return r
		}, parts[i]))
		return n
	}
	for i := range 3 {
		if x, y := field(a, i), field(b, i); x != y {
			return x < y
		}
	}
	return false
}
