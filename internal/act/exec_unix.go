//go:build unix

package act

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"syscall"

	"github.com/etknorr/hop/internal/tty"
)

// ExecEditor replaces hopx with the editor, so it owns the terminal, the signals and the job slot.
// - A key-handler caller can hand hopx pipes, so fds 0-2 are pointed at the terminal first.
// - The shell function is waiting on this pid, so a cmdfile written before the exec is still read afterwards.
func ExecEditor(argv []string) int {
	path, err := exec.LookPath(argv[0])
	if err != nil {
		fmt.Fprintln(os.Stderr, "hop:", err)
		return 1
	}
	tty.Attach()
	var env []string
	for _, e := range os.Environ() {
		if !strings.HasPrefix(e, "HOPX_CMDFILE=") && !strings.HasPrefix(e, "HOPX_SESSION=") {
			env = append(env, e)
		}
	}
	err = syscall.Exec(path, argv, env)
	fmt.Fprintln(os.Stderr, "hopx: exec:", err)
	return 1
}
