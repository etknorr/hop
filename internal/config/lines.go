package config

import (
	"regexp"
	"strings"
)

// lineIndex maps a key to its source line, which BurntSushi/toml does not expose for array tables.
// - It is a line scan, not a parser: a key inside an inline table or a multi-line string is not found.
// - An unfound key reports the line of its [[kind]] or [[kind.source]] header, which still points at the right table.
type lineIndex struct {
	keys    map[lineKey]int
	headers []int
	sources [][]int
}

type lineKey struct {
	section string
	kind    int
	src     int
	key     string
}

var (
	reHeader = regexp.MustCompile(`^\s*\[\[?\s*([A-Za-z0-9_.-]+)\s*\]\]?`)
	reKey    = regexp.MustCompile(`^\s*("[^"]*"|'[^']*'|[A-Za-z0-9_-]+)\s*=`)
)

func indexLines(src string) *lineIndex {
	li := &lineIndex{keys: map[lineKey]int{}}
	section, kind, source := "", -1, -1
	for n, line := range strings.Split(src, "\n") {
		ln := n + 1
		if m := reHeader.FindStringSubmatch(line); m != nil && !reKey.MatchString(line) {
			section = m[1]
			array := strings.Contains(line, "[[")
			switch {
			case section == "kind" && array:
				kind++
				source = -1
				li.headers = append(li.headers, ln)
				li.sources = append(li.sources, nil)
			case section == "kind.source" && array && kind >= 0:
				source++
				li.sources[kind] = append(li.sources[kind], ln)
			}
			continue
		}
		if m := reKey.FindStringSubmatch(line); m != nil {
			k := lineKey{section, -1, -1, strings.Trim(m[1], `"'`)}
			switch section {
			case "kind":
				k.kind = kind
			case "kind.source":
				k.section, k.kind, k.src = "kind", kind, source
			}
			if _, ok := li.keys[k]; !ok {
				li.keys[k] = ln
			}
		}
	}
	return li
}

// kindLine is the line of key in the i-th [[kind]] (or its src-th source, when src >= 0), else the table's header, else 0.
func (li *lineIndex) kindLine(i, src int, key string) int {
	if li == nil {
		return 0
	}
	if ln, ok := li.keys[lineKey{"kind", i, src, key}]; ok {
		return ln
	}
	if i >= 0 && i < len(li.headers) {
		if src >= 0 && src < len(li.sources[i]) {
			return li.sources[i][src]
		}
		return li.headers[i]
	}
	return 0
}

func (li *lineIndex) line(section, key string) int {
	if li == nil {
		return 0
	}
	return li.keys[lineKey{section, -1, -1, key}]
}
