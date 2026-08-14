#!/usr/bin/env bash
#
# Shared cache-profile selection protocol for Bash and Zsh consumers.

DOTFILES_CACHE_MANAGED_MARKER='# Managed by dotfiles script/cache-env.sh.'
DOTFILES_CACHE_MANAGED_END_MARKER='# End managed dotfiles cache environment.'
DOTFILES_CACHE_PROFILE=''

dotfiles_cache_profile_is_complete () {
	local candidate=$1
	local marker='' end_marker='' line='' first_line=true

	[[ -e "$candidate" && ! -L "$candidate" && -f "$candidate" &&
		-r "$candidate" ]] || return 1
	while IFS= read -r line || [[ -n "$line" ]]
	do
		if [[ "$first_line" == "true" ]]
		then
			marker=$line
			first_line=false
		fi
		end_marker=$line
	done < "$candidate"

	[[ "$marker" == "$DOTFILES_CACHE_MANAGED_MARKER" &&
		"$end_marker" == "$DOTFILES_CACHE_MANAGED_END_MARKER" ]]
}

dotfiles_cache_find_latest_version () {
	local version_dir=$1
	local candidate candidate_name version_digits latest_name=''

	DOTFILES_CACHE_PROFILE=''
	[[ -d "$version_dir" && ! -L "$version_dir" ]] || return 1
	if [[ -n "${ZSH_VERSION:-}" ]]
	then
		setopt LOCAL_OPTIONS NULL_GLOB
	fi

	for candidate in "$version_dir"/v*.sh
	do
		candidate_name=${candidate##*/}
		version_digits=${candidate_name#v}
		version_digits=${version_digits%.sh}
		[[ ${#version_digits} -eq 18 &&
			"$version_digits" != *[!0-9]* ]] || continue
		dotfiles_cache_profile_is_complete "$candidate" || continue
		if [[ -z "$latest_name" || "$candidate_name" > "$latest_name" ]]
		then
			latest_name=$candidate_name
			DOTFILES_CACHE_PROFILE=$candidate
		fi
	done

	[[ -n "$DOTFILES_CACHE_PROFILE" ]]
}

dotfiles_cache_select_profile () {
	local cache_root=$1
	local compatibility_file="$cache_root/cache-env.sh"
	local marker=''

	if dotfiles_cache_find_latest_version "$cache_root/cache-env.d"
	then
		return 0
	fi

	DOTFILES_CACHE_PROFILE=''
	if [[ -L "$compatibility_file" || ! -f "$compatibility_file" ||
		! -r "$compatibility_file" ]] ||
		! IFS= read -r marker < "$compatibility_file" ||
		[[ "$marker" != "$DOTFILES_CACHE_MANAGED_MARKER" ]]
	then
		return 1
	fi

	DOTFILES_CACHE_PROFILE=$compatibility_file
}
