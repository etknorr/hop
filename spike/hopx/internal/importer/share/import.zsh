#!/usr/bin/env zsh
# hopx config import, the zsh half: let zsh parse config.zsh, and record every hop_kind and hop_preset call.
# - zsh does the parsing because config.zsh is shell code: quoting, continuations, variables and conditionals.
# - Records go to fd 3 as NUL-terminated tokens, so a config that prints to stdout cannot corrupt them.
# - Record shapes: preset 1 NAME | kind N ARGV... | fn 2 NAME DEFINED | set 2 VAR VALUE | orphan 1 FUNC
# - Option parsing is NOT done here: hopx ports dsl.zsh's parser, so both read argv identically.
emulate -L zsh
local cfg=$1

hop_preset() {
	local p
	for p in "$@"; do
		print -rN -- preset 1 "$p" >&3
	done
	return 0
}

hop_kind() {
	print -rN -- kind $# "$@" >&3
	local prev='' a
	for a in "$@"; do
		if [[ $prev == --fn || $prev == --name-fn ]]; then
			print -rN -- fn 2 "$a" $(( ${+functions[$a]} )) >&3
		fi
		prev=$a
	done
	return 0
}

local -a vars=(HOP_ACTION HOP_JUMP HOP_CODE HOP_CLIPBOARD HOP_VIM HOP_FZF_HEIGHT HOP_HIST_MAX HOP_DEFAULT_KINDS HOP_WORKSPACES HOP_REPOS)
local v
for v in "${vars[@]}"; do
	unset "$v"
done

source "$cfg" || exit 1

for v in "${vars[@]}"; do
	(( ${+parameters[$v]} )) && print -rN -- set 2 "$v" "${(P)v}" >&3
done

local f
for f in ${(k)functions[(I)_hop_provider_*]}; do
	print -rN -- orphan 1 "$f" >&3
done
