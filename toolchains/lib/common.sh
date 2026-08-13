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
	local temporary_script status=0
	shift
	temporary_script="$(mktemp)" || return 1

	if have_command curl
	then
		if ! curl -fsSL --retry 2 --connect-timeout 15 --max-time 300 "$url" -o "$temporary_script"
		then
			rm -f -- "$temporary_script"
			return 1
		fi
	elif have_command wget
	then
		if ! wget -q --timeout=15 --tries=2 -O "$temporary_script" "$url"
		then
			rm -f -- "$temporary_script"
			return 1
		fi
	else
		info "neither curl nor wget is available; skipping $url"
		rm -f -- "$temporary_script"
		return 1
	fi

	if "$@" < "$temporary_script"
	then
		status=0
	else
		status=$?
	fi
	rm -f -- "$temporary_script"
	return "$status"
}
