#!/usr/bin/env bash
#
# Install or update the official Neovim release and sync plugins.

set -euo pipefail

info () {
	printf "\r  [ \033[00;34m..\033[0m ] %s\n" "$1"
}

success () {
	printf "\r\033[2K  [ \033[00;32mOK\033[0m ] %s\n" "$1"
}

run_with_timeout () {
	local seconds=$1
	shift

	if command -v timeout >/dev/null 2>&1
	then
		timeout "$seconds" "$@"
	else
		"$@"
	fi
}

install_neovim () {
	local os arch asset version version_name install_root install_dir current_link tmp_dir url archive extracted_dir

	os="$(uname -s)"
	arch="$(uname -m)"
	version="${DOTFILES_NEOVIM_VERSION:-v0.11.5}"
	version_name="${version#v}"

	if [[ "$os" != "Linux" ]]
	then
		info "unsupported OS for automatic Neovim install: $os"
		return 1
	fi

	case "$arch" in
		x86_64)
			asset='nvim-linux-x86_64.tar.gz'
			;;
		aarch64|arm64)
			asset='nvim-linux-arm64.tar.gz'
			;;
		*)
			info "unsupported architecture for automatic Neovim install: $arch"
			return 1
			;;
	esac

	install_root="$HOME/.local/opt"
	install_dir="$install_root/neovim-$version_name"
	current_link="$install_root/neovim-current"

	mkdir -p "$HOME/.local/bin" "$install_root"

	if [[ -x "$install_dir/bin/nvim" ]]
	then
		ln -sfn "$install_dir" "$current_link"
		ln -sfn "$current_link/bin/nvim" "$HOME/.local/bin/nvim"
		return 0
	fi

	tmp_dir="$(mktemp -d)"
	trap 'rm -rf "'"$tmp_dir"'"' EXIT

	url="https://github.com/neovim/neovim-releases/releases/download/$version/$asset"
	archive="$tmp_dir/$asset"

	info "installing Neovim $version_name from the official release"
	curl -fsSL "$url" -o "$archive"
	tar -xzf "$archive" -C "$tmp_dir"

	extracted_dir="$tmp_dir/${asset%.tar.gz}"
	rm -rf "$install_dir"
	mv "$extracted_dir" "$install_dir"
	ln -sfn "$install_dir" "$current_link"
	ln -sfn "$current_link/bin/nvim" "$HOME/.local/bin/nvim"
	hash -r 2>/dev/null || true

	success "installed Neovim $version_name"
	return 0
}

NVIM_BIN="${HOME}/.local/bin/nvim"

if [[ ! -x "$NVIM_BIN" ]]
then
	install_neovim || true
fi

if [[ ! -x "$NVIM_BIN" ]] && command -v nvim >/dev/null 2>&1
then
	NVIM_BIN="$(command -v nvim)"
fi

if [[ ! -x "$NVIM_BIN" ]]
then
	info 'neovim is not installed yet; skipping plugin sync'
	exit 0
fi

info 'syncing Neovim plugins'
if run_with_timeout "${DOTFILES_NVIM_PLUGIN_TIMEOUT:-300}" "$NVIM_BIN" --headless "+Lazy! sync" +qa >/dev/null 2>&1
then
	success 'synced Neovim plugins'
else
	info 'Neovim plugin sync failed; run :Lazy sync manually after network and git are available'
fi

if [[ "${DOTFILES_INSTALL_TOOLCHAINS:-0}" != "1" ]]
then
	exit 0
fi

info 'installing Mason language tools for the toolchain profile'
if run_with_timeout "${DOTFILES_MASON_TOOL_TIMEOUT:-600}" "$NVIM_BIN" --headless "+MasonToolsInstallSync" +qa >/dev/null 2>&1
then
	success 'installed Mason language tools'
else
	info 'Mason tool installation failed; run :MasonToolsInstallSync manually after network is available'
fi
