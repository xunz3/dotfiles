#!/usr/bin/env bash
#
# Interactive, dependency-free setup wizard.

set -euo pipefail

cd "$(dirname "$0")/.."
DOTFILES_ROOT=$(pwd -P)

dry_run=false
event_file=''
plain=false
preset_user=false

usage () {
	cat <<'EOF'
Usage: script/setup-tui.sh [options]

Options:
  --dry-run     collect choices and print the equivalent setup command
  --user        start with user-only installation selected
  -h, --help    show this help text
EOF
}

while [[ $# -gt 0 ]]
do
	case "$1" in
		--dry-run)
			dry_run=true
			;;
		--user)
			preset_user=true
			;;
		--events)
			if [[ $# -lt 2 || ! -r "${2:-}" ]]
			then
				printf 'setup TUI: --events requires a readable event file\n' >&2
				exit 2
			fi
			event_file=$2
			shift
			;;
		--plain)
			plain=true
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			printf 'setup TUI: unknown option: %s\n' "$1" >&2
			exit 2
			;;
	esac
	shift
done

if [[ -z "$event_file" && ( ! -t 0 || ! -t 1 ) ]]
then
	cat >&2 <<'EOF'
setup TUI: an interactive terminal is required.
Use `bin/dot setup --help` for the non-interactive CLI.
EOF
	exit 1
fi

if [[ -n "$event_file" ]]
then
	exec 3< "$event_file"
fi

use_ansi=false
use_color=false
if [[ "$plain" != "true" && -t 1 && "${TERM:-dumb}" != "dumb" ]]
then
	use_ansi=true
	if [[ -z "${NO_COLOR:-}" ]]
	then
		use_color=true
	fi
fi

reset=''
bold=''
dim=''
cyan=''
green=''
yellow=''
red=''
if [[ "$use_color" == "true" ]]
then
	reset=$'\033[0m'
	bold=$'\033[1m'
	dim=$'\033[2m'
	cyan=$'\033[36m'
	green=$'\033[32m'
	yellow=$'\033[33m'
	red=$'\033[31m'
fi

ui_active=false
TUI_EVENT=''
TUI_NAV=''
TUI_INDEX=0
TUI_TEXT=''
TUI_ERROR=''

ui_clear () {
	if [[ "$use_ansi" == "true" ]]
	then
		printf '\033[2J\033[H'
	else
		printf '\n'
	fi
}

ui_enter () {
	ui_active=true
	if [[ "$use_ansi" == "true" ]]
	then
		printf '\033[?25l'
	fi
}

ui_leave () {
	if [[ "$ui_active" != "true" ]]
	then
		return
	fi
	if [[ "$use_ansi" == "true" ]]
	then
		printf '\033[0m\033[?25h'
	fi
	ui_active=false
}

cleanup () {
	ui_leave
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

ui_header () {
	local step=$1 title=$2

	printf '%b\n' "${cyan}╭─ dotfiles · guided setup ─────────────────────────────╮${reset}"
	printf '%b\n' "${cyan}│${reset}  ${bold}${title}${reset}"
	printf '%b\n' "${cyan}╰──────────────────────────────────────────── ${step} ─╯${reset}"
	printf '\n'
}

ui_error () {
	if [[ -n "$TUI_ERROR" ]]
	then
		printf '  %b%s%b\n\n' "$red" "$TUI_ERROR" "$reset"
	fi
}

ui_hint () {
	printf '\n  %b%s%b\n' "$dim" "$1" "$reset"
}

read_terminal_event () {
	local key='' suffix=''

	if ! IFS= read -rsn1 key
	then
		TUI_EVENT='quit'
		return
	fi

	if [[ "$key" == $'\033' ]]
	then
		IFS= read -rsn2 -t 0.08 suffix || true
		key+="$suffix"
	fi

	case "$key" in
		$'\033[A'|$'\033OA'|k|K)
			TUI_EVENT='up'
			;;
		$'\033[B'|$'\033OB'|j|J)
			TUI_EVENT='down'
			;;
		$'\033[D'|$'\033OD'|$'\177'|$'\b'|b|B|$'\033')
			TUI_EVENT='back'
			;;
		$'\033[C'|$'\033OC'|$'\r'|'')
			TUI_EVENT='enter'
			;;
		' ')
			TUI_EVENT='toggle'
			;;
		a|A)
			TUI_EVENT='all'
			;;
		n|N)
			TUI_EVENT='none'
			;;
		q|Q)
			TUI_EVENT='quit'
			;;
		*)
			TUI_EVENT='unknown'
			;;
	esac
}

read_event () {
	if [[ -n "$event_file" ]]
	then
		if ! IFS= read -r TUI_EVENT <&3
		then
			TUI_EVENT='quit'
		fi
		return
	fi

	read_terminal_event
}

ui_radio () {
	local step=$1 title=$2 prompt=$3 current=$4
	shift 4
	local options=("$@")
	local option label description marker index

	TUI_NAV=''
	while true
	do
		ui_clear
		ui_header "$step" "$title"
		printf '  %s\n\n' "$prompt"
		ui_error

		for index in "${!options[@]}"
		do
			option=${options[$index]}
			label=${option%%|*}
			description=${option#*|}
			if [[ "$index" -eq "$current" ]]
			then
				marker="${green}●${reset}"
				printf '  %b  %b%s%b\n' "$marker" "$bold" "$label" "$reset"
			else
				marker="${dim}○${reset}"
				printf '  %b  %s\n' "$marker" "$label"
			fi
			printf '     %b%s%b\n\n' "$dim" "$description" "$reset"
		done

		ui_hint '↑/↓ or j/k move · Enter continue · b back · q quit'
		read_event
		TUI_ERROR=''
		case "$TUI_EVENT" in
			up)
				current=$((current - 1))
				[[ "$current" -lt 0 ]] && current=$((${#options[@]} - 1))
				;;
			down)
				current=$((current + 1))
				[[ "$current" -ge "${#options[@]}" ]] && current=0
				;;
			enter|toggle)
				TUI_INDEX=$current
				TUI_NAV='next'
				return
				;;
			back)
				TUI_INDEX=$current
				TUI_NAV='back'
				return
				;;
			quit)
				TUI_NAV='quit'
				return
				;;
		esac
	done
}

ui_text_input () {
	local step=$1 title=$2 prompt=$3 current=${4:-}
	local value=''

	TUI_NAV=''
	ui_clear
	ui_header "$step" "$title"
	printf '  %s\n' "$prompt"
	if [[ -n "$current" ]]
	then
		printf '  %bCurrent: %s%b\n' "$dim" "$current" "$reset"
	fi
	printf '\n'
	ui_error

	if [[ -n "$event_file" ]]
	then
		ui_hint 'event input: text:VALUE · back · quit'
		read_event
		case "$TUI_EVENT" in
			text:*)
				value=${TUI_EVENT#text:}
				;;
			back)
				TUI_NAV='back'
				return
				;;
			quit)
				TUI_NAV='quit'
				return
				;;
			*)
				TUI_ERROR='Expected text input.'
				TUI_NAV='retry'
				return
				;;
		esac
	else
		if [[ "$use_ansi" == "true" ]]
		then
			printf '\033[?25h'
		fi
		printf '  > '
		if ! IFS= read -r value
		then
			TUI_NAV='quit'
			return
		fi
		if [[ "$use_ansi" == "true" ]]
		then
			printf '\033[?25l'
		fi
		if [[ "$value" == ':back' ]]
		then
			TUI_NAV='back'
			return
		fi
	fi

	[[ -z "$value" ]] && value=$current
	TUI_TEXT=$value
	TUI_NAV='next'
}

detect_package_manager () {
	if command -v apt-get >/dev/null 2>&1
	then
		printf 'apt'
	elif command -v dnf >/dev/null 2>&1
	then
		printf 'dnf'
	elif command -v pacman >/dev/null 2>&1
	then
		printf 'pacman'
	elif command -v zypper >/dev/null 2>&1
	then
		printf 'zypper'
	else
		printf 'not detected'
	fi
}

detect_distro () {
	if [[ -r /etc/os-release ]]
	then
		(
			set +u
			# shellcheck source=/dev/null
			source /etc/os-release
			printf '%s' "${PRETTY_NAME:-${NAME:-Linux}}"
		)
	else
		printf 'Linux'
	fi
}

workspace_parent_is_writable () {
	local path=$1 parent=$1

	if [[ -e "$path" || -L "$path" ]]
	then
		[[ -d "$path" && -w "$path" && -x "$path" ]]
		return
	fi

	while [[ "$parent" != "/" && ! -e "$parent" && ! -L "$parent" ]]
	do
		parent="${parent%/*}"
		[[ -n "$parent" ]] || parent='/'
	done

	[[ -d "$parent" && -w "$parent" && -x "$parent" ]]
}

path_is_managed_link () {
	local source_path=$1 target_path=$2
	[[ -L "$target_path" && "$(readlink "$target_path")" == "$source_path" ]]
}

collect_conflicts () {
	local source_path target_path relative_path
	CONFLICT_PATHS=()

	while IFS= read -r -d '' source_path
	do
		target_path="$HOME/.$(basename "${source_path%.*}")"
		if [[ -e "$target_path" || -L "$target_path" ]]
		then
			path_is_managed_link "$source_path" "$target_path" || CONFLICT_PATHS+=("$target_path")
		fi
	done < <(find -H "$DOTFILES_ROOT" -maxdepth 2 -name '*.symlink' \
		-not -name 'gitconfig.local.symlink' -not -path '*.git*' -print0)

	while IFS= read -r -d '' source_path
	do
		relative_path="${source_path#"$DOTFILES_ROOT"/}"
		relative_path="${relative_path#*/config/}"
		target_path="$HOME/.config/$relative_path"
		if [[ -e "$target_path" || -L "$target_path" ]]
		then
			path_is_managed_link "$source_path" "$target_path" || CONFLICT_PATHS+=("$target_path")
		fi
	done < <(find -H "$DOTFILES_ROOT" -mindepth 3 -maxdepth 3 -path '*/config/*' \
		-not -path '*.git*' -print0)
}

decode_hex () {
	local hex=$1 decoded='' byte=''
	local index

	if [[ -z "$hex" || "$hex" == *[![:xdigit:]]* ||
		$((${#hex} % 2)) -ne 0 ]]
	then
		return 1
	fi

	for ((index = 0; index < ${#hex}; index += 2))
	do
		[[ "${hex:index:2}" != '00' ]] || return 1
		printf -v byte '%b' "\\x${hex:index:2}"
		decoded+=$byte
	done

	printf '%s' "$decoded"
}

find_latest_cache_profile () {
	local version_dir=$1 candidate candidate_name version_digits latest_name=''
	local marker='' end_marker='' line='' first_line=false

	CACHE_LATEST_PROFILE=''
	[[ -d "$version_dir" && ! -L "$version_dir" ]] || return 1
	for candidate in "$version_dir"/v*.sh
	do
		[[ -e "$candidate" && ! -L "$candidate" && -f "$candidate" &&
			-r "$candidate" ]] || continue
		candidate_name=${candidate##*/}
		version_digits=${candidate_name#v}
		version_digits=${version_digits%.sh}
		[[ ${#version_digits} -eq 18 &&
			"$version_digits" != *[!0-9]* ]] || continue
		marker=''
		end_marker=''
		line=''
		first_line=true
		while IFS= read -r line || [[ -n "$line" ]]
		do
			if [[ "$first_line" == "true" ]]
			then
				marker=$line
				first_line=false
			fi
			end_marker=$line
		done < "$candidate"
		[[ "$marker" == '# Managed by dotfiles script/cache-env.sh.' &&
			"$end_marker" == '# End managed dotfiles cache environment.' ]] ||
			continue
		if [[ -z "$latest_name" || "$candidate_name" > "$latest_name" ]]
		then
			latest_name=$candidate_name
			CACHE_LATEST_PROFILE=$candidate
		fi
	done

	[[ -n "$CACHE_LATEST_PROFILE" ]]
}

detect_cache_workspace () {
	local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
	local cache_root version_dir cache_file marker='' metadata='' decoded=''
	local header=()

	CACHE_PROFILE_STATUS='missing'
	CACHE_PROFILE_DETAIL='not configured'
	CURRENT_CACHE_WORKSPACE=''
	cache_root="$config_home/dotfiles"
	version_dir="$cache_root/cache-env.d"
	cache_file="$cache_root/cache-env.sh"
	CACHE_CONFIG_FILE=$cache_file

	if [[ "$config_home" != /* ]]
	then
		CACHE_PROFILE_STATUS='blocked'
		CACHE_PROFILE_DETAIL='XDG_CONFIG_HOME is not absolute'
		return
	fi
	if [[ -L "$version_dir" || ( -e "$version_dir" && ! -d "$version_dir" ) ]]
	then
		CACHE_PROFILE_STATUS='blocked'
		CACHE_PROFILE_DETAIL='cache-env.d is not a regular directory'
		CACHE_CONFIG_FILE=$version_dir
		return
	fi
	if find_latest_cache_profile "$version_dir"
	then
		cache_file=$CACHE_LATEST_PROFILE
		CACHE_CONFIG_FILE=$cache_file
	elif [[ ! -e "$cache_file" && ! -L "$cache_file" ]]
	then
		return
	fi
	if [[ -L "$cache_file" ]]
	then
		CACHE_PROFILE_STATUS='blocked'
		CACHE_PROFILE_DETAIL='cache-env.sh is a symbolic link'
		return
	fi
	if [[ ! -e "$cache_file" ]]
	then
		return
	fi
	if [[ ! -f "$cache_file" || ! -r "$cache_file" ]]
	then
		CACHE_PROFILE_STATUS='blocked'
		CACHE_PROFILE_DETAIL='cache-env.sh is not a readable regular file'
		return
	fi

	mapfile -t header < <(head -n 2 -- "$cache_file")
	marker=${header[0]:-}
	if [[ "$marker" != '# Managed by dotfiles script/cache-env.sh.' ]]
	then
		CACHE_PROFILE_STATUS='blocked'
		CACHE_PROFILE_DETAIL='cache-env.sh is not managed by dotfiles'
		return
	fi

	CACHE_PROFILE_STATUS='managed'
	CACHE_PROFILE_DETAIL='managed profile (workspace unavailable)'
	metadata=${header[1]:-}
	if [[ "$metadata" != '# Workspace-Hex: '* ]]
	then
		return
	fi
	if ! decoded="$(decode_hex "${metadata#\# Workspace-Hex: }")" ||
		[[ "$decoded" != /* || "$decoded" == "/" || "$decoded" =~ [[:cntrl:]] ]]
	then
		return
	fi

	CURRENT_CACHE_WORKSPACE=$decoded
	CACHE_PROFILE_DETAIL="$CURRENT_CACHE_WORKSPACE/cache"
}

trim_whitespace () {
	local value=$1

	value="${value#"${value%%[![:space:]]*}"}"
	value="${value%"${value##*[![:space:]]}"}"
	printf '%s' "$value"
}

parse_toolchain_defaults_value () {
	local value
	local double_quoted='^"([[:alnum:]_[:space:]-]*)"([[:space:]]+#.*)?[[:space:]]*$'
	local single_quoted="^'([[:alnum:]_[:space:]-]*)'([[:space:]]+#.*)?[[:space:]]*$"
	local unquoted='^([[:alnum:]_-]*)([[:space:]]+#.*)?[[:space:]]*$'

	value="$(trim_whitespace "$1")"
	if [[ "$value" =~ $double_quoted || "$value" =~ $single_quoted ||
		"$value" =~ $unquoted ]]
	then
		TOOLCHAIN_PARSED_VALUE=${BASH_REMATCH[1]}
		return 0
	fi

	return 1
}

read_toolchain_defaults () {
	local file=$1 line='' value='' trimmed=''
	local found=false valid=false tainted=false

	[[ -f "$file" && -r "$file" ]] || return 1
	while IFS= read -r line || [[ -n "$line" ]]
	do
		if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?DOTFILES_TOOLCHAINS[[:space:]]*=(.*)$ ]]
		then
			found=true
			value=${BASH_REMATCH[2]}
			if parse_toolchain_defaults_value "$value"
			then
				value=$TOOLCHAIN_PARSED_VALUE
				valid=true
			else
				valid=false
			fi
			continue
		fi

		trimmed="$(trim_whitespace "$line")"
		if [[ -z "$trimmed" || "$trimmed" == \#* ]]
		then
			continue
		fi
		if [[ "$trimmed" == *DOTFILES_TOOLCHAINS* ||
			"$trimmed" == source\ * || "$trimmed" == .\ * ||
			"$trimmed" == eval\ * ]]
		then
			found=true
			valid=false
			tainted=true
		fi
	done < "$file"

	[[ "$found" == "true" && "$valid" == "true" &&
		"$tainted" == "false" ]] || return 1
	printf '%s' "$value"
}

profile_description () {
	case "$1" in
		nvim) printf 'Neovim Mason language servers and formatters' ;;
		node) printf 'Node.js LTS, pnpm, yarn, and global tools' ;;
		java) printf 'JDK, Maven, Gradle, and Kotlin' ;;
		rust) printf 'Rust stable, rustfmt, and clippy' ;;
		go) printf 'Go language server, formatter, imports, and debugger' ;;
		python) printf 'uv, Ruff, IPython, and configured Python tools' ;;
		bun) printf 'Bun runtime and package manager' ;;
		*) printf 'Optional developer toolchain' ;;
	esac
}

load_profile_defaults () {
	local defaults="${DOTFILES_TOOLCHAINS:-}"
	local profile index

	PROFILE_DEFAULTS_WARNING=''
	if [[ -z "$defaults" &&
		( -e "$HOME/.toolchainsrc" || -L "$HOME/.toolchainsrc" ) ]]
	then
		if ! defaults="$(read_toolchain_defaults "$HOME/.toolchainsrc")"
		then
			defaults=''
			PROFILE_DEFAULTS_WARNING='Could not safely read DOTFILES_TOOLCHAINS; no profiles were preselected.'
		fi
	fi
	if [[ -z "$defaults" && -z "$PROFILE_DEFAULTS_WARNING" ]]
	then
		defaults='nvim'
	fi

	PROFILE_SELECTED=()
	for _ in "${PROFILE_NAMES[@]}"
	do
		PROFILE_SELECTED+=(0)
	done
	for profile in $defaults
	do
		if [[ "$profile" == "all" ]]
		then
			for index in "${!PROFILE_SELECTED[@]}"
			do
				PROFILE_SELECTED[$index]=1
			done
			continue
		fi
		if [[ "$profile" == "default" ]]
		then
			profile='nvim'
		fi
		for index in "${!PROFILE_NAMES[@]}"
		do
			if [[ "${PROFILE_NAMES[$index]}" == "$profile" ]]
			then
				PROFILE_SELECTED[$index]=1
			fi
		done
	done
	return 0
}

ui_toolchains () {
	local cursor=${1:-0}
	local index marker description

	TUI_NAV=''
	while true
	do
		ui_clear
		ui_header 'tools' 'Developer toolchains'
		printf '  Select any profiles to install. An empty selection installs none.\n\n'
		if [[ -n "$PROFILE_DEFAULTS_WARNING" ]]
		then
			printf '  %bWarning:%b %s\n\n' "$yellow" "$reset" "$PROFILE_DEFAULTS_WARNING"
		fi
		ui_error

		for index in "${!PROFILE_NAMES[@]}"
		do
			if [[ "${PROFILE_SELECTED[$index]}" == "1" ]]
			then
				marker="${green}✓${reset}"
			else
				marker=' '
			fi
			description="$(profile_description "${PROFILE_NAMES[$index]}")"
			if [[ "$index" -eq "$cursor" ]]
			then
				printf '  %b› [%b] %b%s%b\n' "$cyan" "$marker" "$bold" "${PROFILE_NAMES[$index]}" "$reset"
			else
				printf '    [%b] %s\n' "$marker" "${PROFILE_NAMES[$index]}"
			fi
			printf '        %b%s%b\n' "$dim" "$description" "$reset"
		done

		ui_hint '↑/↓ move · Space toggle · a all · n none · Enter continue · b back'
		read_event
		TUI_ERROR=''
		case "$TUI_EVENT" in
			up)
				cursor=$((cursor - 1))
				[[ "$cursor" -lt 0 ]] && cursor=$((${#PROFILE_NAMES[@]} - 1))
				;;
			down)
				cursor=$((cursor + 1))
				[[ "$cursor" -ge "${#PROFILE_NAMES[@]}" ]] && cursor=0
				;;
			toggle)
				if [[ "${PROFILE_SELECTED[$cursor]}" == "1" ]]
				then
					PROFILE_SELECTED[$cursor]=0
				else
					PROFILE_SELECTED[$cursor]=1
				fi
				;;
			all)
				for index in "${!PROFILE_SELECTED[@]}"
				do
					PROFILE_SELECTED[$index]=1
				done
				;;
			none)
				for index in "${!PROFILE_SELECTED[@]}"
				do
					PROFILE_SELECTED[$index]=0
				done
				;;
			enter)
				PROFILE_CURSOR=$cursor
				TUI_NAV='next'
				return
				;;
			back)
				PROFILE_CURSOR=$cursor
				TUI_NAV='back'
				return
				;;
			quit)
				TUI_NAV='quit'
				return
				;;
		esac
	done
}

selected_profiles () {
	local index
	SELECTED_PROFILES=()
	for index in "${!PROFILE_NAMES[@]}"
	do
		if [[ "${PROFILE_SELECTED[$index]}" == "1" ]]
		then
			SELECTED_PROFILES+=("${PROFILE_NAMES[$index]}")
		fi
	done
	return 0
}

build_setup_args () {
	local force_path
	local force_path_list=()

	SETUP_ARGS=()
	case "$CONFLICT_INDEX" in
		0) SETUP_ARGS+=(--backup) ;;
		1) ;;
		2) SETUP_ARGS+=(--skip) ;;
		3)
			if [[ "$FORCE_PATHS_CONFIRMED" == "true" ]]
			then
				force_path_list=("${CONFIRMED_CONFLICT_PATHS[@]}")
			else
				force_path_list=("${CONFLICT_PATHS[@]}")
			fi
			for force_path in "${force_path_list[@]}"
			do
				SETUP_ARGS+=(--force-path "$force_path")
			done
			;;
	esac
	[[ "$PACKAGE_INDEX" == "1" ]] && SETUP_ARGS+=(--user)
	if [[ "$CACHE_INDEX" == "1" ]]
	then
		SETUP_ARGS+=(--cache-workspace "$CACHE_WORKSPACE")
	fi
	if [[ "$GIT_CONFIG_STATUS" == "blocked" ||
		( "$GIT_CONFIG_EXISTS" != "true" && "$GIT_INDEX" == "1" ) ]]
	then
		SETUP_ARGS+=(--skip-gitconfig)
	fi

	selected_profiles
	if [[ ${#SELECTED_PROFILES[@]} -gt 0 ]]
	then
		SETUP_ARGS+=(--toolchains "${SELECTED_PROFILES[@]}")
	fi
}

display_command () {
	local argument
	if [[ "$GIT_CONFIG_EXISTS" != "true" && "$GIT_INDEX" == "0" ]]
	then
		printf 'DOTFILES_GIT_AUTHORNAME=%q DOTFILES_GIT_AUTHOREMAIL=%q ' \
			"$GIT_AUTHOR_NAME" "$GIT_AUTHOR_EMAIL"
	fi
	printf 'bin/dot setup'
	for argument in "${SETUP_ARGS[@]}"
	do
		printf ' %q' "$argument"
	done
}

ui_welcome () {
	local index

	TUI_NAV=''
	while true
	do
		ui_clear
		ui_header 'start' 'Set up this Linux device'
		printf '  Review this machine, choose what to install, then run the\n'
		printf '  existing setup command. Nothing changes before confirmation.\n\n'
		printf '  %-18s %s\n' 'System' "$DISTRO_NAME"
		printf '  %-18s %s\n' 'Package manager' "$PACKAGE_MANAGER"
		printf '  %-18s %s\n' 'Home' "$HOME"
		printf '  %-18s %s\n' 'Repository' "$DOTFILES_ROOT"
		printf '  %-18s %s\n' 'Link conflicts' "${#CONFLICT_PATHS[@]}"
		printf '  %-18s %s\n' 'Cache profile' "$CACHE_PROFILE_DETAIL"
		printf '  %-18s %s\n' 'Git config' "$GIT_CONFIG_DETAIL"
		printf '  %-18s %s\n' 'Privileges' "$PRIVILEGE_DETAIL"
		if [[ ${#CONFLICT_PATHS[@]} -gt 0 ]]
		then
			printf '\n  %bConflicting paths:%b\n' "$yellow" "$reset"
			for index in "${!CONFLICT_PATHS[@]}"
			do
				[[ "$index" -ge 4 ]] && break
				printf '    %s\n' "${CONFLICT_PATHS[$index]}"
			done
			[[ ${#CONFLICT_PATHS[@]} -gt 4 ]] &&
				printf '    … and %d more\n' "$((${#CONFLICT_PATHS[@]} - 4))"
		fi
		if [[ "$CACHE_PROFILE_STATUS" == "blocked" ]]
		then
			printf '\n  %bCache setup warning:%b %s\n' "$yellow" "$reset" "$CACHE_PROFILE_DETAIL"
		fi
		if [[ "$GIT_CONFIG_STATUS" == "blocked" ]]
		then
			printf '\n  %bGit setup warning:%b %s\n' "$yellow" "$reset" "$GIT_CONFIG_DETAIL"
		fi
		ui_hint 'Enter begin · q quit'
		read_event
		case "$TUI_EVENT" in
			enter)
				TUI_NAV='next'
				return
				;;
			quit|back)
				TUI_NAV='quit'
				return
				;;
		esac
	done
}

ui_summary () {
	local cache_summary git_summary profile_summary conflict_summary package_summary

	build_setup_args
	if [[ ${#CONFLICT_PATHS[@]} -eq 0 ]]
	then
		conflict_summary='No conflicts detected'
	else
		case "$CONFLICT_INDEX" in
			0) conflict_summary='Back up conflicts' ;;
			1) conflict_summary='Ask for each conflict' ;;
			2) conflict_summary='Skip conflicting links' ;;
			3) conflict_summary='Overwrite confirmed paths' ;;
		esac
	fi
	if [[ "$PACKAGE_INDEX" == "0" ]]
	then
		package_summary="Install with $PACKAGE_MANAGER"
	else
		package_summary='User-only; skip system packages'
	fi
	if [[ "$CACHE_INDEX" == "1" ]]
	then
		cache_summary="$CACHE_WORKSPACE/cache"
	elif [[ -n "$CURRENT_CACHE_WORKSPACE" ]]
	then
		cache_summary="Keep $CURRENT_CACHE_WORKSPACE/cache"
	elif [[ "$CACHE_PROFILE_STATUS" == "managed" ]]
	then
		cache_summary='Keep existing managed cache profile'
	elif [[ "$CACHE_PROFILE_STATUS" == "blocked" ]]
	then
		cache_summary='Leave existing cache target unchanged'
	else
		cache_summary='System defaults'
	fi
	selected_profiles
	profile_summary="${SELECTED_PROFILES[*]:-none}"
	if [[ -n "$PROFILE_DEFAULTS_WARNING" && ${#SELECTED_PROFILES[@]} -eq 0 ]]
	then
		profile_summary='none (defaults unreadable)'
	fi
	if [[ "$GIT_CONFIG_STATUS" == "valid" ]]
	then
		git_summary='Keep existing ~/.gitconfig.local'
	elif [[ "$GIT_CONFIG_STATUS" == "blocked" ]]
	then
		git_summary='Skip invalid ~/.gitconfig.local target'
	elif [[ "$GIT_INDEX" == "0" ]]
	then
		git_summary="$GIT_AUTHOR_NAME <$GIT_AUTHOR_EMAIL>"
	else
		git_summary='Configure later'
	fi

	SUMMARY_INDEX=${SUMMARY_INDEX:-0}
	while true
	do
		ui_clear
		ui_header 'review' 'Ready to set up'
		printf '  %-18s %s\n' 'Conflicts' "$conflict_summary"
		printf '  %-18s %s\n' 'Packages' "$package_summary"
		printf '  %-18s %s\n' 'Cache' "$cache_summary"
		printf '  %-18s %s\n' 'Toolchains' "$profile_summary"
		printf '  %-18s %s\n' 'Git identity' "$git_summary"
		printf '\n  %bEquivalent command:%b\n  ' "$dim" "$reset"
		display_command
		printf '\n\n'
		ui_error

		if [[ "$SUMMARY_INDEX" == "0" ]]
		then
			printf '  %b●  %bRun setup%b\n' "$green" "$bold" "$reset"
		else
			printf '  ○  Run setup\n'
		fi
		if [[ "$SUMMARY_INDEX" == "1" ]]
		then
			printf '  %b●  %bReview choices again%b\n' "$green" "$bold" "$reset"
		else
			printf '  ○  Review choices again\n'
		fi
		if [[ "$SUMMARY_INDEX" == "2" ]]
		then
			printf '  %b●  %bQuit without changes%b\n' "$green" "$bold" "$reset"
		else
			printf '  ○  Quit without changes\n'
		fi

		ui_hint '↑/↓ move · Enter select · b back · q quit'
		read_event
		TUI_ERROR=''
		case "$TUI_EVENT" in
			up)
				SUMMARY_INDEX=$((SUMMARY_INDEX - 1))
				[[ "$SUMMARY_INDEX" -lt 0 ]] && SUMMARY_INDEX=2
				;;
			down)
				SUMMARY_INDEX=$((SUMMARY_INDEX + 1))
				[[ "$SUMMARY_INDEX" -gt 2 ]] && SUMMARY_INDEX=0
				;;
			enter|toggle)
				case "$SUMMARY_INDEX" in
					0) TUI_NAV='run' ;;
					1) TUI_NAV='edit' ;;
					2) TUI_NAV='quit' ;;
				esac
				return
				;;
			back)
				TUI_NAV='back'
				return
				;;
			quit)
				TUI_NAV='quit'
				return
				;;
		esac
	done
}

# shellcheck source=toolchains/lib/profiles.sh
source "$DOTFILES_ROOT/toolchains/lib/profiles.sh"
mapfile -t PROFILE_NAMES < <(dotfiles_toolchain_all_profiles)
load_profile_defaults
PROFILE_CURSOR=0
SELECTED_PROFILES=()
SETUP_ARGS=()

DISTRO_NAME="$(detect_distro)"
PACKAGE_MANAGER="$(detect_package_manager)"
CAN_INSTALL_PACKAGES=true
if [[ "$PACKAGE_MANAGER" == "not detected" ]]
then
	CAN_INSTALL_PACKAGES=false
	PRIVILEGE_DETAIL='system packages unavailable'
elif [[ "${EUID}" -ne 0 ]] && ! command -v sudo >/dev/null 2>&1
then
	CAN_INSTALL_PACKAGES=false
	PRIVILEGE_DETAIL='sudo unavailable; user-only setup'
elif [[ "${EUID}" -eq 0 ]]
then
	PRIVILEGE_DETAIL='running as root'
else
	PRIVILEGE_DETAIL='sudo authentication after confirmation'
fi

collect_conflicts
detect_cache_workspace

PACKAGE_INDEX=0
if [[ "$preset_user" == "true" || "$CAN_INSTALL_PACKAGES" != "true" ]]
then
	PACKAGE_INDEX=1
fi
CONFLICT_INDEX=0
CONFIRMED_CONFLICT_PATHS=()
FORCE_PATHS_CONFIRMED=false
CACHE_INDEX=0
CACHE_WORKSPACE="${CURRENT_CACHE_WORKSPACE:-}"
GIT_CONFIG_EXISTS=false
GIT_CONFIG_STATUS='missing'
GIT_CONFIG_DETAIL='not configured'
if [[ -f "$HOME/.gitconfig.local" && -r "$HOME/.gitconfig.local" ]]
then
	GIT_CONFIG_EXISTS=true
	GIT_CONFIG_STATUS='valid'
	GIT_CONFIG_DETAIL='readable ~/.gitconfig.local'
elif [[ -e "$HOME/.gitconfig.local" || -L "$HOME/.gitconfig.local" ]]
then
	GIT_CONFIG_EXISTS=true
	GIT_CONFIG_STATUS='blocked'
	GIT_CONFIG_DETAIL='~/.gitconfig.local is not a readable regular file'
fi
GIT_INDEX=0
GIT_AUTHOR_NAME="${DOTFILES_GIT_AUTHORNAME:-}"
GIT_AUTHOR_EMAIL="${DOTFILES_GIT_AUTHOREMAIL:-}"
SUMMARY_INDEX=0

ui_enter
screen='welcome'
while true
do
	case "$screen" in
		welcome)
			ui_welcome
			case "$TUI_NAV" in
				next) screen='packages' ;;
				quit) break ;;
			esac
			;;
		packages)
			ui_radio 'packages' 'Installation scope' \
				'Choose whether setup may install system packages.' "$PACKAGE_INDEX" \
				"Install system packages|Use $PACKAGE_MANAGER, sudo when needed, then install user tools" \
				'User-only setup|Skip the system package manager and install user-level topics'
			PACKAGE_INDEX=$TUI_INDEX
			case "$TUI_NAV" in
				next)
					if [[ "$PACKAGE_INDEX" == "0" && "$CAN_INSTALL_PACKAGES" != "true" ]]
					then
						TUI_ERROR='No supported package manager or sudo access was detected.'
					elif [[ ${#CONFLICT_PATHS[@]} -eq 0 ]]
					then
						screen='cache'
					else
						screen='conflicts'
					fi
					;;
				back) screen='welcome' ;;
				quit) break ;;
			esac
			;;
		conflicts)
			ui_radio 'files' 'Existing configuration' \
				"Choose how to handle ${#CONFLICT_PATHS[@]} conflicting managed paths." "$CONFLICT_INDEX" \
				'Back up conflicts (recommended)|Move conflicts into a timestamped, recoverable backup session' \
				'Ask for each conflict|Use the existing bootstrap prompt for every conflicting path' \
				'Skip conflicting links|Keep conflicting files and do not create those managed links' \
				'Overwrite conflicts (dangerous)|Remove only the paths listed in the next confirmation'
			CONFLICT_INDEX=$TUI_INDEX
			FORCE_PATHS_CONFIRMED=false
			CONFIRMED_CONFLICT_PATHS=()
			case "$TUI_NAV" in
				next)
					if [[ -n "$event_file" && "$CONFLICT_INDEX" == "1" ]]
					then
						TUI_ERROR='Per-file conflict prompts require a real interactive terminal.'
					else
						screen='cache'
					fi
					;;
				back) screen='packages' ;;
				quit) break ;;
			esac
			;;
		cache)
			if [[ "$CACHE_PROFILE_STATUS" == "blocked" ]]
			then
				cache_options=(
					"Leave cache target unchanged|Resolve $CACHE_CONFIG_FILE manually before configuring it"
				)
			elif [[ "$CACHE_PROFILE_STATUS" == "managed" ]]
			then
				if [[ -n "$CURRENT_CACHE_WORKSPACE" ]]
				then
					cache_options=(
						"Keep current cache workspace|Continue using $CURRENT_CACHE_WORKSPACE/cache"
						'Change cache workspace|Generate the cache profile for a different data directory'
					)
				else
					cache_options=(
						'Keep existing cache profile|Leave the existing managed profile unchanged'
						'Set cache workspace|Regenerate it with a known workspace directory'
					)
				fi
			else
				cache_options=(
					'Use application defaults|Do not generate a machine-local cache profile'
					'Configure a cache workspace|Put supported application caches under WORKSPACE/cache'
				)
			fi
			ui_radio 'cache' 'Cache workspace' \
				'Choose where large caches and temporary build data should live.' "$CACHE_INDEX" \
				"${cache_options[@]}"
			CACHE_INDEX=$TUI_INDEX
			case "$TUI_NAV" in
				next)
					if [[ "$CACHE_INDEX" == "1" ]]
					then
						screen='cache_path'
					else
						screen='toolchains'
					fi
					;;
				back)
					if [[ ${#CONFLICT_PATHS[@]} -eq 0 ]]
					then
						screen='packages'
					else
						screen='conflicts'
					fi
					;;
				quit) break ;;
			esac
			;;
		cache_path)
			ui_text_input 'cache' 'Cache workspace' \
				'Enter an absolute workspace path. Type :back to return.' "$CACHE_WORKSPACE"
			case "$TUI_NAV" in
				next)
					if [[ -z "$TUI_TEXT" || "$TUI_TEXT" != /* ]]
					then
						TUI_ERROR='The cache workspace must be an absolute path.'
					elif ! CACHE_WORKSPACE="$(realpath -m -- "$TUI_TEXT")" ||
						[[ "$CACHE_WORKSPACE" == "/" ]]
					then
						TUI_ERROR='The cache workspace cannot resolve to /.'
					elif ! workspace_parent_is_writable "$CACHE_WORKSPACE"
					then
						TUI_ERROR='The workspace or its nearest existing parent is not a writable directory.'
					else
						TUI_ERROR=''
						screen='toolchains'
					fi
					;;
				retry) ;;
				back) screen='cache' ;;
				quit) break ;;
			esac
			;;
		toolchains)
			ui_toolchains "$PROFILE_CURSOR"
			case "$TUI_NAV" in
				next)
					if [[ "$GIT_CONFIG_EXISTS" == "true" ]]
					then
						screen='summary'
					else
						screen='git'
					fi
					;;
				back)
					if [[ "$CACHE_INDEX" == "1" ]]
					then
						screen='cache_path'
					else
						screen='cache'
					fi
					;;
				quit) break ;;
			esac
			;;
		git)
			ui_radio 'identity' 'Git identity' \
				'Configure the local Git identity used on this device.' "$GIT_INDEX" \
				'Configure now|Create ~/.gitconfig.local from the name and email entered here' \
				'Configure later|Skip ~/.gitconfig.local during this setup'
			GIT_INDEX=$TUI_INDEX
			case "$TUI_NAV" in
				next)
					if [[ "$GIT_INDEX" == "0" ]]
					then
						screen='git_name'
					else
						screen='summary'
					fi
					;;
				back) screen='toolchains' ;;
				quit) break ;;
			esac
			;;
		git_name)
			ui_text_input 'identity' 'Git identity' \
				'Enter the author name. Type :back to return.' "$GIT_AUTHOR_NAME"
			case "$TUI_NAV" in
				next)
					if [[ -z "$TUI_TEXT" ]]
					then
						TUI_ERROR='Git author name cannot be empty.'
					else
						GIT_AUTHOR_NAME=$TUI_TEXT
						TUI_ERROR=''
						screen='git_email'
					fi
					;;
				retry) ;;
				back) screen='git' ;;
				quit) break ;;
			esac
			;;
		git_email)
			ui_text_input 'identity' 'Git identity' \
				'Enter the author email. Type :back to return.' "$GIT_AUTHOR_EMAIL"
			case "$TUI_NAV" in
				next)
					if [[ -z "$TUI_TEXT" || "$TUI_TEXT" != *@* ]]
					then
						TUI_ERROR='Enter a non-empty Git email containing @.'
					else
						GIT_AUTHOR_EMAIL=$TUI_TEXT
						TUI_ERROR=''
						screen='summary'
					fi
					;;
				retry) ;;
				back) screen='git_name' ;;
				quit) break ;;
			esac
			;;
		summary)
			collect_conflicts
			ui_summary
			case "$TUI_NAV" in
				run)
					if [[ "$CONFLICT_INDEX" == "3" ]]
					then
						collect_conflicts
						FORCE_PATHS_CONFIRMED=false
						CONFIRMED_CONFLICT_PATHS=()
						if [[ ${#CONFLICT_PATHS[@]} -gt 0 ]]
						then
							screen='overwrite'
						else
							FORCE_PATHS_CONFIRMED=true
							screen='execute'
						fi
					else
						screen='execute'
					fi
					;;
				edit) screen='packages' ;;
				back)
					if [[ "$GIT_CONFIG_EXISTS" == "true" ]]
					then
						screen='toolchains'
					elif [[ "$GIT_INDEX" == "0" ]]
					then
						screen='git_email'
					else
						screen='git'
					fi
					;;
				quit) break ;;
			esac
			;;
		overwrite)
			overwrite_prompt='These conflicting paths will be removed:'
			for conflict_path in "${CONFLICT_PATHS[@]}"
			do
				overwrite_prompt+=$'\n    '"$conflict_path"
			done
			overwrite_prompt+=$'\n\nType OVERWRITE to continue, or :back to return.'
			ui_text_input 'confirm' 'Overwrite existing paths' \
				"$overwrite_prompt" ''
			case "$TUI_NAV" in
				next)
					if [[ "$TUI_TEXT" == "OVERWRITE" ]]
					then
						CONFIRMED_CONFLICT_PATHS=("${CONFLICT_PATHS[@]}")
						FORCE_PATHS_CONFIRMED=true
						screen='execute'
					else
						TUI_ERROR='Confirmation did not match OVERWRITE.'
					fi
					;;
				retry) ;;
				back) screen='summary' ;;
				quit) break ;;
			esac
			;;
		execute)
			if [[ "$dry_run" != "true" && "$PACKAGE_INDEX" == "0" &&
				"${EUID}" -ne 0 ]]
			then
				ui_clear
				ui_leave
				printf 'Checking sudo authentication before setup...\n'
				if sudo -v
				then
					break
				fi
				printf 'Sudo authentication failed; returning to installation scope.\n' >&2
				PACKAGE_INDEX=1
				TUI_ERROR='Sudo failed. User-only is selected; retry system packages if appropriate.'
				ui_enter
				screen='packages'
			else
				break
			fi
			;;
	esac
done

ui_clear
ui_leave
trap - EXIT INT TERM HUP

if [[ "$screen" != "execute" ]]
then
	printf 'Setup cancelled; no changes were made.\n'
	exit 0
fi

build_setup_args
printf 'Equivalent command: '
display_command
printf '\n'

if [[ "$dry_run" == "true" ]]
then
	printf 'Dry run only; no changes were made.\n'
	exit 0
fi

if [[ "$GIT_CONFIG_EXISTS" != "true" && "$GIT_INDEX" == "0" ]]
then
	export DOTFILES_GIT_AUTHORNAME="$GIT_AUTHOR_NAME"
	export DOTFILES_GIT_AUTHOREMAIL="$GIT_AUTHOR_EMAIL"
fi

exec "$DOTFILES_ROOT/bin/dot" setup "${SETUP_ARGS[@]}"
