# CLI tools: Ubuntu package names, eza as ls, zoxide.

# Debian/Ubuntu install bat and fd as batcat and fdfind.
if (( $+commands[batcat] && ! $+commands[bat] )); then
  alias bat='batcat'
fi
if (( $+commands[fdfind] && ! $+commands[fd] )); then
  alias fd='fdfind'
fi

if (( $+commands[eza] )); then
  alias ls='eza --group-directories-first'
  alias ll='eza -l --git --group-directories-first'
  alias la='eza -la --git --group-directories-first'
  alias lt='eza --tree --level=2 --group-directories-first'
fi

if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"
fi
