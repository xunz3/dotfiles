# Uses git's zsh completion if a packaged `_git` completion file exists.
for completion in \
  "$(brew --prefix 2>/dev/null)/share/zsh/site-functions/_git" \
  /usr/share/zsh/site-functions/_git \
  /usr/share/zsh/vendor-completions/_git \
  /usr/local/share/zsh/site-functions/_git
do
  if [[ -f "$completion" ]]
  then
    source "$completion"
    break
  fi
done
