# Prefer exact completion, then retry case-insensitively and across common word
# separators. Keeping this to two passes avoids an expensive completion fanout.
zstyle ':completion:*' matcher-list \
  '' \
  'm:{a-zA-Z}={A-Za-z} r:|[._-]=* r:|=*'

zstyle ':completion:*' menu select=2
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
zstyle ':completion:*:warnings' format '%F{red}no matches found%f'
zstyle ':completion:*' squeeze-slashes true
zstyle ':completion:*' verbose true
zstyle ':completion:*' use-cache true
zstyle ':completion:*' cache-path "${ZSH_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zsh}/completions"

if [[ -n "${LS_COLORS:-}" ]]
then
  zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
fi

# pasting with tabs doesn't perform completion
zstyle ':completion:*' insert-tab pending
