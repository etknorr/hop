#!/bin/sh
# fx, fixture-fn.zsh's _hop_provider_fx as an exec kind: name TAB path TAB preview TAB scope TAB env TAB region.
git -c core.quotepath=off ls-files --cached -- ':(glob)svc/*/f' | while IFS= read -r rel; do
	d=${rel%/*}
	printf '%s\t%s\t%s\tsvc\t-\t-\n' "${d##*/}" "$HOP_ROOT/$d" "$HOP_ROOT/$rel"
done
printf 'readme\t%s\t%s\tsvc\tprod\teu\n' "$HOP_ROOT/svc/alpha/README.md" "$HOP_ROOT/svc/alpha/README.md"
