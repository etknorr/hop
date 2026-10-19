# Fixture config for the engine tests: every hop_kind option, run by zsh hop and imported for hop.
hop_preset dir file helm backstage
hop_kind tg --default --marker terragrunt.hcl --under infra/ \
	--layout 'scope,env,region,name...' --layout 'scope,name...' \
	--trim 'scope:acct-,env:env-,scope:a' \
	--preview 'main.tf,*.tf,terragrunt.hcl' --preview-skip 'provider_*.tf' --desc 'units'
hop_kind tgx --marker terragrunt.hcl --exclude '*/shared/*,infra/acct-b*' --layout 'scope,name...' --name-template '{scope}:{env}:{name}' --desc 'excl'
hop_kind tgroot --marker terragrunt.hcl --desc 'no layout, no under'
hop_kind tie --marker terragrunt.hcl --under infra --layout 'scope,env' --layout 'scope,name...' --desc 'equal width'
hop_kind svc --dirs 'svc,nope,' --preview 'README.md,**/*.md,f' --desc 'dirs'
hop_kind svc2 --dirs svc --depth 2 --scope-literal LIT --desc 'depth2'
hop_kind cfg --files 'cfg/*/conf/*/*' --under cfg --strip-ext --layout 'scope,-,name,env' --desc 'files'
hop_kind cfgnl --files 'cfg/**' --strip-ext --trim 'name:p' --name-template '{scope}!' --desc 'files, no layout'
hop_kind ents --files 'ents/*' --name-fn _hop_entity_name --scope-literal E --desc 'entities'
hop_kind odd --files 'odd/**,[.]rootdot' --exclude 'odd/skip*' --desc 'odd names'

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
