// Package resolve is a function-by-function port of hop's resolver, lib/match.zsh.
// - Each function names its zsh original in its doc line, so the two can be read side by side.
// - Clear enough to jump is structural, never a score, and fzf stays the only matcher, as in hop.
package resolve

import (
	"fmt"
	"os"
	"path"
	"slices"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/etknorr/hop/internal/collate"
	"github.com/etknorr/hop/internal/match"
	"github.com/etknorr/hop/internal/rows"
)

// ApproxMax is _HOP_APPROX_MAX: above this many rows T2 and T3 are skipped.
const ApproxMax = 6000

// Target is a row's (dir preview rel), rel undimmed, as _hop_res_fields returns it.
type Target struct{ Dir, Preview, Rel string }

// String is the TAB-joined form _hop_res_target holds.
func (t Target) String() string {
	if t == (Target{}) {
		return ""
	}
	return t.Dir + "\t" + t.Preview + "\t" + t.Rel
}

// Result mirrors the _hop_res_* fields.
type Result struct {
	Verdict, Tier, Rule, Query, Note string
	Target                           Target
	N, M, Inj                        int
	Rows                             []string
}

// Resolver carries _hop_resolve's arguments other than the query and rows.
// - Root is "" for the workspace and repo levels, which turns off synthetic rows and J2.
// - Under is the -c subtree, absolute, or "".
// - Kinds is _HOP_ALL_KINDS, which joins the T2 vocabulary and drives J2's kind-word guard.
type Resolver struct {
	Match  match.Matcher
	Root   string
	Action string
	Jump   string
	Under  string
	Kinds  []string
	// Like is a row of the list being resolved, so the ancestor rows it injects line up with it (_hop_row_like).
	Like string
	// Vim is the modal layer, which the T4 hint names esc for.
	Vim bool

	err error
}

// Err is the first matcher failure of the last Resolve; hop lets fzf's own stderr speak and reads it as no match.
func (r *Resolver) Err() error { return r.err }

func (r *Resolver) match(q string, rs []string, extra ...string) []string {
	out, err := r.Match.Filter(q, rs, extra...)
	if err != nil && r.err == nil {
		r.err = err
	}
	return out
}

// RelOf is _hop_rels_of for one row: its last field, SGR stripped.
func RelOf(row string) string {
	if i := strings.LastIndexByte(row, '\t'); i >= 0 {
		row = row[i+1:]
	}
	return rows.StripANSI(row)
}

func relsOf(rs []string) []string {
	out := make([]string, len(rs))
	for i, r := range rs {
		out[i] = RelOf(r)
	}
	return out
}

// Fields is _hop_res_fields: (dir preview rel), rel undimmed and an empty preview read as the dir.
func Fields(row string) Target {
	f := strings.Split(row, "\t")
	get := func(i int) string {
		if i < len(f) {
			return f[i]
		}
		return ""
	}
	t := Target{get(1), get(2), rows.StripANSI(get(3))}
	if t.Preview == "" {
		t.Preview = t.Dir
	}
	return t
}

func display(row string) string {
	d, _, _ := strings.Cut(row, "\t")
	return d
}

func dirOf(row string) string {
	return Fields(row).Dir
}

// zHead is zsh's :h on a relative or absolute path.
func zHead(p string) string { return path.Dir(p) }

// minimal is _hop_minimal: the rels no other given rel is an ancestor of, sorted by collation.
func minimal(rels []string) []string {
	have := map[string]bool{}
	for _, r := range rels {
		have[r] = true
	}
	var out []string
	for r := range have {
		p := strings.TrimSuffix(r, "/")
		keep := true
		for strings.Contains(p, "/") {
			p = p[:strings.LastIndexByte(p, '/')]
			if have[p+"/"] {
				keep = false
				break
			}
		}
		if keep {
			out = append(out, r)
		}
	}
	collate.Sort(out)
	return out
}

// ancestors is _hop_ancestors: every strict ancestor dir of the rels, minus dirs already among them.
// - The walk stops at `.`; a `~` or absolute rel names no ancestor inside the repo.
// - under is the -c subtree relative to the root, or ""; only ancestors strictly beneath it survive.
func ancestors(under string, rels []string) []string {
	have := map[string]bool{}
	var cur []string
	for _, r := range rels {
		if strings.HasSuffix(r, "/") {
			have[strings.TrimSuffix(r, "/")] = true
		}
		if strings.HasPrefix(r, "/") || strings.HasPrefix(r, "~") {
			continue
		}
		cur = append(cur, zHead(strings.TrimSuffix(r, "/")))
	}
	cur = uniq(cur)
	var anc []string
	for len(cur) > 0 {
		next := cur[:0:0]
		for _, c := range cur {
			if c != "." && c != "/" {
				next = append(next, c)
			}
		}
		anc = append(anc, next...)
		cur = cur[:0:0]
		for _, c := range next {
			cur = append(cur, zHead(c))
		}
		cur = uniq(cur)
	}
	var out []string
	for _, a := range uniq(anc) {
		if have[a] {
			continue
		}
		if under != "" && !strings.HasPrefix(a, under+"/") {
			continue
		}
		out = append(out, a)
	}
	return out
}

func isSep(b byte) bool { return b == '/' || b == '_' || b == '.' || b == '-' }

// aligned is _hop_aligned: every term names a whole token run of the dir, and one of them its last segment.
func aligned(dirRel string, terms []string) bool {
	x := "/" + strings.ToLower(dirRel)
	last := false
	for _, t := range terms {
		t = strings.TrimSuffix(strings.TrimPrefix(t, "/"), "/")
		found := false
		for i := 1; i+len(t) < len(x); i++ {
			if isSep(x[i-1]) && strings.HasPrefix(x[i:], t) && isSep(x[i+len(t)]) {
				found = true
				break
			}
		}
		if !found {
			return false
		}
		if n := len(x) - len(t) - 1; n >= 1 && strings.HasSuffix(x, t+"/") && isSep(x[n-1]) {
			last = true
		}
	}
	return last
}

// coherence is _hop_coherence: the rows, stably bucketed by how many query terms one rel segment holds.
// - An OR group counts once and a negated term never counts; it only runs on 2+ terms and 500 rows or fewer.
func coherence(q string, rs []string) []string {
	var pats []string
	join := false
	for _, w := range splitWS(strings.ToLower(q)) {
		if w == "|" {
			join = true
			continue
		}
		if strings.HasPrefix(w, "'") || strings.HasPrefix(w, "^") {
			w = w[1:]
		}
		w = strings.TrimSuffix(w, "$")
		if join && len(pats) > 0 {
			pats[len(pats)-1] += "|" + w
		} else {
			pats = append(pats, w)
		}
		join = false
	}
	pats = slices.DeleteFunc(pats, func(p string) bool { return strings.HasPrefix(p, "!") })
	if len(pats) < 2 || len(rs) > 500 {
		return rs
	}
	scores := make([]int, len(rs))
	top := 0
	for i, r := range rs {
		best := 0
		for seg := range strings.SplitSeq(strings.ToLower(RelOf(r)), "/") {
			c := 0
			for _, p := range pats {
				for a := range strings.SplitSeq(p, "|") {
					if strings.Contains(seg, a) {
						c++
						break
					}
				}
			}
			best = max(best, c)
		}
		scores[i] = best
		top = max(top, best)
	}
	out := make([]string, 0, len(rs))
	for s := top; s >= 0; s-- {
		for i, r := range rs {
			if scores[i] == s {
				out = append(out, r)
			}
		}
	}
	return out
}

// readme is the first of root/x's (#i)README*(.N), the preview an injected dir gets.
func readme(dir string) string {
	ents, err := os.ReadDir(dir)
	if err != nil {
		return ""
	}
	var hits []string
	for _, e := range ents {
		if !e.Type().IsRegular() || !strings.HasPrefix(strings.ToLower(e.Name()), "readme") {
			continue
		}
		hits = append(hits, dir+"/"+e.Name())
	}
	if len(hits) == 0 {
		return ""
	}
	collate.Sort(hits)
	return hits[0]
}

// state is one _hop_resolve call's locals, which hop's helpers read through dynamic scope.
type state struct {
	*Resolver
	q     string
	all   []string
	rels  []string
	v     *vocab
	text  string
	tried string
	res   Result
}

// decide is _hop_decide: the verdict for rows M, which matched eq.
// - Intermediate dirs come in as synthetic rows, one per strict ancestor of a match that is not already one.
// - They are filtered by the same query, so only an ancestor the query itself names is ever offered.
func (s *state) decide(tier, eq string, approx, opq bool, M []string) {
	R := relsOf(M)
	var anc []string
	if !opq && s.Root != "" {
		under := ""
		if s.Under != "" {
			under = strings.TrimPrefix(s.Under, s.Root+"/")
		}
		anc = ancestors(under, R)
	}
	synby := map[string]string{}
	var S, srels []string
	if len(anc) > 0 {
		raw := make([]rows.Row, len(anc))
		for i, a := range anc {
			scope := zHead(a)
			if scope == "." {
				scope = "-"
			}
			d := s.Root + "/" + a
			raw[i] = rows.New("dir", scope, "-", "-", path.Base(a), d, d, false)
		}
		var like *rows.Widths
		if w, ok := rows.ParseWidths(s.Like); ok {
			like = &w
		}
		syn := rows.List(raw, s.Root, like)
		for _, r := range syn {
			synby[RelOf(r)] = r
		}
		S = s.match(eq, syn)
		srels = relsOf(S)
	}
	var dirs []string
	for _, r := range srels {
		if strings.HasSuffix(r, "/") {
			dirs = append(dirs, r)
		}
	}
	for _, r := range R {
		if strings.HasSuffix(r, "/") {
			dirs = append(dirs, r)
		}
	}
	X := minimal(dirs)

	var inj []string
	for _, x := range X {
		if !slices.Contains(srels, x) {
			continue
		}
		r := synby[x]
		if rd := readme(s.Root + "/" + strings.TrimSuffix(x, "/")); rd != "" {
			f := strings.Split(r, "\t")
			f[2] = rd
			r = strings.Join(f, "\t")
		}
		inj = append(inj, r)
	}
	cand := append(slices.Clone(inj), M...)
	s.res.Tier, s.res.Query = tier, eq
	s.res.N, s.res.M, s.res.Inj = len(cand), len(M), len(inj)

	s.res.Verdict = "pick"
	if !approx && s.Jump != "never" {
		s.decideJump(tier, eq, opq, M, R, srels, inj, X, cand)
	}
	if s.res.Verdict == "jump" {
		return
	}
	s.res.Rows = append(slices.Clone(inj), coherence(eq, M)...)
}

func (s *state) jump(rule string, t Target) {
	s.res.Verdict, s.res.Rule, s.res.Target = "jump", rule, t
}

// unclip is _hop_unclip: the row with its clipped name restored from its rel, or false when rel cannot say what was cut.
// - Only the name: a clipped scope or env leaves no trace in rel, and neither does a name read from a file.
// - The name may be the rel's last segments, with or without the extension; the rel is tried whole, then from its last / back.
func unclip(row string) (string, bool) {
	disp, tail, _ := strings.Cut(row, "\t")
	d := rows.StripANSI(disp)
	name, rest := d, ""
	if i := strings.IndexByte(d, ' '); i >= 0 {
		name, rest = d[:i], d[i:]
	}
	a, b, ok := strings.Cut(name, "…")
	if !ok || a == "" || b == "" || strings.Contains(rest, "…") {
		return "", false
	}
	f := strings.Split(row, "\t")
	rel := strings.TrimSuffix(rows.StripANSI(f[len(f)-1]), "/")
	cands := []string{rel}
	if i := strings.LastIndexByte(rel, '.'); i >= 0 {
		cands = append(cands, rel[:i])
	}
	for _, r := range cands {
		starts := []int{0}
		for i := len(r) - 1; i >= 0; i-- {
			if r[i] == '/' {
				starts = append(starts, i+1)
			}
		}
		for _, st := range starts {
			x := r[st:]
			if strings.HasPrefix(x, a) && strings.HasSuffix(x, b) && utf8.RuneCountInString(x) > utf8.RuneCountInString(a)+utf8.RuneCountInString(b) {
				return x + rest + "\t" + tail, true
			}
		}
	}
	return "", false
}

// decideJump is _hop_decide_jump: J1, J1b, J3, J0 and J2, in that order.
// - J3 runs before J2, which is what keeps every jump the display-only matcher made.
func (s *state) decideJump(tier, eq string, opq bool, M, R, srels, inj, X, cand []string) {
	if len(cand) == 1 {
		s.jump("single", Fields(cand[0]))
		return
	}
	// J1b: one identity across M; under cd that is the dir, so files sharing one dir collapse.
	if len(inj) == 0 {
		var ident []string
		if s.Action == "cd" {
			for _, m := range M {
				ident = append(ident, dirOf(m))
			}
		} else {
			ident = slices.Clone(R)
		}
		if len(uniq(ident)) == 1 {
			t := Fields(M[0])
			if s.Action == "cd" && !strings.HasSuffix(t.Rel, "/") {
				t.Rel = zHead(t.Rel) + "/"
			}
			s.jump("onedir", t)
			return
		}
	}
	// J3: one display hit still jumps, unless another match has a clipped column that only hid the words.
	// - A clipped name its rel spells out whole is matched whole instead (hop 0.3.0), so a narrow name column costs no jump.
	if hits := s.match(eq, M, "--nth=1"); len(hits) == 1 {
		clipped, unclipped := false, false
		whole := make([]string, 0, len(M))
		for _, m := range M {
			if m != hits[0] && strings.Contains(display(m), "…") {
				if u, ok := unclip(m); ok {
					m, unclipped = u, true
				} else {
					clipped = true
				}
			}
			whole = append(whole, m)
		}
		if !clipped && unclipped && len(s.match(eq, whole, "--nth=1")) != 1 {
			clipped = true
		}
		if !clipped {
			s.jump("display", Fields(hits[0]))
			return
		}
	}
	if s.Jump == "unique" {
		return
	}

	// J0, the workspace and repo levels only: one row's name is the whole query.
	if s.Root == "" && tier == "T1" && !opq && !strings.ContainsFunc(eq, unicode.IsSpace) {
		var named []string
		for _, row := range M {
			if w := strings.Fields(display(row)); len(w) > 0 && strings.ToLower(w[0]) == strings.ToLower(eq) {
				named = append(named, row)
			}
		}
		if len(named) == 1 {
			t := Fields(named[0])
			s.jump("name", t)
			if len(M) == 2 {
				s.res.Note = fmt.Sprintf("hop: %s -> %s (exact name; 1 other contains it)", s.q, t.Rel)
			} else {
				s.res.Note = fmt.Sprintf("hop: %s -> %s (exact name; %d others contain it)", s.q, t.Rel, len(M)-1)
			}
			return
		}
	}

	// J2: every match lies under one dir the query names on token boundaries, and no term is a kind word.
	if len(X) != 1 || opq || s.Root == "" {
		return
	}
	for _, r := range append(slices.Clone(srels), R...) {
		if !strings.HasPrefix(r, X[0]) {
			return
		}
	}
	terms := splitWS(strings.ToLower(eq))
	for _, t := range terms {
		if slices.Contains(s.Kinds, t) {
			return
		}
	}
	if !aligned(X[0], terms) {
		return
	}
	var row string
	if slices.Contains(srels, X[0]) {
		row = inj[0]
	} else {
		row = M[slices.Index(R, X[0])]
	}
	s.jump("dir", Fields(row))
	s.res.Note = fmt.Sprintf("hop: %s -> %s (all %d matches are under it)", s.q, X[0], len(M))
	if tier == "T2a" {
		s.res.Note += " (read as: " + eq + ")"
	}
}

// Resolve is _hop_resolve: T1, then T2a/T2 rewrites, T3 loose, relaxed, all-but-one, and T4.
// - A query holding ' ^ $ ! or | is the user's own fzf syntax, so it gets T1 alone.
func (r *Resolver) Resolve(q string, rs []string) Result {
	r.err = nil
	s := &state{Resolver: r, q: q}
	for _, row := range rs {
		if row != "" {
			s.all = append(s.all, row)
		}
	}
	s.res = Result{Verdict: "none", Query: q}

	if strings.TrimFunc(q, unicode.IsSpace) == "" {
		s.res.Verdict, s.res.Query, s.res.N = "empty", "", len(s.all)
		if len(s.all) == 1 {
			s.res.Target = Fields(s.all[0])
		}
		return s.res
	}

	opq := strings.ContainsAny(q, `'^$!|`)
	terms := strings.FieldsFunc(strings.ReplaceAll(q, "\t", " "), func(c rune) bool { return c == ' ' })

	if M := s.match(q, s.all); len(M) > 0 {
		s.decide("T1", q, false, opq, M)
		return s.res
	}
	if opq {
		s.none()
		return s.res
	}
	if len(s.all) > ApproxMax {
		s.none()
		s.res.Note = "typo matching skipped above " + strconv.Itoa(ApproxMax) + " rows"
		return s.res
	}

	s.rels = relsOf(s.all)
	s.v = buildVocab(s.rels, r.Kinds)

	for _, wide := range []bool{false, true} {
		eq, approx, ok := s.v.rewrite(q, wide)
		if !ok || eq == s.tried {
			continue
		}
		s.tried = eq
		M := s.match(eq, s.all)
		if len(M) == 0 {
			continue
		}
		if approx {
			s.decide("T2", eq, true, false, M)
			s.res.Note = "no exact match for: " + q + " (showing: " + eq + ")"
		} else {
			// T2a reorders and spreads the words, so every outcome says how it read them; J2 already did.
			s.decide("T2a", eq, false, false, M)
			if s.res.Verdict == "pick" {
				s.res.Note = "no exact match for: " + q + " (read as: " + eq + ")"
			} else if s.res.Rule != "dir" {
				s.res.Note = "hop: " + q + " -> " + s.res.Target.Rel + " (read as: " + eq + ")"
			}
		}
		return s.res
	}
	if eq, ok := s.v.loose(q); ok {
		if M := s.match(eq, s.all); len(M) > 0 {
			s.decide("T3", eq, true, false, M)
			s.res.Note = "no exact match for: " + q + " (showing: " + eq + ")"
			return s.res
		}
	}

	// Relaxed: each word resolves alone, through whichever tier reads it, and the words nothing reads are dropped.
	if len(terms) >= 2 {
		var keep, drop, eqs []string
		s.textBuild()
		for _, t := range terms {
			if e, ok := s.termEq(t); ok {
				keep, eqs = append(keep, t), append(eqs, e)
			} else {
				drop = append(drop, t)
			}
		}
		eq := strings.Join(eqs, " ")
		if len(keep) > 0 && eq != q && eq != s.tried {
			if M := s.match(eq, s.all); len(M) > 0 {
				if len(drop) > 0 {
					s.decide("relaxed", eq, true, false, M)
					s.res.Note = "ignored: " + strings.Join(drop, " ")
				} else {
					s.decide("T3", eq, true, false, M)
					s.res.Note = "no exact match for: " + q + " (showing: " + eq + ")"
				}
				return s.res
			}
		}
		if len(keep) >= 2 && s.allButOne(eqs) {
			note := "ignored: "
			if len(drop) > 0 {
				note += strings.Join(drop, " ") + ", and "
			}
			s.res.Note = note + "one of: " + strings.Join(keep, ", ")
			return s.res
		}
	}

	s.none()
	return s.res
}

// none is _hop_resolve_none: T4, nothing close, so the picker opens on the query as typed.
// - The hint names the key that clears it: esc twice under the modal layer (SEARCH to NORMAL, then clear), ctrl-u without.
func (s *state) none() {
	s.res.Verdict, s.res.Tier, s.res.Query = "none", "T4", s.q
	hint := " (ctrl-u clears)"
	if s.Vim {
		hint = " (esc twice clears)"
	}
	s.res.Note = "nothing close to: " + s.q + hint
}

// textBuild is _hop_text_build: fields 1 and 4 lowercased, or "" when the text holds non-ASCII besides hop's … marker.
func (s *state) textBuild() {
	var b strings.Builder
	for i, row := range s.all {
		if i > 0 {
			b.WriteByte('\n')
		}
		b.WriteString(rows.StripANSI(display(row)))
	}
	b.WriteByte('\n')
	b.WriteString(strings.Join(s.rels, "\n"))
	s.text = strings.ToLower(b.String())
	for _, c := range strings.ReplaceAll(s.text, "…", "") {
		if c < 0x01 || c > 0x7f {
			s.text = ""
			return
		}
	}
}

// hits is _hop_hits: whether some row matches eq, answered in Go whenever that is provably fzf's answer.
// - For one OR group of plain ASCII words, an --exact match is a substring search of the text.
func (s *state) hits(eq string) bool {
	e := strings.ToLower(eq)
	fast := s.text != "" && !strings.Contains(strings.ReplaceAll(e, " | ", ""), " ") && !strings.ContainsAny(e, `'^$!\`)
	if fast {
		for _, c := range e {
			if c < 0x20 || c > 0x7e {
				fast = false
				break
			}
		}
	}
	if fast {
		for a := range strings.SplitSeq(e, " | ") {
			if strings.Contains(s.text, a) {
				return true
			}
		}
		return false
	}
	return len(s.match(e, s.all)) > 0
}

// termEq is _hop_term_eq: the term as the first tier that reads it does: T1, T2 narrow, T2 wide, T3.
func (s *state) termEq(t string) (string, bool) {
	if s.hits(t) {
		return t, true
	}
	for _, wide := range []bool{false, true} {
		eq, _, ok := s.v.rewrite(t, wide)
		if !ok {
			continue
		}
		if s.hits(eq) {
			return eq, true
		}
	}
	if eq, ok := s.v.loose(t); ok && s.hits(eq) {
		return eq, true
	}
	return "", false
}

// allButOne is _hop_all_but_one: rows matching every kept word but one, decided as a relaxed pick.
// - The picker opens on every pair OR-ed, which keeps exactly the rows missing one word; the smallest set comes first.
func (s *state) allButOne(eqs []string) bool {
	for _, e := range eqs {
		if strings.Contains(strings.ReplaceAll(e, " | ", ""), " ") {
			return false
		}
	}
	got := map[int][]string{}
	var order []string
	for i := range eqs {
		rest := append(slices.Clone(eqs[:i]), eqs[i+1:]...)
		M := s.match(strings.Join(rest, " "), s.all)
		if len(M) == 0 {
			continue
		}
		got[i] = M
		order = append(order, fmt.Sprintf("%08d:%d", len(M), i))
	}
	if len(order) == 0 {
		return false
	}
	collate.Sort(order)
	seen := map[string]bool{}
	var out []string
	for _, k := range order {
		i, _ := strconv.Atoi(k[strings.IndexByte(k, ':')+1:])
		for _, r := range got[i] {
			if !seen[r] {
				seen[r] = true
				out = append(out, r)
			}
		}
	}
	var pairs []string
	for i := 0; i < len(eqs); i++ {
		for j := i + 1; j < len(eqs); j++ {
			pairs = append(pairs, eqs[i]+" | "+eqs[j])
		}
	}
	// No ancestor is injected: one that holds a single word, as every acct-*-prod/ does for prod, would bury the order.
	s.decide("relaxed", strings.Join(pairs, " "), true, true, out)
	return true
}

// Rank is _hop_res_rank: T0/T1 5, T2a 4, T2 or T3 3, relaxed 2, nothing 1.
func (res Result) Rank() int {
	switch res.Tier {
	case "T0", "T1":
		return 5
	case "T2a":
		return 4
	case "T2", "T3":
		return 3
	case "relaxed":
		return 2
	}
	return 1
}

// Input is _hop_res_input: the picker's stdin, the candidates first in their coloured form, then every other row.
func (res Result) Input(all []string) []string {
	orig := make(map[string]string, len(all))
	for _, a := range all {
		orig[rows.StripANSI(a)] = a
	}
	front := make([]string, 0, len(all))
	inFront := map[string]bool{}
	for _, r := range res.Rows {
		o, ok := orig[r]
		if !ok {
			o = r
		}
		front = append(front, o)
		inFront[o] = true
	}
	for _, a := range all {
		if !inFront[a] {
			front = append(front, a)
		}
	}
	return front
}

// FilterUnder is _hop_filter_under: the rows whose dir is under or lies beneath it.
func FilterUnder(rs []string, under string) []string {
	var out []string
	for _, r := range rs {
		if d := dirOf(r); d == under || strings.HasPrefix(d, under+"/") {
			out = append(out, r)
		}
	}
	return out
}
