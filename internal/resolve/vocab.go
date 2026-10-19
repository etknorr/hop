package resolve

import (
	"strings"
)

// EnvWords is _HOP_ENV_WORDS: env words people shorten past what a typo fix reaches.
var EnvWords = map[string]string{
	"prd":         "prod",
	"production":  "prod",
	"stg":         "staging",
	"stag":        "staging",
	"stage":       "staging",
	"devel":       "dev",
	"develop":     "dev",
	"development": "dev",
}

// vocab holds _hop_vocab, _hop_vocab_set and _hop_segs, built once per resolve.
type vocab struct {
	words []string
	set   map[string]bool
	segs  []string
}

func uniq(ss []string) []string {
	seen := make(map[string]bool, len(ss))
	out := ss[:0:0]
	for _, s := range ss {
		if !seen[s] {
			seen[s] = true
			out = append(out, s)
		}
	}
	return out
}

func runeLen(s string) int { return len([]rune(s)) }

// buildVocab is _hop_vocab_build.
// - words: every rel token split on / - _ . and lowercased, unique, 1- and 2-char tokens dropped, then the kind names.
// - segs: every whole rel segment lowercased, extension stripped, unique, 3 chars or more.
func buildVocab(rels, kinds []string) *vocab {
	v := &vocab{set: map[string]bool{}}
	var toks []string
	for _, r := range rels {
		r = strings.Map(func(c rune) rune {
			if c == '/' || c == '_' || c == '.' || c == '-' {
				return ' '
			}
			return c
		}, r)
		for t := range strings.SplitSeq(r, " ") {
			if t != "" {
				toks = append(toks, strings.ToLower(t))
			}
		}
	}
	for _, t := range uniq(toks) {
		if n := runeLen(t); n != 1 && n != 2 {
			v.words = append(v.words, t)
		}
	}
	v.words = append(v.words, kinds...)
	for _, w := range v.words {
		v.set[w] = true
	}
	var segs []string
	for _, r := range rels {
		for s := range strings.SplitSeq(strings.ToLower(r), "/") {
			if s == "" {
				continue
			}
			if i := strings.LastIndexByte(s, '.'); i >= 0 {
				s = s[:i]
			}
			segs = append(segs, s)
		}
	}
	for _, s := range uniq(segs) {
		if runeLen(s) >= 3 {
			v.segs = append(v.segs, s)
		}
	}
	return v
}

func anyContains(list []string, sub string) bool {
	for _, w := range list {
		if strings.Contains(w, sub) {
			return true
		}
	}
	return false
}

// subseqFrom reports whether w starts with p's first rune and holds the rest of p in order: ${~pat}* with pat a*b*c.
func subseqFrom(w, p []rune) bool {
	if len(p) == 0 {
		return true
	}
	if len(w) == 0 || w[0] != p[0] {
		return false
	}
	j := 1
	for i := 1; i < len(w) && j < len(p); i++ {
		if w[i] == p[j] {
			j++
		}
	}
	return j == len(p)
}

// abbrevs is _hop_abbrevs: every vocabulary word w abbreviates to, letters in order, account -> acct.
// - From 6 chars; the short form is at least half the word, 3 chars or more, and not merely a prefix of it.
func (v *vocab) abbrevs(w string) []string {
	wr := []rune(w)
	if len(wr) < 6 {
		return nil
	}
	var out []string
	for _, cand := range v.words {
		cr := []rune(cand)
		if len(cr) == 0 || cr[0] != wr[0] {
			continue
		}
		if len(cr) < 3 || len(cr) >= len(wr) || len(cr)*2 < len(wr) {
			continue
		}
		if subseqFrom(wr, cr) && !strings.HasPrefix(w, cand) {
			out = append(out, cand)
		}
	}
	return out
}

// compound is _hop_compound: the two or three vocabulary words, 3 chars or more each, a token runs together.
// - The longest first word wins, and two words before three.
func (v *vocab) compound(t string) []string {
	r := []rune(t)
	n := len(r)
	for i := n - 3; i >= 3; i-- {
		a, b := string(r[:i]), string(r[i:])
		if v.set[a] && v.set[b] {
			return []string{a, b}
		}
	}
	for i := n - 6; i >= 3; i-- {
		a := string(r[:i])
		if !v.set[a] {
			continue
		}
		for j := n - 3; j >= i+3; j-- {
			b, c := string(r[i:j]), string(r[j:])
			if v.set[b] && v.set[c] {
				return []string{a, b, c}
			}
		}
	}
	return nil
}

// prune is _hop_prune: the alternatives that hold no other one, so an OR group matches the same rows.
// - An exact duplicate never prunes its twin, as in zsh, where `$a != $b` skips it.
func prune(alts []string) []string {
	var out []string
outer:
	for _, a := range alts {
		for _, b := range alts {
			if a != b && strings.Contains(a, b) {
				continue outer
			}
		}
		out = append(out, a)
	}
	return out
}

// approxWithin is zsh's (#aN) whole-word match: restricted Damerau-Levenshtein distance at most n.
// - zsh counts an insertion, a deletion, a substitution or an adjacent transposition as one error each.
func approxWithin(a, b []rune, n int) bool {
	if d := len(a) - len(b); d > n || -d > n {
		return false
	}
	la, lb := len(a), len(b)
	prev2 := make([]int, lb+1)
	prev := make([]int, lb+1)
	cur := make([]int, lb+1)
	for j := range prev {
		prev[j] = j
	}
	for i := 1; i <= la; i++ {
		cur[0] = i
		low := cur[0]
		for j := 1; j <= lb; j++ {
			cost := 1
			if a[i-1] == b[j-1] {
				cost = 0
			}
			c := min(prev[j]+1, cur[j-1]+1, prev[j-1]+cost)
			if i > 1 && j > 1 && a[i-1] == b[j-2] && a[i-2] == b[j-1] {
				c = min(c, prev2[j-2]+1)
			}
			cur[j] = c
			low = min(low, c)
		}
		if low > n {
			return false
		}
		prev2, prev, cur = prev, cur, prev2
	}
	return prev[lb] <= n
}

func splitSeps(q string) []string {
	return strings.FieldsFunc(q, func(c rune) bool {
		return c == ' ' || c == '/' || c == '_' || c == '.' || c == '-'
	})
}

// rewrite is _hop_rewrite: the query as fzf OR groups (T2), with approx false when only separators or case changed (T2a).
// - ok is false when some token nothing explains, or when the rewrite is the lowercased query itself.
func (v *vocab) rewrite(q string, wide bool) (eq string, approx, ok bool) {
	q = strings.ToLower(q)
	var groups []string
	for _, tok := range splitSeps(q) {
		tl := runeLen(tok)
		if tl < 3 {
			groups = append(groups, tok)
			continue
		}
		var alts, typo []string
		exact := false
		if anyContains(v.words, tok) {
			exact = true
			alts = append(alts, tok)
		} else if long := EnvWords[tok]; long != "" && v.set[long] {
			groups = append(groups, long)
			approx = true
			continue
		} else if tl >= 4 {
			n := 1
			if tl >= 8 {
				n = 2
			}
			tr := []rune(tok)
			for _, w := range v.words {
				if approxWithin([]rune(w), tr, n) {
					typo = append(typo, w)
				}
			}
			alts = append(alts, typo...)
		}
		if !exact && len(typo) == 0 && tl >= 6 {
			if parts := v.compound(tok); parts != nil {
				groups = append(groups, parts...)
				approx = true
				continue
			}
		}
		if len(typo) == 0 && (!exact || wide) {
			alts = append(alts, v.abbrevs(tok)...)
		}
		if wide {
			for _, w := range typo {
				alts = append(alts, v.abbrevs(w)...)
			}
		}
		alts = prune(uniq(alts))
		if len(alts) == 0 {
			return "", false, false
		}
		if strings.Join(alts, " ") != tok {
			approx = true
		}
		groups = append(groups, strings.Join(alts, " | "))
	}
	if len(groups) == 0 {
		return "", false, false
	}
	eq = strings.Join(groups, " ")
	return eq, approx, eq != q
}

// initials is ${(j::)${(M)${(s:-:)${s//[_.]/-}}#?}}: the first letter of every - _ . separated word.
func initials(s string) string {
	var b strings.Builder
	for w := range strings.SplitSeq(strings.NewReplacer("_", "-", ".", "-").Replace(s), "-") {
		if w != "" {
			r := []rune(w)
			b.WriteRune(r[0])
		}
	}
	return b.String()
}

// loose is _hop_loose: the query rewritten into whole rel segments (T3), strictly.
// - A term inside some segment is kept; otherwise a segment must start with it as a subsequence.
// - And the segment's initials must start with the term, or the term must be at least a third of it.
func (v *vocab) loose(q string) (string, bool) {
	q = strings.ToLower(q)
	var groups []string
	for _, tok := range splitWS(q) {
		var hit []string
		tr := []rune(tok)
		if anyContains(v.segs, tok) {
			hit = []string{tok}
		} else if len(tr) >= 3 {
			for _, s := range v.segs {
				if !subseqFrom([]rune(s), tr) {
					continue
				}
				if strings.HasPrefix(initials(s), tok) || len(tr)*3 >= runeLen(s) {
					hit = append(hit, s)
				}
			}
		}
		if len(hit) == 0 {
			return "", false
		}
		groups = append(groups, strings.Join(prune(hit), " | "))
	}
	if len(groups) == 0 {
		return "", false
	}
	eq := strings.Join(groups, " ")
	return eq, eq != q
}

// splitWS is ${=x} under IFS=$' \t'.
func splitWS(s string) []string {
	return strings.FieldsFunc(s, func(c rune) bool { return c == ' ' || c == '\t' })
}
