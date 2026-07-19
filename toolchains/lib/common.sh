#!/usr/bin/env bash

info () {
	printf "\r  [ \033[00;34m..\033[0m ] %s\n" "$1"
}

success () {
	printf "\r\033[2K  [ \033[00;32mOK\033[0m ] %s\n" "$1"
}

fail () {
	printf "\r\033[2K  [\033[0;31mFAIL\033[0m] %s\n" "$1" >&2
	exit 1
}

have_command () {
	command -v "$1" >/dev/null 2>&1
}

prepend_path_if_dir () {
	local dir=$1

	[[ -d "$dir" ]] || return 0

	case ":$PATH:" in
		*":$dir:"*) ;;
		*) export PATH="$dir:$PATH" ;;
	esac
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

load_toolchain_config () {
	if [[ -f "$HOME/.toolchainsrc" ]]
	then
		# shellcheck source=/dev/null
		source "$HOME/.toolchainsrc"
	fi
}
