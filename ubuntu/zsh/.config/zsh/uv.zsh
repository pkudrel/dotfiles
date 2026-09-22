# uv (Python): tab completion for uv and uvx. Installed by ubuntu/features/10-uv.sh.

(( $+commands[uv] )) || return 0

# Generated once, loaded on the first Tab (cached_completion is in env.zsh).
cached_completion uv uv generate-shell-completion zsh
if (( $+commands[uvx] )); then
  cached_completion uvx uvx --generate-shell-completion zsh
fi
