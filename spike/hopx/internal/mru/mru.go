// Package mru is hop's history, one absolute dir per line, most recent first: _hop_rank and _hop_remember.
package mru

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
)

// Load reads the history, dropping empty lines; a missing or unreadable file is an empty history.
func Load(path string) []string {
	if path == "" {
		return nil
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var out []string
	for l := range strings.SplitSeq(string(b), "\n") {
		if l != "" {
			out = append(out, l)
		}
	}
	return out
}

// dirOf is _hop_dirs_of for one row: field 2, or "" for a row with no TAB.
func dirOf(row string) string {
	_, rest, ok := strings.Cut(row, "\t")
	if !ok {
		return ""
	}
	d, _, _ := strings.Cut(rest, "\t")
	return d
}

// Rank is _hop_rank (hop.zsh:158): rows whose dir is in hist move to the front by first-seen rank, then input index.
// - Every other row keeps its input order, behind them.
func Rank(rows, hist []string) []string {
	if len(hist) == 0 {
		return rows
	}
	rank := make(map[string]int, len(hist))
	for _, h := range hist {
		if _, ok := rank[h]; !ok {
			rank[h] = len(rank) + 1
		}
	}
	type keyed struct{ rank, idx int }
	var front []keyed
	rest := make([]string, 0, len(rows))
	for i, r := range rows {
		if n, ok := rank[dirOf(r)]; ok {
			front = append(front, keyed{n, i})
		} else {
			rest = append(rest, r)
		}
	}
	if len(front) == 0 {
		return rows
	}
	slices.SortStableFunc(front, func(a, b keyed) int {
		if a.rank != b.rank {
			return a.rank - b.rank
		}
		return a.idx - b.idx
	})
	out := make([]string, 0, len(rows))
	for _, k := range front {
		out = append(out, rows[k.idx])
	}
	return append(out, rest...)
}

func isDir(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.IsDir()
}

// Remember is _hop_remember (lib/actions.zsh:57): dir to the front, deduped, absolute and live dirs only, max kept.
// - Written to a temp file in the same dir and renamed, so a concurrent reader sees the old file or the new one.
// - Like hop, every failure is silent: a history that can't be written must never fail a jump.
func Remember(path, dir string, max int) {
	if dir == "" || path == "" {
		return
	}
	d := filepath.Dir(path)
	if err := os.MkdirAll(d, 0o755); err != nil {
		return
	}
	h := []string{dir}
	for _, e := range Load(path) {
		if e != dir {
			h = append(h, e)
		}
	}
	kept := h[:0]
	for _, e := range h {
		if strings.HasPrefix(e, "/") && isDir(e) {
			kept = append(kept, e)
		}
	}
	if max > 0 && len(kept) > max {
		kept = kept[:max]
	}
	f, err := os.CreateTemp(d, ".history.*")
	if err != nil {
		return
	}
	tmp := f.Name()
	_, werr := f.WriteString(strings.Join(kept, "\n") + "\n")
	cerr := f.Close()
	if werr != nil || cerr != nil {
		os.Remove(tmp)
		return
	}
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
	}
}
