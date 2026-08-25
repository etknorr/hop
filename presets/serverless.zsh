#!/usr/bin/env zsh
# Serverless Framework and AWS SAM deployables under serverless/.
# - The marker is directory existence, not a manifest, because a SAM unit has no serverless.yml.
# - A README at the family root is a file, so it drops out and never becomes a unit.

hop_kind serverless \
	--dirs 'serverless' \
	--preview 'serverless.yml,serverless.yaml,template.yaml,requirements.txt,README.md' \
	--desc 'lambda deployables'
