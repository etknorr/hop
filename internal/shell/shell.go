// Package shell holds the embedded `hop init` scripts and the `hop __complete` candidates.
package shell

import (
	"crypto/sha256"
	"embed"
	"encoding/hex"
	"fmt"
	"io/fs"
	"regexp"
	"slices"
	"strings"
)

//go:embed init/*
var scripts embed.FS

// Names is every shell `hop init` takes, in the order help and completion list them.
var Names = []string{"zsh", "bash", "fish"}

var cmdName = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_-]*$`)

// Hash is the first 12 hex digits of sha256 over every template, which each script exports as HOP_INIT_HASH.
// - One hash for all shells: a template change asks every shell to reload, which costs one `exec` and never misses one.
func Hash() string {
	h := sha256.New()
	names, _ := fs.Glob(scripts, "init/*")
	slices.Sort(names)
	for _, n := range names {
		b, _ := scripts.ReadFile(n)
		fmt.Fprintf(h, "%s\x00%d\x00", n, len(b))
		h.Write(b)
	}
	return hex.EncodeToString(h.Sum(nil))[:12]
}

// Init is `hop init <shell> [--cmd NAME]`: the script with its function named.
// - The function is hop unless --cmd renames it, zoxide-style.
// - hopr and hopw come only with the plain name, so a try-out `--cmd hop1` leaves an installed hop's alone.
func Init(sh, cmd string) (string, error) {
	if !slices.Contains(Names, sh) {
		return "", fmt.Errorf("unsupported shell %q: one of %s", sh, strings.Join(Names, ", "))
	}
	if cmd == "" {
		cmd = "hop"
	}
	if !cmdName.MatchString(cmd) {
		return "", fmt.Errorf("--cmd %q is not a plain function name", cmd)
	}
	b, err := scripts.ReadFile("init/hop." + sh)
	if err != nil {
		return "", err
	}
	s := string(b)
	if cmd == "hop" {
		x, err := scripts.ReadFile("init/hopr." + sh)
		if err != nil {
			return "", err
		}
		s += "\n" + string(x)
	}
	s = strings.ReplaceAll(s, "@HASH@", Hash())
	return strings.ReplaceAll(s, "@CMD@", cmd), nil
}

// Kind is a completion candidate for -k: a name and its description.
type Kind struct{ Name, Desc string }

// flag is one option; a flag on the line drops every name in its group, as zsh hop's _arguments exclusion lists do.
// - stop marks -h, -V and --doctor, which end hop's option loop, so nothing completes after one.
type flag struct {
	names []string
	desc  string
	group []string
	stop  bool
}

var hopFlags = []flag{
	{names: []string{"-a", "--all"}, desc: "include every registered kind, not just the defaults"},
	{names: []string{"-k", "--kinds"}, desc: "restrict to these kinds, comma-separated"},
	{names: []string{"-R", "--repos"}, desc: "pick a repo"},
	{names: []string{"-w", "--workspaces"}, desc: "pick a workspace; l shows its repos"},
	{names: []string{"-c", "--cwd", "--here"}, desc: "only targets under $PWD, for any kind"},
	{names: []string{"-p", "--pick"}, desc: "always open the picker, even for a clear match"},
	{names: []string{"--cd"}, desc: "cd to the target, then do what -o or -e asks", group: []string{"--cd", "--action="}},
	{names: []string{"-o", "--open"}, desc: "enter opens the target in VS Code instead of cd-ing", group: []string{"-o", "--open", "-e", "--reveal", "--action="}},
	{names: []string{"-e", "--reveal"}, desc: "enter shows the target in the VS Code explorer", group: []string{"-o", "--open", "-e", "--reveal", "--action="}},
	{names: []string{"--action="}, desc: "what enter does: cd, open, reveal, cd+open, cd+reveal", group: []string{"--cd", "-o", "--open", "-e", "--reveal", "--action="}},
	{names: []string{"--no-vim"}, desc: "search-first fzf, no modal layer (same as HOP_VIM=0)", group: []string{"--vim", "--no-vim"}},
	{names: []string{"--vim"}, desc: "force the modal layer on when HOP_VIM=0 is set", group: []string{"--vim", "--no-vim"}},
	{names: []string{"--doctor", "--doctor="}, desc: "dump config, tools and kind counts for a bug report", stop: true},
	{names: []string{"-h", "--help"}, desc: "show usage and exit", stop: true},
	{names: []string{"-V", "-v", "--version"}, desc: "show the version, and whether the shell integration is current", stop: true},
}

var upgradeFlags = []flag{
	{names: []string{"--check", "--dry-run", "-n"}, desc: "report installed vs released, change nothing"},
	{names: []string{"-h", "--help"}, desc: "show upgrade usage and exit", stop: true},
}

var importFlags = []flag{
	{names: []string{"-o"}, desc: "write the TOML to this file instead of stdout"},
	{names: []string{"--force"}, desc: "overwrite the -o file"},
}

var firstWords = [][2]string{
	{"/", "the repo root"}, {"-", "the previous directory (cd -)"},
	{"upgrade", "update hop to a release"}, {"init", "print the shell integration"}, {"import", "turn zsh hop's config.zsh into TOML"},
}

// flagName is the word as a flag table names it: `--action=cd` is `--action=`.
func flagName(w string) string {
	if i := strings.IndexByte(w, '='); i > 0 && strings.HasPrefix(w, "--") {
		return w[:i+1]
	}
	return w
}

// Complete is `hop __complete <words...>`: the words after the command name, the last one being the word under the cursor.
// - Each candidate is `word<TAB>description`; zsh and fish show the description, bash keeps the word.
func Complete(words []string, kinds []Kind, actions []string) []string {
	cur, prev := "", ""
	n := len(words)
	if n > 0 {
		cur = words[n-1]
		if n > 1 {
			prev = words[n-2]
		}
	}
	var before []string
	if n > 1 {
		before = words[:n-1]
	}
	var out []string
	add := func(c, d string) {
		if strings.HasPrefix(c, cur) {
			out = append(out, c+"\t"+d)
		}
	}
	verb := ""
	if len(before) > 0 {
		verb = before[0]
	}
	switch verb {
	case "init":
		switch {
		case prev == "--cmd":
		case len(before) == 1:
			for _, s := range Names {
				add(s, "")
			}
		case strings.HasPrefix(cur, "-") && !slices.Contains(before, "--cmd"):
			add("--cmd", "name the function something other than hop")
		}
		return out
	case "upgrade":
		if strings.HasPrefix(cur, "-") {
			addFlags(upgradeFlags, before[1:], add)
		}
		return out
	case "import":
		if prev != "-o" && strings.HasPrefix(cur, "-") {
			addFlags(importFlags, before[1:], add)
		}
		return out
	}
	if slices.Contains(before, "--") {
		return nil
	}
	switch {
	case prev == "-k" || prev == "--kinds":
		head := ""
		if i := strings.LastIndexByte(cur, ','); i >= 0 {
			head = cur[:i+1]
		}
		have := strings.Split(head, ",")
		for _, k := range kinds {
			if !slices.Contains(have, k.Name) {
				add(head+k.Name, k.Desc)
			}
		}
		return out
	case strings.HasPrefix(cur, "--action="):
		if stopped(hopFlags, before) || excluded(hopFlags, "--action=", before) {
			return nil
		}
		for _, a := range actions {
			add("--action="+a, "what enter does")
		}
		return out
	case strings.HasPrefix(cur, "--doctor="):
		if !stopped(hopFlags, before) {
			add("--doctor=short", "the same, minus paths and names; safe to paste publicly")
		}
		return out
	}
	if len(before) == 0 {
		for _, f := range firstWords {
			add(f[0], f[1])
		}
	}
	if strings.HasPrefix(cur, "-") {
		addFlags(hopFlags, before, add)
	}
	return out
}

func addFlags(fl []flag, before []string, add func(c, d string)) {
	if stopped(fl, before) {
		return
	}
	for _, f := range fl {
		if excluded(fl, f.names[0], before) {
			continue
		}
		for _, name := range f.names {
			add(name, f.desc)
		}
	}
}

// stopped reports a flag on the line that ends the option loop.
func stopped(fl []flag, before []string) bool {
	for _, f := range fl {
		for _, w := range before {
			if f.stop && slices.Contains(f.names, flagName(w)) {
				return true
			}
		}
	}
	return false
}

// excluded reports whether name's group already has a member on the line; with no group, the group is the flag's own names.
func excluded(fl []flag, name string, before []string) bool {
	for _, f := range fl {
		if !slices.Contains(f.names, name) {
			continue
		}
		group := f.group
		if group == nil {
			group = f.names
		}
		for _, w := range before {
			if slices.Contains(group, flagName(w)) {
				return true
			}
		}
	}
	return false
}
