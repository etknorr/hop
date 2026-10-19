package resolve

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/etknorr/hop/internal/rows"
)

// Place is somewhere a path typed outside its repo may live: a repo hop knows, or a workspace root.
type Place struct {
	Name, Path string
	Workspace  bool
}

// Away is what Elsewhere found: a jump, or rows to pick from, with Res describing either.
type Away struct {
	Jump bool
	Res  Result
	Rows []string
}

// Elsewhere is _hop_elsewhere (hop 0.3.0): T0 again, for a path typed outside the repo it lives in.
// - Every repo and workspace root is an anchor, minus pwd and root for the path as typed, which T0 already tried.
// - A path may start with its repo's own name, as in configuration/terraform/x.
// - One distinct target jumps unless jump is never.
// - Several jump only under auto, when all are checkouts of one origin and exactly one is on its default branch.
// - Otherwise the caller opens a picker on Rows, the repo visited most recently first.
// - ok is false when no place holds the path; hint is then hop's line naming the repos that hold its first dir, or "".
func Elsewhere(word, root, pwd string, places []Place, jump string, hist []string) (a Away, hint string, ok bool) {
	w := strings.TrimRight(word, "/")
	if !strings.Contains(w, "/") || strings.HasPrefix(w, "/") || strings.HasPrefix(w, "~") ||
		strings.HasPrefix(w, "./") || strings.HasPrefix(w, "../") ||
		strings.Contains("/"+w+"/", "/./") || strings.Contains("/"+w+"/", "/../") {
		return a, "", false
	}
	if root != "" {
		root = realpath(root)
	}
	slash := strings.IndexByte(w, '/')
	first := strings.ToLower(w[:slash])
	var anchors []anchor
	for _, p := range places {
		if p.Workspace {
			continue
		}
		anchors = append(anchors, anchor{p.Path, w, p.Name, false})
		if strings.ToLower(filepath.Base(p.Path)) == first {
			anchors = append(anchors, anchor{p.Path, w[slash+1:], p.Name, false})
		}
	}
	for _, p := range places {
		if p.Workspace {
			anchors = append(anchors, anchor{p.Path, w, p.Name, true})
		}
	}

	type hit struct {
		path, where, home string
		ws                bool
	}
	var hits []hit
	seen := map[string]bool{}
	cwd := realpath(pwd)
	for _, an := range anchors {
		ap := realpath(an.path)
		if an.rest == w && (ap == cwd || ap == root) {
			continue
		}
		h, found := pathUnder(ap, an.rest)
		if !found || seen[realpath(h)] {
			continue
		}
		seen[realpath(h)] = true
		home := ap
		if an.ws {
			seg, _, _ := strings.Cut(strings.TrimPrefix(h, ap+"/"), "/")
			home = ap + "/" + seg
		}
		hits = append(hits, hit{h, an.name, home, an.ws})
	}
	if len(hits) == 0 {
		return a, nearHint(w, root, anchors), false
	}

	j, why := -1, ""
	if jump != "never" && len(hits) == 1 {
		j = 0
	} else if jump == "auto" {
		homes := make([]string, len(hits))
		for i, h := range hits {
			homes[i] = h.home
		}
		if i, branch, found := mainCheckout(homes); found {
			j, why = i, fmt.Sprintf(", the %s checkout of %d", branch, len(hits))
		}
	}
	if j >= 0 {
		t := literalFields(hits[j].path, "")
		where := hits[j].where
		if hits[j].ws {
			where = "workspace " + where
		}
		a.Jump = true
		a.Res = Result{Verdict: "jump", Tier: "T0", Rule: "elsewhere", Query: word, Target: t, N: 1, M: 1,
			Note: fmt.Sprintf("hop: %s -> %s (found in %s%s)", word, t.Rel, where, why)}
		return a, "", true
	}

	// A repo ranks by its first appearance in the history, as the repo or anything inside it, then by path, in byte order.
	keys := make([]string, len(hits))
	for i, h := range hits {
		at := len(hist) + 1
		for n, d := range hist {
			if d == h.home || strings.HasPrefix(d, h.home+"/") {
				at = n + 1
				break
			}
		}
		keys[i] = fmt.Sprintf("%06d%s\t%s\t%d", at, h.home, h.path, i)
	}
	sort.Strings(keys)
	var raw []rows.Row
	var where []string
	for _, k := range keys {
		i, _ := strconv.Atoi(k[strings.LastIndexByte(k, '\t')+1:])
		h := hits[i]
		where = append(where, rows.Tilde(h.home))
		t := literalFields(h.path, "")
		kind, file := "dir", !isDir(h.path)
		if file {
			kind = "file"
		}
		raw = append(raw, rows.New(kind, "-", "-", "-", filepath.Base(h.home), t.Dir, t.Preview, file))
	}
	a.Rows = rows.List(raw, "", nil)
	a.Res = Result{
		Verdict: "pick", Tier: "T0", Rule: "elsewhere", Query: word, N: len(a.Rows), M: len(a.Rows),
		Note: fmt.Sprintf("found in %d places: %s", len(a.Rows), strings.Join(where, ", ")),
	}
	for _, r := range a.Rows {
		a.Res.Rows = append(a.Res.Rows, rows.StripANSI(r))
	}
	return a, "", true
}

// anchor is one place Elsewhere tries, with the part of the path it tries there.
type anchor struct {
	path, rest, name string
	ws               bool
}

// nearHint names the repos holding a missing path's first dir, since only the repo a misspelt path lives in can correct it.
func nearHint(w, root string, anchors []anchor) string {
	var near []string
	seen := map[string]bool{}
	seg := ""
	for _, an := range anchors {
		if an.ws || !strings.Contains(an.rest, "/") {
			continue
		}
		ap := realpath(an.path)
		if ap == root || seen[ap] {
			continue
		}
		s, _, _ := strings.Cut(an.rest, "/")
		if h, found := pathUnder(ap, s); !found || !isDir(h) {
			continue
		}
		seen[ap] = true
		near = append(near, an.name)
		if seg == "" {
			seg = s
		}
	}
	if len(near) == 0 {
		return ""
	}
	more := ""
	if len(near) > 3 {
		more = fmt.Sprintf(" and %d more", len(near)-3)
	}
	return fmt.Sprintf("hop: no repo has %s, but %s/ is in %s%s; hop corrects a misspelt path from inside its repo.",
		w, seg, strings.Join(near[:min(3, len(near))], ", "), more)
}

// mainCheckout is _hop_main_checkout: the one dir on its default branch, when every dir is a checkout of one origin.
func mainCheckout(dirs []string) (int, string, bool) {
	origin, at, branch, n := "", -1, "", 0
	for i, d := range dirs {
		o, b, def, ok := gitFacts(d)
		if !ok || (origin != "" && o != origin) {
			return 0, "", false
		}
		origin = o
		if b == "" || b != def {
			continue
		}
		n++
		at, branch = i, b
	}
	if n != 1 {
		return 0, "", false
	}
	return at, branch, true
}

func readLine(p string) (string, bool) {
	b, err := os.ReadFile(p)
	if err != nil {
		return "", false
	}
	l, _, _ := strings.Cut(string(b), "\n")
	return l, true
}

// gitFacts is _hop_git_facts: origin, branch and default branch, read from the checkout's git files without running git.
// - origin drops scheme, user and a trailing .git, so git@host:org/repo and https://host/org/repo agree.
// - branch is "" on a detached HEAD; default is origin/HEAD's, else main when a main branch exists, else master.
// - Anything it cannot read fails, a reftable repo included, so a guess never becomes a jump.
func gitFacts(d string) (origin, branch, def string, ok bool) {
	g := d + "/.git"
	st, err := os.Stat(g)
	if err != nil {
		return
	}
	if !st.IsDir() {
		l, found := readLine(g)
		if !found {
			return
		}
		g = strings.TrimPrefix(l, "gitdir: ")
		if !strings.HasPrefix(g, "/") {
			g = d + "/" + g
		}
	}
	common := g
	if l, found := readLine(g + "/commondir"); found {
		if strings.HasPrefix(l, "/") {
			common = l
		} else {
			common = g + "/" + l
		}
	}
	cfg, err := os.ReadFile(common + "/config")
	if err != nil || exists(common+"/reftable") {
		return
	}
	head, found := readLine(g + "/HEAD")
	if !found {
		return
	}
	sect, url := "", ""
	for l := range strings.SplitSeq(string(cfg), "\n") {
		l = strings.TrimSpace(l)
		switch {
		case strings.HasPrefix(l, "["):
			sect = l
		case url == "" && strings.EqualFold(sect, `[remote "origin"]`) && len(l) >= 3 && strings.EqualFold(l[:3], "url") &&
			strings.HasPrefix(strings.TrimLeft(l[3:], " \t"), "="):
			_, v, _ := strings.Cut(l, "=")
			url = strings.TrimLeft(v, " \t")
		}
	}
	url = strings.TrimSuffix(strings.TrimPrefix(url, `"`), `"`)
	if url == "" {
		return
	}
	url = strings.TrimSuffix(strings.TrimSuffix(url, "/"), ".git")
	if _, rest, scheme := strings.Cut(url, "://"); scheme {
		if _, r, at := strings.Cut(rest, "@"); at {
			rest = r
		}
		url = rest
	} else {
		if _, r, at := strings.Cut(url, "@"); at {
			url = r
		}
		url = strings.Replace(url, ":", "/", 1)
	}
	branch, _ = strings.CutPrefix(head, "ref: refs/heads/")
	if branch == head {
		branch = ""
	}
	if l, found := readLine(common + "/refs/remotes/origin/HEAD"); found {
		if d, isRef := strings.CutPrefix(l, "ref: refs/remotes/origin/"); isRef {
			def = d
		}
	}
	if def == "" {
		def = "main"
		if !gitHas(common, "main") && gitHas(common, "master") {
			def = "master"
		}
	}
	return strings.ToLower(url), branch, def, true
}

// gitHas is _hop_git_has: the branch exists, locally or on origin, as a loose or a packed ref.
func gitHas(c, b string) bool {
	if exists(c+"/refs/heads/"+b) || exists(c+"/refs/remotes/origin/"+b) {
		return true
	}
	p, err := os.ReadFile(c + "/packed-refs")
	if err != nil {
		return false
	}
	s := "\n" + string(p) + "\n"
	return strings.Contains(s, " refs/heads/"+b+"\n") || strings.Contains(s, " refs/remotes/origin/"+b+"\n")
}
