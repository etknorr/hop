#!/usr/bin/env bash
# build.sh [OUT]: hop for six targets with CGO off, stripped and trimmed, printing each binary's size and `file` line.
# - OUT defaults to dist/ at the repo root; a target is os/arch, and windows gets .exe.
# - BUILD_TARGETS overrides the list, space-separated.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-$root/dist}
targets=${BUILD_TARGETS:-darwin/arm64 darwin/amd64 linux/amd64 linux/arm64 windows/amd64 windows/arm64}
mkdir -p "$out"
printf '%-14s %9s %8s  %s\n' target bytes MiB file
for t in $targets; do
	os=${t%/*} arch=${t#*/} ext=
	[ "$os" = windows ] && ext=.exe
	b=$out/hop-$os-$arch$ext
	(cd "$root" && CGO_ENABLED=0 GOOS=$os GOARCH=$arch go build -trimpath -ldflags='-s -w' -o "$b" .)
	n=$(wc -c <"$b" | tr -d ' ')
	printf '%-14s %9s %8s  %s\n' "$t" "$n" "$(awk -v n="$n" 'BEGIN { printf "%.2f", n / 1048576 }')" "$(file -b "$b" | cut -c1-70)"
done
