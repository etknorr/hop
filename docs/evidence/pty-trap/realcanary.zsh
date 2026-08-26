# Does the REAL, UNMODIFIED pty_canary wipe the fixtures it depends on?
emulate -L zsh
export HOP_HOME=/private/tmp/hop-pristine
export HOP_TESTS=$HOP_HOME/tests
export HOP_T_COLOR=0
source "$HOP_TESTS/lib/assert.zsh"
source "$HOP_TESTS/lib/fixture.zsh"
source "$HOP_TESTS/lib/pty.zsh"
pty_supported || { print -r -- 'no zpty'; exit 1 }
pty_env || { print -r -- 'pty_env failed'; exit 1 }
print -r -- "ptyshared=$HOP_PTY_SHARED"
print -r -- "ptyhome=$HOME"
print -r -- "--- before canary: shared=$([[ -d $HOP_PTY_SHARED ]] && print yes || print NO) home=$([[ -d $HOME ]] && print yes || print NO)"
if pty_canary; then
	print -r -- "canary: PASS (returned ctrl-o=[$HOP_PTY_CANARY])"
else
	print -r -- "canary: FAIL (got [$HOP_PTY_CANARY])"
fi
print -r -- "--- after canary:  shared=$([[ -d $HOP_PTY_SHARED ]] && print yes || print NO-WIPED) home=$([[ -d $HOME ]] && print yes || print NO-WIPED)"
print -r -- "--- fixture dirs registered: ${#HOP_FIX_DIRS}"
typeset d gone=0
for d in "${HOP_FIX_DIRS[@]}"; do [[ -d $d ]] || (( gone++ )); done
print -r -- "--- of those, missing: ${gone}"
pty_reap_all
