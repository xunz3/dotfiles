#!/usr/bin/env bash
#
# Install selected developer toolchain profiles.

set -euo pipefail

cd "$(dirname "$0")/.."
DOTFILES_ROOT=$(pwd -P)
TOOLCHAINS_ROOT="$DOTFILES_ROOT/toolchains"

# shellcheck source=toolchains/lib/common.sh
source "$TOOLCHAINS_ROOT/lib/common.sh"
# shellcheck source=toolchains/lib/profiles.sh
source "$TOOLCHAINS_ROOT/lib/profiles.sh"
# shellcheck source=toolchains/lib/runtimes.sh
source "$TOOLCHAINS_ROOT/lib/runtimes.sh"

usage () {
	cat <<'EOF'
Usage: toolchains/install.sh [profiles]

Profiles:
  nvim   Install Neovim Mason language tools
  node   Install nvm, Node.js LTS, pnpm, yarn, and npm globals
  java   Install sdkman, JDK, Maven, Gradle, and Kotlin
  rust   Install rustup, Rust stable, rustfmt, and clippy
  go     Install common Go tools with go install
  python Install uv and selected Python CLI tools
  bun    Install bun
  all    Install every profile

Commands:
  list      Print available profiles

When no profile is passed, DOTFILES_TOOLCHAINS from ~/.toolchainsrc is used.
If DOTFILES_TOOLCHAINS is unset, the default is nvim.
EOF
}

print_profiles () {
	dotfiles_toolchain_all_profiles
}

run_profile () {
	local profile=$1
	local profile_file="$TOOLCHAINS_ROOT/profiles/$profile.sh"
	local profile_function="profile_${profile//-/_}"

	if ! dotfiles_toolchain_profile_exists "$profile"
	then
		info "unknown toolchain profile: $profile"
		return 1
	fi

	if [[ ! -f "$profile_file" ]]
	then
		info "toolchain profile has no installer: $profile"
		return 1
	fi

	# shellcheck source=/dev/null
	if ! source "$profile_file"
	then
		info "failed to load toolchain profile: $profile"
		return 1
	fi

	if ! declare -F "$profile_function" >/dev/null
	then
		info "toolchain profile is missing $profile_function"
		return 1
	fi

	info "running toolchain profile: $profile"
	"$profile_function"
}

run_profiles () {
	local requested=("$@")
	local profiles=()
	local profile
	local succeeded=()
	local failed=()

	load_toolchain_config
	mapfile -t profiles < <(dotfiles_toolchain_resolve_profiles "${requested[@]}")

	if [[ ${#profiles[@]} -eq 0 ]]
	then
		info 'no toolchain profiles selected; skipping'
		return 0
	fi

	for profile in "${profiles[@]}"
	do
		if run_profile "$profile"
		then
			success "toolchain profile complete: $profile"
			succeeded+=("$profile")
		else
			failed+=("$profile")
		fi
	done

	printf '\nToolchain summary\n'
	printf '  profiles: %d succeeded, %d failed\n' "${#succeeded[@]}" "${#failed[@]}"

	if [[ ${#failed[@]} -gt 0 ]]
	then
		printf '\nFailed profiles:\n'
		for profile in "${failed[@]}"
		do
			printf '  profile: %s\n' "$profile"
		done
		return 1
	fi

	return 0
}

case "${1:-}" in
	-h|--help)
		usage
		exit 0
		;;
	list)
		print_profiles
		exit 0
		;;
esac

run_profiles "$@"
