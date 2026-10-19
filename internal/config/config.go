// Package config is hop's TOML kind registry: presets, ordered [[kind]] tables, extend, and [settings].
package config

import (
	"embed"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"

	"github.com/BurntSushi/toml"
)

//go:embed presets/*.toml
var presetFS embed.FS

// PresetOrder is the order hop.zsh:37 loads presets in when a config declares no kind.
var PresetOrder = []string{"terragrunt", "terraform-modules", "helm", "serverless", "puppet", "backstage", "dir", "file"}

type TrimSpec struct{ Col, Prefix string }

type Kind struct {
	Name, Desc   string
	Default      bool
	Shape        string // dirs | files | marker | builtin | exec
	Dirs, Files  []string
	Marker       string
	Builtin      string
	Exec         []string
	Depth        int
	Under        string
	Layouts      []string
	NameTemplate string
	NameFrom     string
	StripExt     bool
	Exclude      []string
	Preview      []string
	PreviewSkip  []string
	Scope        string
	Trim         []TrimSpec
	Origin       string
}

type Config struct {
	Path     string
	Kinds    []*Kind
	byName   map[string]*Kind
	Settings Settings
	Warnings []string
}

// Error is a config problem with the file and line it came from.
type Error struct {
	File string
	Line int
	Msg  string
}

func (e *Error) Error() string {
	if e.Line > 0 {
		return fmt.Sprintf("%s:%d: %s", e.File, e.Line, e.Msg)
	}
	return fmt.Sprintf("%s: %s", e.File, e.Msg)
}

var shapeKeys = []string{"dirs", "files", "marker", "builtin", "exec"}

var knownKindKeys = map[string]bool{
	"name": true, "extend": true, "desc": true, "default": true, "dirs": true, "files": true,
	"marker": true, "builtin": true, "exec": true, "depth": true, "under": true, "layout": true,
	"name_template": true, "name_from": true, "strip_ext": true, "exclude": true, "preview": true,
	"preview_skip": true, "scope": true, "trim": true,
}

// Builtins are the kinds too irregular to declare, implemented in Go (lib/providers.zsh:257, :308).
var Builtins = map[string]bool{"dir": true, "helm": true}

var Columns = []string{"scope", "env", "region", "name"}

func New() *Config { return &Config{byName: map[string]*Kind{}} }

// Path is $HOP_CONFIG, else ${XDG_CONFIG_HOME:-~/.config}/hop/config.toml.
// - A $HOP_CONFIG ending in .zsh is zsh hop's, which it exports into every child, so it is never read as TOML.
func Path() string {
	if p := os.Getenv("HOP_CONFIG"); p != "" && !strings.HasSuffix(p, ".zsh") {
		return p
	}
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		if runtime.GOOS == "windows" {
			base, _ = os.UserConfigDir()
		} else {
			base = filepath.Join(os.Getenv("HOME"), ".config")
		}
	}
	return filepath.Join(base, "hop", "config.toml")
}

func (c *Config) Lookup(name string) (*Kind, bool) {
	k, ok := c.byName[name]
	return k, ok
}

// declare is hop_kind's registry write: a redeclared name replaces the kind and keeps its menu slot.
func (c *Config) declare(k *Kind) {
	if old, ok := c.byName[k.Name]; ok {
		*old = *k
		return
	}
	c.byName[k.Name] = k
	c.Kinds = append(c.Kinds, k)
}

func PresetSource(name string) (string, error) {
	b, err := presetFS.ReadFile("presets/" + name + ".toml")
	if err != nil {
		return "", fmt.Errorf("no such preset: %s", name)
	}
	return string(b), nil
}

func (c *Config) LoadPreset(name string) error {
	src, err := PresetSource(name)
	if err != nil {
		return err
	}
	return c.Apply(src, "preset:"+name, false)
}

func (c *Config) LoadAllPresets() error {
	for _, p := range PresetOrder {
		if err := c.LoadPreset(p); err != nil {
			return err
		}
	}
	return nil
}

// Load reads path; a missing file behaves like hop with no config.zsh, which loads every preset.
func Load(path string) (*Config, error) {
	c := New()
	c.Path = path
	b, err := os.ReadFile(path)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	if err == nil {
		if err := c.Apply(string(b), path, true); err != nil {
			return nil, err
		}
	}
	// hop.zsh:36 tests the registry, not the file: a config declaring no kind still gets every preset.
	if len(c.Kinds) == 0 {
		if err := c.LoadAllPresets(); err != nil {
			return nil, err
		}
	}
	c.applyEnv()
	return c, nil
}

type rawFile struct {
	Version  int              `toml:"version"`
	Presets  *[]string        `toml:"presets"`
	Settings map[string]any   `toml:"settings"`
	Kind     []map[string]any `toml:"kind"`
}

// Apply layers one TOML document onto the registry; only a top-level file may name presets or settings.
func (c *Config) Apply(src, origin string, top bool) error {
	var rf rawFile
	md, err := toml.Decode(src, &rf)
	if err != nil {
		var pe toml.ParseError
		if errors.As(err, &pe) {
			return &Error{origin, pe.Position.Line, pe.Message}
		}
		return &Error{origin, 0, err.Error()}
	}
	li := indexLines(src)
	for _, k := range md.Undecoded() {
		if len(k) > 0 && (k[0] == "kind" || k[0] == "settings") {
			continue
		}
		return &Error{origin, li.line("", k[len(k)-1]), fmt.Sprintf("unknown key %q", k.String())}
	}
	if rf.Version > 1 {
		return &Error{origin, li.line("", "version"), fmt.Sprintf("version %d is newer than this hop understands", rf.Version)}
	}
	if rf.Presets != nil {
		if !top {
			return &Error{origin, li.line("", "presets"), "a preset cannot load presets"}
		}
		for _, p := range *rf.Presets {
			if err := c.LoadPreset(p); err != nil {
				return &Error{origin, li.line("", "presets"), err.Error()}
			}
		}
	}
	for i, raw := range rf.Kind {
		if err := c.applyKind(raw, i, li, origin); err != nil {
			return err
		}
	}
	if rf.Settings != nil {
		if !top {
			return &Error{origin, li.line("", "settings"), "a preset cannot hold [settings]"}
		}
		if err := c.applySettings(rf.Settings, li, origin); err != nil {
			return err
		}
	}
	return nil
}

func asString(v any, key string) (string, error) {
	s, ok := v.(string)
	if !ok {
		return "", fmt.Errorf("%s must be a string", key)
	}
	return s, nil
}

func asBool(v any, key string) (bool, error) {
	b, ok := v.(bool)
	if !ok {
		return false, fmt.Errorf("%s must be true or false", key)
	}
	return b, nil
}

// asList accepts a list of strings or one string, which is never comma-split: the TOML list is the separator.
func asList(v any, key string) ([]string, error) {
	switch t := v.(type) {
	case string:
		return []string{t}, nil
	case []any:
		out := make([]string, 0, len(t))
		for _, e := range t {
			s, ok := e.(string)
			if !ok {
				return nil, fmt.Errorf("%s must hold only strings", key)
			}
			if s != "" {
				out = append(out, s)
			}
		}
		return out, nil
	}
	return nil, fmt.Errorf("%s must be a string or a list of strings", key)
}

// ApplyKind declares one kind from a decoded [[kind]] table, as the importer replays hop_kind calls.
func (c *Config) ApplyKind(raw map[string]any, origin string) error {
	return c.applyKind(raw, -1, nil, origin)
}

func (c *Config) applyKind(raw map[string]any, idx int, li *lineIndex, origin string) error {
	fail := func(key, format string, a ...any) error {
		msg := fmt.Sprintf(format, a...)
		if n, ok := raw["name"].(string); ok {
			msg = fmt.Sprintf("kind %q: %s", n, msg)
		}
		return &Error{origin, li.kindLine(idx, key), msg}
	}
	nameV, ok := raw["name"]
	if !ok {
		return fail("", "a [[kind]] needs a name")
	}
	name, err := asString(nameV, "name")
	if err != nil {
		return fail("name", "%v", err)
	}
	// dsl.zsh:37 rejects a leading '-'; comma and space are rejected too, since -k and HOP_DEFAULT_KINDS split on them.
	if name == "" || strings.HasPrefix(name, "-") || strings.ContainsAny(name, ", \t\n") {
		return fail("name", "kind name %q must be non-empty, not start with '-', and hold no comma or space", name)
	}
	extend := false
	if v, ok := raw["extend"]; ok {
		if extend, err = asBool(v, "extend"); err != nil {
			return fail("extend", "%v", err)
		}
	}
	k := &Kind{Name: name, Depth: 1, Origin: origin}
	if extend {
		old, ok := c.byName[name]
		if !ok {
			return fail("extend", "extend = true, but no earlier kind %q exists", name)
		}
		cp := *old
		k = &cp
		k.Origin = origin
	}
	keys := make([]string, 0, len(raw))
	for key := range raw {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	var shapes []string
	for _, s := range shapeKeys {
		if _, ok := raw[s]; ok {
			shapes = append(shapes, s)
		}
	}
	if len(shapes) > 1 {
		return fail(shapes[1], "set exactly one of dirs, files, marker, builtin or exec, not %s", strings.Join(shapes, " and "))
	}
	if len(shapes) == 1 {
		k.Dirs, k.Files, k.Marker, k.Builtin, k.Exec = nil, nil, "", "", nil
	}
	for _, key := range keys {
		v := raw[key]
		if !knownKindKeys[key] {
			return fail(key, "unknown key %q", key)
		}
		switch key {
		case "name", "extend":
		case "desc":
			k.Desc, err = asString(v, key)
		case "default":
			k.Default, err = asBool(v, key)
		case "dirs":
			k.Dirs, err = asList(v, key)
			k.Shape = "dirs"
		case "files":
			k.Files, err = asList(v, key)
			k.Shape = "files"
		case "marker":
			k.Marker, err = asString(v, key)
			k.Shape = "marker"
			if err == nil && (k.Marker == "" || strings.ContainsAny(k.Marker, "*?[")) {
				err = errors.New("marker must be a literal file name")
			}
		case "builtin":
			k.Builtin, err = asString(v, key)
			k.Shape = "builtin"
			if err == nil && !Builtins[k.Builtin] {
				err = fmt.Errorf("unknown builtin %q (dir or helm)", k.Builtin)
			}
		case "exec":
			switch t := v.(type) {
			case string:
				// A string is a shell command line; a list is argv, which is the only portable form.
				if runtime.GOOS == "windows" {
					k.Exec = []string{"powershell", "-NoProfile", "-Command", t}
				} else {
					k.Exec = []string{"/bin/sh", "-c", t}
				}
			default:
				k.Exec, err = asList(v, key)
				if err == nil && len(k.Exec) == 0 {
					err = errors.New("exec needs a command")
				}
			}
			k.Shape = "exec"
		case "depth":
			n, ok := v.(int64)
			if !ok || n < 1 {
				err = errors.New("depth must be a positive integer")
			}
			k.Depth = int(n)
		case "under":
			k.Under, err = asString(v, key)
			k.Under = strings.TrimSuffix(k.Under, "/")
		case "layout":
			k.Layouts, err = asList(v, key)
			if err == nil {
				err = checkLayouts(k.Layouts)
			}
		case "name_template":
			k.NameTemplate, err = asString(v, key)
		case "name_from":
			k.NameFrom, err = asString(v, key)
			if err == nil && k.NameFrom != "yaml:metadata.name" {
				err = errors.New(`name_from supports only "yaml:metadata.name"`)
			}
		case "strip_ext":
			k.StripExt, err = asBool(v, key)
		case "exclude":
			k.Exclude, err = asList(v, key)
		case "preview":
			k.Preview, err = asList(v, key)
		case "preview_skip":
			k.PreviewSkip, err = asList(v, key)
		case "scope":
			k.Scope, err = asString(v, key)
		case "trim":
			k.Trim, err = parseTrim(v)
		}
		if err != nil {
			return fail(key, "%v", err)
		}
	}
	if k.Shape == "" {
		return fail("name", "needs one of dirs, files, marker, builtin or exec")
	}
	for _, w := range inapplicable(k, raw) {
		c.Warnings = append(c.Warnings, (&Error{origin, li.kindLine(idx, w), fmt.Sprintf("kind %q: %s has no effect on a %s kind", name, w, k.Shape)}).Error())
	}
	c.declare(k)
	return nil
}

func checkLayouts(lays []string) error {
	for _, l := range lays {
		cols := splitNonEmpty(l, ",")
		if len(cols) == 0 {
			return fmt.Errorf("layout %q has no column", l)
		}
		for i, col := range cols {
			base := strings.TrimSuffix(col, "...")
			if base != col && i != len(cols)-1 {
				return fmt.Errorf("layout %q: only the last column may end in ...", l)
			}
			switch base {
			case "scope", "env", "region", "name", "-":
			default:
				return fmt.Errorf("layout %q: unknown column %q (scope, env, region, name or -)", l, col)
			}
		}
	}
	return nil
}

// parseTrim takes { scope = "acct-", env = ["env-", "e-"] }; a list applies its prefixes in order.
func parseTrim(v any) ([]TrimSpec, error) {
	m, ok := v.(map[string]any)
	if !ok {
		return nil, errors.New(`trim must be a table like { scope = "acct-" }`)
	}
	cols := make([]string, 0, len(m))
	for col := range m {
		cols = append(cols, col)
	}
	sort.Strings(cols)
	for _, col := range cols {
		switch col {
		case "scope", "env", "region", "name":
		default:
			return nil, fmt.Errorf("trim: unknown column %q (scope, env, region or name)", col)
		}
	}
	var out []TrimSpec
	for _, col := range Columns {
		pv, ok := m[col]
		if !ok {
			continue
		}
		ps, err := asList(pv, "trim."+col)
		if err != nil {
			return nil, err
		}
		for _, p := range ps {
			out = append(out, TrimSpec{col, p})
		}
	}
	return out, nil
}

// inapplicable names options the chosen shape ignores, which dsl.zsh accepts silently.
func inapplicable(k *Kind, raw map[string]any) []string {
	use := map[string][]string{
		"dirs":    {"depth", "preview", "preview_skip", "scope"},
		"files":   {"under", "layout", "name_template", "name_from", "strip_ext", "exclude", "scope", "trim"},
		"marker":  {"under", "layout", "name_template", "exclude", "preview", "preview_skip", "scope", "trim"},
		"builtin": {},
		"exec":    {"preview", "preview_skip"},
	}[k.Shape]
	ok := map[string]bool{"name": true, "extend": true, "desc": true, "default": true}
	for _, s := range shapeKeys {
		ok[s] = true
	}
	for _, u := range use {
		ok[u] = true
	}
	var w []string
	for key := range raw {
		if !ok[key] {
			w = append(w, key)
		}
	}
	sort.Strings(w)
	return w
}

func splitNonEmpty(s, sep string) []string {
	var out []string
	for _, p := range strings.Split(s, sep) {
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

// SplitNonEmpty is zsh's unquoted ${(s:sep:)s}, which drops empty fields.
func SplitNonEmpty(s, sep string) []string { return splitNonEmpty(s, sep) }

// RegistryKey is a stable dump of the registry with origins dropped, for comparing two loads.
func (c *Config) RegistryKey() string {
	var b strings.Builder
	for _, k := range c.Kinds {
		cp := *k
		cp.Origin = ""
		fmt.Fprintf(&b, "%+v;", cp)
	}
	return b.String()
}
