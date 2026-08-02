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

replace_managed_symlink () {
	local target=$1
	local link_path=$2
	local temporary_link="${link_path}.tmp.$$"

	if [[ -e "$link_path" && ! -L "$link_path" ]]
	then
		info "$link_path exists and is not a symlink; leaving it unchanged"
		return 1
	fi

	ln -s "$target" "$temporary_link" || return 1
	mv -Tf "$temporary_link" "$link_path" || return 1
}

neovim_checksum () {
	local version=$1
	local asset=$2

	if [[ -n "${DOTFILES_NEOVIM_SHA256:-}" ]]
	then
		printf '%s' "$DOTFILES_NEOVIM_SHA256"
		return 0
	fi

	case "$version:$asset" in
		v0.11.5:nvim-linux-x86_64.tar.gz)
			printf 'b2f91117be5b5ea39edd7297156dc2a4a8df4add6c95a90809a8df19e7ab6f52'
			;;
		v0.11.5:nvim-linux-arm64.tar.gz)
			printf 'ea4f9a31b11cc1477ff014aebb7b207684e7280f94ffa97abdab6cacd9b98519'
			;;
		*)
			info "no pinned SHA-256 for $version/$asset; set DOTFILES_NEOVIM_SHA256" >&2
			return 1
			;;
	esac
}

install_neovim () {
	local os arch asset version version_name install_root install_dir current_link tmp_dir url archive extracted_dir
	local expected_checksum actual_checksum

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

	mkdir -p "$HOME/.local/bin" "$install_root" || return 1

	if [[ -x "$install_dir/bin/nvim" ]]
	then
		replace_managed_symlink "$install_dir" "$current_link" || return 1
		replace_managed_symlink "$current_link/bin/nvim" "$HOME/.local/bin/nvim" || return 1
		success "selected Neovim $version_name"
		return 0
	fi

	if [[ -e "$install_dir" || -L "$install_dir" ]]
	then
		info "$install_dir exists but does not contain an executable nvim; leaving it unchanged"
		return 1
	fi

	if ! command -v curl >/dev/null 2>&1 || ! command -v sha256sum >/dev/null 2>&1
	then
		info 'curl and sha256sum are required to install Neovim'
		return 1
	fi

	if ! expected_checksum="$(neovim_checksum "$version" "$asset")"
	then
		return 1
	fi

	tmp_dir="$(mktemp -d)" || return 1
	trap "rm -rf -- '$tmp_dir'" EXIT

	url="https://github.com/neovim/neovim/releases/download/$version/$asset"
	archive="$tmp_dir/$asset"

	info "installing Neovim $version_name from the official release"
	curl -fsSL --connect-timeout 15 --max-time 300 "$url" -o "$archive" || return 1
	actual_checksum="$(sha256sum "$archive")" || return 1
	actual_checksum="${actual_checksum%% *}"
	if [[ "$actual_checksum" != "$expected_checksum" ]]
	then
		info "Neovim archive checksum mismatch for $asset"
		return 1
	fi

	tar -xzf "$archive" -C "$tmp_dir" || return 1

	extracted_dir="$tmp_dir/${asset%.tar.gz}"
	if [[ ! -x "$extracted_dir/bin/nvim" ]]
	then
		info "Neovim archive did not contain $extracted_dir/bin/nvim"
		return 1
	fi

	mv "$extracted_dir" "$install_dir" || return 1
	replace_managed_symlink "$install_dir" "$current_link" || return 1
	replace_managed_symlink "$current_link/bin/nvim" "$HOME/.local/bin/nvim" || return 1
	hash -r 2>/dev/null || true

	success "installed Neovim $version_name"
	return 0
}

NVIM_BIN="${HOME}/.local/bin/nvim"
install_status=0

if ! install_neovim
then
	info 'Neovim installation or version selection failed'
	install_status=1
fi

if [[ ! -x "$NVIM_BIN" ]] && command -v nvim >/dev/null 2>&1
then
	NVIM_BIN="$(command -v nvim)"
fi

if [[ ! -x "$NVIM_BIN" ]]
then
	info 'neovim is not installed yet; skipping plugin sync'
	exit 1
fi

info 'syncing Neovim plugins'
if "$NVIM_BIN" --headless "+Lazy! sync" +qa >/dev/null 2>&1
then
	success 'synced Neovim plugins'
else
	info 'Neovim plugin sync failed; run :Lazy sync manually after network and git are available'
	install_status=1
fi

exit "$install_status"
