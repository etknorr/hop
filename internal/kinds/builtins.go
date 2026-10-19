package kinds

import (
	"bufio"
	"fmt"
	"os"
	"path"
	"slices"
	"strings"

	"github.com/etknorr/hop/internal/config"
	"github.com/etknorr/hop/internal/rows"
	"github.com/etknorr/hop/internal/workspace"
)

func firstFile(dir string, cands ...string) string {
	for _, c := range cands {
		if p := dir + "/" + c; nonEmptyFile(p) {
			return p
		}
	}
	return ""
}

// previewDoc is _hop_preview_doc: README.md, README, CLAUDE.md, else the dir.
func previewDoc(dir string) string {
	if p := firstFile(dir, "README.md", "README", "CLAUDE.md"); p != "" {
		return p
	}
	return dir
}

var dirSkip = []string{"target", "tmp"}

// builtinDir is _hop_provider_dir: the root plus every top-level tracked directory not in the kind's skip.
// - With no preview set it keeps _hop_preview_doc's -f test, which a declared preview chain loosens to -s.
func (e *Engine) builtinDir(k *config.Kind) []rows.Row {
	skip := k.Skip
	if skip == nil {
		skip = dirSkip
	}
	rs := []rows.Row{rows.New("dir", "-", "-", "-", "<root>", e.Root, "", false)}
	if ls, ok := e.ls(); ok {
		seen := map[string]bool{}
		for _, p := range ls {
			i := strings.IndexByte(p, '/')
			if i < 0 {
				continue
			}
			top := p[:i]
			if seen[top] {
				continue
			}
			seen[top] = true
			if slices.Contains(skip, top) {
				continue
			}
			dir := e.Root + "/" + top
			if !isDir(dir) {
				continue
			}
			rs = append(rs, rows.New("dir", "-", "-", "-", top, dir, "", false))
		}
	}
	if k.Preview != nil {
		return withPreviews(rs, func(dir string) string { return previewFor(dir, k) })
	}
	return withPreviews(rs, previewDoc)
}

// RepoRows is _hop_provider_repo: one row per existing repo dir, rendered with no root so rel is ~-relative.
func RepoRows(repos []string) []rows.Row {
	var rs []rows.Row
	for _, r := range repos {
		if r == "" || !isDir(r) {
			continue
		}
		rs = append(rs, rows.New("repo", "-", "-", "-", zTail(r), r, previewDoc(r), false))
	}
	return rs
}

// WorkspaceRows is _hop_provider_ws: one row per workspace, its ~ path as scope and its repo count as env.
func WorkspaceRows(wss []workspace.Workspace) []rows.Row {
	home := os.Getenv("HOME")
	var rs []rows.Row
	for _, w := range wss {
		n := len(workspace.Repos(w.Path))
		unit := "repos"
		if n == 1 {
			unit = "repo"
		}
		// ${path/#$HOME/~} is a plain prefix test, so it does not insist on a / after $HOME.
		scope := w.Path
		if home != "" && strings.HasPrefix(scope, home) {
			scope = "~" + scope[len(home):]
		}
		rs = append(rs, rows.New("ws", scope, fmt.Sprintf("%d %s", n, unit), "-", w.Name, w.Path, w.Path, false))
	}
	return rs
}

// entityName is _hop_entity_name: metadata.name from a 40-line scan, else the basename minus .yaml.
// - `read` fails on a final line with no newline, so zsh never looks at it, and neither does this.
func entityName(file string) string {
	def := strings.TrimSuffix(path.Base(file), ".yaml")
	f, err := os.Open(file)
	if err != nil {
		return def
	}
	defer f.Close()
	br := bufio.NewReader(f)
	inmeta := false
	for n := 0; n < 40; n++ {
		line, err := br.ReadString('\n')
		if err != nil {
			break
		}
		line = line[:len(line)-1]
		if strings.HasPrefix(line, "metadata:") {
			inmeta = true
			continue
		}
		if !inmeta {
			continue
		}
		if line == "" || !isSpace(line[0]) {
			break
		}
		rest, ok := strings.CutPrefix(strings.TrimLeft(line, spaces), "name:")
		if !ok || rest == "" {
			continue
		}
		v := strings.Trim(rest, spaces)
		if strings.HasPrefix(v, `"`) || strings.HasPrefix(v, `'`) {
			v = v[1:]
		}
		if strings.HasSuffix(v, `"`) || strings.HasSuffix(v, `'`) {
			v = v[:len(v)-1]
		}
		if v != "" {
			return v
		}
		return def
	}
	return def
}

const spaces = " \t\r\v\f"

func isSpace(b byte) bool { return strings.IndexByte(spaces, b) >= 0 }
