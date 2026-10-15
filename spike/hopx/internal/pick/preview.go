package pick

import (
	"bufio"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/etknorr/hop/spike/hopx/internal/collate"
)

const (
	off  = "\x1b[0m"
	hdr  = "\x1b[1;36m"
	sub  = "\x1b[2m"
	warn = "\x1b[33m"

	maxLines   = 400
	maxEntries = 200
	rule       = sub + "────────────────────────────────" + off
)

// gitTop walks up for .git rather than forking `git rev-parse`, which hop-preview pays on every cursor move.
func gitTop(dir string) string {
	for d := dir; d != ""; {
		if _, err := os.Lstat(filepath.Join(d, ".git")); err == nil {
			return d
		}
		p := filepath.Dir(d)
		if p == d {
			return ""
		}
		d = p
	}
	return ""
}

func relTo(root, p string) string {
	switch {
	case root != "" && p == root:
		return filepath.Base(root)
	case root != "" && strings.HasPrefix(p, root+"/"):
		return p[len(root)+1:]
	}
	return p
}

// Preview is `hopx __preview {2} {3}`, a port of bin/hop-preview without the `--keys` overlay.
// - A dir lists up to 200 entries, dotfiles included, in zsh's glob order; a file shows its first 400 lines.
// - It never fails loudly: a bad argument prints one line.
func Preview(w io.Writer, dir, target string) {
	bw := bufio.NewWriter(w)
	defer bw.Flush()
	if target == "" {
		target = dir
	}
	if dir == "" && target == "" {
		bw.WriteString(warn + "hop: nothing to preview" + off + "\n")
		return
	}
	start := dir
	if start == "" {
		start = "."
	}
	if abs, err := filepath.Abs(start); err == nil {
		start = abs
	}
	root := gitTop(start)
	bw.WriteString(hdr + relTo(root, dir) + off + "\n")
	st, err := os.Stat(target)
	if err != nil {
		bw.WriteString(warn + "no preview: " + relTo(root, target) + " does not exist" + off + "\n")
		return
	}
	if st.IsDir() {
		bw.WriteString(sub + "directory listing" + off + "\n" + rule + "\n")
		ents, _ := os.ReadDir(target)
		if len(ents) == 0 {
			bw.WriteString(sub + "(empty)" + off + "\n")
			return
		}
		names := make([]string, len(ents))
		for i, e := range ents {
			names[i] = e.Name()
		}
		collate.Sort(names)
		for i, n := range names {
			if i >= maxEntries {
				bw.WriteString(sub + "… " + strconv.Itoa(len(names)-maxEntries) + " more" + off + "\n")
				break
			}
			if fi, err := os.Stat(filepath.Join(target, n)); err == nil && fi.IsDir() {
				bw.WriteString(hdr + n + "/" + off + "\n")
			} else {
				bw.WriteString(n + "\n")
			}
		}
		return
	}
	bw.WriteString(sub + relTo(root, target) + off + "\n" + rule + "\n")
	if bat, err := exec.LookPath("bat"); err == nil {
		bw.Flush()
		c := exec.Command(bat, "--color=always", "--style=plain", "--line-range=:"+strconv.Itoa(maxLines), target)
		c.Stdout = w
		if c.Run() == nil {
			return
		}
	}
	f, err := os.Open(target)
	if err != nil {
		bw.WriteString(warn + "no preview: cannot read " + relTo(root, target) + off + "\n")
		return
	}
	defer f.Close()
	head(bw, f, maxLines)
}

// head is `head -n`: bytes up to the nth newline, a last line with no newline kept as it is.
func head(w *bufio.Writer, r io.Reader, n int) {
	br := bufio.NewReaderSize(r, 64<<10)
	for i := 0; i < n; i++ {
		line, err := br.ReadSlice('\n')
		w.Write(line)
		if err == bufio.ErrBufferFull {
			i--
			continue
		}
		if err != nil {
			return
		}
	}
}
