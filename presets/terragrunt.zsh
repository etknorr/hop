#!/usr/bin/env zsh
# Terragrunt units: any directory under terraform/ holding a terragrunt.hcl.
# - Two layouts cover the usual conventions: account/env/region/unit, and account/unit.
# - The longer layout is tried first, so a nested unit renders as parent/child.
# - A terragrunt.hcl at depth 1 matches NEITHER layout, which is how a shared include is excluded.
# - No content check could exclude that include: it is byte-identical to a real unit.
# - Add --trim in your own config if your directories carry a naming prefix worth hiding.

hop_kind tg --default \
	--marker 'terragrunt.hcl' \
	--under 'terraform' \
	--layout 'scope,env,region,name...' \
	--layout 'scope,name...' \
	--preview 'main.tf,*.tf,terragrunt.hcl,README.md' \
	--preview-skip 'provider_*.tf,variables_defaults.tf,versions_override.tf' \
	--desc 'terragrunt units'
