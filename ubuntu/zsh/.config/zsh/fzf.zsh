# fzf key bindings (Ctrl+R history, Alt+T / Ctrl+T files, Alt+C cd) and completion.

(( $+commands[fzf] )) || return 0

# `fzf --zsh` needs fzf >= 0.48; older versions just skip the integration.
if _fzf_init="$(fzf --zsh 2>/dev/null)"; then
  eval "$_fzf_init"
fi
unset _fzf_init

# Ctrl+T opens a new tab in Windows Terminal, so the file picker is also on Alt+T.
if (( $+widgets[fzf-file-widget] )); then
  bindkey '\et' fzf-file-widget
fi

if (( $+commands[fd] )); then
  _fzf_fd=fd
elif (( $+commands[fdfind] )); then
  _fzf_fd=fdfind
fi
if [[ -n "${_fzf_fd:-}" ]]; then
  export FZF_DEFAULT_COMMAND="$_fzf_fd --type f --hidden --exclude .git"
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND="$_fzf_fd --type d --hidden --exclude .git"
fi
unset _fzf_fd
