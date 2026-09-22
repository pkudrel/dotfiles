# Node.js via fnm: node/npm on PATH, version follows .nvmrc / .node-version on cd.
# Installed by ubuntu/features/20-node.sh.

(( $+commands[fnm] )) || return 0

# fnm env must run in every shell (it creates a per-shell PATH entry).
eval "$(fnm env --use-on-cd --shell zsh)"
# Generated once, loaded on the first Tab (cached_completion is in env.zsh).
cached_completion fnm fnm completions --shell zsh
