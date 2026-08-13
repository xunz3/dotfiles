export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if ! (( $+functions[nvm] )) && [[ -s "$NVM_DIR/nvm.sh" ]]
then
  # Fallback for DOTFILES_USE_OH_MY_ZSH=0. With Oh My Zsh, its nvm plugin
  # installs lazy command shims before this module is loaded.
  source "$NVM_DIR/nvm.sh"
  [[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"
fi

export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
[[ -d "$PNPM_HOME/bin" ]] && path=("$PNPM_HOME/bin" $path)
[[ -d "$PNPM_HOME" ]] && path=("$PNPM_HOME" $path)

export SDKMAN_DIR="${SDKMAN_DIR:-$HOME/.sdkman}"
[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"

[[ -d "$HOME/clash" ]] && path=("$HOME/clash" $path)
[[ -d "$HOME/.opencode/bin" ]] && path=("$HOME/.opencode/bin" $path)

if [[ -d /usr/local/go/bin ]]
then
  path+=('/usr/local/go/bin')
fi

export GOPATH="${GOPATH:-$HOME/go}"
[[ -d "$GOPATH/bin" ]] && path+=("$GOPATH/bin")

if [[ -d /usr/local/cmake/bin ]]
then
  path=('/usr/local/cmake/bin' $path)
fi

[[ -s "$HOME/.local/bin/env" ]] && source "$HOME/.local/bin/env"

[[ -s "$HOME/.bun/_bun" ]] && source "$HOME/.bun/_bun"
export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
[[ -d "$BUN_INSTALL/bin" ]] && path=("$BUN_INSTALL/bin" $path)

export PATH
