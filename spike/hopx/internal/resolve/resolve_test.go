package resolve

import (
	"bytes"
	"flag"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync"
	"testing"

	"github.com/etknorr/hop/spike/hopx/internal/config"
	"github.com/etknorr/hop/spike/hopx/internal/kinds"
	"github.com/etknorr/hop/spike/hopx/internal/match"
	"github.com/etknorr/hop/spike/hopx/internal/mru"
	"github.com/etknorr/hop/spike/hopx/internal/rows"
	"github.com/etknorr/hop/spike/hopx/internal/testfix"
)

var update = flag.Bool("update", false, "rewrite testdata/golden/resolve.tsv from zsh hop's _hop_resolve")

const (
	SP = "terraform/acct-security-tooling-prod"
	IP = "terraform/acct-infrastructure/env-prod/us-east-1"
)

func testdata(p string) string { return filepath.Join(testfix.ModuleRoot(), "testdata", p) }

type fix struct {
	root string
	cfg  *config.Config
	all  []string
	fzf  *match.FZF
}

var (
	fixOnce sync.Once
	fixVal  *fix
	fixErr  error
	fixDir  string
)

func TestMain(m *testing.M) {
	flag.Parse()
	code := m.Run()
	if fixDir != "" {
		os.RemoveAll(fixDir)
	}
	os.Exit(code)
}

// matchFix builds the match fixture once per test binary, since every case reads the same rows.
func matchFix(t *testing.T) *fix {
	t.Helper()
	fixOnce.Do(func() {
		fzf, err := match.New(os.Stderr)
		if err != nil {
			fixErr = err
			return
		}
		d, err := os.MkdirTemp("", "hopx-match-")
		if err != nil {
			fixErr = err
			return
		}
		fixDir = d
		root := filepath.Join(testfix.Resolved(d), "repo")
		if fixErr = testfix.BuildMatch(root); fixErr != nil {
			return
		}
		cfg, err := config.Load(testdata("match.toml"))
		if err != nil {
			fixErr = err
			return
		}
		var stderr bytes.Buffer
		var all []string
		for _, r := range kinds.Generate(cfg, root, cfg.DefaultKinds(), &stderr) {
			all = append(all, rows.Render(r, root))
		}
		if stderr.Len() > 0 {
			fixErr = &os.PathError{Op: "generate", Path: root, Err: os.ErrInvalid}
			return
		}
		fixVal = &fix{root, cfg, all, fzf}
	})
	if fixErr != nil {
		t.Skip("match fixture unavailable: ", fixErr)
	}
	return fixVal
}

type kase struct{ q, cwd, action, jump, under string }

func (k kase) key() string {
	return strings.Join([]string{k.q, k.cwd, k.action, k.jump, k.under}, "\t")
}

func c(q string, rest ...string) kase {
	k := kase{q, ".", "cd", "auto", "-"}
	for i, v := range rest {
		switch i {
		case 0:
			k.cwd = v
		case 1:
			k.action = v
		case 2:
			k.jump = v
		case 3:
			k.under = v
		}
	}
	return k
}

func nonsense(t *testing.T) []string {
	b, err := os.ReadFile(filepath.Join(testfix.HopHome(), "tests", "fixtures", "nonsense.txt"))
	if err != nil {
		t.Fatal(err)
	}
	return match.Lines(string(b))
}

// cases is suite_match.zsh's MT_CASES table, in its order.
func cases(t *testing.T) []kase {
	var ks []kase
	for _, q := range []string{
		"terraform/acct-security-tooling-prod", "Terraform/ACCT-Security-Tooling-Prod",
		"terraform/acct-security-tooling-prod/env-prod/us-east-1/vpc", "kubernetes/services/monitoring/grafana.yaml",
		"./sandbox/abg", "terraform/nope/x", "acct-security-tooling-prod/env-prod", "curity-tooling-prod/env-pr",
		"security-tooling-prod", "Security-Tooling-Prod", "security_tooling_prod", "acct sec prod", "terraform/account-security", "terraform/acount-security",
		"securty-tooling-prod", "secuirty-tooling-prod", "routemaxter", "rotuemaster", "routemastr", "routemaster-prod", "externaldns", "securitytoolingprod", "kps", "kpstack", "kubeprom",
		"vpc", "Vpc", "TG vpc", "tg", "mesos", "helm", "kub", "kubernetes", "values", "eks security", "vpc security !staging", "^vpc",
		"acct sec prd", "stg", "prod_vpc", "trust prod", "security vpc", "infrastructure dev", "data prod", "active infrastructure", "monitoring/grafana", "abg", "zzqx", "zzzz", "vpc zzqx", "thanos",
		"kps zzqx", "routemaxter kps zzqx", "routemaster dev",
		"'security-tooling-prod", "securty-tooling-prod$", "^terraform/acct-securty", "secutiry-tooling-prod",
	} {
		ks = append(ks, c(q))
	}
	for _, q := range nonsense(t) {
		ks = append(ks, c(q))
	}
	return append(ks,
		c("../abg", "sandbox/alpha-beta-gamma"),
		c("..", "sandbox/alpha-beta-gamma"),
		c("../", "sandbox/alpha-beta-gamma"),
		c(".", "terraform"),
		c("./", "terraform"),
		c("/mesos", "terraform"),
		c("modules/", "terraform"),
		c("mesos/services", "terraform"),
		c("monitoring/grafana", ".", "open"),
		c("security-tooling-prod", ".", "cd", "unique"),
		c("eks security", ".", "cd", "unique"),
		c("eks security", ".", "cd", "never"),
		c("terraform/acct-security-tooling-prod", ".", "cd", "never"),
		c("vpc", "terraform/acct-infrastructure", "cd", "auto", "c"),
		c("infrastructure", "terraform/acct-infrastructure/env-prod", "cd", "auto", "c"),
		c("infrastructure", "terraform/acct-infrastructure/env-prod"),
		c("acct-l[a]b*#/env-prod"),
		c("env-prod", "terraform/acct-l[a]b*#", "cd", "auto", "c"),
	)
}

type out struct {
	res     Result
	t0      bool
	report  string
	visible []string
}

// run is hx_runner's body for one case, in Go.
func (f *fix) run(k kase, all []string) out {
	pwd := filepath.Join(f.root, k.cwd)
	rs, under := all, ""
	if k.under == "c" {
		under = testfix.Resolved(pwd)
		rs = FilterUnder(all, under)
	}
	if k.jump != "never" && len(strings.Fields(k.q)) == 1 {
		if t, ok := Literal(k.q, f.root, pwd); ok {
			return out{res: Result{Verdict: "jump", Tier: "T0", Rule: "path", Target: t, N: 1, M: 1}, t0: true, visible: rs}
		}
	}
	r := &Resolver{Match: f.fzf, Root: f.root, Action: k.action, Jump: k.jump, Under: under, Kinds: f.cfg.AllKinds()}
	res := r.Resolve(k.q, rs)
	o := out{res: res, visible: rs}
	if res.Verdict != "jump" {
		var b bytes.Buffer
		Report(&b, res, k.q, k.jump)
		o.report = strings.ReplaceAll(strings.TrimRight(b.String(), "\n"), "\n", `\n`)
	}
	return o
}

// line is hx_runner's TSV line for a case.
func (o out) line(k kase) string {
	r := o.res
	f := []string{k.key(), r.Verdict, r.Tier, r.Rule, r.Target.Dir, r.Target.Preview, r.Target.Rel,
		strconv.Itoa(r.N), strconv.Itoa(r.M), strconv.Itoa(r.Inj)}
	if o.t0 {
		return strings.Join(append(f, "", "", "", ""), "\t")
	}
	return strings.Join(append(f, strings.Join(relsOf(r.Rows), ","), r.Query, r.Note, o.report), "\t")
}

func (f *fix) zshTable(t *testing.T, ks []kase) map[string]string {
	t.Helper()
	cf := filepath.Join(t.TempDir(), "cases")
	var b strings.Builder
	for _, k := range ks {
		b.WriteString(k.key() + "\n")
	}
	os.WriteFile(cf, []byte(b.String()), 0o644)
	got, err := testfix.Zsh(testdata("match.zsh"), `source "$1" && hx_runner "$2" "$3"`, nil, testdata("resolve_runner.zsh"), f.root, cf)
	if err != nil {
		t.Fatal(err)
	}
	return byKey(got)
}

func byKey(text string) map[string]string {
	m := map[string]string{}
	for _, l := range match.Lines(text) {
		f := strings.SplitN(l, "\t", 6)
		if len(f) >= 5 {
			m[strings.Join(f[:5], "\t")] = l
		}
	}
	return m
}

func (f *fix) goTable(ks []kase) map[string]string {
	m := map[string]string{}
	for _, k := range ks {
		m[k.key()] = f.run(k, f.all).line(k)
	}
	return m
}

func compareTables(t *testing.T, ks []kase, want, got map[string]string, src string) {
	t.Helper()
	bad := 0
	for _, k := range ks {
		w, g := want[k.key()], got[k.key()]
		if w == "" {
			t.Errorf("%s has no line for %q", src, k.key())
			continue
		}
		if w != g {
			bad++
			t.Errorf("case %q differs from %s\n  want %s\n  got  %s", k.key(), src, w, g)
		}
	}
	if bad > 0 {
		t.Logf("%d of %d cases differ", bad, len(ks))
	}
}

// TestGoldenTable compares every case's whole line with the golden captured from zsh hop's resolver.
func TestGoldenTable(t *testing.T) {
	f := matchFix(t)
	ks := cases(t)
	golden := testdata("golden/resolve.tsv")
	if *update {
		if !testfix.HaveZsh() {
			t.Fatal("-update needs zsh and hop.zsh")
		}
		z := f.zshTable(t, ks)
		var b strings.Builder
		for _, k := range ks {
			b.WriteString(strings.ReplaceAll(z[k.key()], f.root, "@ROOT@") + "\n")
		}
		if err := os.WriteFile(golden, []byte(b.String()), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	text, err := os.ReadFile(golden)
	if err != nil {
		t.Fatal(err)
	}
	compareTables(t, ks, byKey(strings.ReplaceAll(string(text), "@ROOT@", f.root)), f.goTable(ks), golden)
}

// TestLiveZsh reruns the table through zsh hop, so a golden gone stale against hop cannot hide a regression.
func TestLiveZsh(t *testing.T) {
	if !testfix.HaveZsh() {
		t.Skip("zsh or hop.zsh not available")
	}
	f := matchFix(t)
	ks := cases(t)
	compareTables(t, ks, f.zshTable(t, ks), f.goTable(ks), "live zsh")
}

func (f *fix) get(t *testing.T, k kase) out {
	t.Helper()
	return f.run(k, f.all)
}

// TestSuiteMatch is suite_match.zsh's mt_jump and mt_pick assertions, case by case.
func TestSuiteMatch(t *testing.T) {
	f := matchFix(t)
	type exp struct {
		k                kase
		want, rel, first string
		n                int
		query, note      string
	}
	jump := func(want, rel string, k kase) exp { return exp{k: k, want: want, rel: rel, n: -1} }
	pick := func(tier string, n int, first string, k kase) exp {
		return exp{k: k, want: "pick " + tier, first: first, n: n}
	}
	withQ := func(e exp, q string) exp { e.query = q; return e }
	withNote := func(e exp, n string) exp { e.note = n; return e }
	tbl := []exp{
		jump("jump T0 path", SP+"/", c("terraform/acct-security-tooling-prod")),
		jump("jump T0 path", SP+"/", c("Terraform/ACCT-Security-Tooling-Prod")),
		jump("jump T0 path", SP+"/env-prod/us-east-1/vpc/", c(SP+"/env-prod/us-east-1/vpc")),
		jump("jump T0 path", "kubernetes/services/monitoring/grafana.yaml", c("kubernetes/services/monitoring/grafana.yaml")),
		jump("jump T0 path", "sandbox/abg/", c("./sandbox/abg")),
		jump("jump T0 path", "sandbox/abg/", c("../abg", "sandbox/alpha-beta-gamma")),
		jump("jump T0 path", "sandbox/", c("..", "sandbox/alpha-beta-gamma")),
		jump("jump T0 path", "sandbox/", c("../", "sandbox/alpha-beta-gamma")),
		jump("jump T0 path", "terraform/", c(".", "terraform")),
		jump("jump T0 path", "terraform/", c("./", "terraform")),
		jump("jump T0 path", "mesos/", c("/mesos", "terraform")),
		jump("jump T0 path", "terraform/modules/", c("modules/", "terraform")),
		jump("jump T0 path", "mesos/services/", c("mesos/services", "terraform")),

		jump("jump T1 dir", SP+"/env-prod/", c("acct-security-tooling-prod/env-prod")),
		pick("T1", -1, SP+"/env-prod/", c("curity-tooling-prod/env-pr")),
		withNote(jump("jump T1 dir", SP+"/", c("security-tooling-prod")), "hop: security-tooling-prod -> "+SP+"/ (all 3 matches are under it)"),
		jump("jump T1 dir", SP+"/", c("Security-Tooling-Prod")),
		jump("jump T2a dir", SP+"/", c("security_tooling_prod")),
		pick("T1", 7, SP+"/", c("acct sec prod")),
		withNote(withQ(pick("T2", 7, SP+"/", c("terraform/account-security")), "terraform account | acct security"), "no exact match for: terraform/account-security (showing: terraform account | acct security)"),
		withQ(pick("T2", 7, SP+"/", c("terraform/acount-security")), "terraform account | acct security"),
		withQ(pick("T2", 4, SP+"/", c("securty-tooling-prod")), "security tooling prod"),
		withQ(pick("T2", 4, SP+"/", c("secuirty-tooling-prod")), "security tooling prod"),
		pick("T2", 4, SP+"/", c("secutiry-tooling-prod")),
		withQ(pick("T2", 2, "", c("routemaxter")), "routemaster"),
		withQ(pick("T2", 2, "", c("rotuemaster")), "routemaster"),
		withQ(pick("T2", 2, "", c("routemastr")), "routemaster"),
		withNote(withQ(jump("jump T2a single", IP+"/routemaster/", c("routemaster-prod")), "routemaster prod"), "hop: routemaster-prod -> "+IP+"/routemaster/ (read as: routemaster prod)"),
		withNote(pick("T2a", 3, "", c("prod_vpc")), "no exact match for: prod_vpc (read as: prod vpc)"),
		withQ(pick("T2", 2, "kubernetes/values/external-dns/", c("externaldns")), "external dns"),
		withQ(pick("T2", 4, SP+"/", c("securitytoolingprod")), "security tooling prod"),
		withQ(pick("T2", 7, SP+"/", c("acct sec prd")), "acct sec prod"),
		withQ(pick("T2", -1, "", c("stg")), "staging"),
		pick("T3", 2, "kubernetes/values/kube-prometheus-stack/", c("kps")),
		pick("T3", 2, "kubernetes/values/kube-prometheus-stack/", c("kpstack")),
		pick("T3", 2, "kubernetes/values/kube-prometheus-stack/", c("kubeprom")),
		pick("T1", 5, "", c("vpc")),
		pick("T1", 5, "", c("Vpc")),
		pick("T1", 5, "", c("TG vpc")),
		pick("T1", -1, "", c("tg")),
		pick("T1", -1, "", c("mesos")),
		pick("T1", -1, "", c("helm")),
		pick("T1", -1, "", c("kub")),
		jump("jump T1 dir", "kubernetes/", c("kubernetes")),
		jump("jump T1 dir", "kubernetes/values/", c("values")),
		jump("jump T1 single", SP+"/env-prod/us-east-1/eks/", c("eks security")),
		jump("jump T1 single", SP+"/env-prod/us-east-1/vpc/", c("vpc security !staging")),
		pick("T1", 5, "", c("^vpc")),
		pick("T1", 3, "", c("'security-tooling-prod")),
		jump("jump T1 display", "terraform/acct-infrastructure/env-dev/us-east-1/vpc/", c("infrastructure dev")),
		pick("T1", 2, "", c("security vpc")),
		pick("T1", 3, "", c("trust prod")),
		pick("T1", -1, "", c("data prod")),
		pick("T1", 2, "", c("active infrastructure")),
		jump("jump T1 onedir", "kubernetes/services/monitoring/", c("monitoring/grafana")),
		pick("T1", 2, "", c("monitoring/grafana", ".", "open")),
		jump("jump T1 single", "sandbox/abg/", c("abg")),
		withNote(pick("relaxed", 5, "", c("vpc zzqx")), "ignored: zzqx"),
		withNote(withQ(pick("relaxed", 2, "kubernetes/values/kube-prometheus-stack/", c("kps zzqx")), "kube-prometheus-stack"), "ignored: zzqx"),
		withNote(withQ(pick("relaxed", 4, "", c("routemaxter kps zzqx")), "routemaster | kube-prometheus-stack"), "ignored: zzqx, and one of: routemaxter, kps"),
		withNote(pick("relaxed", 3, "terraform/acct-infrastructure/env-dev/us-east-1/vpc/", c("routemaster dev")), "ignored: one of: routemaster, dev"),
		pick("T1", -1, SP+"/", c("security-tooling-prod", ".", "cd", "unique")),
		jump("jump T1 single", SP+"/env-prod/us-east-1/eks/", c("eks security", ".", "cd", "unique")),
		pick("T1", 1, "", c("eks security", ".", "cd", "never")),
		pick("T1", 2, "", c("vpc", "terraform/acct-infrastructure", "cd", "auto", "c")),
		pick("T1", 8, IP+"/", c("infrastructure", "terraform/acct-infrastructure/env-prod", "cd", "auto", "c")),
		jump("jump T1 dir", "terraform/acct-l[a]b*#/env-prod/", c("acct-l[a]b*#/env-prod")),
		jump("jump T1 dir", "terraform/acct-l[a]b*#/env-prod/", c("env-prod", "terraform/acct-l[a]b*#", "cd", "auto", "c")),
	}
	for _, e := range tbl {
		t.Run(e.k.key(), func(t *testing.T) {
			o := f.get(t, e.k)
			r := o.res
			if strings.HasPrefix(e.want, "jump") {
				if got := r.Verdict + " " + r.Tier + " " + r.Rule; got != e.want {
					t.Fatalf("verdict %q, want %q (note %q)", got, e.want, r.Note)
				}
				if r.Target.Rel != e.rel {
					t.Errorf("jumped to %q, want %q", r.Target.Rel, e.rel)
				}
			} else {
				if got := r.Verdict + " " + r.Tier; got != e.want {
					t.Fatalf("verdict %q, want %q (query %q)", got, e.want, r.Query)
				}
				if e.n >= 0 && r.N != e.n {
					t.Errorf("n %d, want %d", r.N, e.n)
				}
				if e.first != "" && (len(r.Rows) == 0 || RelOf(r.Rows[0]) != e.first) {
					t.Errorf("first row %v, want %q", relsOf(r.Rows[:min(1, len(r.Rows))]), e.first)
				}
				f.checkParity(t, o)
			}
			if e.query != "" && r.Query != e.query {
				t.Errorf("query %q, want %q", r.Query, e.query)
			}
			if e.note != "" && r.Note != e.note {
				t.Errorf("note %q, want %q", r.Note, e.note)
			}
		})
	}
}

// checkParity is suite_match's parity column: a pick's matches are exactly fzf's own rows for the picker query.
func (f *fix) checkParity(t *testing.T, o out) {
	t.Helper()
	m := slices.Clone(o.res.Rows[o.res.Inj:])
	want, err := f.fzf.Filter(o.res.Query, o.visible)
	if err != nil {
		t.Fatal(err)
	}
	slices.Sort(m)
	slices.Sort(want)
	if !slices.Equal(m, want) {
		t.Errorf("candidates are not fzf's rows for %q:\n got %v\nwant %v", o.res.Query, relsOf(m), relsOf(want))
	}
}

func TestSuiteMatchDetails(t *testing.T) {
	f := matchFix(t)
	t.Run("T0 spells the target the way the disk does", func(t *testing.T) {
		r := f.get(t, c("Terraform/ACCT-Security-Tooling-Prod")).res
		if r.Target.Dir != f.root+"/"+SP {
			t.Errorf("dir %q", r.Target.Dir)
		}
	})
	t.Run("T0 on a file cds to its parent and previews the file", func(t *testing.T) {
		r := f.get(t, c("kubernetes/services/monitoring/grafana.yaml")).res
		if r.Target.Dir != f.root+"/kubernetes/services/monitoring" || r.Target.Preview != f.root+"/kubernetes/services/monitoring/grafana.yaml" {
			t.Errorf("target %+v", r.Target)
		}
	})
	t.Run("T0 tries pwd before the root", func(t *testing.T) {
		if r := f.get(t, c("modules/", "terraform")).res; r.Target.Dir != f.root+"/terraform/modules" {
			t.Errorf("dir %q", r.Target.Dir)
		}
	})
	t.Run("a missing path falls through to the matcher", func(t *testing.T) {
		if r := f.get(t, c("terraform/nope/x")).res; r.Tier == "T0" || r.Verdict != "none" {
			t.Errorf("%s %s", r.Verdict, r.Tier)
		}
	})
	t.Run("a path under never opens the picker", func(t *testing.T) {
		if r := f.get(t, c("terraform/acct-security-tooling-prod", ".", "cd", "never")).res; r.Verdict != "pick" {
			t.Errorf("verdict %s", r.Verdict)
		}
	})
	t.Run("a rewritten jump says what it read", func(t *testing.T) {
		if r := f.get(t, c("security_tooling_prod")).res; !strings.Contains(r.Note, "(read as: security tooling prod)") {
			t.Errorf("note %q", r.Note)
		}
	})
	t.Run("acct sec prod injects the account dir, then its own units", func(t *testing.T) {
		r := f.get(t, c("acct sec prod")).res
		if r.Inj != 1 {
			t.Fatalf("inj %d", r.Inj)
		}
		for _, rel := range relsOf(r.Rows[1:4]) {
			if !strings.HasPrefix(rel, SP+"/") {
				t.Errorf("rows 2-4 must be under the account dir: %v", relsOf(r.Rows[:4]))
			}
		}
	})
	t.Run("row 2 of the T2 rewrite is the staging account dir", func(t *testing.T) {
		r := f.get(t, c("terraform/account-security")).res
		if got := RelOf(r.Rows[1]); got != "terraform/acct-security-tooling-staging/" {
			t.Errorf("row 2 %q", got)
		}
	})
	t.Run("an operator query synthesises nothing", func(t *testing.T) {
		for _, q := range []string{"^vpc", "'security-tooling-prod"} {
			if r := f.get(t, c(q)).res; r.Inj != 0 {
				t.Errorf("%s: inj %d", q, r.Inj)
			}
		}
		for _, q := range []string{"securty-tooling-prod$", "^terraform/acct-securty"} {
			if r := f.get(t, c(q)).res; r.Verdict+" "+r.Tier != "none T4" {
				t.Errorf("%s: %s %s", q, r.Verdict, r.Tier)
			}
		}
	})
	t.Run("nothing close", func(t *testing.T) {
		for _, q := range []string{"zzqx", "zzzz"} {
			r := f.get(t, c(q)).res
			if r.Verdict+" "+r.Tier != "none T4" || r.Note != "nothing close to: "+q+" (esc clears)" {
				t.Errorf("%s: %s %s %q", q, r.Verdict, r.Tier, r.Note)
			}
		}
	})
	t.Run("an ancestor holding one word alone is never injected", func(t *testing.T) {
		if r := f.get(t, c("routemaster dev")).res; r.Inj != 0 {
			t.Errorf("inj %d", r.Inj)
		}
	})
	t.Run("-c keeps every candidate and ancestor inside pwd", func(t *testing.T) {
		for _, k := range []kase{c("vpc", "terraform/acct-infrastructure", "cd", "auto", "c"), c("infrastructure", "terraform/acct-infrastructure/env-prod", "cd", "auto", "c")} {
			r := f.get(t, k).res
			if len(r.Rows) == 0 {
				t.Fatalf("%s: no candidates", k.q)
			}
			for _, rel := range relsOf(r.Rows) {
				if !strings.HasPrefix(rel, k.cwd+"/") {
					t.Errorf("%s: %s escaped %s", k.q, rel, k.cwd)
				}
			}
		}
		r := f.get(t, c("infrastructure", "terraform/acct-infrastructure/env-prod")).res
		if !slices.Contains(relsOf(r.Rows), "terraform/acct-infrastructure/") {
			t.Errorf("control: without -c the account dir above pwd is offered: %v", relsOf(r.Rows))
		}
	})
	t.Run("the env dir under a -c dir named with [ ] * # is the injected ancestor", func(t *testing.T) {
		if r := f.get(t, c("env-prod", "terraform/acct-l[a]b*#", "cd", "auto", "c")).res; r.Inj != 1 {
			t.Errorf("inj %d", r.Inj)
		}
	})
	t.Run("no nonsense word jumps, and none occurs in the fixture", func(t *testing.T) {
		text := strings.ToLower(strings.Join(f.all, "\n"))
		words := nonsense(t)
		if len(words) != 50 {
			t.Fatalf("nonsense.txt holds %d words", len(words))
		}
		for _, w := range words {
			if r := f.get(t, c(w)).res; r.Verdict != "pick" && r.Verdict != "none" {
				t.Errorf("%s: %s", w, r.Verdict)
			}
			if strings.Contains(text, w) {
				t.Errorf("%s occurs in the fixture", w)
			}
		}
	})
	t.Run("an injected dir previews its README, and a dir with none previews itself", func(t *testing.T) {
		r := f.get(t, c("terraform/account-security")).res
		var got []string
		for _, row := range r.Rows[:r.Inj] {
			ft := Fields(row)
			got = append(got, ft.Rel+" "+strings.TrimPrefix(ft.Preview, f.root+"/"))
		}
		for _, w := range []string{"terraform/acct-security-tooling-staging/ terraform/acct-security-tooling-staging/README.md", SP + "/ " + SP} {
			if !slices.Contains(got, w) {
				t.Errorf("missing %q in %v", w, got)
			}
		}
	})
	t.Run("the picker input is the candidates in colour, then every other row", func(t *testing.T) {
		r := f.get(t, c("vpc")).res
		in := r.Input(f.all)
		if len(in) != len(f.all) {
			t.Fatalf("%d input rows for %d rows", len(in), len(f.all))
		}
		for i, row := range r.Rows {
			if rows.StripANSI(in[i]) != row || in[i] == row {
				t.Errorf("row %d is not the coloured form of candidate %q", i, RelOf(row))
			}
		}
		if slices.Contains(in[len(r.Rows):], in[0]) {
			t.Error("a candidate is repeated in the rest")
		}
	})
	t.Run("an injected row keeps its colour", func(t *testing.T) {
		r := f.get(t, c("acct sec prod")).res
		if !strings.Contains(r.Rows[0], rows.CDim+SP+"/"+rows.Off) {
			t.Errorf("row 1 %q", r.Rows[0])
		}
	})
}

// TestKindWordGuard is suite_match's MT_KIND: a kind word never J2-jumps, even when every match sits under one dir.
func TestKindWordGuard(t *testing.T) {
	f := matchFix(t)
	var stderr bytes.Buffer
	var rs []string
	for _, r := range kinds.Generate(f.cfg, f.root, []string{"dir", "mesos"}, &stderr) {
		rs = append(rs, rows.Render(r, f.root))
	}
	res := (&Resolver{Match: f.fzf, Root: f.root, Action: "cd", Jump: "auto", Kinds: f.cfg.AllKinds()}).Resolve("mesos", rs)
	if got := res.Verdict + " " + strings.Join(relsOf(res.Rows), ","); got != "pick mesos/,mesos/services/routemaster/" {
		t.Errorf("got %q", got)
	}
	res = (&Resolver{Match: f.fzf, Root: f.root, Action: "cd", Jump: "auto"}).Resolve("mesos", rs)
	if res.Verdict != "jump" || res.Rule != "dir" {
		t.Errorf("control: with no kind words, mesos is a J2 jump; got %s %s", res.Verdict, res.Rule)
	}
}

// TestMRU is suite_match's MT_MRU: history decides same-name ties, never turns a pick into a jump, and never beats an exact name.
func TestMRU(t *testing.T) {
	f := matchFix(t)
	ranked := mru.Rank(f.all, []string{f.root + "/" + IP + "/vpc", f.root + "/kubernetes/values/thanos-legacy"})
	r := &Resolver{Match: f.fzf, Root: f.root, Action: "cd", Jump: "auto", Kinds: f.cfg.AllKinds()}
	for q, want := range map[string]string{"vpc": IP + "/vpc/", "thanos": "kubernetes/values/thanos/"} {
		res := r.Resolve(q, ranked)
		if res.Verdict != "pick" || RelOf(res.Rows[0]) != want {
			t.Errorf("%s: %s first %q, want pick %q", q, res.Verdict, RelOf(res.Rows[0]), want)
		}
	}
}

func TestEmptyQuery(t *testing.T) {
	f := matchFix(t)
	r := &Resolver{Match: f.fzf, Root: f.root, Action: "cd", Jump: "auto"}
	if res := r.Resolve("  \t", f.all); res.Verdict != "empty" || res.N != len(f.all) || res.Query != "" {
		t.Errorf("%+v", res)
	}
	one := f.all[:1]
	if res := r.Resolve("", one); res.Target != Fields(one[0]) {
		t.Errorf("one row: target %+v", res.Target)
	}
}

func TestApproxMax(t *testing.T) {
	big := make([]string, ApproxMax+1)
	for i := range big {
		big[i] = rows.Render(rows.New("dir", "-", "-", "-", "n"+strconv.Itoa(i), "/r/d"+strconv.Itoa(i), "", false), "/r")
	}
	f := matchFix(t)
	res := (&Resolver{Match: f.fzf, Root: "/r", Action: "cd", Jump: "auto"}).Resolve("securty", big)
	if res.Tier != "T4" || res.Note != "typo matching skipped above 6000 rows" {
		t.Errorf("%s %q", res.Tier, res.Note)
	}
}
