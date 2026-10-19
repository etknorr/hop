// Package act carries out a chosen target: cd through the cmdfile protocol, and the VS Code, editor, copy and browse verbs.
package act

import (
	"fmt"
	"io"
	"os"

	"github.com/etknorr/hop/internal/mru"
)

// CD hands dir to the shell function and remembers it, as _hop_act_cd does after its cd.
// - With HOP_CMDFILE set, the dir goes into that file, created O_EXCL and 0600, with no newline.
// - Without it, as in a script, the dir is printed on stdout, so `cd "$(hop foo)"` works.
func CD(dir string, stdout, stderr io.Writer, hist string, histMax int) int {
	if st, err := os.Stat(dir); err != nil || !st.IsDir() {
		fmt.Fprintln(stderr, "hop: not a directory:", dir)
		return 1
	}
	if cf := os.Getenv("HOP_CMDFILE"); cf != "" {
		f, err := os.OpenFile(cf, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
		if err != nil {
			fmt.Fprintln(stderr, "hop: cannot write the cd file:", err)
			return 1
		}
		_, werr := io.WriteString(f, dir)
		if cerr := f.Close(); werr != nil || cerr != nil {
			fmt.Fprintln(stderr, "hop: cannot write the cd file:", cf)
			return 1
		}
	} else {
		fmt.Fprintln(stdout, dir)
	}
	mru.Remember(hist, dir, histMax)
	return 0
}
