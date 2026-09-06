# Shell aliases and Linux package-name shims.
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

# Keep discoverable, memorable names for modern tools without changing the
# argument grammar of their POSIX counterparts.
(( $+commands[rg] )) && alias search='rg --smart-case'
if (( $+commands[fd] )) || (( $+commands[fdfind] )); then
  alias ff='fd --type file'
  alias fdir='fd --type directory'
fi
(( $+commands[duf] )) && alias disk='duf'
(( $+commands[sd] )) && alias replace='sd'
(( $+commands[btop] )) && alias bt='btop'
(( $+commands[tldr] )) && alias how='tldr'
(( $+commands[fastfetch] )) && alias fetch='fastfetch'

# Preserve the retired command name for muscle memory while using the
# maintained implementation and its managed config.
if (( $+commands[fastfetch] )); then
  alias neofetch='fastfetch'
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

# rg/fd/duf/btop intentionally use different option grammars from the commands
# they replace. Enable these interactive-only aliases explicitly in ~/.localrc;
# prefix a command with `command` or a backslash to bypass an alias temporarily.
if [[ "${DOTFILES_MODERN_ALIASES:-0}" == "1" ]]; then
  (( $+commands[rg] )) && alias grep='rg'
  if (( $+commands[fd] )) || (( $+commands[fdfind] )); then
    alias find='fd'
  fi
  (( $+commands[duf] )) && alias df='duf'
  (( $+commands[btop] )) && alias top='btop'
fi
