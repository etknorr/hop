// Package importer is `hop import`: zsh replays config.zsh, and Go re-parses every hop_kind call.
package importer

import (
	"bytes"
	_ "embed"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/BurntSushi/toml"
	"github.com/etknorr/hop/internal/config"
)

var shapeKeys = []string{"dirs", "files", "marker", "builtin", "exec"}

func splitNonEmpty(s, sep string) []string { return config.SplitNonEmpty(s, sep) }

//go:embed share/import.zsh
var importZsh []byte

//go:embed v031/presets.toml
var v031Presets []byte

type frozen struct {
	EnvColors map[string][]string `toml:"env_colors"`
	Preset    []struct {
		Name string
		Kind []map[string]any
	}
}

var v031 = func() frozen {
	var f frozen
	if _, err := toml.Decode(string(v031Presets), &f); err != nil {
		panic("importer: v031/presets.toml: " + err.Error())
	}
	return f
}()

// PresetOrder is the order hop.zsh:37 loads presets in when a config declares no kind.
func PresetOrder() []string {
	out := make([]string, len(v031.Preset))
	for i, p := range v031.Preset {
		out[i] = p.Name
	}
	return out
}

// LoadPreset declares 0.3.1's own definition of preset name into c.
func LoadPreset(c *config.Config, name string) error {
	for _, p := range v031.Preset {
		if p.Name != name {
			continue
		}
		for _, k := range p.Kind {
			if err := c.ApplyKind(k, "v0.3.1:"+name); err != nil {
				return err
			}
		}
		return nil
	}
	return fmt.Errorf("no such preset: %s", name)
}

func presetKind(name, kind string) map[string]any {
	for _, p := range v031.Preset {
		if p.Name != name {
			continue
		}
		for _, k := range p.Kind {
			if k["name"] == kind {
				return k
			}
		}
	}
	panic("importer: v031 has no kind " + kind + " in preset " + name)
}

type event struct {
	typ  string
	args []string
}

func runDumper(cfg string) ([]event, error) {
	tmp, err := os.CreateTemp("", "hop-import-*.zsh")
	if err != nil {
		return nil, err
	}
	defer os.Remove(tmp.Name())
	tmp.Write(importZsh)
	tmp.Close()
	r, w, err := os.Pipe()
	if err != nil {
		return nil, err
	}
	cmd := exec.Command("zsh", "-f", tmp.Name(), cfg)
	cmd.ExtraFiles = []*os.File{w}
	cmd.Stdout = os.Stderr
	cmd.Stderr = os.Stderr
	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("zsh is needed to read %s: %w", cfg, err)
	}
	w.Close()
	var buf bytes.Buffer
	buf.ReadFrom(r)
	if err := cmd.Wait(); err != nil {
		return nil, fmt.Errorf("sourcing %s failed: %w", cfg, err)
	}
	toks := strings.Split(buf.String(), "\x00")
	var evs []event
	for i := 0; i+1 < len(toks); {
		n, err := strconv.Atoi(toks[i+1])
		if err != nil || i+2+n > len(toks) {
			return nil, fmt.Errorf("corrupt import record at token %d", i)
		}
		evs = append(evs, event{toks[i], toks[i+2 : i+2+n]})
		i += 2 + n
	}
	return evs, nil
}

// parseHopKind is dsl.zsh:34-96, emitting a TOML-shaped decl instead of filling the registry.
// - An --fn kind ignores every shape option in zsh hop, so its decl keeps only name, desc and default.
func parseHopKind(argv []string) (map[string]any, []string, error) {
	var warn []string
	if len(argv) == 0 || argv[0] == "" || strings.HasPrefix(argv[0], "-") {
		return nil, nil, fmt.Errorf("hop_kind: first argument must be a kind name")
	}
	name := argv[0]
	d := map[string]any{"name": name}
	var layouts []string
	depth := "1"
	shapes := 0
	fn := ""
	setShape := func(key string, v any) {
		for _, s := range shapeKeys {
			delete(d, s)
		}
		delete(d, "fn")
		fn = ""
		d[key] = v
		shapes++
	}
	a := argv[1:]
	for len(a) > 0 {
		opt := a[0]
		if opt != "--default" && opt != "--strip-ext" && strings.HasPrefix(opt, "--") && len(a) < 2 {
			return nil, nil, fmt.Errorf("hop_kind %s: %s needs a value", name, opt)
		}
		val := ""
		if len(a) > 1 {
			val = a[1]
		}
		step := 2
		switch opt {
		case "--default":
			d["default"] = true
			step = 1
		case "--strip-ext":
			d["strip_ext"] = true
			step = 1
		case "--desc":
			d["desc"] = val
		case "--dirs":
			setShape("dirs", splitNonEmpty(val, ","))
		case "--depth":
			depth = val
		case "--files":
			setShape("files", splitNonEmpty(val, ","))
		case "--marker":
			setShape("marker", val)
		case "--under":
			d["under"] = strings.TrimSuffix(val, "/")
		case "--layout":
			layouts = append(layouts, val)
		case "--name-template":
			d["name_template"] = val
		case "--name-fn":
			if val != "_hop_entity_name" {
				return nil, nil, fmt.Errorf("kind %s: --name-fn %s has no hop equivalent; only _hop_entity_name does, as name_from = \"yaml:metadata.name\"", name, val)
			}
			d["name_from"] = "yaml:metadata.name"
		case "--exclude":
			d["exclude"] = splitNonEmpty(val, ",")
		case "--preview":
			d["preview"] = splitNonEmpty(val, ",")
		case "--preview-skip":
			d["preview_skip"] = splitNonEmpty(val, ",")
		case "--scope-literal":
			d["scope"] = val
		case "--trim":
			t := map[string]any{}
			for _, spec := range splitNonEmpty(val, ",") {
				col, pre, ok := strings.Cut(spec, ":")
				if !ok {
					continue
				}
				switch col {
				case "scope", "env", "region", "name":
					if old, ok := t[col]; ok {
						t[col] = append(toList(old), pre)
					} else {
						t[col] = pre
					}
				default:
					warn = append(warn, fmt.Sprintf("kind %s: --trim column %q is ignored by hop and was dropped", name, col))
				}
			}
			d["trim"] = t
		case "--fn":
			switch val {
			case "_hop_provider_dir", "_hop_provider_helm":
				setShape("fn", val)
				fn = val
			default:
				return nil, nil, fmt.Errorf("kind %s: --fn %s has no hop equivalent: rewrite it as an exec kind printing rows", name, val)
			}
		default:
			return nil, nil, fmt.Errorf("hop_kind %s: unknown option: %s", name, opt)
		}
		a = a[step:]
	}
	if shapes == 0 {
		return nil, nil, fmt.Errorf("hop_kind %s: needs one of --dirs, --files, --marker or --fn", name)
	}
	n, err := strconv.Atoi(depth)
	if err != nil || n < 1 || strings.TrimLeft(depth, "0123456789") != "" {
		return nil, nil, fmt.Errorf("hop_kind %s: --depth must be a positive integer", name)
	}
	if fn != "" {
		out := map[string]any{"name": name}
		for _, key := range []string{"desc", "default"} {
			if v, ok := d[key]; ok {
				out[key] = v
			}
		}
		if fn == "_hop_provider_dir" {
			out["builtin"] = "dir"
		} else {
			out["source"] = presetKind("helm", "helm")["source"]
		}
		return out, warn, nil
	}
	if n != 1 {
		d["depth"] = int64(n)
	}
	if len(layouts) > 0 {
		d["layout"] = layouts
	}
	return d, warn, nil
}

func toList(v any) []string {
	switch t := v.(type) {
	case string:
		return []string{t}
	case []string:
		return t
	}
	return nil
}

func tildePath(p string) string {
	abs, err := filepath.Abs(p)
	if err != nil {
		return p
	}
	if h := os.Getenv("HOME"); h != "" && strings.HasPrefix(abs, h+"/") {
		return "~" + abs[len(h):]
	}
	return abs
}

// kindDecl renders a resolved Kind back into decl form, the shape a [[kind]] table decodes to.
func kindDecl(k *config.Kind, top bool) map[string]any {
	d := map[string]any{}
	if top {
		d["name"] = k.Name
		if k.Desc != "" {
			d["desc"] = k.Desc
		}
		if k.Default {
			d["default"] = true
		}
	}
	switch k.Shape {
	case "dirs":
		d["dirs"] = k.Dirs
	case "files":
		d["files"] = k.Files
	case "marker":
		if len(k.Marker) == 1 {
			d["marker"] = k.Marker[0]
		} else {
			d["marker"] = k.Marker
		}
	case "builtin":
		d["builtin"] = k.Builtin
	case "exec":
		d["exec"] = k.Exec
	case "sources":
		srcs := make([]map[string]any, len(k.Sources))
		for i, s := range k.Sources {
			srcs[i] = kindDecl(s, false)
		}
		d["source"] = srcs
		return d
	}
	if k.Depth != 1 {
		d["depth"] = int64(k.Depth)
	}
	if k.MinDepth != 0 {
		d["min_depth"] = int64(k.MinDepth)
	}
	if !k.Nested {
		d["nested"] = false
	}
	if k.Under != "" {
		d["under"] = k.Under
	}
	if len(k.Layouts) > 0 {
		d["layout"] = k.Layouts
	}
	if k.NameTemplate != "" {
		d["name_template"] = k.NameTemplate
	}
	if k.NameFrom != "" {
		d["name_from"] = k.NameFrom
	}
	if k.StripExt {
		d["strip_ext"] = true
	}
	if len(k.Exclude) > 0 {
		d["exclude"] = k.Exclude
	}
	if len(k.Preview) > 0 {
		d["preview"] = k.Preview
	}
	if len(k.PreviewSkip) > 0 {
		d["preview_skip"] = k.PreviewSkip
	}
	if k.Skip != nil {
		d["skip"] = k.Skip
	}
	if k.Scope != "" {
		d["scope"] = k.Scope
	}
	if len(k.Trim) > 0 {
		t := map[string]any{}
		for _, s := range k.Trim {
			if old, ok := t[s.Col]; ok {
				t[s.Col] = append(toList(old), s.Prefix)
			} else {
				t[s.Col] = s.Prefix
			}
		}
		d["trim"] = t
	}
	return d
}

type Result struct {
	Kinds    []map[string]any
	Settings map[string]string
	Warnings []string
}

// Import replays the recorded calls in zsh hop's order and flattens them into complete [[kind]] tables.
// - hop_preset inlines 0.3.1's definition, so a recipe changed later never moves an imported config's rows.
// - A redeclared kind replaces the earlier one in its menu slot, as hop_kind does, so the output needs no extend.
// - The result is verified by loading it back: a mismatch with the replay is an error, never a silent change.
func Import(cfg string) (*Result, error) {
	evs, err := runDumper(cfg)
	if err != nil {
		return nil, err
	}
	res := &Result{Settings: map[string]string{}}
	replay := config.New()
	for _, e := range evs {
		switch e.typ {
		case "preset":
			if err := LoadPreset(replay, e.args[0]); err != nil {
				return nil, fmt.Errorf("hop_preset: %w", err)
			}
		case "kind":
			d, warn, err := parseHopKind(e.args)
			if err != nil {
				return nil, err
			}
			res.Warnings = append(res.Warnings, warn...)
			if err := replay.ApplyKind(toTomlish(d), cfg); err != nil {
				return nil, err
			}
		case "set":
			if e.args[0] == "HOP_HOPRC" {
				res.Warnings = append(res.Warnings, fmt.Sprintf("HOP_HOPRC=%s is not carried over: hop never reads a repo's .hoprc", e.args[1]))
				continue
			}
			if bad := invalidSetting(e.args[0], e.args[1]); bad != "" {
				res.Warnings = append(res.Warnings, bad)
				continue
			}
			res.Settings[e.args[0]] = e.args[1]
		case "orphan":
			switch f := e.args[0]; f {
			case "_hop_provider_helm", "_hop_provider_dir", "_hop_provider_repo", "_hop_provider_ws":
			default:
				res.Warnings = append(res.Warnings, fmt.Sprintf("%s is a provider function, which hop cannot run; zsh hop listed it as kind %s, so declare that kind with exec if you still want it", f, strings.TrimPrefix(f, "_hop_provider_")))
			}
		}
	}
	if len(replay.Kinds) == 0 {
		for _, p := range PresetOrder() {
			LoadPreset(replay, p)
		}
	}
	for _, k := range replay.Kinds {
		res.Kinds = append(res.Kinds, kindDecl(k, true))
	}
	text := res.TOML(cfg)
	got := config.New()
	if err := got.Apply(text, "imported", true); err != nil {
		return nil, fmt.Errorf("imported config does not load: %w\n%s", err, text)
	}
	if a, b := replay.RegistryKey(), got.RegistryKey(); a != b {
		return nil, fmt.Errorf("imported config differs from zsh hop's registry\nzsh hop: %s\nhop:     %s", a, b)
	}
	return res, nil
}

// invalidSetting is the warning for a value zsh hop would have warned about and replaced, which hop's [settings] rejects.
func invalidSetting(name, val string) string {
	var ok []string
	switch name {
	case "HOP_ACTION":
		ok = config.Actions
	case "HOP_JUMP":
		ok = config.Jumps
	default:
		return ""
	}
	for _, v := range ok {
		if v == val {
			return ""
		}
	}
	return fmt.Sprintf("%s=%s is not one of %s, so zsh hop ignored it; it is not carried over", name, val, strings.Join(ok, ", "))
}

func toTomlish(d map[string]any) map[string]any {
	out := map[string]any{}
	for k, v := range d {
		switch t := v.(type) {
		case []string:
			l := make([]any, len(t))
			for i, s := range t {
				l[i] = s
			}
			out[k] = l
		case map[string]any:
			out[k] = toTomlish(t)
		default:
			out[k] = v
		}
	}
	return out
}

var keyOrder = []string{"name", "desc", "default", "marker", "dirs", "files", "builtin", "exec", "depth", "min_depth", "nested", "under", "layout", "trim", "name_template", "name_from", "strip_ext", "exclude", "scope", "preview", "preview_skip", "skip"}

func tq(s string) string {
	if !strings.ContainsAny(s, "'\n\r") {
		return "'" + s + "'"
	}
	return strconv.Quote(s)
}

func tv(v any) string {
	switch t := v.(type) {
	case string:
		return tq(t)
	case bool:
		return strconv.FormatBool(t)
	case int64:
		return strconv.FormatInt(t, 10)
	case []string:
		q := make([]string, len(t))
		for i, s := range t {
			q[i] = tq(s)
		}
		return "[" + strings.Join(q, ", ") + "]"
	case map[string]any:
		var parts []string
		for _, c := range []string{"scope", "env", "region", "name"} {
			if x, ok := t[c]; ok {
				parts = append(parts, c+" = "+tv(x))
			}
		}
		return "{ " + strings.Join(parts, ", ") + " }"
	}
	return fmt.Sprintf("%q", fmt.Sprint(v))
}

var settingKey = map[string]string{
	"HOP_ACTION": "action", "HOP_JUMP": "jump", "HOP_CODE": "code", "HOP_CLIPBOARD": "clipboard",
	"HOP_FZF_HEIGHT": "fzf_height", "HOP_VIM": "vim", "HOP_HIST_MAX": "hist_max",
	"HOP_DEFAULT_KINDS": "default_kinds", "HOP_WORKSPACES": "workspaces", "HOP_REPOS": "repos",
	"HOP_HISTFILE": "hist_file", "HOP_WORKSPACES_FILE": "workspaces_file", "HOP_DEBUG": "debug",
	"HOP_DEBUG_LOG": "debug_log", "HOP_GUARD_WINDOW": "guard_window", "HOP_FZF_MIN": "fzf_min",
}

func envColors() string {
	var parts []string
	for _, cls := range config.EnvClasses {
		parts = append(parts, cls+" = "+tv(v031.EnvColors[cls]))
	}
	return "{ " + strings.Join(parts, ", ") + " }"
}

func (r *Result) TOML(cfg string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "# hop config, imported from %s by `hop import`.\n", tildePath(cfg))
	b.WriteString("# Every kind is written out in full, so no recipe change can move these rows.\n")
	b.WriteString("version = 1\nrecipes = []\n")
	b.WriteString("\n[settings]\n")
	vars := make([]string, 0, len(r.Settings))
	for v := range r.Settings {
		vars = append(vars, v)
	}
	sort.Strings(vars)
	for _, v := range vars {
		val := r.Settings[v]
		switch v {
		case "HOP_VIM":
			fmt.Fprintf(&b, "%s = %t\n", settingKey[v], val != "0")
		case "HOP_DEBUG":
			fmt.Fprintf(&b, "%s = %t\n", settingKey[v], val != "")
		case "HOP_HIST_MAX":
			fmt.Fprintf(&b, "%s = %s\n", settingKey[v], val)
		case "HOP_DEFAULT_KINDS":
			fmt.Fprintf(&b, "%s = %s\n", settingKey[v], tv(strings.Fields(strings.ReplaceAll(val, ",", " "))))
		case "HOP_WORKSPACES", "HOP_REPOS":
			fmt.Fprintf(&b, "%s = %s\n", settingKey[v], tv(splitNonEmpty(val, ":")))
		default:
			fmt.Fprintf(&b, "%s = %s\n", settingKey[v], tq(val))
		}
	}
	fmt.Fprintf(&b, "env_colors = %s\n", envColors())
	for _, d := range r.Kinds {
		b.WriteString("\n[[kind]]\n")
		writeKeys(&b, d, "")
		srcs, _ := d["source"].([]map[string]any)
		for _, s := range srcs {
			b.WriteString("\n  [[kind.source]]\n")
			writeKeys(&b, s, "  ")
		}
	}
	return b.String()
}

func writeKeys(b *strings.Builder, d map[string]any, indent string) {
	for _, key := range keyOrder {
		if v, ok := d[key]; ok {
			fmt.Fprintf(b, "%s%s = %s\n", indent, key, tv(v))
		}
	}
}
