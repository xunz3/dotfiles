#!/usr/bin/env bash
#
# Install a pinned Fastfetch release with its Zsh completion and man page.

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

fastfetch_checksum () {
	local requested_version=$1
	local requested_asset=$2

	if [[ -n "${DOTFILES_FASTFETCH_SHA256:-}" ]]
	then
		printf '%s' "$DOTFILES_FASTFETCH_SHA256"
		return 0
	fi

	case "$requested_version:$requested_asset" in
		2.67.1:fastfetch-linux-amd64.tar.gz)
			printf 'adc8a9eb64eccef267e50bb1e6f9a767bb608da5ee4a3b652ef36a10d9105d4d'
			;;
		2.67.1:fastfetch-linux-aarch64.tar.gz)
			printf 'b974b76e3d8df90311440a2250c83561aa0a863f129925285f2789d932b4cbaa'
			;;
		*)
			info "no pinned SHA-256 for $requested_version/$requested_asset; set DOTFILES_FASTFETCH_SHA256" >&2
			return 1
			;;
	esac
}

os="$(uname -s)"
arch="$(uname -m)"
version="${DOTFILES_FASTFETCH_VERSION:-2.67.1}"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
tmp_dir=''

if [[ "$os" != 'Linux' ]]
then
	info "unsupported OS for automatic Fastfetch install: $os"
	exit 1
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
then
	info "invalid Fastfetch version: $version"
	exit 1
fi

if [[ "$data_home" != /* ]]
then
	info 'XDG_DATA_HOME must be an absolute path for the Fastfetch installation'
	exit 1
fi

case "$arch" in
	x86_64|amd64)
		asset='fastfetch-linux-amd64.tar.gz'
		archive_root='fastfetch-linux-amd64'
		;;
	aarch64|arm64)
		asset='fastfetch-linux-aarch64.tar.gz'
		archive_root='fastfetch-linux-aarch64'
		;;
	*)
		info "unsupported architecture for automatic Fastfetch install: $arch"
		exit 1
		;;
esac

install_root="$HOME/.local/opt"
install_dir="$install_root/fastfetch-$version"
current_link="$install_root/fastfetch-current"
binary_link="$HOME/.local/bin/fastfetch"
completion_link="$data_home/zsh/site-functions/_fastfetch"
man_link="$data_home/man/man1/fastfetch.1"
managed_current_pattern="$install_root/fastfetch-[0-9]*"
managed_binary_pattern="$install_root/fastfetch-[0-9]*/usr/bin/fastfetch"
managed_completion_pattern="$install_root/fastfetch-[0-9]*/usr/share/zsh/site-functions/_fastfetch"
managed_man_pattern="$install_root/fastfetch-[0-9]*/usr/share/man/man1/fastfetch.1"

cleanup () {
	if [[ -n "$tmp_dir" && -d "$tmp_dir" &&
		"$tmp_dir" == "$install_root"/.fastfetch-install-"$version".* ]]
	then
		rm -rf -- "$tmp_dir"
	fi
}
trap cleanup EXIT

mkdir -p "$HOME/.local/bin" "$install_root" \
	"$(dirname "$completion_link")" "$(dirname "$man_link")"

# Refuse unmanaged public paths before downloading or changing any selection.
managed_symlink_is_replaceable "$install_dir" "$current_link" \
	"$managed_current_pattern" || exit 1
managed_symlink_is_replaceable "$current_link/usr/bin/fastfetch" "$binary_link" \
	"$current_link/usr/bin/fastfetch" "$managed_binary_pattern" || exit 1
managed_symlink_is_replaceable \
	"$current_link/usr/share/zsh/site-functions/_fastfetch" "$completion_link" \
	"$current_link/usr/share/zsh/site-functions/_fastfetch" \
	"$managed_completion_pattern" || exit 1
managed_symlink_is_replaceable \
	"$current_link/usr/share/man/man1/fastfetch.1" "$man_link" \
	"$current_link/usr/share/man/man1/fastfetch.1" "$managed_man_pattern" || exit 1

if [[ -x "$install_dir/usr/bin/fastfetch" &&
	-s "$install_dir/usr/share/zsh/site-functions/_fastfetch" &&
	-s "$install_dir/usr/share/man/man1/fastfetch.1" ]]
then
	replace_managed_symlink "$install_dir" "$current_link" \
		"$managed_current_pattern"
	replace_managed_symlink "$current_link/usr/bin/fastfetch" "$binary_link" \
		"$current_link/usr/bin/fastfetch" "$managed_binary_pattern"
	replace_managed_symlink \
		"$current_link/usr/share/zsh/site-functions/_fastfetch" "$completion_link" \
		"$current_link/usr/share/zsh/site-functions/_fastfetch" \
		"$managed_completion_pattern"
	replace_managed_symlink \
		"$current_link/usr/share/man/man1/fastfetch.1" "$man_link" \
		"$current_link/usr/share/man/man1/fastfetch.1" "$managed_man_pattern"
	success "selected Fastfetch $version"
	exit 0
fi

if [[ -e "$install_dir" || -L "$install_dir" ]]
then
	info "$install_dir exists but is incomplete; leaving it unchanged"
	exit 1
fi

for required_command in curl sha256sum tar
do
	if ! command -v "$required_command" >/dev/null 2>&1
	then
		info "$required_command is required to install Fastfetch"
		exit 1
	fi
done

expected_checksum="$(fastfetch_checksum "$version" "$asset")" || exit 1
if [[ ! "$expected_checksum" =~ ^[[:xdigit:]]{64}$ ]]
then
	info 'the configured Fastfetch SHA-256 is invalid'
	exit 1
fi
expected_checksum="${expected_checksum,,}"

tmp_dir="$(mktemp -d "$install_root/.fastfetch-install-$version.XXXXXX")"
stage_dir="$tmp_dir/fastfetch-$version"
download="$tmp_dir/$asset"
url="https://github.com/fastfetch-cli/fastfetch/releases/download/$version/$asset"
mkdir -p "$stage_dir"

info "installing Fastfetch $version from the official release"
curl -fsSL --connect-timeout 15 --max-time 300 "$url" -o "$download"
actual_checksum="$(sha256sum "$download")"
actual_checksum="${actual_checksum%% *}"
if [[ "$actual_checksum" != "$expected_checksum" ]]
then
	info "Fastfetch archive checksum mismatch for $asset"
	exit 1
fi

tar -xzf "$download" -C "$stage_dir" --strip-components=1 "$archive_root/usr"
if [[ ! -x "$stage_dir/usr/bin/fastfetch" ||
	! -s "$stage_dir/usr/share/zsh/site-functions/_fastfetch" ||
	! -s "$stage_dir/usr/share/man/man1/fastfetch.1" ]]
then
	info 'the Fastfetch archive is missing required files'
	exit 1
fi

actual_version="$("$stage_dir/usr/bin/fastfetch" --version 2>&1)"
if [[ "$actual_version" != "fastfetch $version "* ]]
then
	info "downloaded Fastfetch did not report version $version"
	exit 1
fi

mv "$stage_dir" "$install_dir"
replace_managed_symlink "$install_dir" "$current_link" \
	"$managed_current_pattern"
replace_managed_symlink "$current_link/usr/bin/fastfetch" "$binary_link" \
	"$current_link/usr/bin/fastfetch" "$managed_binary_pattern"
replace_managed_symlink \
	"$current_link/usr/share/zsh/site-functions/_fastfetch" "$completion_link" \
	"$current_link/usr/share/zsh/site-functions/_fastfetch" \
	"$managed_completion_pattern"
replace_managed_symlink \
	"$current_link/usr/share/man/man1/fastfetch.1" "$man_link" \
	"$current_link/usr/share/man/man1/fastfetch.1" "$managed_man_pattern"
hash -r 2>/dev/null || true

success "installed Fastfetch $version"
