emulate -L zsh
zmodload zsh/zpty
L=/private/tmp/hop-ptytrap/d.log
onexit() { print -r -- "FIRED-$PHASE" >> "$L" }
trap onexit EXIT INT TERM

# --- PHASE 1: spawn at TOP LEVEL of the script
PHASE=toplevel
: > "$L"
zpty -b P "zsh -f -c 'exit 0'"
sleep 0.5
zpty -d P 2>/dev/null
print -r -- "TOP-LEVEL spawn : log=[$(tr '\n' ';' < "$L")]"

# --- PHASE 2: spawn inside a function (what pty.zsh actually does)
PHASE=infunction
: > "$L"
fnspawn() { zpty -b P "zsh -f -c 'exit 0'" }
fnspawn
sleep 0.5
zpty -d P 2>/dev/null
print -r -- "IN-FUNCTION spawn: log=[$(tr '\n' ';' < "$L")]"

trap - EXIT INT TERM
