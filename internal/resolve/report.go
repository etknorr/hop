package resolve

import (
	"fmt"
	"io"
	"slices"
	"strings"
	"unicode"

	"github.com/etknorr/hop/internal/rows"
)

// WordUnread is _hop_word_unread: no row holds word as a whole token of its name line or its rel.
// - Tokens split on whitespace and / - _ ., as the vocabulary splits a rel; a substring test kept `conf` a word in configuration.
func WordUnread(word string, rs []string) bool {
	t := strings.ToLower(word)
	sep := func(r rune) bool {
		return r == '/' || r == '-' || r == '_' || r == '.' || unicode.IsSpace(r)
	}
	for _, r := range rs {
		disp, _, _ := strings.Cut(r, "\t")
		for _, s := range []string{rows.StripANSI(disp), RelOf(r)} {
			if slices.Contains(strings.FieldsFunc(strings.ToLower(s), sep), t) {
				return false
			}
		}
	}
	return true
}

// Report is _hop_headless_report: with no terminal, explain the resolve on w and return 1.
// - The one exception is an empty query over exactly one row, which auto-accepts as --select-1 would; then it returns accept.
// - kword is the kind a first word was read as (hop 0.3.0); a kind word alone lists that kind and never auto-accepts.
// - The text is hop's, "hop:" prefix included, so a report diffs clean against zsh hop's.
func Report(w io.Writer, res Result, query, jump, kword string) (accept bool, rc int) {
	if res.Verdict == "empty" && kword == "" && res.N == 1 && jump != "never" {
		return true, 0
	}
	if res.Verdict == "pick" && res.Tier != "T0" && res.Tier != "T1" {
		if res.Tier == "relaxed" {
			fmt.Fprintf(w, "hop: no exact match for: %s (%s)\n", query, res.Note)
		} else {
			fmt.Fprintf(w, "hop: no exact match for: %s (read as: %s)\n", query, res.Query)
		}
	}
	fmt.Fprintln(w, "hop: no terminal available, so the picker cannot run (/dev/tty could not be opened).")
	the := ""
	if query != "" {
		the = " the query: " + query
	}
	if res.Verdict == "none" {
		with := ""
		if kword != "" {
			with = " with -k " + kword
		}
		fmt.Fprintf(w, "hop: nothing matched%s%s, so there was nothing to jump to.\n", the, with)
		if res.Note != "" && !strings.HasPrefix(res.Note, "nothing close to: ") {
			fmt.Fprintf(w, "hop: %s, so a misspelt word is not corrected; -k narrows the kinds.\n", res.Note)
		}
		return false, 1
	}
	unit := "targets"
	if res.N == 1 {
		unit = "target"
	}
	fmt.Fprintf(w, "hop: %d %s matched%s, and picking one needs a terminal.\n", res.N, unit, the)
	if len(res.Rows) > 0 {
		best := relsOf(res.Rows[:min(3, len(res.Rows))])
		fmt.Fprintf(w, "hop: best matches: %s\n", strings.Join(best, ", "))
	}
	switch {
	case jump == "never":
		fmt.Fprintln(w, "hop: -p and HOP_JUMP=never always open the picker, and the picker needs a terminal.")
	case res.Tier == "relaxed":
		fmt.Fprintf(w, "hop: drop or fix: %s\n", strings.TrimPrefix(res.Note, "ignored: "))
	case res.Tier == "T2" || res.Tier == "T3":
		fmt.Fprintln(w, "hop: fix the spelling, since hop never jumps on a corrected query.")
	case res.Tier == "T0":
		fmt.Fprintln(w, "hop: put the repo name in front of the path, or give the whole path from ~/, so it names one of them.")
	case kword != "" && res.Verdict == "empty" && res.N == 1:
		fmt.Fprintf(w, "hop: a kind word alone lists that kind and never jumps; hop -k %s jumps to its one target.\n", kword)
	default:
		fmt.Fprintln(w, "hop: narrow the query until exactly one target matches and hop will jump straight to it.")
	}
	return false, 1
}
