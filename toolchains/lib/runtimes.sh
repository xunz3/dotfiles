#!/usr/bin/env bash

install_rustup () {
	if have_command rustup
	then
		success 'rustup already installed'
		return
	fi

	info 'installing rustup'
	run_remote_script "https://sh.rustup.rs" sh -s -- -y
	success 'installed rustup'
}

source_cargo () {
	if [[ -s "$HOME/.cargo/env" ]]
	then
		set +u
		source "$HOME/.cargo/env"
		set -u
	fi
	have_command rustup
}

install_nvm () {
	local target_dir="${NVM_DIR:-$HOME/.nvm}"

	if [[ -s "$target_dir/nvm.sh" ]]
	then
		success 'nvm already installed'
		return
	fi

	if ! have_command git
	then
		info 'git is required to install nvm; skipping'
		return 1
	fi

	if [[ -e "$target_dir" ]]
	then
		info "$target_dir exists and is not an nvm install; skipping"
		return 1
	fi

	info 'cloning nvm'
	git clone --depth=1 https://github.com/nvm-sh/nvm.git "$target_dir"
	success 'installed nvm'
}

source_nvm () {
	export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
	[[ -s "$NVM_DIR/nvm.sh" ]] || return 1

	# shellcheck source=/dev/null
	set +u
	source "$NVM_DIR/nvm.sh"
	set -u
}

install_bun_runtime () {
	if have_command bun
	then
		success 'bun already installed'
		return
	fi

	info 'installing bun'
	run_remote_script "https://bun.sh/install" bash
	success 'installed bun'
}

source_bun () {
	export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
	[[ -d "$BUN_INSTALL/bin" ]] && export PATH="$BUN_INSTALL/bin:$PATH"
	have_command bun
}

install_sdkman () {
	local sdkman_dir="${SDKMAN_DIR:-$HOME/.sdkman}"

	if [[ -s "$sdkman_dir/bin/sdkman-init.sh" ]]
	then
		success 'sdkman already installed'
		return
	fi

	info 'installing sdkman'
	export SDKMAN_DIR="$sdkman_dir"
	run_remote_script "https://get.sdkman.io" bash
	success 'installed sdkman'
}

source_sdkman () {
	export SDKMAN_DIR="${SDKMAN_DIR:-$HOME/.sdkman}"
	[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] || return 1

	export SDKMAN_AUTO_ANSWER="${SDKMAN_AUTO_ANSWER:-true}"
	export SDKMAN_SELFUPDATE="${SDKMAN_SELFUPDATE:-false}"
	# shellcheck source=/dev/null
	set +u
	source "$SDKMAN_DIR/bin/sdkman-init.sh"
	set -u
}
