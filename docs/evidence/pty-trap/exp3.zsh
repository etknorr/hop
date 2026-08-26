#!/usr/bin/env zsh
# Task #43 experiment 3: why is the real flake ~1-in-40 rather than every run?
# - exp1's trap went STRAIGHT to cleanup and won every race, which is not what the real one does.
# - The real _hop_pty_onexit runs _hop_t_report, then pty_reap_all, THEN fixture_cleanup.
# - pty_reap_all forks `ps -A` inside _hop_pty_tree, so the destructive step is materially delayed.
# - This models that preamble faithfully and measures how often the poll wins.

emulate -L zsh
setopt no_nomatch
zmodload zsh/zpty || exit 1

typeset -g Q=/private/tmp/hop-ptytrap
typeset -gi RUNS=${RUNS:-10}
typeset -gi WON=0 LOST=0

for (( i = 1; i <= RUNS; i++ )); do
	typeset W=$Q/w3.$i
	rm -rf -- "$W"
	mkdir -p "$W/ptyshared" "$W/ptyhome" "$W/ptycanary"
	print -rl -- alpha bravo > "$W/ptycanary/list"

	typeset -ga FIXDIRS=("$W/ptyshared" "$W/ptyhome" "$W/ptycanary")

	# A faithful stand-in for _hop_pty_onexit: report, then reap (with real ps forks), then cleanup.
	fake_onexit() {
		# _hop_t_report equivalent: one line of output.
		print -r -- '##hop-test-count 0 0 0' >> "$W/sentinel"
		# pty_reap_all equivalent: _hop_pty_tree forks `ps -A` per registered pid.
		local -a pairs
		pairs=("${(@f)$(ps -A -o pid=,ppid= 2>/dev/null)}")
		pairs=("${(@f)$(ps -A -o pid=,ppid= 2>/dev/null)}")
		# fixture_cleanup equivalent: the destructive step, reached LAST.
		local d
		for d in "${FIXDIRS[@]}"; do
			[[ -n $d && -d $d ]] || continue
			rm -rf -- "$d"
		done
		return 0
	}
	trap fake_onexit EXIT INT TERM

	zpty -b C3 "fzf --no-height --layout=reverse --bind 'o:print(ctrl-o)+accept' < ${W}/ptycanary/list > ${W}/ptycanary/out 2> ${W}/ptycanary/err" || { print -r -- "run ${i}: zpty failed"; continue }

	typeset junk
	typeset -F spent=0
	while (( spent < 0.4 )); do
		while zpty -r -t C3 junk 2>/dev/null; do :; done
		sleep 0.02
		(( spent += 0.02 ))
	done
	zpty -w -n C3 'o'

	spent=0
	typeset broke=no
	while (( spent < 3 )); do
		while zpty -r -t C3 junk 2>/dev/null; do :; done
		if [[ -s $W/ptycanary/out ]]; then
			broke=yes
			break
		fi
		sleep 0.02
		(( spent += 0.02 ))
	done
	zpty -d C3 2>/dev/null

	typeset res=''
	[[ -r $W/ptycanary/out ]] && read -r res < "$W/ptycanary/out"
	if [[ $broke == yes && $res == ctrl-o ]]; then
		(( WON++ ))
		print -r -- "run ${i}: poll WON  (canary ok, dirs $([[ -d $W/ptyshared ]] && print survived || print DELETED))"
	else
		(( LOST++ ))
		print -r -- "run ${i}: poll LOST (broke=${broke} res=[${res}] dirs $([[ -d $W/ptyshared ]] && print survived || print DELETED))"
	fi
	trap - EXIT INT TERM
	rm -rf -- "$W"
done

print -r -- ''
print -r -- "=== ${RUNS} runs: poll won ${WON}, poll lost ${LOST} ==="
exit 0
