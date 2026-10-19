package act

import (
	"bytes"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type rig struct {
	t                *testing.T
	a                *Actor
	out, err         *bytes.Buffer
	log, cmdfile     string
	execd            []string
	root, unit, file string
}

// newRig stubs code (logging its argv, exiting $CODE_RC), pbcopy (keeping its stdin), and the editor exec.
func newRig(t *testing.T) *rig {
	d := t.TempDir()
	bin := filepath.Join(d, "bin")
	os.Mkdir(bin, 0o755)
	r := &rig{t: t, out: &bytes.Buffer{}, err: &bytes.Buffer{}, log: filepath.Join(d, "log"), cmdfile: filepath.Join(d, "cmdfile")}
	os.WriteFile(filepath.Join(bin, "code"), []byte("#!/bin/sh\necho \"code $*\" >>\""+r.log+"\"\nexit ${CODE_RC:-0}\n"), 0o755)
	os.WriteFile(filepath.Join(bin, "pbcopy"), []byte("#!/bin/sh\ncat >\""+r.log+".clip\"\n"), 0o755)
	t.Setenv("PATH", bin+":/usr/bin:/bin")
	t.Setenv("DISPLAY", ":0")
	t.Setenv("HOP_CMDFILE", r.cmdfile)
	t.Setenv("VISUAL", "")
	t.Setenv("EDITOR", "vi -n")
	r.root = filepath.Join(d, "repo")
	r.unit = filepath.Join(r.root, "svc", "web")
	os.MkdirAll(r.unit, 0o755)
	os.WriteFile(filepath.Join(r.unit, "main.tf"), []byte("x"), 0o644)
	os.WriteFile(filepath.Join(r.unit, "README.md"), []byte("x"), 0o644)
	r.file = filepath.Join(r.unit, "values.yaml")
	os.WriteFile(r.file, []byte("x"), 0o644)
	r.a = &Actor{Mode: "cd", Code: "code", Hist: filepath.Join(d, "hist"), HistMax: 300, Stdout: r.out, Stderr: r.err,
		Exec: func(argv []string) int { r.execd = argv; return 0 }, Terminal: func() bool { return true }}
	return r
}

func (r *rig) reset() {
	os.Remove(r.cmdfile)
	os.Remove(r.log)
	os.Remove(r.a.Hist)
	r.out.Reset()
	r.err.Reset()
	r.execd = nil
}

func (r *rig) codeLog() string {
	b, _ := os.ReadFile(r.log)
	return strings.TrimSpace(string(b))
}

func (r *rig) cd() string {
	b, _ := os.ReadFile(r.cmdfile)
	return string(b)
}

func (r *rig) hist() string {
	b, _ := os.ReadFile(r.a.Hist)
	return strings.TrimSpace(string(b))
}

func TestEnterModes(t *testing.T) {
	r := newRig(t)
	main := filepath.Join(r.unit, "main.tf")
	for _, c := range []struct {
		mode, preview, rel string
		folder             bool
		code, cd           string
		rc                 int
	}{
		{"cd", main, "svc/web/", false, "", r.unit, 0},
		{"open", main, "svc/web/", false, "code -n " + r.unit, "", 0},
		{"open", r.file, "svc/web/values.yaml", false, "code -r " + r.file, "", 0},
		{"reveal", main, "svc/web/", false, "code -r " + main, "", 0},
		{"reveal", r.unit, "svc/web/", false, "code -r " + filepath.Join(r.unit, "README.md"), "", 0},
		{"cd+open", main, "svc/web/", false, "code -n " + r.unit, r.unit, 0},
		{"cd+reveal", r.unit, "svc/web/", false, "code -r " + filepath.Join(r.unit, "README.md"), r.unit, 0},
		{"reveal", r.unit, "", true, "code -n " + r.unit, "", 0},
	} {
		r.reset()
		r.a.Mode, r.a.Folder = c.mode, c.folder
		rc := r.a.Dispatch("", r.unit, c.preview, c.rel)
		if rc != c.rc || r.codeLog() != c.code || r.cd() != c.cd {
			t.Errorf("%s %s folder=%v: rc %d code %q cd %q, want %d %q %q (%s)", c.mode, c.rel, c.folder, rc, r.codeLog(), r.cd(), c.rc, c.code, c.cd, r.err)
		}
		if r.hist() != r.unit {
			t.Errorf("%s: every Enter remembers the dir, history %q", c.mode, r.hist())
		}
	}
}

func TestCdKeepsCdWhenCodeFails(t *testing.T) {
	r := newRig(t)
	t.Setenv("CODE_RC", "3")
	r.a.Mode = "cd+open"
	if rc := r.a.Dispatch("", r.unit, r.unit, "svc/web/"); rc != 3 || r.cd() != r.unit {
		t.Errorf("a failed code keeps the cd and returns its status: rc %d cd %q", rc, r.cd())
	}
}

func TestNoCode(t *testing.T) {
	r := newRig(t)
	r.a.Code = "nocode-here"
	r.a.Mode = "cd+open"
	if rc := r.a.Dispatch("", r.unit, r.unit, "svc/web/"); rc != 0 || r.cd() != r.unit || !strings.Contains(r.err.String(), "nocode-here is not installed, cannot open VS Code, so this was a cd only") {
		t.Errorf("cd+open without code is a cd: rc %d %q", rc, r.err)
	}
	r.reset()
	r.a.Mode = "open"
	if rc := r.a.Dispatch("", r.unit, r.file, "svc/web/values.yaml"); rc != 0 || strings.Join(r.execd, " ") != "vi -n "+r.file {
		t.Errorf("open without code falls back to the editor: rc %d exec %q", rc, r.execd)
	}
	r.reset()
	r.a.Terminal = func() bool { return false }
	if rc := r.a.Dispatch("ctrl-o", r.unit, r.file, ""); rc != 1 || r.execd != nil || !strings.Contains(r.err.String(), "no terminal for an editor; target: "+r.file) {
		t.Errorf("no terminal, no editor: rc %d %q", rc, r.err)
	}
	r.reset()
	r.a.Mode = "reveal"
	if rc := r.a.Dispatch("", r.unit, r.unit, "svc/web/"); rc != 1 || !strings.Contains(r.err.String(), "only VS Code can reveal svc/web") {
		t.Errorf("reveal without code: rc %d %q", rc, r.err)
	}
}

func TestKeys(t *testing.T) {
	r := newRig(t)
	main := filepath.Join(r.unit, "main.tf")
	for _, c := range []struct {
		key, preview, code, cd, exec string
		remember                     bool
	}{
		{"ctrl-o", main, "code -r " + main, "", "", true},
		{"ctrl-o", r.unit, "code -n " + r.unit, "", "", true},
		{"ctrl-t", main, "code -n " + r.unit, "", "", true},
		{"alt-o", main, "", "", "vi -n " + main, false},
		{"alt-enter", main, "", r.unit, "", true},
	} {
		r.reset()
		r.a.Mode = "open"
		rc := r.a.Dispatch(c.key, r.unit, c.preview, "svc/web/")
		if rc != 0 || r.codeLog() != c.code || r.cd() != c.cd || strings.Join(r.execd, " ") != c.exec || (r.hist() != "") != c.remember {
			t.Errorf("%s: rc %d code %q cd %q exec %q hist %q (%s)", c.key, rc, r.codeLog(), r.cd(), r.execd, r.hist(), r.err)
		}
	}
	for _, c := range []struct{ key, want string }{{"ctrl-y", r.unit}, {"alt-y", main}} {
		r.reset()
		rc := r.a.Dispatch(c.key, r.unit, main, "svc/web/")
		clip, _ := os.ReadFile(r.log + ".clip")
		if rc != 0 || string(clip) != c.want || r.out.String() != "hop: copied "+c.want+"\n" || r.hist() != "" {
			t.Errorf("%s: rc %d clip %q out %q hist %q", c.key, rc, clip, r.out, r.hist())
		}
	}
	r.reset()
	r.a.Clipboard = "nope-clip"
	if rc := r.a.Dispatch("ctrl-y", r.unit, main, ""); rc == 0 || !strings.Contains(r.err.String(), "nope-clip failed to copy") {
		t.Errorf("HOP_CLIPBOARD overrides the probe: rc %d %q", rc, r.err)
	}
	r.reset()
	if rc := r.a.Dispatch("", "helm", "/r", ""); rc != 1 || !strings.Contains(r.err.String(), "not a target directory: helm") {
		t.Errorf("a kind-menu row is never acted on: rc %d %q", rc, r.err)
	}
	if rc := r.a.Dispatch("ctrl-q", r.unit, main, ""); rc != 1 || !strings.Contains(r.err.String(), "unhandled key: ctrl-q") {
		t.Errorf("unknown key: rc %d", rc)
	}
}

// TestCodeUsable is _hop_code_usable's cases: the launcher, a live IPC socket, SSH, and a Linux display or WSL.
func TestCodeUsable(t *testing.T) {
	r := newRig(t)
	defer func(g string) { goos = g }(goos)
	goos = "darwin"
	for _, k := range []string{"VSCODE_IPC_HOOK_CLI", "SSH_CONNECTION", "SSH_TTY", "DISPLAY", "WAYLAND_DISPLAY", "WSL_DISTRO_NAME", "WSL_INTEROP", "HOP_CODE"} {
		t.Setenv(k, "")
	}
	usable := func() (bool, string) { return CodeUsable(os.Getenv("HOP_CODE")) }
	if ok, why := usable(); !ok {
		t.Errorf("the stub on PATH is usable: %s", why)
	}
	t.Setenv("HOP_CODE", "nocode-here -x")
	if ok, why := usable(); ok || why != "nocode-here is not installed, cannot open VS Code" {
		t.Errorf("a launcher not installed is unusable with need's reason: %q", why)
	}
	t.Setenv("HOP_CODE", "/no/such/code")
	if ok, why := usable(); ok || why != "/no/such/code does not exist, cannot open VS Code" {
		t.Errorf("a launcher path that doesn't exist: %q", why)
	}
	t.Setenv("HOP_CODE", "")
	sock := filepath.Join(t.TempDir(), "s")
	t.Setenv("VSCODE_IPC_HOOK_CLI", sock)
	if ok, why := usable(); ok || why != "VSCODE_IPC_HOOK_CLI names no live VS Code socket: "+sock {
		t.Errorf("a stale IPC hook is unusable: %q", why)
	}
	l, err := net.Listen("unix", sock)
	if err != nil {
		t.Skip("no unix sockets here:", err)
	}
	defer l.Close()
	goos = "linux"
	t.Setenv("SSH_CONNECTION", "1 2 3 4")
	if ok, why := usable(); !ok {
		t.Errorf("a live socket is usable even over SSH on Linux with no DISPLAY: %s", why)
	}
	t.Setenv("VSCODE_IPC_HOOK_CLI", "")
	if ok, why := usable(); ok || why != "this is an SSH session with no VS Code window attached" {
		t.Errorf("SSH_CONNECTION with no hook: %q", why)
	}
	t.Setenv("SSH_CONNECTION", "")
	t.Setenv("SSH_TTY", "/dev/ttys001")
	if ok, _ := usable(); ok {
		t.Error("SSH_TTY with no hook is unusable too")
	}
	t.Setenv("SSH_TTY", "")
	if ok, why := usable(); ok || why != "there is no DISPLAY or WAYLAND_DISPLAY for VS Code to open on" {
		t.Errorf("Linux with no display: %q", why)
	}
	for _, k := range []string{"DISPLAY", "WAYLAND_DISPLAY", "WSL_DISTRO_NAME", "WSL_INTEROP"} {
		t.Setenv(k, "x")
		if ok, why := usable(); !ok {
			t.Errorf("%s alone is enough: %s", k, why)
		}
		t.Setenv(k, "")
	}
	r.a.Mode = "open"
	if rc := r.a.Dispatch("ctrl-o", r.unit, r.file, ""); rc != 0 || r.codeLog() != "" || strings.Join(r.execd, " ") != "vi -n "+r.file ||
		!strings.Contains(r.err.String(), "hop: there is no DISPLAY or WAYLAND_DISPLAY for VS Code to open on; using the terminal editor instead") {
		t.Errorf("ctrl-o with VS Code unreachable says why and falls back to the editor: rc %d exec %q %q", rc, r.execd, r.err)
	}
}

func TestBrowseNamesTheDrill(t *testing.T) {
	r := newRig(t)
	os.WriteFile(filepath.Join(filepath.Dir(r.log), "bin", "gh"), []byte("#!/bin/sh\nexit 0\n"), 0o755)
	real, _ := filepath.EvalSymlinks(r.unit)
	if rc := r.a.Dispatch("ctrl-g", r.unit, r.unit, ""); rc != 1 ||
		!strings.Contains(r.err.String(), "hop: not in a git repository: "+real+"\nhop: to go INTO a repo from a workspace, press l (NORMAL) or ctrl-l (SEARCH)\n") {
		t.Errorf("browse outside a repo names the drill key: rc %d %q", rc, r.err)
	}
}

// TestClipboardProbe is suite_clipboard: the probe order, HOP_CLIPBOARD's word-split override, and the text on stdin, never argv.
func TestClipboardProbe(t *testing.T) {
	r := newRig(t)
	bin := t.TempDir()
	log := filepath.Join(bin, "calls")
	t.Setenv("PATH", bin)
	tools := []string{"pbcopy", "wl-copy", "xclip", "xsel", "clip.exe"}
	want := []string{"pbcopy", "wl-copy", "xclip -selection clipboard", "xsel --clipboard --input", "clip.exe"}
	for _, n := range tools {
		os.WriteFile(filepath.Join(bin, n), []byte("#!/bin/sh\nprintf '%s %s|' \""+n+"\" \"$*\" >>\""+log+"\"\n/bin/cat >>\""+log+"\"\n"), 0o755)
	}
	text := "/a/b c/it's here.hcl"
	for i := range tools {
		os.Remove(log)
		if rc := r.a.Dispatch("alt-y", r.unit, text, ""); rc != 0 {
			t.Fatalf("copy with %s: rc %d %s", tools[i], rc, r.err)
		}
		b, _ := os.ReadFile(log)
		args := strings.TrimPrefix(strings.TrimPrefix(want[i], tools[i]), " ")
		if string(b) != tools[i]+" "+args+"|"+text {
			t.Errorf("%s is chosen once the tools before it are gone, with the text on stdin: %q", want[i], b)
		}
		os.Remove(filepath.Join(bin, tools[i]))
	}
	os.Remove(log)
	r.err.Reset()
	if rc := r.a.Dispatch("ctrl-y", r.unit, text, ""); rc != 1 || r.err.String() != "hop: no clipboard tool found, install pbcopy, wl-copy, xclip, xsel, or clip.exe (WSL)\n" {
		t.Errorf("no tool: one stderr line naming the install options: rc %d %q", rc, r.err)
	}
	os.WriteFile(filepath.Join(bin, "xclip"), []byte("#!/bin/sh\nprintf '%s|' \"$*\" >>\""+log+"\"\n/bin/cat >>\""+log+"\"\n"), 0o755)
	r.a.Clipboard = "xclip -sel c"
	if rc := r.a.Dispatch("ctrl-y", r.unit, text, ""); rc != 0 {
		t.Fatalf("HOP_CLIPBOARD: rc %d", rc)
	}
	if b, _ := os.ReadFile(log); string(b) != "-sel c|"+r.unit {
		t.Errorf("HOP_CLIPBOARD word-splits, so its arguments reach the tool: %q", b)
	}
}

// TestNeed is suite_editor_path's _hop_need: a bare name on PATH, a path with a slash checked where it is, with hop's wording.
func TestNeed(t *testing.T) {
	d := t.TempDir()
	exe, plain := filepath.Join(d, "ed"), filepath.Join(d, "plain")
	os.WriteFile(exe, []byte("#!/bin/sh\n"), 0o755)
	os.WriteFile(plain, []byte("x"), 0o644)
	t.Setenv("PATH", d)
	for _, c := range []struct{ cmd, want string }{
		{"ed", ""},
		{"nope", "nope is not installed, cannot edit a file"},
		{exe, ""},
		{filepath.Join(d, "missing"), filepath.Join(d, "missing") + " does not exist, cannot edit a file"},
		{plain, plain + " is not executable, cannot edit a file"},
		{d, d + " is not executable, cannot edit a file"},
	} {
		err := need(c.cmd, "edit a file")
		if got := fmt.Sprint(err); (c.want == "" && err != nil) || (c.want != "" && got != c.want) {
			t.Errorf("need(%s) = %v, want %q", c.cmd, err, c.want)
		}
	}
	t.Chdir(d)
	if err := need("./ed", "edit a file"); err != nil {
		t.Errorf("a relative path with a slash is checked against the cwd: %v", err)
	}
	r := newRig(t)
	t.Setenv("EDITOR", filepath.Join(d, "missing"))
	if rc := r.a.Dispatch("alt-o", r.unit, r.file, ""); rc != 1 || r.execd != nil || !strings.Contains(r.err.String(), "does not exist, cannot edit a file") {
		t.Errorf("an absolute $EDITOR that doesn't exist fails and is never run: rc %d %q", rc, r.err)
	}
}
