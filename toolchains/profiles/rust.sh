#!/usr/bin/env bash

profile_rust () {
	local rust_toolchain="${DOTFILES_RUST_TOOLCHAIN:-stable}"
	local cargo_packages="${DOTFILES_RUST_CARGO_PACKAGES:-}"
	local package_list=()

	install_rustup || return 1
	source_cargo || {
		info 'rustup is not available after install'
		return 1
	}

	info "installing Rust toolchain: $rust_toolchain"
	rustup toolchain install "$rust_toolchain"
	rustup default "$rust_toolchain"
	rustup component add rustfmt clippy
	success 'Rust toolchain is ready'

	if [[ -n "$cargo_packages" ]]
	then
		read -r -a package_list <<< "$cargo_packages"
		for package in "${package_list[@]}"
		do
			info "installing cargo tool: $package"
			cargo install "$package"
		done
	fi
}
