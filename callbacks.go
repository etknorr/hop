package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strings"
	"sync"

	"github.com/etknorr/hop/internal/config"
	"github.com/etknorr/hop/internal/kinds"
	"github.com/etknorr/hop/internal/mru"
	"github.com/etknorr/hop/internal/pick"
	"github.com/etknorr/hop/internal/shell"
)

// self is the binary's absolute path, which --with-shell and the pwsh script bake in.
func self() string {
	p, err := os.Executable()
	if err != nil {
		return "hopx"
	}
	return p
}

func cmdInit(args []string, stdout io.Writer) error {
	sh, cmd := "", ""
	for i := 0; i < len(args); i++ {
		switch a := args[i]; {
		case a == "--cmd" && i+1 < len(args):
			i++
			cmd = args[i]
		case strings.HasPrefix(a, "--cmd="):
			cmd = a[len("--cmd="):]
		case sh == "" && !strings.HasPrefix(a, "-"):
			sh = a
		default:
			return errUsage
		}
	}
	if sh == "" {
		return errUsage
	}
	s, err := shell.Init(sh, cmd, self())
	if err != nil {
		return err
	}
	_, err = io.WriteString(stdout, s)
	return err
}

// cmdRowsSession is the picker's reload: the session's root and -c dir, ranked by history, as _hop_rows does.
func cmdRowsSession(names []string, stdout, stderr io.Writer) error {
	s, err := pick.Load()
	if err != nil {
		return err
	}
	cfg, err := load(stderr)
	if err != nil {
		return err
	}
	if len(names) == 0 {
		names = s.Kinds
	}
	gen := kinds.Generate(cfg, s.Root, uniqStrings(names), stderr)
	if s.Under != "" {
		gen = underRows(gen, s.Under)
	}
	all := mru.Rank(renderAll(gen, s.Root), mru.Load(cfg.Settings.HistFile))
	bw := bufio.NewWriterSize(stdout, 1<<16)
	for _, r := range all {
		bw.WriteString(r)
		bw.WriteByte('\n')
	}
	return bw.Flush()
}

const (
	menuKind = "\x1b[1;36m"
	menuNum  = "\x1b[1m"
	menuDesc = "\x1b[2m"
	menuOff  = "\x1b[0m"
)

// cmdMenu is `hopx __menu`, bin/hop-kinds' menu: one row per kind holding targets here, with its live count.
// - hop caches the counts per HEAD and index because a zsh sweep costs about 1.6 s; one shared listing makes them cheap enough to count live.
// - Field 2 is the kind name, which the enter callback gets back as {2}.
func cmdMenu(stdout, stderr io.Writer) error {
	s, err := pick.Load()
	if err != nil {
		return err
	}
	cfg, err := load(stderr)
	if err != nil {
		return err
	}
	e := kinds.New(s.Root, io.Discard)
	counts := make([]int, len(cfg.Kinds))
	var wg sync.WaitGroup
	for i, k := range cfg.Kinds {
		wg.Go(func() {
			for _, r := range e.Emit(k) {
				if s.Under == "" || r.Dir == s.Under || strings.HasPrefix(r.Dir, s.Under+"/") {
					counts[i]++
				}
			}
		})
	}
	wg.Wait()
	bw := bufio.NewWriter(stdout)
	for i, k := range cfg.Kinds {
		if counts[i] == 0 {
			continue
		}
		fmt.Fprintf(bw, "%s%-11s%s %s%8d%s  %s%s%s\t%s\t%s\n", menuKind, k.Name, menuOff, menuNum, counts[i], menuOff, menuDesc, k.Desc, menuOff, k.Name, s.Root)
	}
	return bw.Flush()
}

func cmdComplete(words []string, stdout, stderr io.Writer) error {
	var ks []shell.Kind
	if cfg, err := config.Load(config.Path()); err == nil {
		for _, k := range cfg.Kinds {
			ks = append(ks, shell.Kind{Name: k.Name, Desc: k.Desc})
		}
	}
	bw := bufio.NewWriter(stdout)
	for _, c := range shell.Complete(words, ks, config.Actions) {
		bw.WriteString(c)
		bw.WriteByte('\n')
	}
	return bw.Flush()
}
