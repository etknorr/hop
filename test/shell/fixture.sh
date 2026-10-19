#!/bin/sh
# fixture.sh DIR: the shell tests' repo, config and stubs, built the same way on the host and in docker.
set -eu
d=$1
mkdir -p "$d/repo" "$d/stub" "$d/tmp" "$d/home"
cd "$d/repo"
nl=$(printf 'nl\nx')
for u in plain 'with space' 'trail-space-backslash\ ' café "$nl" 'brack[1]' alpha beta/gamma; do
	mkdir -p "$u"
	printf 'unit\n' >"$u/UNIT"
done
git init -q
git add -A
cat >"$d/config.toml" <<'TOML'
version = 1
recipes = []

[[kind]]
name = 'u'
desc = 'units'
default = true
marker = 'UNIT'
TOML
printf '#!/bin/sh\nexit 3\n' >"$d/stub/code-fail"
printf '#!/bin/sh\ncat >"%s/clip"\n' "$d" >"$d/stub/pbcopy"
chmod +x "$d/stub/code-fail" "$d/stub/pbcopy"
