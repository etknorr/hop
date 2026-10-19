package pick

import (
	"strings"

	"github.com/etknorr/hop/internal/rows"
)

// Result is what fzf returned: the key (empty for plain Enter) and the --accept-nth fields.
type Result struct{ Key, Dir, Preview, Rel string }

// Parse is _hop_parse_result.
// - The last line is the accept-nth fields; the key is the first non-empty line before it, which covers print()+accept's extra line.
// - Fields split with empties kept, rel loses its dim SGR, and an empty preview is the dir.
func Parse(out string) (Result, bool) {
	var r Result
	out = strings.TrimRight(out, "\n")
	if out == "" {
		return r, false
	}
	lines := strings.Split(out, "\n")
	for _, l := range lines[:len(lines)-1] {
		if l != "" {
			r.Key = l
			break
		}
	}
	f := rows.Split(lines[len(lines)-1])
	get := func(i int) string {
		if i < len(f) {
			return f[i]
		}
		return ""
	}
	r.Dir, r.Preview, r.Rel = get(0), get(1), rows.StripANSI(get(2))
	if r.Preview == "" {
		r.Preview = r.Dir
	}
	return r, r.Dir != ""
}
