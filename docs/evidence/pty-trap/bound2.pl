# The tests/run:128-145 bound verbatim: fork, child setpgrp, parent alarm, KILL the negative pid.
# - Used for the cases that MUST keep a controlling terminal, where setsid would destroy the thing
#   under test. setpgrp changes only the process group, and a ctty belongs to the session.
my $secs = shift @ARGV;
my $pid = fork();
die "fork: $!" unless defined $pid;
if ($pid == 0) { setpgrp(0, 0); exec @ARGV; exit 127 }
setpgrp($pid, $pid);
$SIG{ALRM} = sub {
    kill("KILL", -$pid);
    kill("KILL", $pid);
    waitpid($pid, 0);
    exit 142;
};
alarm $secs;
waitpid($pid, 0);
my $st = $?;
alarm 0;
exit($st & 127 ? 128 + ($st & 127) : $st >> 8);
