// Package kinds is hop's enumeration engine (lib/dsl.zsh) plus the builtin providers (lib/providers.zsh).
package kinds

import (
	"fmt"
	"io"
	"os"
	"path"
	"runtime"
	"sort"
	"strings"
	"sync"

	"github.com/etknorr/hop/internal/collate"
	"github.com/etknorr/hop/internal/config"
	"github.com/etknorr/hop/internal/gitls"
	"github.com/etknorr/hop/internal/rows"
)

// Engine enumerates kinds in one repo root, sharing one index listing across every kind.
type Engine struct {
	Root   string
	Stderr io.Writer

	once sync.Once
	ix   *gitls.Index
	err  error
	warn sync.Once
}

func New(root string, stderr io.Writer) *Engine {
	if stderr == nil {
		stderr = io.Discard
	}
	return &Engine{Root: root, Stderr: stderr}
}

// ls is _hop_ls against the shared listing; a git failure is reported once and yields no paths.
func (e *Engine) ls(specs ...string) ([]string, bool) {
	e.once.Do(func() { e.ix, e.err = gitls.List(e.Root) })
	if e.err != nil {
		e.warn.Do(func() { fmt.Fprintln(e.Stderr, "hop:", e.err) })
		return nil, false
	}
	out, err := e.ix.Match(specs...)
	if err != nil {
		fmt.Fprintln(e.Stderr, "hop:", err)
		return nil, false
	}
	return out, true
}

func isDir(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.IsDir()
}

func isRegular(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.Mode().IsRegular()
}

// nonEmptyFile is [[ -f p && -s p ]], following symlinks (providers.zsh:185).
func nonEmptyFile(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.Mode().IsRegular() && st.Size() > 0
}

// nonEmpty is [[ -s p ]]: exists with a size above zero, of any type, following symlinks.
func nonEmpty(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.Size() > 0
}

// zHead and zTail are zsh's :h and :t, where :h of a bare name is '.' and :t of "" is "".
func zHead(p string) string { return path.Dir(p) }

func zTail(p string) string {
	if p == "" {
		return ""
	}
	return path.Base(p)
}

// childDirs is _hop_child_dirs: unique depth-N prefixes under fam/, in index order, .gitkeep-only skipped.
func (e *Engine) childDirs(fam string, depth int) ([]string, bool) {
	ls, ok := e.ls(fam + "/")
	if !ok {
		return nil, false
	}
	seen := map[string]bool{}
	var out []string
	for _, p := range ls {
		p = strings.TrimPrefix(p, fam+"/")
		if strings.HasSuffix(p, "/.gitkeep") {
			continue
		}
		segs := config.SplitNonEmpty(p, "/")
		if len(segs) <= depth {
			continue
		}
		c := strings.Join(segs[:depth], "/")
		if !seen[c] {
			seen[c] = true
			out = append(out, c)
		}
	}
	return out, true
}

func skipped(name string, skips []string) bool {
	for _, s := range skips {
		if zshPattern(s, true).MatchString(name) {
			return true
		}
	}
	return false
}

// previewFor is _hop_dsl_preview: the first candidate naming a non-empty file, else the dir.
// - A literal candidate is only `-s` there, so a directory named main.tf wins; kept for byte parity.
func previewFor(dir string, k *config.Kind) string {
	for _, c := range k.Preview {
		if strings.ContainsAny(c, "*?") {
			for _, f := range zglob(dir, c) {
				if !skipped(path.Base(f), k.PreviewSkip) {
					return f
				}
			}
			continue
		}
		p := dir + "/" + c
		if nonEmpty(p) && !skipped(path.Base(c), k.PreviewSkip) {
			return p
		}
	}
	return dir
}

func excluded(k *config.Kind, rel string) bool {
	for _, p := range k.Exclude {
		if zshPattern(p, true).MatchString(rel) {
			return true
		}
	}
	return false
}

type cols struct{ scope, env, region, name string }

type layout struct {
	key  string
	cols []string
}

// columns is _hop_dsl_columns: map path segments onto scope/env/region/name; false when no layout fits.
// - Layouts are tried longest first; ties go to the reverse-sorted layout text, as zsh's (O) sort does.
// - With no layout, trim and name_template are skipped, exactly as the early return at dsl.zsh:231 does.
func columns(k *config.Kind, p string) (cols, bool) {
	c := cols{"-", "-", "-", "-"}
	if len(k.Layouts) == 0 {
		c.name = zTail(p)
		c.scope = zHead(p)
		if c.scope == p {
			c.scope = "-"
		}
		return c, true
	}
	segs := config.SplitNonEmpty(p, "/")
	lays := make([]layout, 0, len(k.Layouts))
	for _, l := range k.Layouts {
		lc := config.SplitNonEmpty(l, ",")
		lays = append(lays, layout{fmt.Sprintf("%03d\t%s", len(lc), l), lc})
	}
	sort.SliceStable(lays, func(i, j int) bool { return collate.Compare(lays[i].key, lays[j].key) > 0 })
	matched := false
	for _, l := range lays {
		want := len(l.cols)
		if want == 0 {
			continue
		}
		greedy := strings.HasSuffix(l.cols[want-1], "...")
		if (greedy && len(segs) < want) || (!greedy && len(segs) != want) {
			continue
		}
		for i, col := range l.cols {
			val := segs[i]
			if strings.HasSuffix(col, "...") {
				col = strings.TrimSuffix(col, "...")
				val = strings.Join(segs[i:], "/")
			}
			switch col {
			case "scope":
				c.scope = val
			case "env":
				c.env = val
			case "region":
				c.region = val
			case "name":
				c.name = val
			}
		}
		matched = true
		break
	}
	if !matched {
		return c, false
	}
	for _, t := range k.Trim {
		switch t.Col {
		case "scope":
			c.scope = strings.TrimPrefix(c.scope, t.Prefix)
		case "env":
			c.env = strings.TrimPrefix(c.env, t.Prefix)
		case "region":
			c.region = strings.TrimPrefix(c.region, t.Prefix)
		case "name":
			c.name = strings.TrimPrefix(c.name, t.Prefix)
		}
	}
	if k.NameTemplate != "" {
		n := strings.ReplaceAll(k.NameTemplate, "{scope}", c.scope)
		n = strings.ReplaceAll(n, "{env}", c.env)
		n = strings.ReplaceAll(n, "{region}", c.region)
		c.name = n
	}
	return c, true
}

func orDefault(lit, v string) string {
	if lit != "" {
		return lit
	}
	return v
}

// parallel runs f over [0,n) on a worker per CPU; previews and stats are the I/O-bound part of enumeration.
func parallel(n int, f func(i int)) {
	w := min(runtime.GOMAXPROCS(0), 8, n)
	if w <= 1 {
		for i := 0; i < n; i++ {
			f(i)
		}
		return
	}
	var wg sync.WaitGroup
	var next int
	var mu sync.Mutex
	for range w {
		wg.Go(func() {
			for {
				mu.Lock()
				i := next
				next++
				mu.Unlock()
				if i >= n {
					return
				}
				f(i)
			}
		})
	}
	wg.Wait()
}

// withPreviews fills each row's preview from fn in parallel, keeping row order.
func withPreviews(rs []rows.Row, fn func(dir string) string) []rows.Row {
	parallel(len(rs), func(i int) { rs[i].Preview = fn(rs[i].Dir) })
	return rs
}

func (e *Engine) emitDirs(k *config.Kind) []rows.Row {
	var rs []rows.Row
	for _, base := range k.Dirs {
		if base == "" || !isDir(e.Root+"/"+base) {
			continue
		}
		kids, ok := e.childDirs(base, k.Depth)
		if !ok {
			continue
		}
		for _, child := range kids {
			dir := e.Root + "/" + base + "/" + child
			rs = append(rs, rows.New(k.Name, orDefault(k.Scope, base), "-", "-", child, dir, "", false))
		}
	}
	return withPreviews(rs, func(dir string) string { return previewFor(dir, k) })
}

func (e *Engine) emitFiles(k *config.Kind) []rows.Row {
	ls, ok := e.ls(k.Files...)
	if !ok {
		return nil
	}
	keep := make([]bool, len(ls))
	parallel(len(ls), func(i int) { keep[i] = isRegular(e.Root + "/" + ls[i]) })
	var rs []rows.Row
	for i, rel := range ls {
		if !keep[i] || excluded(k, rel) {
			continue
		}
		abs := e.Root + "/" + rel
		p := rel
		if k.Under != "" {
			p = strings.TrimPrefix(p, k.Under+"/")
		}
		// ${path%.*} cuts at the LAST dot anywhere, so an extensionless file in a dotted dir loses the dir.
		if k.StripExt {
			if i := strings.LastIndex(p, "."); i >= 0 {
				p = p[:i]
			}
		}
		c, ok := columns(k, p)
		if !ok {
			continue
		}
		if k.NameFrom == "yaml:metadata.name" {
			c.name = entityName(abs)
		}
		rs = append(rs, rows.New(k.Name, orDefault(k.Scope, c.scope), c.env, c.region, c.name, zHead(abs), abs, true))
	}
	return rs
}

// markerTail is the part of rel that one of k's markers matched, such as Chart.yaml or manifests/init.pp.
func markerTail(rel string, markers []string) (string, bool) {
	segs := strings.Split(rel, "/")
	for _, m := range markers {
		n := strings.Count(m, "/") + 1
		if len(segs) < n {
			continue
		}
		tail := strings.Join(segs[len(segs)-n:], "/")
		if mt, err := gitls.Compile(m); err == nil && mt.Match(tail) {
			return tail, true
		}
	}
	return "", false
}

// emitMarker is _hop_dsl_emit's marker shape: one row per dir holding any of the kind's markers.
// - p keeps dsl.zsh's ${rel%/$marker}, which leaves a root-level marker's own name, so a root row is named after its marker.
// - min_depth and nested read the real dir instead, and nested runs after min_depth and exclude.
func (e *Engine) emitMarker(k *config.Kind) []rows.Row {
	prefix := ""
	if k.Under != "" {
		if !isDir(e.Root + "/" + k.Under) {
			return nil
		}
		prefix = k.Under + "/"
	}
	specs := make([]string, len(k.Marker))
	for i, m := range k.Marker {
		specs[i] = prefix + "**/" + m
	}
	ls, ok := e.ls(specs...)
	if !ok {
		return nil
	}
	type hit struct{ dir, p string }
	var hits []hit
	seen := map[string]bool{}
	for _, rel := range ls {
		if excluded(k, rel) {
			continue
		}
		tail, ok := markerTail(rel, k.Marker)
		if !ok {
			continue
		}
		dir := strings.TrimSuffix(strings.TrimSuffix(rel, tail), "/")
		if seen[dir] {
			continue
		}
		if k.MinDepth > 0 {
			below := dir
			if k.Under != "" {
				below = strings.TrimPrefix(strings.TrimPrefix(dir, k.Under), "/")
			}
			if len(config.SplitNonEmpty(below, "/")) < k.MinDepth {
				continue
			}
		}
		seen[dir] = true
		p := strings.TrimSuffix(rel, "/"+tail)
		if k.Under != "" {
			p = strings.TrimPrefix(p, prefix)
		}
		hits = append(hits, hit{dir, p})
	}
	var rs []rows.Row
	for _, h := range hits {
		if !k.Nested && insideAnother(h.dir, seen) {
			continue
		}
		c, ok := columns(k, h.p)
		if !ok {
			continue
		}
		dir := e.Root
		if h.dir != "" {
			dir += "/" + h.dir
		}
		rs = append(rs, rows.New(k.Name, orDefault(k.Scope, c.scope), c.env, c.region, c.name, dir, "", false))
	}
	return withPreviews(rs, func(dir string) string { return previewFor(dir, k) })
}

// insideAnother reports whether a strict ancestor of dir, the root ("") included, is also a match.
func insideAnother(dir string, matches map[string]bool) bool {
	if dir == "" {
		return false
	}
	if matches[""] {
		return true
	}
	for i := len(dir) - 1; i > 0; i-- {
		if dir[i] == '/' && matches[dir[:i]] {
			return true
		}
	}
	return false
}

// Emit returns one kind's rows, whatever its shape; a kind with sources emits them source by source, in order.
func (e *Engine) Emit(k *config.Kind) []rows.Row {
	switch k.Shape {
	case "dirs":
		return e.emitDirs(k)
	case "files":
		return e.emitFiles(k)
	case "marker":
		return e.emitMarker(k)
	case "sources":
		var rs []rows.Row
		for _, s := range k.Sources {
			rs = append(rs, e.Emit(s)...)
		}
		return rs
	case "builtin":
		if k.Builtin == "dir" {
			return e.builtinDir(k)
		}
	case "exec":
		rs, err := e.emitExec(k)
		if err != nil {
			fmt.Fprintln(e.Stderr, "hop:", err)
		}
		return rs
	}
	return nil
}

// Generate is _hop_generate: kinds run concurrently, and rows come back in kind order.
func Generate(cfg *config.Config, root string, names []string, stderr io.Writer) []rows.Row {
	e := New(root, stderr)
	res := make([][]rows.Row, len(names))
	var wg sync.WaitGroup
	for i, n := range names {
		if n == "" {
			continue
		}
		k, ok := cfg.Lookup(n)
		if !ok {
			fmt.Fprintln(e.Stderr, "hop: unknown kind:", n)
			continue
		}
		wg.Go(func() { res[i] = e.Emit(k) })
	}
	wg.Wait()
	var all []rows.Row
	for _, r := range res {
		all = append(all, r...)
	}
	return all
}
