package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strings"
	"sync"

	"github.com/etknorr/hop/internal/kinds"
	"github.com/etknorr/hop/internal/mru"
	"github.com/etknorr/hop/internal/pick"
)

// self is the binary's absolute path, which --with-shell bakes in.
func self() string {
	p, err := os.Executable()
	if err != nil {
		return "hop"
	}
	return p
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

// cmdMenu is `hop __menu`, bin/hop-kinds' menu: one row per kind holding targets here, with its live count.
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
