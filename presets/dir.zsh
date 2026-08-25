#!/usr/bin/env zsh
# The repo root plus every top-level tracked directory. This is the kind that gets you back out.

hop_kind dir --default \
	--fn _hop_provider_dir \
	--desc 'repo root and top-level dirs'
