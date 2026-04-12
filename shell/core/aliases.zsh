# shell aliases and Linux command compatibility shims
alias reload!='. ~/.zshrc'
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
  alias l="gls -lAh --color=auto"
  alias ll="gls -l --color=auto"
  alias la='gls -A --color=auto'
elif ls --color -d . >/dev/null 2>&1; then
  alias ls="ls -F --color=auto"
  alias l="ls -lAh --color=auto"
  alias ll="ls -l --color=auto"
  alias la='ls -A --color=auto'
fi
