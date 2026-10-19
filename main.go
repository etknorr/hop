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
	"path/filepath"
	"strings"

	"github.com/etknorr/hop/internal/config"
	"github.com/etknorr/hop/internal/importer"
	"github.com/etknorr/hop/internal/kinds"
	"github.com/etknorr/hop/internal/pick"
	"github.com/etknorr/hop/internal/rows"
	"github.com/etknorr/hop/internal/workspace"
)

const version = "0.0.0-spike"

const usage = `usage: hopx [-a | -k KINDS] [-c] [-p] [--cd] [-o | -e | --action=MODE] [query...]
       hopx -w | -R [query...]
       hopx / | -
       hopx <command> [args]

  hopx [query...]                          jump on a clear match, else pick in fzf; with no terminal, report
  hopx init zsh|bash|fish|pwsh [--cmd NAME] print the shell function, widget and completion
  hopx rows [-k KINDS] [--root DIR] [-a]   print the rows hop's list would hold, unranked
  hopx rows -w                             workspace rows
  hopx rows -R                             repo rows
  hopx kinds                               the kind registry, * marking a default
  hopx config import [CONFIG.zsh] [-o OUT] convert hop's config.zsh to TOML
  hopx config check                        load the config and report problems
  hopx config path                         print the config path hopx reads
  hopx -V, -v                              version

The config is $HOPX_CONFIG, else ${XDG_CONFIG_HOME:-~/.config}/hop/config.toml.
`

// errUsage is exit 2, which hop also uses for a bad flag combination.
var errUsage = errors.New("usage")

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 || !subcommands[args[0]] {
		return cmdHop(args, stdout, stderr)
	}
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
	var ec exitCode
	if errors.As(err, &ec) {
		return int(ec)
	}
	fmt.Fprintln(stderr, "hopx:", err)
	return 1
}

var errNoRows = errors.New("no rows")

// exitCode is a callback's own status, passed through as it is; 0 is success.
type exitCode int

func (e exitCode) Error() string { return fmt.Sprintf("exit %d", int(e)) }

func argAt(a []string, i int) string {
	if i < len(a) {
		return a[i]
	}
	return ""
}

// subcommands take the first word; anything else is hop's own command line, so a target named rows needs `hopx -- rows`.
var subcommands = map[string]bool{
	"-h": true, "--help": true, "help": true, "-V": true, "-v": true, "--version": true, "init": true,
	"rows": true, "kinds": true, "config": true, "__rows": true, "__resolve-dump": true,
	"__sh": true, "__preview": true, "__menu": true, "__key": true, "__header": true, "__complete": true,
}

func dispatch(args []string, stdout, stderr io.Writer) error {
	if len(args) == 0 {
		return errUsage
	}
	switch args[0] {
	case "-h", "--help", "help":
		fmt.Fprint(stdout, usage)
		return nil
	case "-V", "-v", "--version":
		fmt.Fprintln(stdout, "hopx", version)
		return nil
	case "rows":
		return cmdRows(args[1:], stdout, stderr)
	case "__rows":
		return cmdRowsHidden(args[1:], stdout, stderr)
	case "__resolve-dump":
		return cmdResolveDump(args[1:], stdout, stderr)
	case "init":
		return cmdInit(args[1:], stdout)
	case "__sh":
		if len(args) != 2 {
			return errUsage
		}
		return exitCode(pick.Shim(args[1], func(a []string) int { return run(a, stdout, stderr) }, stdout, stderr))
	case "__preview":
		pick.Preview(stdout, argAt(args, 1), argAt(args, 2))
		return nil
	case "__menu":
		return cmdMenu(stdout, stderr)
	case "__key":
		s, err := pick.Load()
		if err != nil {
			return err
		}
		_, err = io.WriteString(stdout, pick.Key(s, argAt(args, 1), argAt(args, 2)))
		return err
	case "__header":
		s, err := pick.Load()
		if err != nil {
			return err
		}
		_, err = io.WriteString(stdout, s.Header)
		return err
	case "__complete":
		return cmdComplete(args[1:], stdout, stderr)
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
	for _, r := range rows.List(rs, root, nil) {
		bw.WriteString(r)
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

// cmdRowsHidden is `hopx __rows`, with no flag parsing, in two forms.
// - `__rows <root> <kind...>` is the plain enumeration the parity harness compares, unranked.
// - `__rows [kind...]` inside a picker reads the root and -c dir from the session, and ranks, as _hop_rows does for a reload.
func cmdRowsHidden(args []string, stdout, stderr io.Writer) error {
	if os.Getenv("HOPX_SESSION") != "" && (len(args) == 0 || !filepath.IsAbs(args[0])) {
		return cmdRowsSession(args, stdout, stderr)
	}
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
