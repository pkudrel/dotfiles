# .NET SDK in ~/.dotnet: PATH, DOTNET_ROOT and tab completion. Installed by ubuntu/features/30-dotnet.sh.

[[ -x "$HOME/.dotnet/dotnet" ]] || return 0

export DOTNET_ROOT="$HOME/.dotnet"
path=("$DOTNET_ROOT" "$DOTNET_ROOT/tools" $path)

# Completion comes from the SDK itself; dotnet runs only when Tab is pressed.
_dotnet_zsh_complete() {
  local completions=("$(dotnet complete "$words")")
  if [[ -z "$completions" ]]; then
    _arguments '*::arguments: _normal'
    return
  fi
  _values = "${(ps:\n:)completions}"
}
compdef _dotnet_zsh_complete dotnet
