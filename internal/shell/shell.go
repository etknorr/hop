// Package shell holds the embedded `hopx init` scripts and the `hopx __complete` candidates.
package shell

import (
	"embed"
	"fmt"
	"regexp"
	"slices"
	"strings"
)

//go:embed init/*
var scripts embed.FS

// Shells maps each `hopx init` name to its script.
var Shells = map[string]string{"zsh": "hopx.zsh", "bash": "hopx.bash", "fish": "hopx.fish", "pwsh": "hopx.ps1", "powershell": "hopx.ps1"}

var cmdName = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_-]*$`)

// Init is `hopx init <shell> [--cmd NAME]`: the script with its function named, and pwsh's binary path baked in.
// - The function is hopx unless --cmd renames it, zoxide-style; it never defaults to hop, which zsh hop owns.
func Init(sh, cmd, bin string) (string, error) {
	name, ok := Shells[sh]
	if !ok {
		return "", fmt.Errorf("unsupported shell %q: one of zsh, bash, fish, pwsh", sh)
	}
	if cmd == "" {
		cmd = "hopx"
	}
	if !cmdName.MatchString(cmd) {
		return "", fmt.Errorf("--cmd %q is not a plain function name", cmd)
	}
	b, err := scripts.ReadFile("init/" + name)
	if err != nil {
		return "", err
	}
	s := strings.ReplaceAll(string(b), "@CMD@", cmd)
	return strings.ReplaceAll(s, "@BIN@", strings.ReplaceAll(bin, "'", "''")), nil
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

// Complete is `hopx __complete <words...>`: the words after the command name, the last one being the word under the cursor.
// - Each candidate is `word<TAB>description`; zsh, fish and pwsh show the description, bash keeps the word.
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
		for _, s := range []string{"zsh", "bash", "fish", "pwsh"} {
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
