// Package config is hop's TOML kind registry: recipes, ordered [[kind]] tables, extend, and [settings].
package config

import (
	"embed"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"sort"
	"strings"

	"github.com/BurntSushi/toml"
)

//go:embed recipes/*.toml
var recipeFS embed.FS

var recipeOrder = []string{"dir", "project", "file", "terragrunt", "terraform-modules", "helm", "serverless", "puppet", "backstage"}

// DefaultRecipes is what a config naming no recipe and declaring no kind gets.
var DefaultRecipes = []string{"dir", "project", "file"}

// Recipes is every recipe a config can name, in the order hop lists them.
func Recipes() []string { return slices.Clone(recipeOrder) }

type TrimSpec struct{ Col, Prefix string }

type Kind struct {
	Name, Desc   string
	Default      bool
	Shape        string // dirs | files | marker | builtin | exec | sources
	Dirs, Files  []string
	Marker       []string
	Builtin      string
	Exec         []string
	Sources      []*Kind
	Depth        int
	MinDepth     int
	Nested       bool
	Under        string
	Layouts      []string
	NameTemplate string
	NameFrom     string
	StripExt     bool
	Exclude      []string
	Preview      []string
	PreviewSkip  []string
	Skip         []string
	Scope        string
	Trim         []TrimSpec
	Origin       string
}

type Config struct {
	Path     string
	Kinds    []*Kind
	byName   map[string]*Kind
	Settings Settings
	// Warnings are whole lines, printed as they are and only by the top-level call.
	Warnings []string
	// Loaded is the recipes this config loaded, in order.
	Loaded []string
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

var sourceShapes = []string{"dirs", "files", "marker"}

var kindOnlyKeys = map[string]bool{"name": true, "extend": true, "desc": true, "default": true, "source": true}

var optionKeys = map[string]bool{
	"depth": true, "min_depth": true, "nested": true, "under": true, "layout": true, "name_template": true,
	"name_from": true, "strip_ext": true, "exclude": true, "preview": true, "preview_skip": true, "skip": true,
	"scope": true, "trim": true,
}

// Builtins are the kinds too irregular to declare, implemented in Go (lib/providers.zsh:417).
var Builtins = map[string]bool{"dir": true}

var Columns = []string{"scope", "env", "region", "name"}

func New() *Config { return &Config{byName: map[string]*Kind{}} }

// Path is $HOP_CONFIG, else ${XDG_CONFIG_HOME:-~/.config}/hop/config.toml.
// - A $HOP_CONFIG ending in .zsh is zsh hop's, which it exports into every child, so it is never read as TOML.
func Path() string {
	if p := os.Getenv("HOP_CONFIG"); p != "" && !strings.HasSuffix(p, ".zsh") {
		return p
	}
	return filepath.Join(configDir(), "config.toml")
}

func configDir() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		if runtime.GOOS == "windows" {
			base, _ = os.UserConfigDir()
		} else {
			base = filepath.Join(os.Getenv("HOME"), ".config")
		}
	}
	return filepath.Join(base, "hop")
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

func RecipeSource(name string) (string, error) {
	b, err := recipeFS.ReadFile("recipes/" + name + ".toml")
	if err != nil {
		return "", fmt.Errorf("no such recipe: %s (recipes: %s)", name, strings.Join(recipeOrder, ", "))
	}
	return string(b), nil
}

func (c *Config) LoadRecipe(name string) error {
	src, err := RecipeSource(name)
	if err != nil {
		return err
	}
	if err := c.Apply(src, "recipe:"+name, false); err != nil {
		return err
	}
	if !slices.Contains(c.Loaded, name) {
		c.Loaded = append(c.Loaded, name)
	}
	return nil
}

// Load reads path; a missing file, or one naming no recipes and declaring no kind, gets DefaultRecipes.
func Load(path string) (*Config, error) {
	c := New()
	c.Path = path
	b, err := os.ReadFile(path)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	named := false
	if err == nil {
		if named, err = c.apply(string(b), path, true); err != nil {
			return nil, err
		}
	} else {
		c.zshHint()
	}
	if !named && len(c.Kinds) == 0 {
		for _, r := range DefaultRecipes {
			if err := c.LoadRecipe(r); err != nil {
				return nil, err
			}
		}
	}
	c.applyEnv()
	return c, nil
}

// zshHint points a zsh hop user at hop import when only their config.zsh exists.
// - HOP_SESSION marks an fzf callback, whose stderr fzf would paint over the picker.
func (c *Config) zshHint() {
	if os.Getenv("HOP_SESSION") != "" {
		return
	}
	if p := os.Getenv("HOP_CONFIG"); p != "" && !strings.HasSuffix(p, ".zsh") {
		return
	}
	if _, err := os.Stat(filepath.Join(configDir(), "config.zsh")); err == nil {
		c.Warnings = append(c.Warnings, "hop: found config.zsh; run 'hop import -o ~/.config/hop/config.toml' to use it")
	}
}

type rawFile struct {
	Version  int              `toml:"version"`
	Recipes  *[]string        `toml:"recipes"`
	Settings map[string]any   `toml:"settings"`
	Kind     []map[string]any `toml:"kind"`
}

// Apply layers one TOML document onto the registry; only a top-level file may name recipes or settings.
func (c *Config) Apply(src, origin string, top bool) error {
	_, err := c.apply(src, origin, top)
	return err
}

// apply reports whether the document set recipes, which opts it out of the zero-config defaults.
func (c *Config) apply(src, origin string, top bool) (bool, error) {
	var rf rawFile
	md, err := toml.Decode(src, &rf)
	if err != nil {
		var pe toml.ParseError
		if errors.As(err, &pe) {
			return false, &Error{origin, pe.Position.Line, pe.Message}
		}
		return false, &Error{origin, 0, err.Error()}
	}
	li := indexLines(src)
	for _, k := range md.Undecoded() {
		if len(k) > 0 && (k[0] == "kind" || k[0] == "settings") {
			continue
		}
		msg := fmt.Sprintf("unknown key %q", k.String())
		if k.String() == "presets" {
			msg = `unknown key "presets": presets are now recipes, as in recipes = ["dir", "project"]`
		}
		return false, &Error{origin, li.line("", k[len(k)-1]), msg}
	}
	if rf.Version > 1 {
		return false, &Error{origin, li.line("", "version"), fmt.Sprintf("version %d is newer than this hop understands", rf.Version)}
	}
	if rf.Recipes != nil {
		if !top {
			return false, &Error{origin, li.line("", "recipes"), "a recipe cannot load recipes"}
		}
		for _, r := range *rf.Recipes {
			if err := c.LoadRecipe(r); err != nil {
				return false, &Error{origin, li.line("", "recipes"), err.Error()}
			}
		}
	}
	for i, raw := range rf.Kind {
		if err := c.applyKind(raw, i, li, origin); err != nil {
			return false, err
		}
	}
	if rf.Settings != nil {
		if !top {
			return false, &Error{origin, li.line("", "settings"), "a recipe cannot hold [settings]"}
		}
		if err := c.applySettings(rf.Settings, li, origin); err != nil {
			return false, err
		}
	}
	return rf.Recipes != nil, nil
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

func asInt(v any, key string, floor int64) (int, error) {
	n, ok := v.(int64)
	if !ok || n < floor {
		if floor == 0 {
			return 0, fmt.Errorf("%s must be a non-negative integer", key)
		}
		return 0, fmt.Errorf("%s must be a positive integer", key)
	}
	return int(n), nil
}

func asTables(v any) ([]map[string]any, bool) {
	switch t := v.(type) {
	case []map[string]any:
		return t, true
	case []any:
		out := make([]map[string]any, 0, len(t))
		for _, e := range t {
			m, ok := e.(map[string]any)
			if !ok {
				return nil, false
			}
			out = append(out, m)
		}
		return out, true
	}
	return nil, false
}

func sortedKeys(m map[string]any) []string {
	keys := make([]string, 0, len(m))
	for key := range m {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

func present(raw map[string]any, keys []string) []string {
	var out []string
	for _, s := range keys {
		if _, ok := raw[s]; ok {
			out = append(out, s)
		}
	}
	return out
}

// ApplyKind declares one kind from a decoded [[kind]] table, as the importer replays hop_kind calls.
func (c *Config) ApplyKind(raw map[string]any, origin string) error {
	return c.applyKind(raw, -1, nil, origin)
}

func (c *Config) applyKind(raw map[string]any, idx int, li *lineIndex, origin string) error {
	nameV, hasName := raw["name"]
	fail := func(src int, key, format string, a ...any) error {
		msg := fmt.Sprintf(format, a...)
		if n, ok := nameV.(string); ok {
			msg = fmt.Sprintf("kind %q: %s", n, msg)
		}
		return &Error{origin, li.kindLine(idx, src, key), msg}
	}
	warn := func(src int, key, msg string) {
		c.Warnings = append(c.Warnings, "hop: warning: "+(&Error{origin, li.kindLine(idx, src, key), msg}).Error())
	}
	if !hasName {
		return fail(-1, "", "a [[kind]] needs a name")
	}
	name, err := asString(nameV, "name")
	if err != nil {
		return fail(-1, "name", "%v", err)
	}
	// dsl.zsh:37 rejects a leading '-'; comma and space are rejected too, since -k and HOP_DEFAULT_KINDS split on them.
	if name == "" || strings.HasPrefix(name, "-") || strings.ContainsAny(name, ", \t\n") {
		return fail(-1, "name", "kind name %q must be non-empty, not start with '-', and hold no comma or space", name)
	}
	extend := false
	if v, ok := raw["extend"]; ok {
		if extend, err = asBool(v, "extend"); err != nil {
			return fail(-1, "extend", "%v", err)
		}
	}
	k := &Kind{Name: name, Depth: 1, Nested: true, Origin: origin}
	if extend {
		old, ok := c.byName[name]
		if !ok {
			return fail(-1, "extend", "extend = true, but no earlier kind %q exists", name)
		}
		cp := *old
		k = &cp
		k.Origin = origin
	}
	if v, ok := raw["desc"]; ok {
		if k.Desc, err = asString(v, "desc"); err != nil {
			return fail(-1, "desc", "%v", err)
		}
	}
	if v, ok := raw["default"]; ok {
		if k.Default, err = asBool(v, "default"); err != nil {
			return fail(-1, "default", "%v", err)
		}
	}
	shapes := present(raw, shapeKeys)
	if srcV, ok := raw["source"]; ok {
		if len(shapes) > 0 {
			return fail(-1, shapes[0], "a kind with [[kind.source]] tables cannot also set %s; move it into a source", shapes[0])
		}
		for _, key := range sortedKeys(raw) {
			switch {
			case optionKeys[key]:
				return fail(-1, key, "%s belongs on each [[kind.source]] when a kind has sources", key)
			case !kindOnlyKeys[key]:
				return fail(-1, key, "unknown key %q", key)
			}
		}
		tables, ok := asTables(srcV)
		if !ok || len(tables) == 0 {
			return fail(-1, "source", "source must be one or more [[kind.source]] tables")
		}
		srcs := make([]*Kind, 0, len(tables))
		for si, t := range tables {
			sfail := func(key, format string, a ...any) error {
				return fail(si, key, "source %d: %s", si+1, fmt.Sprintf(format, a...))
			}
			for _, key := range sortedKeys(t) {
				if kindOnlyKeys[key] {
					return sfail(key, "%s belongs on the [[kind]], not on a source", key)
				}
			}
			if b := present(t, []string{"builtin", "exec"}); len(b) > 0 {
				return sfail(b[0], "a source is dirs, files or marker, not %s", b[0])
			}
			if ss := present(t, sourceShapes); len(ss) != 1 {
				key := ""
				if len(ss) > 1 {
					key = ss[1]
				}
				return sfail(key, "set exactly one of dirs, files or marker")
			}
			s := &Kind{Name: name, Depth: 1, Nested: true, Origin: origin}
			if err := applyShape(s, t, sfail); err != nil {
				return err
			}
			for _, w := range inapplicable(s, t) {
				warn(si, w, fmt.Sprintf("kind %q: source %d: %s has no effect on a %s source", name, si+1, w, s.Shape))
			}
			srcs = append(srcs, s)
		}
		k.Shape, k.Sources = "sources", srcs
		k.Dirs, k.Files, k.Marker, k.Builtin, k.Exec = nil, nil, nil, "", nil
		c.declare(k)
		return nil
	}
	if len(shapes) > 1 {
		return fail(-1, shapes[1], "set exactly one of dirs, files, marker, builtin or exec, not %s", strings.Join(shapes, " and "))
	}
	if len(shapes) == 1 {
		k.Dirs, k.Files, k.Marker, k.Builtin, k.Exec, k.Sources = nil, nil, nil, "", nil, nil
	}
	if err := applyShape(k, raw, func(key, format string, a ...any) error { return fail(-1, key, format, a...) }); err != nil {
		return err
	}
	if k.Shape == "" {
		return fail(-1, "name", "needs one of dirs, files, marker, builtin or exec, or [[kind.source]] tables")
	}
	for _, w := range inapplicable(k, raw) {
		warn(-1, w, fmt.Sprintf("kind %q: %s has no effect on a %s kind", name, w, k.Shape))
	}
	c.declare(k)
	return nil
}

// applyShape reads the shape and per-shape options of a [[kind]] or a [[kind.source]] into k.
func applyShape(k *Kind, raw map[string]any, fail func(key, format string, a ...any) error) error {
	var err error
	for _, key := range sortedKeys(raw) {
		v := raw[key]
		if kindOnlyKeys[key] {
			continue
		}
		if !optionKeys[key] && !slices.Contains(shapeKeys, key) {
			return fail(key, "unknown key %q", key)
		}
		switch key {
		case "dirs":
			k.Dirs, err = asList(v, key)
			k.Shape = "dirs"
		case "files":
			k.Files, err = asList(v, key)
			k.Shape = "files"
		case "marker":
			k.Marker, err = asList(v, key)
			k.Shape = "marker"
			if err == nil {
				err = checkMarkers(k.Marker)
			}
		case "builtin":
			k.Builtin, err = asString(v, key)
			k.Shape = "builtin"
			switch {
			case err != nil:
			case k.Builtin == "helm":
				err = errors.New(`builtin "helm" is gone: use recipes = ["helm"], or run hop import on the config.zsh that declared it to get its exact sources`)
			case !Builtins[k.Builtin]:
				err = fmt.Errorf("unknown builtin %q (the only builtin is dir)", k.Builtin)
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
			k.Depth, err = asInt(v, key, 1)
		case "min_depth":
			k.MinDepth, err = asInt(v, key, 0)
		case "nested":
			k.Nested, err = asBool(v, key)
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
		case "skip":
			k.Skip, err = asList(v, key)
		case "scope":
			k.Scope, err = asString(v, key)
		case "trim":
			k.Trim, err = parseTrim(v)
		}
		if err != nil {
			return fail(key, "%v", err)
		}
	}
	if k.Shape != "marker" && k.Shape != "" {
		if p := present(raw, []string{"min_depth", "nested"}); len(p) > 0 {
			return fail(p[0], "%s applies only to a marker shape, not to %s", p[0], k.Shape)
		}
	}
	return nil
}

// checkMarkers allows basename globs and relative paths, never one that names the root or climbs out of a dir.
func checkMarkers(ms []string) error {
	if len(ms) == 0 {
		return errors.New("marker needs at least one file name")
	}
	for _, m := range ms {
		for _, s := range strings.Split(m, "/") {
			if s == "" || s == "." || s == ".." || s == "**" {
				return fmt.Errorf("marker %q must be a relative path with no empty, '.', '..' or '**' segment", m)
			}
		}
	}
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

// parseTrim takes { scope = "team-", env = ["env-", "e-"] }; a list applies its prefixes in order.
func parseTrim(v any) ([]TrimSpec, error) {
	m, ok := v.(map[string]any)
	if !ok {
		return nil, errors.New(`trim must be a table like { scope = "team-" }`)
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
		"marker":  {"under", "layout", "name_template", "exclude", "preview", "preview_skip", "scope", "trim", "min_depth", "nested"},
		"builtin": {"skip", "preview"},
		"exec":    {"preview", "preview_skip"},
	}[k.Shape]
	ok := map[string]bool{}
	for key := range kindOnlyKeys {
		ok[key] = true
	}
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
		b.WriteString(kindKey(k))
		b.WriteByte(';')
	}
	return b.String()
}

func kindKey(k *Kind) string {
	cp := *k
	cp.Origin = ""
	srcs := make([]string, len(cp.Sources))
	for i, s := range cp.Sources {
		srcs[i] = kindKey(s)
	}
	cp.Sources = nil
	return fmt.Sprintf("%+v sources=[%s]", cp, strings.Join(srcs, " | "))
}
