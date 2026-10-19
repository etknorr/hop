#!/usr/bin/env bash
# fetch-repos.sh: shallow-fetch each repo in repos.lock at its pinned commit into testdata/repos/<name>.
# - A repo already at its commit is left alone, so a rerun costs one rev-parse per repo.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
dest=${HOP_REPOS_DIR:-$here/repos}
mkdir -p "$dest"
while IFS=$'\t' read -r name url sha _; do
	case $name in '' | '#'*) continue ;; esac
	dir=$dest/$name
	if [ "$(git -C "$dir" rev-parse -q --verify HEAD 2>/dev/null)" = "$sha" ]; then
		continue
	fi
	rm -rf "$dir"
	git init -q "$dir"
	git -C "$dir" remote add origin "$url"
	git -C "$dir" -c protocol.version=2 fetch -q --depth 1 origin "$sha"
	git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
	echo "fetched $name at ${sha:0:12}"
done <"$here/repos.lock"
