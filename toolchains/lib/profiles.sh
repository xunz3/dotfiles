#!/usr/bin/env bash

dotfiles_toolchain_all_profiles () {
	printf '%s\n' node java rust go python bun agent
}

dotfiles_toolchain_profile_is_retired () {
	case "$1" in
		nvim) return 0 ;;
		*) return 1 ;;
	esac
}

dotfiles_load_toolchain_config () {
	local dotfiles_selection_was_set=false
	local dotfiles_selection=''

	if [[ "${DOTFILES_TOOLCHAINS+x}" == "x" ]]
	then
		dotfiles_selection_was_set=true
		dotfiles_selection=$DOTFILES_TOOLCHAINS
	fi

	# Load version/tool settings while keeping an explicit caller selection authoritative.
	if [[ -f "$HOME/.toolchainsrc" ]]
	then
		# shellcheck source=/dev/null
		source "$HOME/.toolchainsrc"
	fi

	if [[ "$dotfiles_selection_was_set" == "true" ]]
	then
		export DOTFILES_TOOLCHAINS="$dotfiles_selection"
	fi
}

dotfiles_toolchain_default_profiles () {
	if [[ -n "${DOTFILES_TOOLCHAINS:-}" ]]
	then
		local profile
		for profile in $DOTFILES_TOOLCHAINS
		do
			# Older templates selected nvim by default; ignore it only as legacy config.
			dotfiles_toolchain_profile_is_retired "$profile" && continue
			printf '%s\n' "$profile"
		done
		return
	fi

	return 0
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
