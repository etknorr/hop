package act

import (
	"errors"
	"os"
	"os/exec"
)

// ExecEditor runs the editor as a child on Windows, which has no exec(2).
func ExecEditor(argv []string) int {
	c := exec.Command(argv[0], argv[1:]...)
	c.Stdin, c.Stdout, c.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := c.Run(); err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			return ee.ExitCode()
		}
		return 1
	}
	return 0
}
