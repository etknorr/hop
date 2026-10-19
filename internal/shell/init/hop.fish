# hop init fish: `hop init fish | source` in ~/.config/fish/config.fish.

# `cd`, not `builtin cd`: fish's cd function is what appends to dirprev, so `cd -` and prevd only work through it.
# - string collect -N keeps a trailing newline in the name, which a plain substitution would drop.
function @CMD@ --description 'jump to a target in this repo'
	if test (count $argv) -eq 1; and test "$argv[1]" = -
		cd -
		return
	end
	set -l tmp /tmp
	set -q TMPDIR; and set tmp $TMPDIR
	set -l f (string trim -r -c / -- $tmp)/hop.$fish_pid.(random)
	HOP_CMDFILE=$f command hop $argv
	set -l rc $status
	set -l dir
	if test -e $f
		set dir (string collect -N < $f)
		command rm -f -- $f
	end
	test -n "$dir"; or return $rc
	cd $dir; or return
	return $rc
end

# The current word goes through a variable: an empty `(commandline -ct)` would substitute to no argument at all.
function __@CMD@_complete
	set -l words (commandline -opc)[2..-1]
	set -l cur (commandline -ct)
	command hop __complete $words "$cur"
end
complete -c @CMD@ -f -a '(__@CMD@_complete)'

# A binding body runs in this shell, so the cd sticks; repaint re-runs fish_prompt, and the half-typed line is never touched.
function __@CMD@_widget
	@CMD@ </dev/tty
	commandline -f repaint
end

if status is-interactive
	for mode in default insert
		bind -M $mode \cg __@CMD@_widget
		bind -M $mode \eg __@CMD@_widget
	end
end
