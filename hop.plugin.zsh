#!/usr/bin/env zsh
# The filename every zsh plugin manager looks for, so hop needs no per-manager configuration.
# - oh-my-zsh REQUIRES <name>.plugin.zsh, and zinit, antidote and sheldon all prefer it.
# - Managers pick ONE entry point, so this never double-sources hop.zsh.
# - HOP_HOME is still derived inside hop.zsh from ITS own path, so this shim adds no new state.
source "${${(%):-%x}:A:h}/hop.zsh"
