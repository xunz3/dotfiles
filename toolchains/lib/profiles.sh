#!/usr/bin/env bash

dotfiles_toolchain_all_profiles () {
	printf '%s\n' nvim node java rust go python bun
}

dotfiles_toolchain_legacy_profiles () {
	printf '%s\n' nvim

	[[ "${DOTFILES_INSTALL_NVM:-0}" == "1" ]] && printf '%s\n' node
	[[ "${DOTFILES_INSTALL_SDKMAN:-0}" == "1" ]] && printf '%s\n' java
	[[ "${DOTFILES_INSTALL_RUSTUP:-0}" == "1" ]] && printf '%s\n' rust
	[[ "${DOTFILES_INSTALL_BUN:-0}" == "1" ]] && printf '%s\n' bun
}

dotfiles_toolchain_default_profiles () {
	if [[ -n "${DOTFILES_TOOLCHAIN_PROFILES:-}" ]]
	then
		local profile
		for profile in $DOTFILES_TOOLCHAIN_PROFILES
		do
			printf '%s\n' "$profile"
		done
		return
	fi

	if [[ -n "${DOTFILES_TOOLCHAINS:-}" ]]
	then
		local profile
		for profile in $DOTFILES_TOOLCHAINS
		do
			printf '%s\n' "$profile"
		done
		return
	fi

	dotfiles_toolchain_legacy_profiles
}

dotfiles_toolchain_profile_exists () {
	local profile=$1
	local known

	for known in $(dotfiles_toolchain_all_profiles)
	do
		[[ "$known" == "$profile" ]] && return 0
	done

	return 1
}

dotfiles_toolchain_resolve_profiles () {
	local requested=("$@")
	local profile

	if [[ ${#requested[@]} -eq 0 ]]
	then
		mapfile -t requested < <(dotfiles_toolchain_default_profiles)
	fi

	{
		for profile in "${requested[@]}"
		do
			case "$profile" in
				all)
					dotfiles_toolchain_all_profiles
					;;
				default)
					dotfiles_toolchain_default_profiles
					;;
				*)
					printf '%s\n' "$profile"
					;;
			esac
		done
	} | awk '!seen[$0]++'
}
