package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/etknorr/hop/internal/config"
	doc "github.com/etknorr/hop/internal/doctor"
	"github.com/etknorr/hop/internal/shell"
	"github.com/etknorr/hop/internal/upgrade"
	"github.com/etknorr/hop/internal/version"
)

// synopsis is what a usage error prints: the forms, without the kinds a full -h needs the config for.
const synopsis = `usage: hop [-a|--all] [-k KIND[,KIND...]] [-c] [-R|-w] [-p] [[--cd] [-o|-e] | --action=MODE] [--no-vim] [-h] [/|-] [words...]
       hop init zsh|bash|fish [--cmd NAME]
       hop import [CONFIG.zsh] [-o OUT] [--force]
       hop upgrade [--check] [VERSION]
`

const usageBody = `
  hop                 pick from the default kinds, starting in NORMAL mode
  hop api prod        a clear match jumps with no UI; otherwise the picker opens best-first
  hop services/api    a path that exists jumps straight there, before any matching;
                      outside its repo, hop looks for it in your repos and workspaces
  hop -p, --pick      always open the picker, even for a clear match (HOP_JUMP=never)
  hop -o, --open      Enter opens the target in VS Code instead of cd-ing
  hop -e, --reveal    Enter shows the target in the VS Code explorer instead of cd-ing
  hop --cd -o         Enter cds, then opens; --cd -e cds, then reveals
  hop --action=MODE   Enter does MODE: cd, open, reveal, cd+open, cd+reveal (HOP_ACTION)
  hop -a, --all       include every registered kind, not just the defaults
  hop -k project,dir  restrict to specific kinds
  hop -c, --cwd       only targets under $PWD, for any kind
  hop -k file x.yml   find a tracked FILE by name (opt-in: it is every file)
  hop file x.yml      the same: a first word naming a kind outside the defaults is -k,
                      when it has targets here and no default target holds the word
  hop -c -k file x    find a file in just this subtree
  hop /   hopr        cd to the repo root
  hop -               cd -
  hop -R, --repos     pick a repo from $HOP_REPOS
  hop -w, --workspaces  pick a workspace; enter cds, ctrl-l or l shows its repos
  hopw                cd to the workspace containing $PWD (longest prefix wins)
  hop --no-vim        search-first fzf, no modal layer (same as HOP_VIM=0)
  hop --vim           force the modal layer on when HOP_VIM=0 is set
  hop --doctor        dump config, tools and kind counts for a bug report
  hop --doctor=short  the same, minus paths and names; safe to paste publicly
  HOP_DEBUG=1 hop     log every pick and key dispatch, read it with --doctor
  hop init zsh        the shell function, widget and completion: eval "$(hop init zsh)"
  hop import          turn zsh hop's config.zsh into TOML, printed or written with -o
  hop upgrade         update to the newest release, the way hop was installed
  hop upgrade 1.2.0   install exactly that release (not under brew)
  hop upgrade --check what is installed vs what is released; changes nothing
  hop -V, -v, --version  print the version, and say when the shell integration is older
  hop -h, --help      this text
`

const usageKeys = `
  NORMAL: j/k move | g/G first/last | ^d/^u half page | enter %[1]s | c cd
          o code file | O code dir | e $EDITOR file | y/Y copy dir/file
          b gh browse | p preview | r refresh | ? help | q quit
          l drill in | h back out | / SEARCH | : switch view
          esc clears the query, or quits when it is empty

  : opens the view menu in place; enter switches, esc goes back.

  SEARCH: every key types | esc NORMAL, query kept | enter %[1]s | alt-enter cd
          ctrl-o code -r file | ctrl-t code -n dir
          ctrl-y copy dir | alt-y copy file | alt-o $EDITOR file
          alt-B gh browse | alt-a all kinds | ctrl-r refresh preview
          alt-p or ctrl-/ toggle preview

  ^G and alt-g launch hop from a half-typed command line.
`

// usage is -h: the forms, examples, the registered kinds with * on the defaults, and the keys.
// - A config that fails to load still gets the usage, with the error where the kinds would be.
func usage(stdout io.Writer) {
	bw := bufio.NewWriter(stdout)
	defer bw.Flush()
	bw.WriteString(synopsis)
	bw.WriteString(usageBody)
	bw.WriteString("\n  kinds, * being in the default set:\n")
	enter := "cd"
	cfg, err := config.Load(config.Path())
	if err != nil {
		fmt.Fprintf(bw, "    (none: %v)\n", err)
	} else {
		enter = cfg.Settings.Action
		def := map[string]bool{}
		for _, n := range cfg.DefaultKinds() {
			def[n] = true
		}
		for _, k := range cfg.Kinds {
			mark := " "
			if def[k.Name] {
				mark = "*"
			}
			fmt.Fprintf(bw, "    %s %-12s %s\n", mark, k.Name, k.Desc)
		}
	}
	fmt.Fprintf(bw, "\n  declare your own in %s; see config.example.toml\n", config.Path())
	fmt.Fprintf(bw, usageKeys, enter)
}

// printVersion is -V: the version line, then the reload hint when the shell's integration is from other templates.
func printVersion(stdout io.Writer) {
	fmt.Fprintln(stdout, version.Line())
	if s := version.Stale(os.Getenv("HOP_INIT_HASH"), os.Getenv("HOP_SHELL")); s != "" {
		fmt.Fprintln(stdout, s)
	}
}

func install() upgrade.Install { return upgrade.Detect(self(), version.Read()) }

// doctor is --doctor; mode is "" or "short", which parseHop has already checked.
func doctor(mode string, stdout io.Writer) int {
	return doc.Run(stdout, doc.Options{
		Short:    mode == "short",
		Install:  install(),
		Version:  strings.TrimPrefix(version.Line(), "hop "),
		InitHash: version.InitHash(),
		Recipes:  config.PresetOrder,
	})
}

// info runs the option-loop case parseHop stopped on: -h, -V, or --doctor[=short].
func info(what string, stdout, stderr io.Writer) int {
	switch what {
	case "help":
		usage(stdout)
	case "version":
		printVersion(stdout)
	case "doctor", "doctor=short":
		return doctor(strings.TrimPrefix(strings.TrimPrefix(what, "doctor"), "="), stdout)
	default:
		fmt.Fprintf(stderr, "hop: --%s: unknown --doctor mode, want: --doctor=short\n", what)
		return 2
	}
	return 0
}

func cmdUpgrade(args []string, stdout, stderr io.Writer) int {
	u := &upgrade.Upgrader{
		Install: install(),
		Version: version.String(),
		Stale:   version.Stale(os.Getenv("HOP_INIT_HASH"), os.Getenv("HOP_SHELL")),
		Stdout:  stdout,
		Stderr:  stderr,
	}
	return u.Run(args)
}

func cmdInit(args []string, stdout io.Writer) error {
	sh, cmd := "", ""
	for i := 0; i < len(args); i++ {
		switch a := args[i]; {
		case a == "--cmd" && i+1 < len(args):
			i++
			cmd = args[i]
		case strings.HasPrefix(a, "--cmd="):
			cmd = a[len("--cmd="):]
		case sh == "" && !strings.HasPrefix(a, "-"):
			sh = a
		default:
			return errUsage
		}
	}
	if sh == "" {
		return errUsage
	}
	s, err := shell.Init(sh, cmd)
	if err != nil {
		return err
	}
	_, err = io.WriteString(stdout, s)
	return err
}

func cmdComplete(words []string, stdout, stderr io.Writer) error {
	var ks []shell.Kind
	if cfg, err := config.Load(config.Path()); err == nil {
		for _, k := range cfg.Kinds {
			ks = append(ks, shell.Kind{Name: k.Name, Desc: k.Desc})
		}
	}
	bw := bufio.NewWriter(stdout)
	for _, c := range shell.Complete(words, ks, config.Actions) {
		bw.WriteString(c)
		bw.WriteByte('\n')
	}
	return bw.Flush()
}
