package pick

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"runtime"
	"strings"
)

// SplitWords parses the POSIX quoting fzf puts on {n}, which it uses on every OS once --with-shell names a program that isn't cmd or pwsh.
func SplitWords(s string) ([]string, error) {
	var words []string
	var cur strings.Builder
	in := false
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == '\'':
			in = true
			j := strings.IndexByte(s[i+1:], '\'')
			if j < 0 {
				return nil, errors.New("unterminated single quote")
			}
			cur.WriteString(s[i+1 : i+1+j])
			i += j + 1
		case c == '"':
			in = true
			i++
			for ; i < len(s) && s[i] != '"'; i++ {
				if s[i] == '\\' && i+1 < len(s) && strings.IndexByte("$`\"\\\n", s[i+1]) >= 0 {
					i++
				}
				cur.WriteByte(s[i])
			}
			if i >= len(s) {
				return nil, errors.New("unterminated double quote")
			}
		case c == '\\' && i+1 < len(s):
			in = true
			i++
			cur.WriteByte(s[i])
		case c == ' ' || c == '\t' || c == '\n':
			if in {
				words = append(words, cur.String())
				cur.Reset()
				in = false
			}
		default:
			in = true
			cur.WriteByte(c)
		}
	}
	if in {
		words = append(words, cur.String())
	}
	return words, nil
}

// Shim is `hop __sh <command>`, the program fzf runs every callback through.
// - A `hop __verb` command is dispatched in this process, so the user's $SHELL (fish, pwsh, cmd) never parses it.
// - Anything else is a bind from the user's FZF_DEFAULT_OPTS, written for their own shell, so it goes to that shell.
func Shim(cmd string, dispatch func(args []string) int, stdout, stderr io.Writer) int {
	words, err := SplitWords(cmd)
	if err == nil && len(words) >= 2 && words[0] == "hop" && strings.HasPrefix(words[1], "__") {
		return dispatch(words[1:])
	}
	var c *exec.Cmd
	if runtime.GOOS == "windows" {
		c = exec.Command("cmd", "/s/c", cmd)
	} else {
		sh := os.Getenv("SHELL")
		if sh == "" {
			sh = "sh"
		}
		c = exec.Command(sh, "-c", cmd)
	}
	c.Stdin, c.Stdout, c.Stderr = os.Stdin, stdout, stderr
	if err := c.Run(); err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			return ee.ExitCode()
		}
		fmt.Fprintln(stderr, "hop:", err)
		return 127
	}
	return 0
}
