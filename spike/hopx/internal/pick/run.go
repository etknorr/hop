package pick

import (
	"bufio"
	"errors"
	"io"
	"os"
	"os/exec"
	"strings"

	"github.com/etknorr/hop/spike/hopx/internal/tty"
)

// Run is _hop_pick's fzf call: rows on fzf's stdin, the result read from its stdout, the screen on the terminal.
//   - fzf reads keys from /dev/tty itself; its stderr is pointed at the terminal when hopx's isn't one,
//     since a PSReadLine key handler hands the binary pipes and the picker would draw into them.
//   - The status is fzf's: 0 picked, 1 no match, 130 cancelled.
func Run(fzf string, o Opts, s *Session, input []string, stderr io.Writer) (string, int, error) {
	dir, sp, err := s.Write()
	if err != nil {
		return "", 2, err
	}
	defer os.RemoveAll(dir)
	c := exec.Command(fzf, Args(o)...)
	c.Env = append(envWithout("HOPX_SESSION", "HOPX_CMDFILE"), "HOPX_SESSION="+sp)
	c.Stderr = stderr
	if f, ok := stderr.(*os.File); !ok || !tty.Is(f) {
		if t := tty.Open(); t != nil {
			defer t.Close()
			c.Stderr = t
		}
	}
	in, err := c.StdinPipe()
	if err != nil {
		return "", 2, err
	}
	go func() {
		bw := bufio.NewWriterSize(in, 64<<10)
		for _, r := range input {
			bw.WriteString(r)
			bw.WriteByte('\n')
		}
		bw.Flush()
		in.Close()
	}()
	out, err := c.Output()
	if err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			return string(out), ee.ExitCode(), nil
		}
		return "", 2, err
	}
	return string(out), 0, nil
}

func envWithout(names ...string) []string {
	var env []string
	for _, e := range os.Environ() {
		k, _, _ := strings.Cut(e, "=")
		drop := false
		for _, n := range names {
			drop = drop || k == n
		}
		if !drop {
			env = append(env, e)
		}
	}
	return env
}
