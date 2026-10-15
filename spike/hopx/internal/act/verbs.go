package act

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/etknorr/hop/spike/hopx/internal/collate"
	"github.com/etknorr/hop/spike/hopx/internal/mru"
	"github.com/etknorr/hop/spike/hopx/internal/tty"
)

// Actor is _hop_dispatch and the _hop_act_* verbs, with the settings they read by dynamic scope in hop.
// - Mode is what Enter does; Folder marks workspace and repo rows, where open and reveal both mean `code -n` on the folder.
// - Exec replaces the process with the terminal editor and Terminal reports a reachable tty; tests stub both.
type Actor struct {
	Mode           string
	Folder         bool
	Code           string
	Clipboard      string
	Hist           string
	HistMax        int
	Stdout, Stderr io.Writer
	Exec           func(argv []string) int
	Terminal       func() bool
}

func (a *Actor) remember(dir string) { mru.Remember(a.Hist, dir, a.HistMax) }

func (a *Actor) cd(dir string) int { return CD(dir, a.Stdout, a.Stderr, a.Hist, a.HistMax) }

// Dispatch is _hop_dispatch: an empty key is Enter, alt-enter always cds, and every other verb leaves the shell where it was.
// - ctrl-o and ctrl-t remember the dir, as a cd does; copy and browse don't.
func (a *Actor) Dispatch(key, dir, preview, rel string) int {
	if preview == "" {
		preview = dir
	}
	if !filepath.IsAbs(dir) {
		fmt.Fprintln(a.Stderr, "hop: not a target directory:", dir)
		return 1
	}
	switch key {
	case "":
		return a.Enter(dir, preview, rel)
	case "alt-enter":
		return a.cd(dir)
	case "ctrl-o":
		return a.andRemember(dir, func() int { return a.open(preview) })
	case "ctrl-t":
		return a.andRemember(dir, func() int { return a.folder(dir) })
	case "ctrl-y":
		return a.copy(dir)
	case "ctrl-g":
		return a.browse(dir)
	case "alt-o":
		return a.edit(preview)
	case "alt-y":
		return a.copy(preview)
	}
	fmt.Fprintln(a.Stderr, "hop: unhandled key:", key)
	return 1
}

// andRemember remembers before the verb runs, because the verb may exec an editor and never come back.
func (a *Actor) andRemember(dir string, verb func() int) int {
	if !isDir(dir) {
		return verb()
	}
	a.remember(dir)
	return verb()
}

func isDir(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.IsDir()
}

func isFile(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.Mode().IsRegular()
}

func exists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

// need is _hop_need: a bare name is looked up on PATH, a name with a slash is checked where it is.
func need(cmd, what string) error {
	if strings.Contains(cmd, "/") {
		st, err := os.Stat(cmd)
		switch {
		case err != nil:
			return fmt.Errorf("%s does not exist, cannot %s", cmd, what)
		case st.IsDir() || st.Mode().Perm()&0o111 == 0:
			return fmt.Errorf("%s is not executable, cannot %s", cmd, what)
		}
		return nil
	}
	if _, err := exec.LookPath(cmd); err != nil {
		return fmt.Errorf("%s is not installed, cannot %s", cmd, what)
	}
	return nil
}

func (a *Actor) codeArgv() []string {
	argv := strings.Fields(a.Code)
	if len(argv) == 0 {
		argv = []string{"code"}
	}
	return argv
}

// codeUsable is _hop_code_usable reduced to "on PATH or not", as the spec allows.
func (a *Actor) codeUsable() error { return need(a.codeArgv()[0], "open VS Code") }

// code runs the launcher as a child; it returns at once, so there is nothing to exec into.
func (a *Actor) code(args ...string) int {
	argv := append(a.codeArgv(), args...)
	return a.run(argv, nil)
}

func (a *Actor) run(argv []string, stdin io.Reader) int {
	c := exec.Command(argv[0], argv[1:]...)
	c.Stdin, c.Stdout, c.Stderr = stdin, a.Stdout, a.Stderr
	if stdin == nil {
		c.Stdin = os.Stdin
	}
	if err := c.Run(); err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			return ee.ExitCode()
		}
		fmt.Fprintln(a.Stderr, "hop:", err)
		return 127
	}
	return 0
}

// codeFallback is _hop_code_fallback: the terminal editor instead of VS Code, after saying why.
func (a *Actor) codeFallback(reason error, target string) int {
	fmt.Fprintf(a.Stderr, "hop: %v; using the terminal editor instead\n", reason)
	if !a.Terminal() {
		fmt.Fprintln(a.Stderr, "hop: no terminal for an editor; target:", target)
		return 1
	}
	return a.edit(target)
}

// open is ctrl-o, _hop_act_open: `code -r` on a file, `code -n` on a dir, since `code -r <dir>` reloads the focused window.
func (a *Actor) open(target string) int {
	if !exists(target) {
		fmt.Fprintln(a.Stderr, "hop: nothing to open at:", target)
		return 1
	}
	if err := a.codeUsable(); err != nil {
		return a.codeFallback(err, target)
	}
	if isDir(target) {
		return a.code("-n", target)
	}
	return a.code("-r", target)
}

// folder is ctrl-t, _hop_act_folder: the dir in a window of its own.
func (a *Actor) folder(dir string) int {
	if !isDir(dir) {
		fmt.Fprintln(a.Stderr, "hop: not a directory:", dir)
		return 1
	}
	if err := a.codeUsable(); err != nil {
		return a.codeFallback(err, dir)
	}
	return a.code("-n", dir)
}

// edit is alt-o, _hop_act_edit: $VISUAL, else $EDITOR, else vi, word-split as hop's ${=REPLY} is, then exec'd.
func (a *Actor) edit(target string) int {
	if !exists(target) {
		fmt.Fprintln(a.Stderr, "hop: nothing to open at:", target)
		return 1
	}
	e := os.Getenv("VISUAL")
	if e == "" {
		e = os.Getenv("EDITOR")
	}
	argv := strings.Fields(e)
	if len(argv) == 0 {
		argv = []string{"vi"}
	}
	if err := need(argv[0], "edit a file"); err != nil {
		fmt.Fprintln(a.Stderr, "hop:", err)
		return 1
	}
	return a.Exec(append(argv, target))
}

// clipboard is _hop_act_copy's probe: HOP_CLIPBOARD overrides, then pbcopy, wl-copy, xclip, xsel, clip.exe.
func (a *Actor) clipboard() []string {
	if f := strings.Fields(a.Clipboard); len(f) > 0 {
		return f
	}
	for _, c := range [][]string{{"pbcopy"}, {"wl-copy"}, {"xclip", "-selection", "clipboard"}, {"xsel", "--clipboard", "--input"}, {"clip.exe"}} {
		if _, err := exec.LookPath(c[0]); err == nil {
			return c
		}
	}
	return nil
}

func (a *Actor) copy(what string) int {
	cmd := a.clipboard()
	if cmd == nil {
		fmt.Fprintln(a.Stderr, "hop: no clipboard tool found, install pbcopy, wl-copy, xclip, xsel, or clip.exe (WSL)")
		return 1
	}
	if rc := a.run(cmd, strings.NewReader(what)); rc != 0 {
		fmt.Fprintf(a.Stderr, "hop: %s failed to copy %s\n", cmd[0], what)
		return rc
	}
	fmt.Fprintln(a.Stdout, "hop: copied", what)
	return 0
}

// browse is alt-B, _hop_act_browse: gh resolves the remote from the cwd, so it runs in the repo with a relative path.
func (a *Actor) browse(dir string) int {
	if err := need("gh", "browse on GitHub"); err != nil {
		fmt.Fprintln(a.Stderr, "hop:", err)
		return 1
	}
	if r, err := filepath.EvalSymlinks(dir); err == nil {
		dir = r
	}
	out, err := exec.Command("git", "-C", dir, "rev-parse", "--show-toplevel").Output()
	root := strings.TrimRight(string(out), "\n")
	if r, e := filepath.EvalSymlinks(root); e == nil {
		root = r
	}
	if err != nil || root == "" {
		fmt.Fprintln(a.Stderr, "hop: not in a git repository:", dir)
		return 1
	}
	argv := []string{"gh", "browse"}
	switch {
	case dir == root:
	case strings.HasPrefix(dir, root+"/"):
		argv = append(argv, "--", dir[len(root)+1:])
	default:
		fmt.Fprintf(a.Stderr, "hop: %s is not inside %s, refusing to guess a path\n", dir, root)
		return 1
	}
	c := exec.Command(argv[0], argv[1:]...)
	c.Dir, c.Stdin, c.Stdout, c.Stderr = root, os.Stdin, a.Stdout, a.Stderr
	if err := c.Run(); err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			return ee.ExitCode()
		}
		return 1
	}
	return 0
}

// revealFile is _hop_reveal_file: a top-level README first, then the first regular file by name.
func revealFile(dir string) string {
	ents, _ := os.ReadDir(dir)
	var readmes, files []string
	for _, e := range ents {
		p := filepath.Join(dir, e.Name())
		if !isFile(p) {
			continue
		}
		files = append(files, e.Name())
		if strings.HasPrefix(strings.ToLower(e.Name()), "readme") {
			readmes = append(readmes, e.Name())
		}
	}
	for _, set := range [][]string{readmes, files} {
		if len(set) > 0 {
			collate.Sort(set)
			return filepath.Join(dir, set[0])
		}
	}
	return ""
}

// reveal is _hop_act_reveal: VS Code can't reveal a folder from the shell, so a file inside it stands in.
// - After a cd, an empty top isn't a failure, since the cd was the point.
func (a *Actor) reveal(dir, preview, rel string, after bool) int {
	if isFile(preview) {
		return a.code("-r", preview)
	}
	if f := revealFile(dir); f != "" {
		return a.code("-r", f)
	}
	fmt.Fprintf(a.Stderr, "hop: nothing to reveal at the top of %s; use -o to open it as a folder\n", rel)
	if after {
		return 0
	}
	return 1
}

// Enter is _hop_act_enter: Enter, a jump, and headless dispatch, applying the mode.
// - A rel without a trailing / is a file target, whose dir is only its parent.
// - open on a dir is always `code -n`; `code -r` only ever gets a file.
// - cd runs first, so a code call that fails afterwards keeps the cd and returns its status.
func (a *Actor) Enter(dir, preview, rel string) int {
	mode := a.Mode
	if mode == "" {
		mode = "cd"
	}
	cd := strings.HasPrefix(mode, "cd")
	verb := strings.TrimPrefix(strings.TrimPrefix(mode, "cd"), "+")
	file := !a.Folder && rel != "" && !strings.HasSuffix(rel, "/")

	switch {
	case cd:
		if rc := a.cd(dir); rc != 0 || verb == "" {
			return rc
		}
	case isDir(dir):
		a.remember(dir)
	default:
		fmt.Fprintln(a.Stderr, "hop: not a directory:", dir)
		return 1
	}
	if file && !exists(preview) {
		fmt.Fprintln(a.Stderr, "hop: nothing to open at:", preview)
		return 1
	}
	shown := rel
	if shown == "" {
		shown = dir
	}
	if err := a.codeUsable(); err != nil {
		switch {
		case cd:
			fmt.Fprintf(a.Stderr, "hop: %v, so this was a cd only\n", err)
			return 0
		case file:
			return a.codeFallback(err, preview)
		case verb == "open" || a.Folder:
			return a.codeFallback(err, dir)
		case isFile(preview):
			fmt.Fprintf(a.Stderr, "hop: %v, and only VS Code can reveal %s in %s; -o opens the directory itself in the terminal editor\n", err, filepath.Base(preview), shown)
			return 1
		}
		fmt.Fprintf(a.Stderr, "hop: %v, and only VS Code can reveal %s; use -o to open it in the terminal editor\n", err, shown)
		return 1
	}
	switch {
	case file:
		return a.code("-r", preview)
	case verb == "open" || a.Folder:
		return a.code("-n", dir)
	}
	return a.reveal(dir, preview, shown, cd)
}

// DefaultTerminal is tty.Available, which is _hop_tty_ok.
func DefaultTerminal() bool { return tty.Available() }
