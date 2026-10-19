package kinds

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strings"
	"time"

	"github.com/etknorr/hop/internal/config"
	"github.com/etknorr/hop/internal/rows"
)

// emitExec runs a provider command in the repo root and reads its rows.
// - Protocol, one row per line: name TAB path [TAB preview [TAB scope [TAB env [TAB region]]]].
// - path and preview are relative to the root unless absolute; '-' or empty means unset.
// - A path naming a regular file makes a file target: dir is its parent, preview defaults to it.
// - A directory row with no preview gets the kind's own preview chain, so exec kinds keep previews.
func (e *Engine) emitExec(k *config.Kind) ([]rows.Row, error) {
	root := e.Root
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	argv := make([]string, len(k.Exec))
	for i, a := range k.Exec {
		argv[i] = expandHome(a)
	}
	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	cmd.Dir = root
	cmd.Stderr = e.Stderr
	cmd.Env = append(os.Environ(), "HOP_ROOT="+root, "HOP_KIND="+k.Name)
	out, err := cmd.Output()
	var rs []rows.Row
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSuffix(line, "\r")
		if line == "" {
			continue
		}
		f := strings.Split(line, "\t")
		for len(f) < 6 {
			f = append(f, "")
		}
		for i := range f {
			if f[i] == "-" {
				f[i] = ""
			}
		}
		name, p, prev := f[0], f[1], f[2]
		if p == "" {
			continue
		}
		p = absUnder(root, p)
		if prev != "" {
			prev = absUnder(root, prev)
		}
		if isRegular(p) {
			rs = append(rs, rows.New(k.Name, f[3], f[4], f[5], name, path.Dir(p), orDefault(prev, p), true))
			continue
		}
		if prev == "" && len(k.Preview) > 0 {
			prev = previewFor(p, k)
		}
		rs = append(rs, rows.New(k.Name, f[3], f[4], f[5], name, p, prev, false))
	}
	if err != nil {
		return rs, fmt.Errorf("kind %s: exec %s: %w", k.Name, argv[0], err)
	}
	return rs, nil
}

func absUnder(root, p string) string {
	if filepath.IsAbs(p) {
		return filepath.Clean(p)
	}
	return path.Clean(root + "/" + p)
}

func expandHome(s string) string {
	if s == "~" {
		return os.Getenv("HOME")
	}
	if strings.HasPrefix(s, "~/") {
		return os.Getenv("HOME") + s[1:]
	}
	return s
}
