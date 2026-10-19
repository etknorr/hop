package rows

import (
	"slices"
	"strings"
	"unicode/utf8"
)

// hop 0.3.0's column caps and floors (lib/providers.zsh:24-34 at v0.3.1).
const (
	CapName   = 56
	MinName   = 20
	FitName   = 28
	CapKind   = 5
	MinKind   = 4
	CapScope  = 22
	CapEnv    = 9
	CapRegion = 14
)

// Widths are one list's five column widths: name, kind, scope, env, region. A 0 drops that column.
type Widths [5]int

// List is _hop_layout: rs rendered as one list whose columns line up, each as wide as its longest value up to a cap.
// - like, when non-nil, gives the widths instead, so rows added to a list later line up with it.
func List(rs []Row, root string, like *Widths) []string {
	out := make([]string, len(rs))
	if len(rs) == 0 {
		return out
	}
	norm := make([]Row, len(rs))
	cols := make([][5]string, len(rs))
	for i, r := range rs {
		r = New(r.Kind, r.Scope, r.Env, r.Region, r.Name, r.Dir, r.Preview, r.File)
		cols[i] = [5]string{us(r.Name), us(r.Kind), us(r.Scope), us(r.Env), us(r.Region)}
		norm[i] = r
	}
	w := widths(cols)
	if like != nil {
		w = *like
	}
	cells := make([]map[string]string, 5)
	for c := range 5 {
		cells[c] = map[string]string{}
	}
	var b strings.Builder
	for i, r := range norm {
		b.Reset()
		for c := range 5 {
			v := cols[i][c]
			if w[c] == 0 {
				b.WriteString(Off)
				continue
			}
			cell, ok := cells[c][v]
			if !ok {
				cell = format(c, v, w[c])
				cells[c][v] = cell
			}
			b.WriteString(cell)
		}
		b.WriteString("\t" + r.Dir + "\t" + r.Preview + "\t" + CDim + Rel(r, root) + Off)
		out[i] = b.String()
	}
	return out
}

// us is _hop_row_raw's guard: a unit separator inside a value would add a cell, so it reads as `?`.
func us(s string) string { return strings.ReplaceAll(s, "\x1f", "?") }

// widths is _hop_layout's width rule, over each column's distinct values.
// - The name is its longest, but past FitName it fits 95% of the distinct names, capped at CapName and floored at MinName.
// - Scope, env and region drop out when every value is `-`; the kind is at least MinKind.
func widths(cols [][5]string) Widths {
	caps := [5]int{CapName, CapKind, CapScope, CapEnv, CapRegion}
	var w Widths
	for c := range 5 {
		seen := map[string]bool{}
		var lens []int
		for _, row := range cols {
			if v := row[c]; !seen[v] {
				seen[v] = true
				lens = append(lens, utf8.RuneCountInString(v))
			}
		}
		if c > 1 && len(seen) == 1 && seen["-"] {
			continue
		}
		slices.SortFunc(lens, func(a, b int) int { return b - a })
		n := lens[0]
		switch c {
		case 0:
			if n > FitName {
				n = max(lens[len(lens)/20], FitName)
			}
			n = max(min(n, caps[c]), MinName)
		default:
			n = min(n, caps[c])
			if c == 1 {
				n = max(n, MinKind)
			}
		}
		w[c] = n
	}
	return w
}

// format is one cell: clipped to n, padded, coloured on the whole value, and closed with a reset.
// - The name keeps both ends around `…`, the scope keeps its end, and the rest keep their start.
// - Every column after the name opens with the space that separates it.
func format(c int, v string, n int) string {
	r := []rune(v)
	clipped := v
	if len(r) > n {
		switch c {
		case 0:
			h := n / 2
			clipped = string(r[:h]) + "…" + string(r[len(r)-(n-h-1):])
		case 2:
			clipped = "…" + string(r[len(r)-(n-1):])
		default:
			clipped = string(r[:n-1]) + "…"
		}
	}
	var b strings.Builder
	switch c {
	case 0:
		b.WriteString(CName)
	case 1:
		b.WriteString(" " + CKind)
	case 2:
		b.WriteString(" ")
		if v == "-" {
			b.WriteString(CDim)
		} else {
			b.WriteString(CScope)
		}
	case 3:
		b.WriteString(" " + envColour(v))
	case 4:
		b.WriteString(" ")
		if v == "-" {
			b.WriteString(CDim)
		} else {
			b.WriteString(CReg)
		}
	}
	pad(&b, clipped, n)
	b.WriteString(Off)
	return b.String()
}

// ParseWidths is _hop_lay_parse: the widths a laid-out row was padded to, read back from its resets.
// - It fails on a row without five reset-closed cells or with no name or kind width, so the caller lays out on its own.
func ParseWidths(line string) (Widths, bool) {
	var w Widths
	disp, _, _ := strings.Cut(line, "\t")
	cells := strings.Split(disp, Off)
	if len(cells) != 6 {
		return w, false
	}
	for c := range 5 {
		s := StripANSI(cells[c])
		if c > 0 {
			s = strings.TrimPrefix(s, " ")
		}
		w[c] = utf8.RuneCountInString(s)
	}
	return w, w[0] > 0 && w[1] > 0
}
