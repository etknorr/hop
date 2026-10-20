// Package doctor is `hop --doctor`: the install, config, tools and state behind a report, in one block to paste.
// - Full mode prints paths, workspace names and kind names; --doctor=short prints counts and shapes instead.
// - $HOME prints as ~ in both, through one substitution at the end, so a forgotten collapse can't leak it.
package doctor

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/BurntSushi/toml"
	"golang.org/x/term"

	"github.com/etknorr/hop/internal/config"
	"github.com/etknorr/hop/internal/debuglog"
	"github.com/etknorr/hop/internal/kinds"
	"github.com/etknorr/hop/internal/upgrade"
	"github.com/etknorr/hop/internal/workspace"
)

// Options is what the caller knows and the environment doesn't say: the binary, its version, and the code check.
type Options struct {
	Short      bool
	Install    upgrade.Install
	Version    string
	InitHash   string
	CodeUsable func(code string) (bool, string)
	Recipes    []string
}

type report struct {
	o        Options
	b        bytes.Buffer
	cfg      *config.Config
	cfgErr   error
	file     map[string]any
	defaults map[string]string
}

func (r *report) line(format string, a ...any) { fmt.Fprintf(&r.b, format+"\n", a...) }
func (r *report) kv(k, v string)               { r.line("  %-22s %s", k, v) }

// Run writes the report and returns its exit status, which is 0 whatever it finds.
func Run(w io.Writer, o Options) int {
	if o.CodeUsable == nil {
		o.CodeUsable = onPath
	}
	r := &report{o: o}
	r.cfg, r.cfgErr = config.Load(config.Path())
	r.file = fileSettings(config.Path())
	r.defaults = defaultPaths()
	if o.Short {
		r.line("--- hop --doctor=short (paste-safe: paths and names withheld) ---")
	} else {
		r.line("--- hop --doctor ---")
	}
	r.line("")
	r.install()
	r.config()
	r.tools()
	r.terminal()
	if o.Short {
		r.shortTail()
	} else {
		r.where()
		r.workspaces()
		r.kinds()
		r.keys()
		r.debug()
	}
	r.line("--- end ---")
	out := r.b.String()
	if home := os.Getenv("HOME"); len(home) > 1 {
		out = strings.ReplaceAll(out, strings.TrimRight(home, "/"), "~")
	}
	io.WriteString(w, out)
	return 0
}

func (r *report) install() {
	r.line("install")
	r.kv("version", r.o.Version)
	m, exe := string(r.o.Install.Method), r.o.Install.Exe
	switch {
	case r.o.Short:
		exe = "(withheld)"
		if r.o.Install.Method == upgrade.Checkout {
			m += " (path withheld)"
		}
	case r.o.Install.Method == upgrade.Checkout:
		m += " at " + r.o.Install.Root
	}
	r.kv("method", m)
	r.kv("binary", exe)
	sh := os.Getenv("HOP_SHELL")
	switch {
	case sh == "":
		r.kv("shell", "none: this call didn't come through `hop init`'s function")
	case os.Getenv("HOP_INIT_HASH") != r.o.InitHash:
		r.kv("shell", sh+", but its integration predates this hop: run 'exec "+sh+"'")
	default:
		r.kv("shell", sh+", integration current")
	}
	r.line("")
}

// fileSettings is the config file's own [settings] table, so a value can be told apart from a default.
func fileSettings(path string) map[string]any {
	var f struct {
		Settings map[string]any `toml:"settings"`
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	if _, err := toml.Decode(string(b), &f); err != nil {
		return nil
	}
	return f.Settings
}

func defaultPaths() map[string]string {
	cfg := os.Getenv("XDG_CONFIG_HOME")
	if cfg == "" {
		cfg = filepath.Join(os.Getenv("HOME"), ".config")
	}
	state := os.Getenv("XDG_STATE_HOME")
	if state == "" {
		state = filepath.Join(os.Getenv("HOME"), ".local", "state")
	}
	return map[string]string{
		"HOP_CONFIG":          filepath.Join(cfg, "hop", "config.toml"),
		"HOP_WORKSPACES_FILE": filepath.Join(cfg, "hop", "workspaces"),
		"HOP_HISTFILE":        filepath.Join(state, "hop", "history"),
		"HOP_DEBUG_LOG":       filepath.Join(state, "hop", "debug.log"),
		"config.zsh":          filepath.Join(cfg, "hop", "config.zsh"),
	}
}

// source is where a setting came from: env beats the file, which beats the default.
func (r *report) source(env, key string) string {
	if v, ok := os.LookupEnv(env); ok && (v != "" || env == "HOP_FZF_HEIGHT") {
		return "env"
	}
	if _, ok := r.file[key]; ok {
		return "config"
	}
	return "default"
}

func readable(p string) string {
	if f, err := os.Open(p); err == nil {
		f.Close()
		return "readable"
	}
	return "MISSING"
}

// path prints a path setting; short mode shows it only while it is still the default, since a customised path is free text.
func (r *report) path(label, val, src string) {
	shown := val
	if r.o.Short && val != r.defaults[label] {
		shown = "(customised, withheld)"
	}
	r.kv(label, fmt.Sprintf("%s (%s, %s)", shown, src, readable(val)))
}

func (r *report) config() {
	r.line("config")
	cp := config.Path()
	src := "default"
	if p := os.Getenv("HOP_CONFIG"); p != "" && !strings.HasSuffix(p, ".zsh") {
		src = "env"
	}
	if _, err := os.Stat(cp); err != nil {
		shown := cp
		if r.o.Short && cp != r.defaults["HOP_CONFIG"] {
			shown = "(customised, withheld)"
		}
		r.kv("HOP_CONFIG", shown+" ("+src+", MISSING, so the zero-config defaults)")
	} else {
		r.path("HOP_CONFIG", cp, src)
	}
	if p := os.Getenv("HOP_CONFIG"); strings.HasSuffix(p, ".zsh") {
		r.kv("", "HOP_CONFIG names a zsh hop config, which this hop never reads as TOML")
	}
	if _, err := os.Stat(cp); err != nil {
		if _, err := os.Stat(r.defaults["config.zsh"]); err == nil {
			r.kv("config.zsh", "found; run 'hop import -o "+r.defaults["HOP_CONFIG"]+"' to use it")
		}
	}
	if r.cfgErr != nil {
		msg := r.cfgErr.Error()
		if r.o.Short {
			msg = "(withheld: it names the file)"
		}
		r.kv("load", "FAILED: "+msg)
		r.line("")
		return
	}
	for _, w := range r.cfg.Warnings {
		if !r.o.Short {
			r.kv("warning", w)
		}
	}
	s := r.cfg.Settings
	r.path("HOP_WORKSPACES_FILE", s.WorkspacesFile, r.source("HOP_WORKSPACES_FILE", "workspaces_file"))
	r.path("HOP_HISTFILE", s.HistFile, r.source("HOP_HISTFILE", "hist_file"))
	r.kv("HOP_HIST_MAX", fmt.Sprintf("%d (%s)", s.HistMax, r.source("HOP_HIST_MAX", "hist_max")))
	switch {
	case len(s.DefaultKinds) == 0:
		r.kv("HOP_DEFAULT_KINDS", "unset, so each kind's own default")
	case r.o.Short:
		r.kv("HOP_DEFAULT_KINDS", fmt.Sprintf("set (%d kinds, %s)", len(s.DefaultKinds), r.source("HOP_DEFAULT_KINDS", "default_kinds")))
	default:
		r.kv("HOP_DEFAULT_KINDS", strings.Join(s.DefaultKinds, " ")+" ("+r.source("HOP_DEFAULT_KINDS", "default_kinds")+")")
	}
	vim := "on"
	if s.Vim != nil && !*s.Vim {
		vim = "off"
	}
	r.kv("HOP_VIM", vim+" ("+r.source("HOP_VIM", "vim")+")")
	r.mode("HOP_ACTION", "action", config.Actions, s.Action, "so Enter cds")
	r.mode("HOP_JUMP", "jump", config.Jumps, s.Jump, "so hop uses auto")
	code := s.Code
	if r.o.Short && !slices.Contains([]string{"code", "cursor", "codium", "code-insiders"}, code) {
		code = "(customised, withheld)"
	}
	r.kv("HOP_CODE", code+" ("+r.source("HOP_CODE", "code")+")")
	ok, why := r.o.CodeUsable(s.Code)
	switch {
	case ok:
		r.kv("VS Code reachable", "yes")
	case !r.o.Short || strings.Contains(why, "SSH") || strings.Contains(why, "DISPLAY"):
		r.kv("VS Code reachable", "no, "+why)
	case strings.HasPrefix(why, "VSCODE_IPC_HOOK_CLI"):
		r.kv("VS Code reachable", "no, VSCODE_IPC_HOOK_CLI names no live socket (withheld)")
	default:
		r.kv("VS Code reachable", "no, the HOP_CODE launcher is not runnable (withheld)")
	}
	clip := s.Clipboard
	if clip == "" {
		clip = "unset, so the first of pbcopy, wl-copy, xclip, xsel, clip.exe"
	} else if r.o.Short {
		clip = "set (withheld)"
	}
	r.kv("HOP_CLIPBOARD", clip)
	h := "80%"
	if s.FzfHeight != nil {
		h = *s.FzfHeight
	}
	if h == "" {
		h = "fullscreen"
	}
	r.kv("HOP_FZF_HEIGHT", h+" ("+r.source("HOP_FZF_HEIGHT", "fzf_height")+")")
	if v := os.Getenv("HOP_HOPRC"); v != "" {
		r.kv("HOP_HOPRC", v+" (env), unsupported: this hop never reads .hoprc")
	} else {
		r.kv("HOP_HOPRC", "unset")
	}
	switch {
	case len(s.Repos) == 0:
		r.kv("HOP_REPOS", "unset, derived from workspaces")
	case r.o.Short:
		r.kv("HOP_REPOS", fmt.Sprintf("set (%d repos, withheld)", len(s.Repos)))
	default:
		r.kv("HOP_REPOS", strings.Join(s.Repos, ":")+" ("+r.source("HOP_REPOS", "repos")+")")
	}
	if debuglog.Enabled() {
		r.kv("HOP_DEBUG", os.Getenv("HOP_DEBUG"))
	} else {
		r.kv("HOP_DEBUG", "unset")
	}
	src = "default"
	if os.Getenv("HOP_DEBUG_LOG") != "" {
		src = "env"
	}
	r.path("HOP_DEBUG_LOG", debuglog.Path(), src)
	r.line("")
}

// mode shows an env value that isn't a mode as given, with what hop does instead, since its warning only prints inside a hop call.
func (r *report) mode(env, key string, valid []string, eff, instead string) {
	src := r.source(env, key)
	v := os.Getenv(env)
	if v == "" || slices.Contains(valid, v) {
		r.kv(env, eff+" ("+src+")")
		return
	}
	if r.o.Short {
		v = "(not a mode, withheld)"
	}
	r.kv(env, v+" ("+src+"), "+instead)
}

// onPath is the code check reduced to "is the launcher runnable", for a caller that doesn't pass act's.
func onPath(code string) (bool, string) {
	argv := strings.Fields(code)
	if len(argv) == 0 {
		argv = []string{"code"}
	}
	if strings.Contains(argv[0], "/") {
		if st, err := os.Stat(argv[0]); err != nil || st.IsDir() || st.Mode().Perm()&0o111 == 0 {
			return false, argv[0] + " is not runnable"
		}
		return true, ""
	}
	if _, err := exec.LookPath(argv[0]); err != nil {
		return false, argv[0] + " is not installed"
	}
	return true, ""
}

// toolTimeout bounds each version probe; a test on a loaded machine raises it, since a slow stub would read as "present".
var toolTimeout = 3 * time.Second

// toolLine is one external command's first version line; stdin is /dev/null and it gets toolTimeout, so a wrapper that reads stdin can't hang the report.
func toolLine(name string) string {
	if _, err := exec.LookPath(name); err != nil {
		return fmt.Sprintf("  %-8s %s", name, "NOT INSTALLED")
	}
	ctx, cancel := context.WithTimeout(context.Background(), toolTimeout)
	defer cancel()
	c := exec.CommandContext(ctx, name, "--version")
	c.WaitDelay = time.Second
	out, _ := c.CombinedOutput()
	v, _, _ := strings.Cut(strings.TrimSpace(string(out)), "\n")
	if v == "" {
		v = "present"
	}
	return fmt.Sprintf("  %-8s %s", name, v)
}

func (r *report) tools() {
	r.line("tools")
	names := []string{"fzf", "git", "gh", "bat", "code", "zsh"}
	lines := make([]string, len(names))
	var wg sync.WaitGroup
	for i, n := range names {
		wg.Go(func() { lines[i] = toolLine(n) })
	}
	wg.Wait()
	for _, l := range lines {
		r.line("%s", l)
	}
	r.line("")
}

func (r *report) terminal() {
	r.line("terminal")
	t := os.Getenv("TERM")
	if t == "" {
		t = "unset"
	}
	r.kv("TERM", t)
	cols := os.Getenv("COLUMNS")
	if cols == "" {
		for _, f := range []*os.File{os.Stdout, os.Stderr} {
			if w, _, err := term.GetSize(int(f.Fd())); err == nil {
				cols = strconv.Itoa(w)
				break
			}
		}
	}
	if cols == "" {
		cols = "unknown"
	}
	r.kv("COLUMNS", cols)
	if sh := os.Getenv("HOP_SHELL"); sh != "" {
		r.kv("completions", "loaded by hop init "+sh)
	} else {
		r.kv("completions", "unknown: add eval \"$(hop init zsh)\" (or bash, or `hop init fish | source`) to your shell rc")
	}
	r.line("")
}

func gitToplevel() string {
	out, err := exec.Command("git", "rev-parse", "--show-toplevel").Output()
	if err != nil {
		return ""
	}
	return strings.TrimRight(string(out), "\n")
}

func pwd() string {
	wd, _ := os.Getwd()
	if p := os.Getenv("PWD"); filepath.IsAbs(p) {
		a, errA := os.Stat(p)
		b, errB := os.Stat(".")
		if errA == nil && errB == nil && os.SameFile(a, b) {
			return p
		}
	}
	return wd
}

func (r *report) wss() []workspace.Workspace {
	if r.cfg == nil {
		return nil
	}
	return workspace.Parse(r.cfg.Settings.Workspaces, r.cfg.Settings.WorkspacesFile)
}

func (r *report) where() {
	r.line("where you are")
	wd := pwd()
	r.kv("PWD", wd)
	top := gitToplevel()
	if top == "" {
		top = "NONE, so hop opens the workspace or repo picker"
	}
	r.kv("git toplevel", top)
	if w, ok := workspace.For(wd, r.wss()); ok {
		r.kv("workspace for PWD", w)
	} else {
		r.kv("workspace for PWD", "none")
	}
	r.line("")
}

func (r *report) workspaces() {
	r.line("workspaces")
	wss := r.wss()
	if len(wss) == 0 {
		r.line("  none configured")
	}
	for _, w := range wss {
		r.kv(w.Name, w.Path)
	}
	r.line("")
}

// loaded is the recipes the registry holds kinds from, in first-seen order.
func (r *report) loaded() []string {
	var out []string
	for _, k := range r.cfg.Kinds {
		for _, p := range []string{"recipe:", "preset:"} {
			if n, ok := strings.CutPrefix(k.Origin, p); ok && !slices.Contains(out, n) {
				out = append(out, n)
			}
		}
	}
	return out
}

func (r *report) recipes() {
	r.line("  recipes available: %s", strings.Join(r.o.Recipes, " "))
	l := r.loaded()
	if len(l) == 0 {
		r.line("  recipes loaded:    none")
	} else {
		r.line("  recipes loaded:    %s", strings.Join(l, " "))
	}
}

func (r *report) kinds() {
	r.line("kinds, with row counts here")
	if r.cfg == nil {
		r.line("  (the config failed to load, so there are no kinds)")
		r.line("")
		return
	}
	root := gitToplevel()
	def := r.cfg.DefaultKinds()
	var e *kinds.Engine
	if root != "" {
		e = kinds.New(root, io.Discard)
	}
	for _, k := range r.cfg.Kinds {
		mark := " "
		if slices.Contains(def, k.Name) {
			mark = "*"
		}
		n := "-"
		if e != nil {
			n = strconv.Itoa(len(e.Emit(k)))
		}
		r.line("  %s %-11s %7s  %-8s %s", mark, k.Name, n, k.Shape, k.Desc)
	}
	r.line("  (* is in the default set)")
	if root == "" {
		r.line("  (not in a repo, so nothing to count)")
	}
	r.recipes()
	r.line("")
}

func (r *report) keys() {
	r.line("keys people mix up")
	r.line("  l / ctrl-l    go INTO the thing under the cursor (workspace -> repos -> targets)")
	r.line("  h / ctrl-h    come back OUT a level")
	r.line("  b / alt-B     open on your git host, NOT navigation")
	r.line("  ^G / alt-g    launch hop from the shell prompt")
	r.line("")
}

func (r *report) debug() {
	lines := debuglog.Tail(15)
	if lines == nil {
		r.line("debug log")
		r.line("  none yet. Run: HOP_DEBUG=1 hop   then re-run hop --doctor")
		return
	}
	r.line("last 15 debug lines (%s)", debuglog.Path())
	for _, l := range lines {
		r.line("  %s", l)
	}
}

func (r *report) shortTail() {
	r.line("workspaces")
	r.kv("configured", strconv.Itoa(len(r.wss())))
	r.line("")
	r.line("kinds")
	if r.cfg == nil {
		r.line("  (the config failed to load, so there are no kinds)")
	} else {
		r.kv("registered", strconv.Itoa(len(r.cfg.Kinds)))
		def := r.cfg.DefaultKinds()
		nd := 0
		by := map[string]int{}
		for _, k := range r.cfg.Kinds {
			if slices.Contains(def, k.Name) {
				nd++
			}
			by[k.Shape]++
		}
		r.kv("in default set", strconv.Itoa(nd))
		r.line("  by shape:")
		for _, s := range []string{"dirs", "files", "marker", "builtin", "exec"} {
			r.line("    %-8s %d", s, by[s])
		}
		r.recipes()
	}
	r.line("")
	r.line("PWD, the git toplevel, workspace names and kind names are withheld deliberately.")
	r.line("This is not a bug: run plain --doctor locally if you need any of those.")
}
