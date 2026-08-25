#!/usr/bin/env zsh
# Backstage catalog entities: one flat directory of YAML files.
# - The unit is the FILE, so `dir` is the containing directory and the preview is the entity.
# - --name-fn reads metadata.name, because the filename and the entity name often disagree.

hop_kind backstage \
	--files 'backstage/*.yaml' \
	--scope-literal 'backstage' \
	--name-fn _hop_entity_name \
	--desc 'catalog entities'
