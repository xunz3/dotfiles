# shell aliases and Linux package-name shims
# Replacing the process avoids registering plugin hooks repeatedly.
alias reload!='exec zsh'
alias cls='clear'

if (( $+commands[fdfind] )) && ! (( $+commands[fd] )); then
  alias fd='fdfind'
fi

if (( $+commands[batcat] )) && ! (( $+commands[bat] )); then
  alias bat='batcat'
fi

if (( $+commands[bat] )) || (( $+commands[batcat] )); then
  alias cat='bat --style=plain --paging=never'
fi

if (( $+commands[gls] )); then
  alias ls="gls -F --color=auto"
elif ls --color -d . >/dev/null 2>&1; then
  alias ls="ls -F --color=auto"
fi

# Keep `ls` compatible with the platform command, while using eza for the
# explicitly interactive views when it is available. Icons stay opt-in so the
# output remains readable without a Nerd Font.
if (( $+commands[eza] )); then
  alias l='eza --long --all --header --group-directories-first --git'
  alias ll='eza --long --header --group-directories-first --git'
  alias la='eza --all --group-directories-first'
  alias lt='eza --tree --level=2 --group-directories-first'
elif (( $+commands[gls] )); then
  alias l="gls -lAh --color=auto"
  alias ll="gls -l --color=auto"
  alias la='gls -A --color=auto'
elif ls --color -d . >/dev/null 2>&1; then
  alias l="ls -lAh --color=auto"
  alias ll="ls -l --color=auto"
  alias la='ls -A --color=auto'
fi
