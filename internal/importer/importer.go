// Package importer is `hop config import`: zsh replays config.zsh, and Go re-parses every hop_kind call.
package importer

import (
	"bytes"
	_ "embed"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"sort"
	"strconv"
	"strings"

	"github.com/etknorr/hop/internal/config"
)

var shapeKeys = []string{"dirs", "files", "marker", "builtin", "exec"}

func splitNonEmpty(s, sep string) []string { return config.SplitNonEmpty(s, sep) }

//go:embed share/import.zsh
var importZsh []byte

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
func parseHopKind(argv []string, fns map[string]bool, cfg string) (map[string]any, []string, error) {
	var warn []string
	if len(argv) == 0 || argv[0] == "" || strings.HasPrefix(argv[0], "-") {
		return nil, nil, fmt.Errorf("hop_kind: first argument must be a kind name")
	}
	name := argv[0]
	d := map[string]any{"name": name}
	var layouts []string
	depth := "1"
	shapes := 0
	setShape := func(key string, v any) {
		for _, s := range shapeKeys {
			delete(d, s)
		}
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
			if val == "_hop_entity_name" {
				d["name_from"] = "yaml:metadata.name"
			} else {
				warn = append(warn, fmt.Sprintf("kind %s: --name-fn %s has no hop equivalent and was dropped", name, val))
			}
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
			switch {
			case val == "_hop_provider_helm":
				setShape("builtin", "helm")
			case val == "_hop_provider_dir":
				setShape("builtin", "dir")
			case !fns[val]:
				return nil, nil, fmt.Errorf("hop_kind %s: --fn %s is not a defined function", name, val)
			default:
				setShape("exec", []string{"zsh", "-fc", `source "$HOP_COMPAT" && source "$1" && "$2" "$HOP_ROOT"`, "hop-compat", tildePath(cfg), val})
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
func kindDecl(k *config.Kind) map[string]any {
	d := map[string]any{"name": k.Name}
	if k.Desc != "" {
		d["desc"] = k.Desc
	}
	if k.Default {
		d["default"] = true
	}
	switch k.Shape {
	case "dirs":
		d["dirs"] = k.Dirs
	case "files":
		d["files"] = k.Files
	case "marker":
		d["marker"] = k.Marker
	case "builtin":
		d["builtin"] = k.Builtin
	case "exec":
		d["exec"] = k.Exec
	}
	if k.Depth != 1 {
		d["depth"] = int64(k.Depth)
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

// normalise drops zero values so a decl and a rendered Kind compare equal when they mean the same thing.
func normalise(d map[string]any) map[string]any {
	out := map[string]any{}
	for k, v := range d {
		switch t := v.(type) {
		case []string:
			if len(t) == 0 {
				continue
			}
		case string:
			if t == "" && k != "scope" {
				continue
			}
		case map[string]any:
			if len(t) == 0 {
				continue
			}
		}
		out[k] = v
	}
	return out
}

type Result struct {
	Presets  []string
	Decls    []map[string]any
	Settings map[string]string
	Warnings []string
}

// Import replays the recorded calls in hop's order, then re-expresses them as presets plus [[kind]] tables.
// - A redeclared preset kind becomes `extend = true` with only the changed keys, when nothing was removed.
// - The result is verified by loading it back: a mismatch with the replay is an error, never a silent change.
func Import(cfg string) (*Result, error) {
	evs, err := runDumper(cfg)
	if err != nil {
		return nil, err
	}
	res := &Result{Settings: map[string]string{}}
	fns := map[string]bool{}
	referenced := map[string]bool{}
	for _, e := range evs {
		if e.typ == "fn" {
			fns[e.args[0]] = fns[e.args[0]] || e.args[1] == "1"
		}
	}
	replay := config.New()
	presetKinds := map[string]map[string]any{}
	seenPreset := map[string]bool{}
	for _, e := range evs {
		switch e.typ {
		case "preset":
			p := e.args[0]
			if err := replay.LoadPreset(p); err != nil {
				return nil, fmt.Errorf("hop_preset: %w", err)
			}
			if !seenPreset[p] {
				seenPreset[p] = true
				res.Presets = append(res.Presets, p)
			}
			for _, k := range replay.Kinds {
				if k.Origin == "preset:"+p {
					presetKinds[k.Name] = normalise(kindDecl(k))
				}
			}
		case "kind":
			d, warn, err := parseHopKind(e.args, fns, cfg)
			if err != nil {
				return nil, err
			}
			res.Warnings = append(res.Warnings, warn...)
			if ex, ok := d["exec"].([]string); ok {
				referenced[ex[len(ex)-1]] = true
			}
			if err := replay.ApplyKind(toTomlish(d), cfg); err != nil {
				return nil, err
			}
			res.Decls = append(res.Decls, d)
		case "set":
			res.Settings[e.args[0]] = e.args[1]
		case "orphan":
			f := e.args[0]
			switch f {
			case "_hop_provider_helm", "_hop_provider_dir", "_hop_provider_repo", "_hop_provider_ws":
			default:
				if !referenced[f] {
					res.Warnings = append(res.Warnings, fmt.Sprintf("%s is a bare provider function with no hop_kind; zsh hop ran it as kind %s, and hop needs a [[kind]] with exec", f, strings.TrimPrefix(f, "_hop_provider_")))
				}
			}
		}
	}
	if len(replay.Kinds) == 0 {
		res.Presets = nil
		replay.LoadAllPresets()
	}
	// Collapse a redeclared preset kind to the keys that changed.
	for i, d := range res.Decls {
		name := d["name"].(string)
		base, ok := presetKinds[name]
		if !ok {
			continue
		}
		nd := normalise(d)
		removed := false
		for key := range base {
			if _, ok := nd[key]; !ok {
				removed = true
			}
		}
		if removed {
			continue
		}
		ext := map[string]any{"name": name, "extend": true}
		for key, v := range nd {
			if key != "name" && !reflect.DeepEqual(v, base[key]) {
				ext[key] = v
			}
		}
		res.Decls[i] = ext
	}
	text := res.TOML(cfg)
	got := config.New()
	if err := got.Apply(text, "imported", true); err != nil {
		return nil, fmt.Errorf("imported config does not load: %w\n%s", err, text)
	}
	if len(got.Kinds) == 0 {
		got.LoadAllPresets()
	}
	if a, b := replay.RegistryKey(), got.RegistryKey(); a != b {
		return nil, fmt.Errorf("imported config differs from hop's registry; config.zsh probably declares a kind before the hop_preset that overrides it\nzsh hop: %s\nhop:     %s", a, b)
	}
	return res, nil
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

var keyOrder = []string{"name", "extend", "desc", "default", "marker", "dirs", "files", "builtin", "exec", "depth", "under", "layout", "trim", "name_template", "name_from", "strip_ext", "exclude", "scope", "preview", "preview_skip"}

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
}

func (r *Result) TOML(cfg string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "# hop config, imported from %s by `hop config import`.\n", tildePath(cfg))
	b.WriteString("version = 1\n")
	if r.Presets != nil {
		fmt.Fprintf(&b, "presets = %s\n", tv(r.Presets))
	}
	if len(r.Settings) > 0 {
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
	}
	for _, d := range r.Decls {
		b.WriteString("\n[[kind]]\n")
		for _, key := range keyOrder {
			if v, ok := d[key]; ok {
				fmt.Fprintf(&b, "%s = %s\n", key, tv(v))
			}
		}
	}
	return b.String()
}
