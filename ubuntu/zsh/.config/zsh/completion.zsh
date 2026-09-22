# Completion tuning (Oh My Zsh already runs compinit).

zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
setopt COMPLETE_IN_WORD
setopt ALWAYS_TO_END
