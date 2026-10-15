// hopx is the cross-shell hop spike: subcommand dispatch only, with the work in internal/.
package main

import (
	"bufio"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"

	"github.com/etknorr/hop/spike/hopx/internal/config"
	"github.com/etknorr/hop/spike/hopx/internal/importer"
	"github.com/etknorr/hop/spike/hopx/internal/kinds"
	"github.com/etknorr/hop/spike/hopx/internal/rows"
	"github.com/etknorr/hop/spike/hopx/internal/workspace"
)

const version = "0.0.0-spike"

const usage = `usage: hopx <command> [args]

  hopx rows [-k KINDS] [--root DIR] [-a]   print the rows hop's list would hold, unranked
  hopx rows -w                             workspace rows
  hopx rows -R                             repo rows
  hopx kinds                               the kind registry, * marking a default
  hopx config import [CONFIG.zsh] [-o OUT] convert hop's config.zsh to TOML
  hopx config check                        load the config and report problems
  hopx config path                         print the config path hopx reads
  hopx -V                                  version

The config is $HOPX_CONFIG, else ${XDG_CONFIG_HOME:-~/.config}/hop/config.toml.
`

// errUsage is exit 2, which hop also uses for a bad flag combination.
var errUsage = errors.New("usage")

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr io.Writer) int {
	err := dispatch(args, stdout, stderr)
	switch {
	case err == nil:
		return 0
	case errors.Is(err, errUsage):
		fmt.Fprint(stderr, usage)
		return 2
	case errors.Is(err, errNoRows):
		return 1
	}
	fmt.Fprintln(stderr, "hopx:", err)
	return 1
}

var errNoRows = errors.New("no rows")

func dispatch(args []string, stdout, stderr io.Writer) error {
	if len(args) == 0 {
		return errUsage
	}
	switch args[0] {
	case "-h", "--help", "help":
		fmt.Fprint(stdout, usage)
		return nil
	case "-V", "--version":
		fmt.Fprintln(stdout, "hopx", version)
		return nil
	case "rows":
		return cmdRows(args[1:], stdout, stderr)
	case "__rows":
		return cmdRowsHidden(args[1:], stdout, stderr)
	case "kinds":
		return cmdKinds(stdout, stderr)
	case "config":
		return cmdConfig(args[1:], stdout, stderr)
	}
	return errUsage
}

func load(stderr io.Writer) (*config.Config, error) {
	cfg, err := config.Load(config.Path())
	if err != nil {
		return nil, err
	}
	for _, w := range cfg.Warnings {
		fmt.Fprintln(stderr, "hopx: warning:", w)
	}
	return cfg, nil
}

func gitRoot() (string, error) {
	out, err := exec.Command("git", "rev-parse", "--show-toplevel").Output()
	if err != nil {
		return "", errors.New("not in a git repository (use --root)")
	}
	return strings.TrimRight(string(out), "\n"), nil
}

// splitKinds is ${=${list//,/ }}: commas and whitespace both separate.
func splitKinds(s string) []string {
	return strings.Fields(strings.ReplaceAll(s, ",", " "))
}

func writeRows(w io.Writer, rs []rows.Row, root string) error {
	bw := bufio.NewWriterSize(w, 1<<16)
	for _, r := range rs {
		bw.WriteString(rows.Render(r, root))
		bw.WriteByte('\n')
	}
	return bw.Flush()
}

func cmdRows(args []string, stdout, stderr io.Writer) error {
	fs := flag.NewFlagSet("rows", flag.ContinueOnError)
	fs.SetOutput(stderr)
	kindList := fs.String("k", "", "kinds, comma or space separated")
	root := fs.String("root", "", "repo root (default: the enclosing git toplevel)")
	all := fs.Bool("a", false, "every kind")
	fs.BoolVar(all, "all", false, "every kind")
	ws := fs.Bool("w", false, "workspace rows")
	repos := fs.Bool("R", false, "repo rows")
	if err := fs.Parse(args); err != nil {
		return errUsage
	}
	if fs.NArg() > 0 || (*ws && *repos) || ((*ws || *repos) && (*all || *kindList != "")) || (*all && *kindList != "") {
		return errUsage
	}
	cfg, err := load(stderr)
	if err != nil {
		return err
	}
	s := cfg.Settings
	if *ws || *repos {
		wss := workspace.Parse(s.Workspaces, s.WorkspacesFile)
		var rs []rows.Row
		if *ws {
			rs = kinds.WorkspaceRows(wss)
		} else {
			rs = kinds.RepoRows(workspace.RepoList(s.Repos, wss))
		}
		if len(rs) == 0 {
			return errNoRows
		}
		return writeRows(stdout, rs, "")
	}
	if *root == "" {
		if *root, err = gitRoot(); err != nil {
			return err
		}
	}
	names := cfg.DefaultKinds()
	switch {
	case *all:
		names = cfg.AllKinds()
	case *kindList != "":
		names = splitKinds(*kindList)
	}
	rs := kinds.Generate(cfg, *root, names, stderr)
	if len(rs) == 0 {
		return errNoRows
	}
	return writeRows(stdout, rs, *root)
}

// cmdRowsHidden is `hopx __rows <root> <kind...>`, the form an fzf reload calls, with no flag parsing.
func cmdRowsHidden(args []string, stdout, stderr io.Writer) error {
	if len(args) < 1 || args[0] == "" {
		return errUsage
	}
	cfg, err := load(stderr)
	if err != nil {
		return err
	}
	names := args[1:]
	if len(names) == 0 {
		names = cfg.DefaultKinds()
	}
	return writeRows(stdout, kinds.Generate(cfg, args[0], names, stderr), args[0])
}

func cmdKinds(stdout, stderr io.Writer) error {
	cfg, err := load(stderr)
	if err != nil {
		return err
	}
	defaults := map[string]bool{}
	for _, n := range cfg.DefaultKinds() {
		defaults[n] = true
	}
	for _, k := range cfg.Kinds {
		mark := " "
		if defaults[k.Name] {
			mark = "*"
		}
		fmt.Fprintf(stdout, "%s %-11s %-8s %s\n", mark, k.Name, k.Shape, k.Desc)
	}
	return nil
}

func cmdConfig(args []string, stdout, stderr io.Writer) error {
	if len(args) == 0 {
		return errUsage
	}
	switch args[0] {
	case "path":
		fmt.Fprintln(stdout, config.Path())
		return nil
	case "check":
		cfg, err := load(stderr)
		if err != nil {
			return err
		}
		fmt.Fprintf(stdout, "%s: %d kinds, defaults %s\n", config.Path(), len(cfg.Kinds), strings.Join(cfg.DefaultKinds(), " "))
		return nil
	case "import":
		return cmdImport(args[1:], stdout, stderr)
	}
	return errUsage
}

// cmdImport writes stdout unless -o names a file, so it never overwrites a config.toml by surprise.
func cmdImport(args []string, stdout, stderr io.Writer) error {
	fs := flag.NewFlagSet("config import", flag.ContinueOnError)
	fs.SetOutput(stderr)
	out := fs.String("o", "", "write the TOML here instead of stdout")
	var src string
	for len(args) > 0 {
		if err := fs.Parse(args); err != nil {
			return errUsage
		}
		args = fs.Args()
		if len(args) > 0 {
			if src != "" {
				return errUsage
			}
			src, args = args[0], args[1:]
		}
	}
	if src == "" {
		src = os.Getenv("HOP_CONFIG")
	}
	if src == "" {
		base := os.Getenv("XDG_CONFIG_HOME")
		if base == "" {
			base = os.Getenv("HOME") + "/.config"
		}
		src = base + "/hop/config.zsh"
	}
	res, err := importer.Import(src)
	if err != nil {
		return err
	}
	for _, w := range res.Warnings {
		fmt.Fprintln(stderr, "hopx: warning:", w)
	}
	text := res.TOML(src)
	if *out == "" {
		_, err := io.WriteString(stdout, text)
		return err
	}
	return os.WriteFile(*out, []byte(text), 0o644)
}
