# ~/.zshrc: managed in ~/.dotfiles/ubuntu/zsh (linked by stow).
# Topic modules: ~/.config/zsh/*.zsh. This machine only: ~/.zshrc.local

# Powerlevel10k instant prompt. Anything that needs console input
# (password prompts, [y/n] questions) must go above this block.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# PATH and editor first, so everything below can find the tools.
source "$HOME/.config/zsh/env.zsh"

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git)
zstyle ':omz:update' mode reminder
source "$ZSH/oh-my-zsh.sh"

for module in "$HOME"/.config/zsh/*.zsh(N); do
  [[ "${module:t}" == env.zsh ]] || source "$module"
done
unset module

ZSH_PLUGINS_DIR="${ZSH_CUSTOM:-$ZSH/custom}/plugins"
if [[ -r "$ZSH_PLUGINS_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$ZSH_PLUGINS_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

[[ ! -r "$HOME/.p10k.zsh" ]] || source "$HOME/.p10k.zsh"
[[ ! -r "$HOME/.zshrc.local" ]] || source "$HOME/.zshrc.local"

# zsh-syntax-highlighting must be sourced last.
if [[ -r "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi
