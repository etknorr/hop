// Package collate approximates the en_US.UTF-8 order zsh's (o) sort and glob expansion use on macOS.
// - Three levels, as in ISO 14651: base character, then accent, then case with lowercase first.
// - Punctuation is not ignored; it sorts before digits, in the order asciiOrder lists.
// - Only ASCII and Latin-1 letters are modelled; any other rune sorts after them by code point.
package collate

import (
	"sort"
	"strings"
)

const asciiOrder = " _-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~$0123456789abcdefghijklmnopqrstuvwxyz"

var primary [128]int

func init() {
	for i := range asciiOrder {
		primary[asciiOrder[i]] = i + 1
	}
	for c := 'A'; c <= 'Z'; c++ {
		primary[c] = primary[c+'a'-'A']
	}
}

// latin1 maps an accented letter to its base and an accent rank; ß expands to ss.
var latin1 = map[rune]struct {
	base   string
	accent int
}{
	'à': {"a", 2}, 'á': {"a", 1}, 'â': {"a", 3}, 'ã': {"a", 5}, 'ä': {"a", 4}, 'å': {"a", 6},
	'ç': {"c", 1}, 'è': {"e", 2}, 'é': {"e", 1}, 'ê': {"e", 3}, 'ë': {"e", 4},
	'ì': {"i", 2}, 'í': {"i", 1}, 'î': {"i", 3}, 'ï': {"i", 4}, 'ñ': {"n", 5},
	'ò': {"o", 2}, 'ó': {"o", 1}, 'ô': {"o", 3}, 'õ': {"o", 5}, 'ö': {"o", 4}, 'ø': {"o", 7},
	'ù': {"u", 2}, 'ú': {"u", 1}, 'û': {"u", 3}, 'ü': {"u", 4}, 'ý': {"y", 1}, 'ÿ': {"y", 4},
	'ß': {"ss", 1},
}

type key struct{ p, s, t []int }

func keyOf(str string) key {
	var k key
	for _, r := range str {
		upper := 0
		lr := r
		if r >= 'A' && r <= 'Z' {
			upper, lr = 1, r+'a'-'A'
		} else if r >= 'À' && r <= 'Þ' && r != '×' {
			upper, lr = 1, r+32
		}
		switch {
		case lr < 128:
			k.p = append(k.p, primary[lr])
			k.s = append(k.s, 0)
		case latin1[lr].base != "":
			e := latin1[lr]
			for _, b := range e.base {
				k.p = append(k.p, primary[b])
				k.s = append(k.s, e.accent)
			}
		default:
			k.p = append(k.p, 1000+int(lr))
			k.s = append(k.s, 0)
		}
		k.t = append(k.t, upper)
	}
	return k
}

func cmpInts(a, b []int) int {
	for i := 0; i < len(a) && i < len(b); i++ {
		if a[i] != b[i] {
			if a[i] < b[i] {
				return -1
			}
			return 1
		}
	}
	return len(a) - len(b)
}

// Compare orders a and b by base characters, then accents, then case, then bytes.
func Compare(a, b string) int {
	ka, kb := keyOf(a), keyOf(b)
	if c := cmpInts(ka.p, kb.p); c != 0 {
		return c
	}
	if c := cmpInts(ka.s, kb.s); c != 0 {
		return c
	}
	if c := cmpInts(ka.t, kb.t); c != 0 {
		return c
	}
	return strings.Compare(a, b)
}

// Sort sorts in place, ascending, the way zsh's (o) does.
func Sort(ss []string) {
	sort.SliceStable(ss, func(i, j int) bool { return Compare(ss[i], ss[j]) < 0 })
}
