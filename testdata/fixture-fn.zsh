# fixture.zsh plus a --fn provider, for zsh hop only: hop runs the same rows from fx.sh as an exec kind.
source "${${(%):-%x}:A:h}/fixture.zsh"

_hop_provider_fx() {
	emulate -L zsh
	local root=$1 rel REPLY
	local -a reply
	_hop_ls "$root" 'svc/*/f' || return 0
	for rel in "${reply[@]}"; do
		_hop_row fx 'svc' '-' '-' "${${rel:h}:t}" "$root/${rel:h}" "$root/$rel"
	done
	_hop_row fx 'svc' 'prod' 'eu' 'readme' "$root/svc/alpha" "$root/svc/alpha/README.md" f
}
hop_kind fx --fn _hop_provider_fx --desc 'a user provider'
