package testfix

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"testing"
)

// Inherited is the environment the test binary started with, and RealHome its $HOME, both from before Isolate.
// - Only a test gated on HOP_PARITY_REPO reads them, since it runs against the user's own setup on purpose.
var (
	Inherited []string
	RealHome  string
)

// Main is a package's whole TestMain: Isolate, run the tests, clean up, exit.
func Main(m *testing.M) {
	done := Isolate()
	code := m.Run()
	done()
	os.Exit(code)
}

// Isolate points HOME and the XDG dirs at a fresh temp dir and drops every inherited HOP_*, HOPX_* and FZF_* variable.
// - hop's defaults are the user's real history and config, and zsh hop exports HOP_CONFIG into every shell, so no test may see either.
// - GOMODCACHE, GOCACHE and GOPATH are pinned from `go env` first, or a `go build` under the temp HOME would refetch modules.
// - Without go on PATH, as in docker, nothing is pinned.
// - HOP_PARITY_* and HOP_TEST_* survive, since they are the test knobs rather than hop's settings.
// - It returns the cleanup that removes the temp dir.
func Isolate() func() {
	Inherited = os.Environ()
	RealHome = os.Getenv("HOME")
	if out, err := exec.Command("go", "env", "GOMODCACHE", "GOCACHE", "GOPATH").Output(); err == nil {
		vals := strings.Split(strings.TrimRight(string(out), "\n"), "\n")
		for i, k := range []string{"GOMODCACHE", "GOCACHE", "GOPATH"} {
			if i < len(vals) && vals[i] != "" {
				os.Setenv(k, vals[i])
			}
		}
	}
	for _, kv := range Inherited {
		k, _, _ := strings.Cut(kv, "=")
		if strings.HasPrefix(k, "HOP_PARITY_") || strings.HasPrefix(k, "HOP_TEST_") {
			continue
		}
		if strings.HasPrefix(k, "HOP_") || strings.HasPrefix(k, "HOPX_") || strings.HasPrefix(k, "FZF_") {
			os.Unsetenv(k)
		}
	}
	tmp, err := os.MkdirTemp("", "hop-test-home-")
	if err != nil {
		fmt.Fprintln(os.Stderr, "testfix: isolate:", err)
		os.Exit(2)
	}
	tmp = Resolved(tmp)
	os.Setenv("HOME", tmp)
	for k, sub := range map[string]string{"XDG_STATE_HOME": ".local/state", "XDG_CONFIG_HOME": ".config", "XDG_CACHE_HOME": ".cache"} {
		os.Setenv(k, tmp+"/"+sub)
	}
	return func() { os.RemoveAll(tmp) }
}
