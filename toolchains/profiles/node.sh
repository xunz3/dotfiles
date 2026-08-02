#!/usr/bin/env bash

profile_node () {
	local node_version="${DOTFILES_NODE_VERSION:-lts}"
	local pnpm_version="${DOTFILES_PNPM_VERSION:-latest}"
	local yarn_version="${DOTFILES_YARN_VERSION:-stable}"
	local global_packages="${DOTFILES_NODE_GLOBAL_PACKAGES:-typescript tsx prettier eslint npm-check-updates}"
	local package_list=()

	install_nvm || return 1
	source_nvm || {
		info 'nvm is not available after install'
		return 1
	}

	info "installing Node.js $node_version"
	case "$node_version" in
		lts|lts/*)
			nvm install --lts || return 1
			nvm alias default 'lts/*' || return 1
			;;
		*)
			nvm install "$node_version" || return 1
			nvm alias default "$node_version" || return 1
			;;
	esac
	nvm use default || return 1
	success 'Node.js is ready'

	if have_command corepack
	then
		info 'enabling Corepack package managers'
		corepack enable || return 1
		corepack prepare "pnpm@$pnpm_version" --activate || return 1
		corepack prepare "yarn@$yarn_version" --activate || return 1
		success 'Corepack package managers are ready'
	fi

	if [[ -n "$global_packages" ]]
	then
		read -r -a package_list <<< "$global_packages"
		info "installing npm globals: ${package_list[*]}"
		npm install -g "${package_list[@]}" || return 1
		success 'installed npm global packages'
	fi
}
