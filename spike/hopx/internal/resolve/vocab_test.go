package resolve

import (
	"fmt"
	"math/rand/v2"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/etknorr/hop/spike/hopx/internal/match"
	"github.com/etknorr/hop/spike/hopx/internal/testfix"
)

func writeLines(t *testing.T, name string, lines []string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(p, []byte(strings.Join(lines, "\n")+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

// TestApproxAgainstZsh fuzzes approxWithin against zsh's own (#aN) on a small alphabet, where edits collide most.
func TestApproxAgainstZsh(t *testing.T) {
	if !testfix.HaveZsh() {
		t.Skip("zsh not available")
	}
	rng := rand.New(rand.NewPCG(1, 2))
	word := func(lo, hi int) string {
		n := lo + rng.IntN(hi-lo+1)
		b := make([]byte, n)
		for i := range b {
			b[i] = "abcd"[rng.IntN(4)]
		}
		return string(b)
	}
	mutate := func(s string) string {
		b := []byte(s)
		for range rng.IntN(4) {
			i := rng.IntN(len(b) + 1)
			switch rng.IntN(4) {
			case 0:
				b = append(b[:i], append([]byte{"abcd"[rng.IntN(4)]}, b[i:]...)...)
			case 1:
				if i < len(b) && len(b) > 1 {
					b = append(b[:i], b[i+1:]...)
				}
			case 2:
				if i < len(b) {
					b[i] = "abcd"[rng.IntN(4)]
				}
			case 3:
				if i+1 < len(b) {
					b[i], b[i+1] = b[i+1], b[i]
				}
			}
		}
		return string(b)
	}
	var pairs []string
	for range 4000 {
		tok := word(4, 9)
		w := word(1, 11)
		if rng.IntN(4) > 0 {
			w = mutate(tok)
		}
		pairs = append(pairs, w+" "+tok)
	}
	f := writeLines(t, "pairs", pairs)
	out, err := testfix.Zsh(testdata("match.zsh"), `
		hx() {
			emulate -L zsh
			setopt local_options extended_glob
			local w tok
			local -i n
			while read -r w tok; do
				n=$(( ${#tok} >= 8 ? 2 : 1 ))
				if [[ $w == (#a${n})${tok} ]]; then print 1; else print 0; fi
			done < "$1"
		}
		hx "$1"`, nil, f)
	if err != nil {
		t.Fatal(err)
	}
	got := match.Lines(out)
	if len(got) != len(pairs) {
		t.Fatalf("zsh answered %d of %d", len(got), len(pairs))
	}
	bad, pos := 0, 0
	for i, p := range pairs {
		w, tok, _ := strings.Cut(p, " ")
		n := 1
		if len(tok) >= 8 {
			n = 2
		}
		if got[i] == "1" {
			pos++
		}
		if g := approxWithin([]rune(w), []rune(tok), n); (got[i] == "1") != g {
			bad++
			if bad <= 10 {
				t.Errorf("%q ~ %q (n=%d): zsh %s, go %v", w, tok, n, got[i], g)
			}
		}
	}
	t.Logf("%d pairs, %d within reach, %d differ", len(pairs), pos, bad)
}

// TestRewriteAgainstZsh runs _hop_rewrite (narrow and wide) and _hop_loose in zsh over the fixture's rels for every query.
func TestRewriteAgainstZsh(t *testing.T) {
	if !testfix.HaveZsh() {
		t.Skip("zsh not available")
	}
	f := matchFix(t)
	rels := relsOf(f.all)
	qs := []string{"securty", "acount", "rotuemaster", "kpstack", "externaldns", "securitytoolingprod", "stg", "prd", "gthbactions", "terraform/account-security"}
	if b, err := os.ReadFile(filepath.Join(testfix.ModuleRoot(), "..", "parity", "corpus", "queries.txt")); err == nil {
		qs = append(qs, match.Lines(string(b))...)
	}
	rng := rand.New(rand.NewPCG(3, 4))
	for _, r := range rels {
		for _, w := range splitSeps(r) {
			if len(w) < 4 {
				continue
			}
			b := []byte(w)
			i := rng.IntN(len(b) - 1)
			b[i], b[i+1] = b[i+1], b[i]
			qs = append(qs, string(b), w[:len(w)-1], w+"x", strings.ReplaceAll(w, "-", ""))
		}
	}
	rf := writeLines(t, "rels", rels)
	qf := writeLines(t, "queries", qs)
	out, err := testfix.Zsh(testdata("match.zsh"), `
		hx() {
			emulate -L zsh
			local -a _hop_vocab _hop_segs reply rels=("${(@f)$(<"$1")}")
			local -A _hop_vocab_set
			local REPLY q a b l
			_hop_vocab_build "${rels[@]}"
			while IFS= read -r q; do
				a=- b=- l=-
				_hop_rewrite "$q" 0 && a="${reply[1]}:${reply[2]}"
				_hop_rewrite "$q" 1 && b="${reply[1]}:${reply[2]}"
				_hop_loose "$q" && l=$REPLY
				print -r -- "${a}	${b}	${l}"
			done < "$2"
		}
		hx "$1" "$2"`, nil, rf, qf)
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimSuffix(out, "\n"), "\n")
	if len(lines) != len(qs) {
		t.Fatalf("zsh answered %d of %d", len(lines), len(qs))
	}
	v := buildVocab(rels, f.cfg.AllKinds())
	show := func(eq string, approx, ok bool) string {
		if !ok {
			return "-"
		}
		a := 0
		if approx {
			a = 1
		}
		return fmt.Sprintf("%d:%s", a, eq)
	}
	bad := 0
	for i, q := range qs {
		a := show(v.rewrite(q, false))
		b := show(v.rewrite(q, true))
		l, ok := v.loose(q)
		if !ok {
			l = "-"
		}
		if got := a + "\t" + b + "\t" + l; got != lines[i] {
			bad++
			if bad <= 10 {
				t.Errorf("%q\n  zsh %s\n  go  %s", q, lines[i], got)
			}
		}
	}
	t.Logf("%d queries, %d differ", len(qs), bad)
}

func TestPruneAndInitials(t *testing.T) {
	segs := &vocab{segs: []string{"github_actions", "github_actions_self_hosted", "github-actions-deploy-auth", "github-actions", "github-actions-runners"}}
	if got, _ := segs.loose("gthbactions"); got != "github_actions | github-actions" {
		t.Errorf("loose %q", got)
	}
	if got := prune([]string{"a", "a", "ab"}); strings.Join(got, ",") != "a,a" {
		t.Errorf("an exact twin never prunes its twin: %v", got)
	}
	if got := initials("kube-prometheus_stack.x"); got != "kpsx" {
		t.Errorf("initials %q", got)
	}
}

func TestAncestors(t *testing.T) {
	got := ancestors("", []string{"t/a/x/", "t/a/y/", "t/", "k/f.yaml", "~/elsewhere/"})
	if strings.Join(got, " ") != "t/a k" && strings.Join(got, " ") != "k t/a" {
		t.Errorf("got %v", got)
	}
	if got := ancestors("t", []string{"t/a/x/", "t/a/y/", "t/", "k/f.yaml"}); strings.Join(got, " ") != "t/a" {
		t.Errorf("under t: %v", got)
	}
}
