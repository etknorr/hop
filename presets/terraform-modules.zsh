#!/usr/bin/env zsh
# Terraform and OpenTofu modules, in the conventional terraform/modules/<namespace>/<module> layout.
# - --depth 2 is the whole point: a one-level listing returns the namespaces, never a module.

hop_kind mod --default \
	--dirs 'terraform/modules' \
	--depth 2 \
	--preview 'main.tf,*.tf,terragrunt.hcl,README.md' \
	--preview-skip 'provider_*.tf,variables_defaults.tf,versions_override.tf' \
	--desc 'terraform modules'
