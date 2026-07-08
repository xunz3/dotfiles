typeset -U path
path=(
  "$HOME/.local/bin"
  "$HOME/bin"
  /usr/local/bin
  /usr/local/sbin
  "$DOTFILES/bin"
  $path
)
export PATH

if [[ -n "${MANPATH:-}" ]]; then
  typeset -U manpath
  manpath=(
    /usr/local/man
    /usr/local/mysql/man
    /usr/local/git/man
    $manpath
  )
  export MANPATH
else
  export MANPATH="/usr/local/man:/usr/local/mysql/man:/usr/local/git/man:"
fi
