#!/usr/bin/env zsh
# Every tracked file, so `hop -k file pr.yml` reaches a plain file the other kinds never list.
# - Opt-in on purpose: a large repo tracks tens of thousands of files and would bury the real targets.
# - The other kinds answer "which unit"; this one answers "which file", a different question.
# - `dir` is the containing directory, so enter cds beside the file while the preview shows the file.

hop_kind file \
	--files '**' \
	--desc 'every tracked file'
