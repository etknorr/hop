package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/etknorr/hop/internal/importer"
)

// cmdImport is `hop import [CONFIG.zsh] [-o OUT] [--force]`, writing stdout unless -o names a file.
// - The source defaults to a HOP_CONFIG ending in .zsh, which zsh hop exports, else zsh hop's own default path.
// - An existing OUT is refused without --force, so an import never replaces a config.toml by surprise.
func cmdImport(args []string, stdout, stderr io.Writer) error {
	fs := flag.NewFlagSet("import", flag.ContinueOnError)
	fs.SetOutput(stderr)
	out := fs.String("o", "", "write the TOML here instead of stdout")
	force := fs.Bool("force", false, "replace an existing -o file")
	var src string
	for len(args) > 0 {
		if err := fs.Parse(args); err != nil {
			return errUsage
		}
		args = fs.Args()
		if len(args) > 0 {
			if src != "" {
				return errUsage
			}
			src, args = args[0], args[1:]
		}
	}
	if src == "" {
		src = defaultImportSource()
	}
	if *out != "" && !*force {
		if _, err := os.Stat(*out); err == nil {
			return fmt.Errorf("import: %s exists; pass --force to replace it", *out)
		}
	}
	res, err := importer.Import(src)
	if err != nil {
		return err
	}
	for _, w := range res.Warnings {
		fmt.Fprintln(stderr, "hop: warning:", w)
	}
	text := res.TOML(src)
	if *out == "" {
		_, err := io.WriteString(stdout, text)
		return err
	}
	if err := os.MkdirAll(filepath.Dir(*out), 0o755); err != nil {
		return err
	}
	tmp := *out + ".tmp"
	if err := os.WriteFile(tmp, []byte(text), 0o644); err != nil {
		return err
	}
	if err := os.Rename(tmp, *out); err != nil {
		os.Remove(tmp)
		return err
	}
	return nil
}

func defaultImportSource() string {
	if p := os.Getenv("HOP_CONFIG"); strings.HasSuffix(p, ".zsh") {
		return p
	}
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(base, "hop", "config.zsh")
}
