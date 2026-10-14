#!/usr/bin/env zsh
# suite_actions: the verbs in lib/actions.zsh that shell out to `code`, reached through _hop_dispatch.
# - `code` is a recording stub, so every assertion reads the exact argv a real VS Code would get.
# - `code -r <dir>` reloads the last-focused window onto that folder, so a directory must get `-n`.
# - A file keeps `-r`, which opens it in the window already there instead of spawning a new one.

stub_bin

typeset -g AC_DIR AC_FILE
fixture_tmpdir actions
AC_DIR=$REPLY
AC_FILE="$AC_DIR/terragrunt.hcl"
print -r -- 'include {}' > "$AC_FILE"

# ---------------------------------------------------------------------------
# ctrl-o / o: open the preview, which is a file on most rows and the dir itself on the rest.
# ---------------------------------------------------------------------------
t 'ctrl-o on a file preview opens it with code -r'
stub_reset
hop_probe "_hop_dispatch ctrl-o ${(q)AC_DIR} ${(q)AC_FILE}"
assert_eq "code	-r	${AC_FILE}" "$(stub_calls code)"

# A dir preview is what _hop_preview_doc falls back to when a dir has no README, README.md or CLAUDE.md.
t 'ctrl-o on a dir preview opens a new window with code -n, never code -r'
stub_reset
hop_probe "_hop_dispatch ctrl-o ${(q)AC_DIR} ${(q)AC_DIR}"
assert_eq "code	-n	${AC_DIR}" "$(stub_calls code)" 'code -r on a dir replaces the focused window'"'"'s folder'

# ---------------------------------------------------------------------------
# ctrl-t / O: the row's dir as a folder, in its own window.
# ---------------------------------------------------------------------------
t 'ctrl-t opens the dir with code -n'
stub_reset
hop_probe "_hop_dispatch ctrl-t ${(q)AC_DIR} ${(q)AC_FILE}"
assert_eq "code	-n	${AC_DIR}" "$(stub_calls code)" 'a bare code <dir> replaces the workspace under openFoldersInNewWindow=off'

# The invariant both fixes serve, checked over every call this suite made rather than one at a time.
t 'no verb ever hands code -r a directory'
stub_reset
hop_probe "_hop_dispatch ctrl-o ${(q)AC_DIR} ${(q)AC_FILE}
_hop_dispatch ctrl-o ${(q)AC_DIR} ${(q)AC_DIR}
_hop_dispatch ctrl-t ${(q)AC_DIR} ${(q)AC_FILE}
_hop_dispatch ctrl-t ${(q)AC_DIR} ${(q)AC_DIR}"
typeset -a AC_CALLS=("${(@f)$(stub_calls code)}")
typeset AC_BAD='' AC_CALL
typeset -a AC_ARGV
for AC_CALL in "${AC_CALLS[@]}"; do
	AC_ARGV=("${(@ps:\t:)AC_CALL}")
	[[ ${AC_ARGV[2]} == -r && -d ${AC_ARGV[3]} ]] && AC_BAD+="${AC_CALL} "
done
assert_eq 4 "${#AC_CALLS}" 'every dispatch above must have reached code, or the scan below proves nothing'
assert_empty "$AC_BAD" 'code -r with a directory reloads the focused window onto it'
