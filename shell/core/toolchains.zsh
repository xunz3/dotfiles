export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"

export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
[[ -d "$PNPM_HOME/bin" ]] && path=("$PNPM_HOME/bin" $path)
[[ -d "$PNPM_HOME" ]] && path=("$PNPM_HOME" $path)

export SDKMAN_DIR="${SDKMAN_DIR:-$HOME/.sdkman}"
[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"

[[ -d "$HOME/clash" ]] && export PATH="$HOME/clash:$PATH"
[[ -d "$HOME/.opencode/bin" ]] && path=("$HOME/.opencode/bin" $path)

if [[ -d /usr/local/go/bin ]]
then
  export PATH="$PATH:/usr/local/go/bin"
fi

export GOPATH="${GOPATH:-$HOME/go}"
[[ -d "$GOPATH/bin" ]] && export PATH="$PATH:$GOPATH/bin"

if [[ -d /usr/local/cmake/bin ]]
then
  export PATH="/usr/local/cmake/bin:$PATH"
fi

[[ -s "$HOME/.local/bin/env" ]] && source "$HOME/.local/bin/env"

[[ -s "$HOME/.bun/_bun" ]] && source "$HOME/.bun/_bun"
export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
[[ -d "$BUN_INSTALL/bin" ]] && export PATH="$BUN_INSTALL/bin:$PATH"
