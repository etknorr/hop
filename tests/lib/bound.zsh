#!/usr/bin/env zsh
# The suite's only real timeout, shared by the runner and by every suite that bounds a child.
#
# Two shapes look identical and only one is a bound, which is why this file exists at all.
# - `alarm N; exec` was NOT a bound: perl BECOMES the child, so a child trapping ALRM ignored it.
# - Proven: `trap "" ALRM; sleep 12` ran all 12 seconds under a 3s bound and exited 0.
# - Measured again at 45s under a 3s bound, and it still exited 0, which is the dangerous half.
# - So it is not a weak bound, it REPORTS SUCCESS: a caller reads green off a runaway child.
# - It also reaped nothing: five fzf processes outlived a run, orphaned to init, hung 11+ minutes.
# - It read as a bound at six call sites, so there is now one implementation and no second spelling.
# - So perl forks instead, keeps the alarm in a process the child cannot reach, and kills the GROUP.
# - That makes a child trapping ALRM structurally irrelevant rather than a case to handle.
# - The group is what gets killed, because a preview or reload runs in a fresh $SHELL grandchild.
# - Both sides call setpgid, because either one may lose the race to the other's first exec.
# - KILL, never TERM: a hung fzf traps TERM in raw mode, and a real TERM left it alive.
# - A killed group exits 142, which is what perl's own alarm death used to report.

# hop_bound <seconds> <command...> -> run the command under a hard bound; 142 when the bound fired.
# - A missing perl must not silently drop the bound, so the command still runs and says nothing.
# - Callers redirect around the call, so nothing here may write to stdout or stderr itself.
hop_bound() {
	emulate -L zsh
	local -i secs=${1:-0}
	shift
	if (( ! ${+commands[perl]} )); then
		"$@"
		return $?
	fi
	perl -e '
		my $secs = shift @ARGV;
		my $pid = fork();
		die "fork: $!" unless defined $pid;
		if ($pid == 0) { setpgrp(0, 0); exec @ARGV; exit 127 }
		setpgrp($pid, $pid);
		$SIG{ALRM} = sub {
			kill("KILL", -$pid);
			waitpid($pid, 0);
			exit 142;
		};
		alarm $secs;
		waitpid($pid, 0);
		my $st = $?;
		alarm 0;
		exit($st & 127 ? 128 + ($st & 127) : $st >> 8);
	' "$secs" "$@"
	return $?
}
