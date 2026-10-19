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

var flags = [][2]string{
	{"-a", "every registered kind"}, {"--all", "every registered kind"},
	{"-k", "these kinds, comma-separated"}, {"--kinds", "these kinds, comma-separated"},
	{"-c", "only targets under $PWD"}, {"--here", "only targets under $PWD"},
	{"-R", "pick a repo"}, {"--repos", "pick a repo"},
	{"-w", "pick a workspace"}, {"--workspaces", "pick a workspace"},
	{"-p", "always open the picker"}, {"--pick", "always open the picker"},
	{"--cd", "cd, then do what -o or -e asks"},
	{"-o", "enter opens in VS Code"}, {"--open", "enter opens in VS Code"},
	{"-e", "enter reveals in VS Code"}, {"--reveal", "enter reveals in VS Code"},
	{"--action=", "what enter does"},
	{"-h", "usage"}, {"-V", "version"},
}

var firstWords = [][2]string{
	{"/", "the repo root"}, {"-", "the previous directory"},
	{"init", "print the shell integration"}, {"rows", "print the rows"}, {"kinds", "list the kinds"}, {"config", "import, check or locate the config"},
}

// Complete is `hop __complete <words...>`: the words after the command name, the last one being the word under the cursor.
// - Each candidate is `word<TAB>description`; zsh and fish show the description, bash keeps the word.
func Complete(words []string, kinds []Kind, actions []string) []string {
	cur, prev := "", ""
	if n := len(words); n > 0 {
		cur = words[n-1]
		if n > 1 {
			prev = words[n-2]
		}
	}
	var out []string
	add := func(c, d string) {
		if strings.HasPrefix(c, cur) {
			out = append(out, c+"\t"+d)
		}
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
	case len(words) == 2 && words[0] == "init":
		for _, s := range Names {
			add(s, "")
		}
	case strings.HasPrefix(cur, "--action="):
		for _, a := range actions {
			add("--action="+a, "what enter does")
		}
	default:
		if len(words) <= 1 {
			for _, f := range firstWords {
				add(f[0], f[1])
			}
		}
		if strings.HasPrefix(cur, "-") {
			for _, f := range flags {
				add(f[0], f[1])
			}
		}
	}
	return out
}
