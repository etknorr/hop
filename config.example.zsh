#!/usr/bin/env zsh
# Example hop config. Copy to $HOP_CONFIG, which defaults to ~/.config/hop/config.zsh.
# - This file is sourced by your shell, so it is the same trust category as .zshrc.
# - With no config at all hop loads every shipped preset, so a fresh clone is useful immediately.
# - Writing anything here REPLACES that default, so name the presets you want.
# - Every declaration below is live and safe to keep: a kind matching nothing emits no rows.
# - A kind with zero matches is also hidden from the `:` menu, so it costs you no clutter.
# - README.md documents every hop_kind option in full.

hop_preset terragrunt terraform-modules helm serverless puppet backstage dir file

# Overriding a preset: redeclaring a kind replaces it and keeps its place in the `:` menu.
# - Here terragrunt gains --trim, so a `proj-payments` directory displays as just `payments`.
hop_kind tg --default \
	--marker 'terragrunt.hcl' \
	--under 'terraform' \
	--layout 'scope,env,region,name...' \
	--layout 'scope,name...' \
	--trim 'scope:proj-' \
	--preview 'main.tf,*.tf,terragrunt.hcl,README.md' \
	--preview-skip 'provider_*.tf,variables_defaults.tf,versions_override.tf' \
	--desc 'terragrunt units'

# Shape 1, --dirs: every child directory of a base is a target.
# - The marker is DIRECTORY EXISTENCE, so a service carrying no manifest is still a target.
# - --depth 2 walks a <namespace>/<name> layout, where one level would return only containers.
hop_kind svc \
	--dirs 'services,platform/services' \
	--preview 'service.yaml,docs/runbook.md,README.md' \
	--desc 'application services'

# Shape 2, --files: every tracked file matching a pathspec, with its directory as the cd target.
# - --layout maps path segments to columns once --under is stripped, and `-` discards a segment.
# - --strip-ext drops the extension first, so `<env>.conf` fills the env column as just `<env>`.
hop_kind envconf \
	--files 'services/*/config/*/*.conf' \
	--under 'services' \
	--strip-ext \
	--layout 'scope,-,name,env' \
	--desc 'per-role config files'

# Shape 3, --marker: a directory holding a marker file is a target.
# - Layouts are tried longest-first, and a trailing `...` swallows the rest of the path.
# - A path matching no layout is not a target, which is how a shared include gets excluded.
hop_kind stack \
	--marker 'Pulumi.yaml' \
	--under 'infra' \
	--layout 'scope,env,name...' \
	--layout 'scope,name...' \
	--preview 'Pulumi.yaml,README.md' \
	--desc 'pulumi stacks'

# --name-template composes a name from other columns, and runs after --trim.
hop_kind alerts \
	--files 'observability/rules/*/*/rules.yaml' \
	--under 'observability/rules' \
	--layout 'scope,env,-' \
	--name-template '{scope}/{env}' \
	--desc 'alerting rules'

# The escape hatch: a family too irregular to declare gets a function and is still a real kind.
# - The function takes the repo root and prints rows with _hop_row.
# - Enumerate with _hop_ls, never `git ls-files`, so :(glob) and NUL handling come for free.
_hop_provider_irregular() {
	emulate -L zsh
	local root=$1 rel REPLY
	local -a reply
	_hop_ls "$root" 'odd/*/thing.json' || return 0
	for rel in "${reply[@]}"; do
		_hop_row irregular 'odd' '-' '-' "${${rel:h}:t}" "$root/${rel:h}" "$root/$rel"
	done
}
hop_kind irregular --fn _hop_provider_irregular --desc 'a shape with no rule'
