#!/usr/bin/env bash
#
# Install a pinned Tealdeer release with its Zsh completion.

set -euo pipefail

info () {
	printf "\r  [ \033[00;34m..\033[0m ] %s\n" "$1"
}

success () {
	printf "\r\033[2K  [ \033[00;32mOK\033[0m ] %s\n" "$1"
}

symlink_target_is_managed () {
	local existing_target=$1 managed_pattern
	shift

	for managed_pattern in "$@"
	do
		[[ "$existing_target" == $managed_pattern ]] && return 0
	done
	return 1
}

managed_symlink_is_replaceable () {
	local target=$1
	local link_path=$2
	local existing_target
	shift 2

	if [[ ! -e "$link_path" && ! -L "$link_path" ]]
	then
		return 0
	fi

	if [[ ! -L "$link_path" ]]
	then
		info "$link_path exists and is not a symlink; leaving it unchanged"
		return 1
	fi

	existing_target="$(readlink -- "$link_path")" || return 1
	if [[ "$existing_target" == "$target" ]] ||
		symlink_target_is_managed "$existing_target" "$@"
	then
		return 0
	fi

	info "$link_path points to an unmanaged target; leaving it unchanged"
	return 1
}

replace_managed_symlink () {
	local target=$1
	local link_path=$2
	local temporary_link="${link_path}.tmp.$$"
	shift 2

	managed_symlink_is_replaceable "$target" "$link_path" "$@" || return 1
	if [[ -L "$link_path" && "$(readlink -- "$link_path")" == "$target" ]]
	then
		return 0
	fi

	ln -sT -- "$target" "$temporary_link" || return 1
	if ! mv -Tf -- "$temporary_link" "$link_path"
	then
		rm -f -- "$temporary_link"
		return 1
	fi
}

binary_checksum () {
	local requested_version=$1 requested_asset=$2

	if [[ -n "${DOTFILES_TEALDEER_SHA256:-}" ]]
	then
		printf '%s' "$DOTFILES_TEALDEER_SHA256"
		return 0
	fi

	case "$requested_version:$requested_asset" in
		1.8.1:tealdeer-linux-x86_64-musl)
			printf '6f2fad4435e0110484d3f25cdc4bf20129dae03238f32d06ebdd00bdc50ae2ed'
			;;
		1.8.1:tealdeer-linux-aarch64-musl)
			printf '09d4506b3ba2efe7376e3a5ce1238aa5e6c33ae6f2532c190156540f6c4e7d69'
			;;
		*)
			info "no pinned SHA-256 for Tealdeer $requested_version/$requested_asset; set DOTFILES_TEALDEER_SHA256" >&2
			return 1
			;;
	esac
}

completion_checksum () {
	local requested_version=$1

	if [[ -n "${DOTFILES_TEALDEER_COMPLETION_SHA256:-}" ]]
	then
		printf '%s' "$DOTFILES_TEALDEER_COMPLETION_SHA256"
		return 0
	fi

	case "$requested_version" in
		1.8.1)
			printf '8b2d55757af91c3fa594c0f2fe57eebf0db48e13451430319ea6d093b65e6889'
			;;
		*)
			info "no pinned completion SHA-256 for Tealdeer $requested_version; set DOTFILES_TEALDEER_COMPLETION_SHA256" >&2
			return 1
			;;
	esac
}

verify_checksum () {
	local file=$1 expected=$2 label=$3 actual

	actual="$(sha256sum "$file")"
	actual="${actual%% *}"
	if [[ "$actual" != "$expected" ]]
	then
		info "Tealdeer $label checksum mismatch"
		return 1
	fi
}

os="$(uname -s)"
arch="$(uname -m)"
version="${DOTFILES_TEALDEER_VERSION:-1.8.1}"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
completion_asset='completions_zsh'
tmp_dir=''

if [[ "$os" != 'Linux' ]]
then
	info "unsupported OS for automatic Tealdeer install: $os"
	exit 1
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
then
	info "invalid Tealdeer version: $version"
	exit 1
fi

if [[ "$data_home" != /* ]]
then
	info 'XDG_DATA_HOME must be an absolute path for the Tealdeer installation'
	exit 1
fi

case "$arch" in
	x86_64|amd64)
		binary_asset='tealdeer-linux-x86_64-musl'
		;;
	aarch64|arm64)
		binary_asset='tealdeer-linux-aarch64-musl'
		;;
	*)
		info "unsupported architecture for automatic Tealdeer install: $arch"
		exit 1
		;;
esac

install_root="$HOME/.local/opt"
install_dir="$install_root/tealdeer-$version"
current_link="$install_root/tealdeer-current"
binary_link="$HOME/.local/bin/tldr"
completion_link="$data_home/zsh/site-functions/_tldr"
managed_current_pattern="$install_root/tealdeer-[0-9]*"
managed_binary_pattern="$install_root/tealdeer-[0-9]*/tldr"
managed_completion_pattern="$install_root/tealdeer-[0-9]*/completions/_tldr"

cleanup () {
	if [[ -n "$tmp_dir" && -d "$tmp_dir" &&
		"$tmp_dir" == "$install_root"/.tealdeer-install-"$version".* ]]
	then
		rm -rf -- "$tmp_dir"
	fi
}
trap cleanup EXIT

mkdir -p "$HOME/.local/bin" "$install_root" "$(dirname "$completion_link")"

# Check every public link before downloading or changing the selected version.
managed_symlink_is_replaceable "$install_dir" "$current_link" "$managed_current_pattern" || exit 1
managed_symlink_is_replaceable "$current_link/tldr" "$binary_link" "$current_link/tldr" "$managed_binary_pattern" || exit 1
managed_symlink_is_replaceable "$current_link/completions/_tldr" "$completion_link" "$current_link/completions/_tldr" "$managed_completion_pattern" || exit 1

if [[ -x "$install_dir/tldr" && -s "$install_dir/completions/_tldr" ]]
then
	actual_version="$("$install_dir/tldr" --version 2>&1)"
	if [[ "$actual_version" != "tealdeer $version" ]]
	then
		info "$install_dir does not contain Tealdeer $version; leaving it unchanged"
		exit 1
	fi

	replace_managed_symlink "$install_dir" "$current_link" "$managed_current_pattern"
	replace_managed_symlink "$current_link/tldr" "$binary_link" "$current_link/tldr" "$managed_binary_pattern"
	replace_managed_symlink "$current_link/completions/_tldr" "$completion_link" "$current_link/completions/_tldr" "$managed_completion_pattern"
	success "selected Tealdeer $version"
	exit 0
fi

if [[ -e "$install_dir" || -L "$install_dir" ]]
then
	info "$install_dir exists but is incomplete; leaving it unchanged"
	exit 1
fi

for required_command in curl sha256sum
do
	if ! command -v "$required_command" >/dev/null 2>&1
	then
		info "$required_command is required to install Tealdeer"
		exit 1
	fi
done

expected_binary_checksum="$(binary_checksum "$version" "$binary_asset")" || exit 1
expected_completion_checksum="$(completion_checksum "$version")" || exit 1
if [[ ! "$expected_binary_checksum" =~ ^[[:xdigit:]]{64}$ ||
	! "$expected_completion_checksum" =~ ^[[:xdigit:]]{64}$ ]]
then
	info 'the configured Tealdeer SHA-256 is invalid'
	exit 1
fi
expected_binary_checksum="${expected_binary_checksum,,}"
expected_completion_checksum="${expected_completion_checksum,,}"

tmp_dir="$(mktemp -d "$install_root/.tealdeer-install-$version.XXXXXX")"
stage_dir="$tmp_dir/tealdeer-$version"
binary_download="$tmp_dir/$binary_asset"
completion_download="$tmp_dir/$completion_asset"
release_url="https://github.com/tealdeer-rs/tealdeer/releases/download/v$version"
mkdir -p "$stage_dir/completions"

info "installing Tealdeer $version from the official release"
curl -fsSL --connect-timeout 15 --max-time 300 "$release_url/$binary_asset" -o "$binary_download"
verify_checksum "$binary_download" "$expected_binary_checksum" 'binary' || exit 1
curl -fsSL --connect-timeout 15 --max-time 300 "$release_url/$completion_asset" -o "$completion_download"
verify_checksum "$completion_download" "$expected_completion_checksum" 'completion' || exit 1

mv "$binary_download" "$stage_dir/tldr"
mv "$completion_download" "$stage_dir/completions/_tldr"
chmod 0755 "$stage_dir/tldr"

actual_version="$("$stage_dir/tldr" --version 2>&1)"
if [[ "$actual_version" != "tealdeer $version" ]]
then
	info "downloaded Tealdeer did not report version $version"
	exit 1
fi

mv "$stage_dir" "$install_dir"
replace_managed_symlink "$install_dir" "$current_link" "$managed_current_pattern"
replace_managed_symlink "$current_link/tldr" "$binary_link" "$current_link/tldr" "$managed_binary_pattern"
replace_managed_symlink "$current_link/completions/_tldr" "$completion_link" "$current_link/completions/_tldr" "$managed_completion_pattern"
hash -r 2>/dev/null || true

success "installed Tealdeer $version"
