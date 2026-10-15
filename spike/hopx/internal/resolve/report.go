package resolve

import (
	"fmt"
	"io"
	"strings"
)

// Report is _hop_headless_report: with no terminal, explain the resolve on w and return 1.
// - The one exception is an empty query over exactly one row, which auto-accepts as --select-1 would; then it returns accept.
// - The text is hop's, "hop:" prefix included, so a report diffs clean against zsh hop's.
func Report(w io.Writer, res Result, query, jump string) (accept bool, rc int) {
	if res.Verdict == "empty" && res.N == 1 && jump != "never" {
		return true, 0
	}
	if res.Verdict == "pick" && res.Tier != "T1" {
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
		fmt.Fprintf(w, "hop: nothing matched%s, so there was nothing to jump to.\n", the)
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
	default:
		fmt.Fprintln(w, "hop: narrow the query until exactly one target matches and hop will jump straight to it.")
	}
	return false, 1
}
