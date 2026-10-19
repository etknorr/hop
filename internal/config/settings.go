package config

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
)

var (
	Actions = []string{"cd", "open", "reveal", "cd+open", "cd+reveal"}
	Jumps   = []string{"auto", "unique", "never"}
)

// Settings resolve flag > env > file > default; flags are applied by the caller after Load.
type Settings struct {
	Action, Jump, Code, Clipboard, HistFile string
	FzfHeight                               *string
	Vim                                     *bool
	HistMax                                 int
	DefaultKinds                            []string
	Workspaces                              []string
	Repos                                   []string
	WorkspacesFile                          string
}

func (c *Config) applySettings(m map[string]any, li *lineIndex, origin string) error {
	s := &c.Settings
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	slices.Sort(keys)
	for _, key := range keys {
		v := m[key]
		var err error
		switch key {
		case "action":
			s.Action, err = asString(v, key)
		case "jump":
			s.Jump, err = asString(v, key)
		case "code":
			s.Code, err = asString(v, key)
		case "clipboard":
			s.Clipboard, err = asString(v, key)
		case "hist_file":
			s.HistFile, err = asString(v, key)
		case "fzf_height":
			var h string
			h, err = asString(v, key)
			s.FzfHeight = &h
		case "vim":
			var b bool
			b, err = asBool(v, key)
			s.Vim = &b
		case "hist_max":
			n, ok := v.(int64)
			if !ok || n < 1 {
				err = fmt.Errorf("hist_max must be a positive integer")
			}
			s.HistMax = int(n)
		case "default_kinds":
			s.DefaultKinds, err = asList(v, key)
		case "workspaces":
			s.Workspaces, err = asList(v, key)
		case "workspaces_file":
			s.WorkspacesFile, err = asString(v, key)
		case "repos":
			s.Repos, err = asList(v, key)
		default:
			err = fmt.Errorf("unknown setting %q", key)
		}
		if err != nil {
			return &Error{origin, li.line("settings", key), "[settings]: " + err.Error()}
		}
	}
	return nil
}

// applyEnv layers HOP_* over the file.
// - This inverts zsh hop, where a `typeset -g HOP_ACTION=` in config.zsh beat the environment.
// - Set-but-empty is honoured where hop honours it: HOP_FZF_HEIGHT= means fullscreen (ui.zsh:476).
func (c *Config) applyEnv() {
	s := &c.Settings
	str := func(name string, dst *string) {
		if v := os.Getenv(name); v != "" {
			*dst = v
		}
	}
	str("HOP_ACTION", &s.Action)
	str("HOP_JUMP", &s.Jump)
	str("HOP_CODE", &s.Code)
	str("HOP_CLIPBOARD", &s.Clipboard)
	str("HOPX_HISTFILE", &s.HistFile)
	str("HOP_WORKSPACES_FILE", &s.WorkspacesFile)
	if v, ok := os.LookupEnv("HOP_FZF_HEIGHT"); ok {
		s.FzfHeight = &v
	}
	if v, ok := os.LookupEnv("HOP_VIM"); ok {
		on := v != "0"
		s.Vim = &on
	}
	if v := os.Getenv("HOP_HIST_MAX"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			s.HistMax = n
		}
	}
	if v := os.Getenv("HOP_DEFAULT_KINDS"); v != "" {
		s.DefaultKinds = strings.Fields(strings.ReplaceAll(v, ",", " "))
	}
	if v := os.Getenv("HOP_WORKSPACES"); v != "" {
		s.Workspaces = splitNonEmpty(v, string(os.PathListSeparator))
	}
	if v := os.Getenv("HOP_REPOS"); v != "" {
		s.Repos = splitNonEmpty(v, string(os.PathListSeparator))
	}
	if s.Action == "" {
		s.Action = "cd"
	}
	if !slices.Contains(Actions, s.Action) {
		c.Warnings = append(c.Warnings, fmt.Sprintf("action %q is not one of %s; using cd", s.Action, strings.Join(Actions, ", ")))
		s.Action = "cd"
	}
	if s.Jump == "" {
		s.Jump = "auto"
	}
	if !slices.Contains(Jumps, s.Jump) {
		c.Warnings = append(c.Warnings, fmt.Sprintf("jump %q is not one of auto, unique, never; using auto", s.Jump))
		s.Jump = "auto"
	}
	if s.Code == "" {
		s.Code = "code"
	}
	if s.FzfHeight == nil {
		h := "80%"
		s.FzfHeight = &h
	}
	if s.Vim == nil {
		on := true
		s.Vim = &on
	}
	if s.HistMax == 0 {
		s.HistMax = 300
	}
	if s.HistFile == "" {
		base := os.Getenv("XDG_STATE_HOME")
		if base == "" {
			base = filepath.Join(os.Getenv("HOME"), ".local", "state")
		}
		s.HistFile = filepath.Join(base, "hopx", "history")
	}
	if s.WorkspacesFile == "" {
		base := os.Getenv("XDG_CONFIG_HOME")
		if base == "" {
			base = filepath.Join(os.Getenv("HOME"), ".config")
		}
		s.WorkspacesFile = filepath.Join(base, "hop", "workspaces")
	}
}

// DefaultKinds is the pinned default_kinds when set, else every kind declared default, in menu order.
func (c *Config) DefaultKinds() []string {
	if len(c.Settings.DefaultKinds) > 0 {
		return c.Settings.DefaultKinds
	}
	var out []string
	for _, k := range c.Kinds {
		if k.Default {
			out = append(out, k.Name)
		}
	}
	return out
}

// AllKinds is every kind in menu order, which is what hop -a lists.
func (c *Config) AllKinds() []string {
	out := make([]string, len(c.Kinds))
	for i, k := range c.Kinds {
		out[i] = k.Name
	}
	return out
}
