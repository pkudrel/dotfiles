# History: large, shared between open terminals, without duplicates.

HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000

setopt EXTENDED_HISTORY      # timestamps
setopt SHARE_HISTORY         # share between sessions
setopt HIST_IGNORE_ALL_DUPS  # drop older duplicates
setopt HIST_SAVE_NO_DUPS
setopt HIST_IGNORE_SPACE     # " cmd" is not saved
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY           # show !! expansions before running
