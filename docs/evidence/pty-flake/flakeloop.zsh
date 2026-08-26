#!/usr/bin/env zsh
# Capture loop for the pty flake. Protocol: CAPTURE, never reason.
# Every run's FULL output is retained in its own file, pass or fail.
emulate -L zsh
setopt local_options
local T=/tmp/hop-wt-flake
local D=/tmp/pinaudit/flake
local N=${1:-45}
mkdir -p $D
cd $T

print -r -- "commit: $(git rev-parse --short HEAD)" > $D/INDEX.txt
print -r -- "runs requested: $N" >> $D/INDEX.txt
print -r -- "started: $(date -u +%FT%TZ)" >> $D/INDEX.txt
print -r -- "" >> $D/INDEX.txt

local -i i fails=0
for (( i = 1; i <= N; i++ )); do
	local f=$D/run-$(printf '%03d' $i).txt
	local load_before=$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}')
	local start=$SECONDS
	# Full output retained. stdin /dev/null so the pipeline hazard is not a variable.
	/tmp/pinaudit/bound 400 zsh tests/run > $f 2>&1 < /dev/null
	local st=$?
	local el=$((SECONDS-start))
	local load_after=$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}')
	local summary=$(grep -E '^(ok|FAIL)  ' $f | tail -1)

	# Append the run's own metadata INTO its file, so the artifact is self-contained.
	{
		print -r -- ""
		print -r -- "### capture metadata"
		print -r -- "run: $i"
		print -r -- "exit: $st"
		print -r -- "elapsed_s: $el"
		print -r -- "loadavg_before: $load_before"
		print -r -- "loadavg_after: $load_after"
		print -r -- "date_utc: $(date -u +%FT%TZ)"
	} >> $f

	local mark=ok
	if [[ -z $summary || $summary == FAIL* ]]; then
		mark=FAIL
		(( fails++ ))
		# Snapshot the machine at the moment of failure, before anything is re-run.
		{
			print -r -- "### failure snapshot"
			print -r -- "--- failing tests:"
			grep -E '✗' $f
			print -r -- "--- failure context (5 lines after each):"
			grep -A5 -E '✗' $f
			print -r -- "--- processes:"
			ps -eo pid,ppid,etime,command | grep -E 'hop-|fzf|zpty|/fzf ' | grep -v grep | cut -c1-160
			print -r -- "--- surviving fixture dirs under TMPDIR:"
			ls -1d ${TMPDIR:-/tmp}/hop-* 2>/dev/null | head -30
		} >> $f
	fi
	printf '%-10s %-6s %4ss  load=%s  %s\n' "run-$i" "$mark" "$el" "${load_before%% *}" "$summary" >> $D/INDEX.txt
done

print -r -- "" >> $D/INDEX.txt
print -r -- "finished: $(date -u +%FT%TZ)" >> $D/INDEX.txt
print -r -- "runs completed: $N  failures: $fails" >> $D/INDEX.txt
print -r -- "LOOP DONE runs=$N failures=$fails"
