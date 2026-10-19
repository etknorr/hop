package workspace

import "testing"

// TestEmptyExpansionSkipped is _hop_ws_parse's -d test on an empty path: a workspace naming an unset variable is no workspace, not $PWD.
func TestEmptyExpansionSkipped(t *testing.T) {
	t.Setenv("HOP_TEST_UNSET", "")
	t.Chdir(t.TempDir())
	if got := Parse([]string{"gone=$HOP_TEST_UNSET", "${HOP_TEST_UNSET}"}, ""); len(got) != 0 {
		t.Errorf("a path expanding to empty is skipped: %v", got)
	}
}
