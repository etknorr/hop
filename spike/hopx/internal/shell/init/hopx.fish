# hopx init fish: `hopx init fish | source` in ~/.config/fish/config.fish.

# `cd`, not `builtin cd`: fish's cd function is what appends to dirprev, so `cd -` and prevd only work through it.
# - string collect -N keeps a trailing newline in the name, which a plain substitution would drop.
function @CMD@ --description 'jump to a target in this repo'
	if test (count $argv) -eq 1; and test "$argv[1]" = -
		cd -
		return
	end
	set -l tmp /tmp
	set -q TMPDIR; and set tmp $TMPDIR
	set -l f (string trim -r -c / -- $tmp)/hopx.$fish_pid.(random)
	HOPX_CMDFILE=$f command hopx $argv
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

complete -c @CMD@ -f -a '(command hopx __complete (commandline -opc)[2..-1] (commandline -ct))'

# A binding body runs in this shell, so the cd sticks; repaint re-runs fish_prompt, and the half-typed line is never touched.
function __hopx_widget
	@CMD@ </dev/tty
	commandline -f repaint
end

if status is-interactive
	for mode in default insert
		bind -M $mode \cg __hopx_widget
		bind -M $mode \eg __hopx_widget
	end
end
