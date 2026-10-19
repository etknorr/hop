# The resolver fixture's config, copied from match_fixture in tests/lib/fixture.zsh.
hop_preset helm terraform-modules dir
hop_kind tg --default --marker terragrunt.hcl --under terraform --layout 'scope,env,region,name...' --layout 'scope,name...' --trim 'scope:acct-,env:env-' --preview 'main.tf,*.tf,terragrunt.hcl,README.md' --desc 'terragrunt units'
hop_kind mesos --default --dirs mesos/services --scope-literal - --preview service.conf --desc 'mesos services'
hop_kind sbx --default --dirs sandbox --desc 'sandbox dirs'
