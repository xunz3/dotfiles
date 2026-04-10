#!/usr/bin/env bash
#
# Install optional developer toolchains. This installer is a no-op unless
# explicitly enabled for the current run or via ~/.toolchainsrc.

set -euo pipefail

info () {
	printf "\r  [ \033[00;34m..\033[0m ] %s\n" "$1"
}

success () {
	printf "\r\033[2K  [ \033[00;32mOK\033[0m ] %s\n" "$1"
}

have_command () {
	command -v "$1" >/dev/null 2>&1
}

run_remote_script () {
	local url=$1
	shift

	if have_command curl
	then
		curl -fsSL "$url" | "$@"
	elif have_command wget
	then
		wget -qO- "$url" | "$@"
	else
		info "neither curl nor wget is available; skipping $url"
		return 1
	fi
}

load_local_flags () {
	if [[ -f "$HOME/.toolchainsrc" ]]
	then
		# shellcheck source=/dev/null
		source "$HOME/.toolchainsrc"
	fi
}

want_toolchain () {
	local flag_name=$1

	[[ "${!flag_name:-0}" == "1" ]]
}

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
		return
	fi

	if [[ -e "$target_dir" ]]
	then
		info "$target_dir exists and is not an nvm install; skipping"
		return
	fi

	info 'cloning nvm'
	git clone --depth=1 https://github.com/nvm-sh/nvm.git "$target_dir"
	success 'installed nvm'
}

install_bun () {
	if have_command bun
	then
		success 'bun already installed'
		return
	fi

	info 'installing bun'
	run_remote_script "https://bun.sh/install" bash
	success 'installed bun'
}

install_sdkman () {
	local sdkman_dir="${SDKMAN_DIR:-$HOME/.sdkman}"

	if [[ -s "$sdkman_dir/bin/sdkman-init.sh" ]]
	then
		success 'sdkman already installed'
		return
	fi

	info 'installing sdkman'
	run_remote_script "https://get.sdkman.io" bash
	success 'installed sdkman'
}

load_local_flags

if [[ "${DOTFILES_INSTALL_TOOLCHAINS:-0}" != "1" ]]
then
	exit 0
fi

if ! want_toolchain DOTFILES_INSTALL_RUSTUP \
	&& ! want_toolchain DOTFILES_INSTALL_NVM \
	&& ! want_toolchain DOTFILES_INSTALL_BUN \
	&& ! want_toolchain DOTFILES_INSTALL_SDKMAN
then
	info 'no optional toolchains enabled in ~/.toolchainsrc; skipping'
	exit 0
fi

want_toolchain DOTFILES_INSTALL_RUSTUP && install_rustup
want_toolchain DOTFILES_INSTALL_NVM && install_nvm
want_toolchain DOTFILES_INSTALL_BUN && install_bun
want_toolchain DOTFILES_INSTALL_SDKMAN && install_sdkman
