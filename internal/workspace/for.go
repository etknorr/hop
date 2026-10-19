package workspace

import "strings"

// For is _hop_ws_for: the workspace path that is dir or holds it, the longest winning when two nest.
func For(dir string, wss []Workspace) (string, bool) {
	best := ""
	for _, w := range wss {
		p := strings.TrimRight(w.Path, "/")
		if (dir == p || strings.HasPrefix(dir, p+"/")) && len(p) > len(best) {
			best = p
		}
	}
	return best, best != ""
}
