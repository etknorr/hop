#!/usr/bin/env zsh
# Puppet modules in a top-level modules/ directory, which is unrelated to terraform/modules.

hop_kind puppet \
	--dirs 'modules' \
	--preview 'README.md,README,CLAUDE.md' \
	--desc 'puppet modules'
