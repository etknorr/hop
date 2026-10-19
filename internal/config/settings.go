package config

import (
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"

	"github.com/etknorr/hop/internal/rows"
)

var (
	Actions = []string{"cd", "open", "reveal", "cd+open", "cd+reveal"}
	Jumps   = []string{"auto", "unique", "never"}
)

// EnvClasses are the env colour classes; an env word in none of them is magenta.
var EnvClasses = []string{"prod", "staging", "dev"}

// Settings resolve flag > env > file > default; flags are applied by the caller after Load.
//   - Action and Jump are always valid; ActionRaw and JumpRaw are the env or file value as given, "" when unset,
//     so the caller can word zsh hop's warning at the point hop() reads it.
//   - A bad action or jump in [settings] is a load error, but a bad HOP_ACTION or HOP_JUMP only falls back.
type Settings struct {
	Action, Jump, Code, Clipboard, HistFile string
	ActionRaw, JumpRaw                      string
	FzfHeight                               *string
	Vim                                     *bool
	Debug                                   bool
	DebugLog                                string
	FzfMin                                  string
	GuardWindow                             string
	HistMax                                 int
	DefaultKinds                            []string
	Workspaces                              []string
	Repos                                   []string
	WorkspacesFile                          string
	EnvColors                               map[string][]string
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
			if err == nil && !slices.Contains(Actions, s.Action) {
				err = fmt.Errorf("action %q is not one of %s", s.Action, strings.Join(Actions, ", "))
			}
		case "jump":
			s.Jump, err = asString(v, key)
			if err == nil && !slices.Contains(Jumps, s.Jump) {
				err = fmt.Errorf("jump %q is not one of %s", s.Jump, strings.Join(Jumps, ", "))
			}
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
		case "debug":
			s.Debug, err = asBool(v, key)
		case "debug_log":
			s.DebugLog, err = asString(v, key)
		case "fzf_min":
			s.FzfMin, err = asString(v, key)
		case "guard_window":
			s.GuardWindow, err = asNumber(v, key)
		case "env_colors":
			s.EnvColors, err = parseEnvColors(v)
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

func asNumber(v any, key string) (string, error) {
	switch t := v.(type) {
	case int64:
		return strconv.FormatInt(t, 10), nil
	case float64:
		return strconv.FormatFloat(t, 'f', -1, 64), nil
	case string:
		return t, nil
	}
	return "", fmt.Errorf("%s must be a number of seconds", key)
}

// parseEnvColors takes { prod = ["prod", "live"], dev = ["dev", "sandbox"] }; a class left out keeps its default.
func parseEnvColors(v any) (map[string][]string, error) {
	m, ok := v.(map[string]any)
	if !ok {
		return nil, fmt.Errorf(`env_colors must be a table like { prod = ["prod"], dev = ["dev", "sandbox"] }`)
	}
	for _, cls := range slices.Sorted(maps.Keys(m)) {
		if !slices.Contains(EnvClasses, cls) {
			return nil, fmt.Errorf("env_colors: unknown class %q (%s)", cls, strings.Join(EnvClasses, ", "))
		}
	}
	out := map[string][]string{}
	for cls, v := range m {
		words, err := asList(v, "env_colors."+cls)
		if err != nil {
			return nil, err
		}
		out[cls] = words
	}
	return out, nil
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
	s.ActionRaw, s.JumpRaw = s.Action, s.Jump
	str("HOP_CODE", &s.Code)
	str("HOP_CLIPBOARD", &s.Clipboard)
	str("HOP_HISTFILE", &s.HistFile)
	str("HOP_WORKSPACES_FILE", &s.WorkspacesFile)
	if v, ok := os.LookupEnv("HOP_FZF_HEIGHT"); ok {
		s.FzfHeight = &v
	}
	if v, ok := os.LookupEnv("HOP_VIM"); ok {
		on := v != "0"
		s.Vim = &on
	}
	str("HOP_DEBUG_LOG", &s.DebugLog)
	str("HOP_FZF_MIN", &s.FzfMin)
	str("HOP_GUARD_WINDOW", &s.GuardWindow)
	// lib/doctor.zsh:15 logs whenever HOP_DEBUG is non-empty, 0 included.
	if v, ok := os.LookupEnv("HOP_DEBUG"); ok {
		s.Debug = v != ""
	}
	if os.Getenv("HOP_HOPRC") != "" && os.Getenv("HOP_SESSION") == "" {
		c.Warnings = append(c.Warnings, "hop: HOP_HOPRC is set, but hop no longer reads a repo's .hoprc; declare its kinds in "+Path())
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
		s.Action = "cd"
	}
	if s.Jump == "" {
		s.Jump = "auto"
	}
	if !slices.Contains(Jumps, s.Jump) {
		s.Jump = "auto"
	}
	if s.GuardWindow == "" {
		s.GuardWindow = "0.15"
	}
	colors := map[string][]string{"prod": {"prod"}, "staging": {"staging"}, "dev": {"dev"}}
	for cls, words := range s.EnvColors {
		colors[cls] = words
	}
	s.EnvColors = colors
	rows.SetEnvColors(colors)
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
		s.HistFile = filepath.Join(base, "hop", "history")
	}
	if s.DebugLog == "" {
		base := os.Getenv("XDG_STATE_HOME")
		if base == "" {
			base = filepath.Join(os.Getenv("HOME"), ".local", "state")
		}
		s.DebugLog = filepath.Join(base, "hop", "debug.log")
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
