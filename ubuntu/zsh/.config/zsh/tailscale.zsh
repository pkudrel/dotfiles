# Tailscale: tab completion. Installed by ubuntu/features/50-tailscale.sh (log in once: sudo tailscale up).

(( $+commands[tailscale] )) || return 0

# Generating the completion takes ~0.3 s: done once, loaded on the first Tab (cached_completion is in env.zsh).
cached_completion tailscale tailscale completion zsh
