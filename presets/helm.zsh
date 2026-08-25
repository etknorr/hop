#!/usr/bin/env zsh
# Helm charts, values trees and ArgoCD application files.
# - Declared with --fn because this one kind spans four genuinely different directory shapes.
# - See _hop_provider_helm in lib/providers.zsh for which families it probes.

hop_kind helm --default \
	--fn _hop_provider_helm \
	--desc 'helm charts, values and apps'
