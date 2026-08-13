export LSCOLORS="exfxcxdxbxegedabagacad"
export CLICOLOR=true

autoload -U $DOTFILES/shell/functions/*(:t)

HISTFILE="${ZDOTDIR:-$HOME}/.zsh_history"
# Keep extra in-memory room so duplicate entries can be discarded before
# unique history is expired.
HISTSIZE=50000
SAVEHIST=40000

setopt NO_BG_NICE # don't nice background tasks
setopt NO_HUP
setopt NO_LIST_BEEP
setopt LOCAL_OPTIONS # allow functions to have local options
setopt LOCAL_TRAPS # allow functions to have local traps
setopt HIST_VERIFY
setopt SHARE_HISTORY # import and append history across interactive sessions
setopt EXTENDED_HISTORY # add timestamps and command duration to history
setopt PROMPT_SUBST
setopt CORRECT
setopt COMPLETE_IN_WORD
setopt IGNORE_EOF
setopt INTERACTIVE_COMMENTS

setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_FCNTL_LOCK
setopt HIST_FIND_NO_DUPS
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt HIST_SAVE_NO_DUPS

# don't expand aliases _before_ completion has finished
#   like: git comm-[tab]
setopt complete_aliases

bindkey -e
bindkey '^[^[[D' backward-word
bindkey '^[^[[C' forward-word
bindkey '^[b' backward-word
bindkey '^[f' forward-word
bindkey '^[[1;3D' backward-word
bindkey '^[[1;3C' forward-word
bindkey '^[[1;5D' backward-word
bindkey '^[[1;5C' forward-word
bindkey '^[[5D' beginning-of-line
bindkey '^[[5C' end-of-line
bindkey '^[[H' beginning-of-line
bindkey '^[OH' beginning-of-line
bindkey '^[[1~' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[OF' end-of-line
bindkey '^[[4~' end-of-line
bindkey '^[[3~' delete-char
bindkey '^?' backward-delete-char
bindkey '^[[Z' reverse-menu-complete
