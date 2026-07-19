#!/usr/bin/env bash

dotfiles_toolchain_all_profiles () {
	printf '%s\n' nvim node java rust go python bun
}

dotfiles_toolchain_default_profiles () {
	if [[ -n "${DOTFILES_TOOLCHAINS:-}" ]]
	then
		local profile
		for profile in $DOTFILES_TOOLCHAINS
		do
			printf '%s\n' "$profile"
		done
		return
	fi

	printf '%s\n' nvim
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
