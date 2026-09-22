# Environment: PATH and editor. Sourced first from ~/.zshrc.

typeset -U path PATH
path=("$HOME/.local/bin" $path)
export PATH

# VS Code when the terminal runs inside it (also Remote-SSH), otherwise nano.
if [[ "${TERM_PROGRAM:-}" == vscode ]] && (( $+commands[code] )); then
  export EDITOR="code --wait"
else
  export EDITOR="nano"
fi
export VISUAL="$EDITOR"
export PAGER="less"
export LESS="-R"

# cached_completion COMMAND GENERATOR...: tab completion for COMMAND from what GENERATOR prints.
# Saved as ~/.cache/zsh/completions/_COMMAND (rebuilt when COMMAND's binary is newer) and loaded
# only on the first Tab, so generating and parsing big completion scripts doesn't slow down startup.
cached_completion() {
  local cmd="$1" dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/completions"
  shift
  if [[ ! -s "$dir/_$cmd" || "$commands[$cmd]" -nt "$dir/_$cmd" ]]; then
    mkdir -p "$dir"
    "$@" >| "$dir/_$cmd" 2>/dev/null
  fi
  (( ${fpath[(Ie)$dir]} )) || fpath=("$dir" $fpath)
  autoload -Uz "_$cmd"
  compdef "_$cmd" "$cmd"
}
