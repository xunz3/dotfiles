#!/usr/bin/env bash
#
# Install the pinned Mike Farah yq release and its Zsh completion.

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

yq_checksum () {
	local requested_version=$1
	local requested_asset=$2

	if [[ -n "${DOTFILES_YQ_SHA256:-}" ]]
	then
		printf '%s' "$DOTFILES_YQ_SHA256"
		return 0
	fi

	case "$requested_version:$requested_asset" in
		v4.53.3:yq_linux_amd64)
			printf 'fa52a4e758c63d38299163fbdd1edfb4c4963247918bf9c1c5d31d84789eded4'
			;;
		v4.53.3:yq_linux_arm64)
			printf '578648e463a11c1b6db6010cbf41eafed6bee79466fcffa1bb446672cf7945ea'
			;;
		*)
			info "no pinned SHA-256 for $requested_version/$requested_asset; set DOTFILES_YQ_SHA256" >&2
			return 1
			;;
	esac
}

os="$(uname -s)"
arch="$(uname -m)"
version="${DOTFILES_YQ_VERSION:-v4.53.3}"
version_name="${version#v}"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
tmp_dir=''

if [[ "$os" != 'Linux' ]]
then
	info "unsupported OS for automatic yq install: $os"
	exit 1
fi

if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
then
	info "invalid yq version: $version"
	exit 1
fi

if [[ "$data_home" != /* ]]
then
	info 'XDG_DATA_HOME must be an absolute path for the yq installation'
	exit 1
fi

case "$arch" in
	x86_64|amd64)
		asset='yq_linux_amd64'
		;;
	aarch64|arm64)
		asset='yq_linux_arm64'
		;;
	*)
		info "unsupported architecture for automatic yq install: $arch"
		exit 1
		;;
esac

install_root="$HOME/.local/opt"
install_dir="$install_root/yq-$version_name"
current_link="$install_root/yq-current"
binary_link="$HOME/.local/bin/yq"
completion_link="$data_home/zsh/site-functions/_yq"
managed_current_pattern="$install_root/yq-[0-9]*"
managed_binary_pattern="$install_root/yq-[0-9]*/yq"
managed_completion_pattern="$install_root/yq-[0-9]*/completions/_yq"

cleanup () {
	if [[ -n "$tmp_dir" && -d "$tmp_dir" &&
		"$tmp_dir" == "$install_root"/.yq-install-"$version_name".* ]]
	then
		rm -rf -- "$tmp_dir"
	fi
}
trap cleanup EXIT

mkdir -p "$HOME/.local/bin" "$install_root" "$(dirname "$completion_link")"

# Check every public link before downloading or changing the selected version.
managed_symlink_is_replaceable "$install_dir" "$current_link" \
	"$managed_current_pattern" || exit 1
managed_symlink_is_replaceable "$current_link/yq" "$binary_link" \
	"$current_link/yq" "$managed_binary_pattern" || exit 1
managed_symlink_is_replaceable "$current_link/completions/_yq" "$completion_link" \
	"$current_link/completions/_yq" "$managed_completion_pattern" || exit 1

if [[ -x "$install_dir/yq" && -s "$install_dir/completions/_yq" ]]
then
	replace_managed_symlink "$install_dir" "$current_link" \
		"$managed_current_pattern"
	replace_managed_symlink "$current_link/yq" "$binary_link" \
		"$current_link/yq" "$managed_binary_pattern"
	replace_managed_symlink "$current_link/completions/_yq" "$completion_link" \
		"$current_link/completions/_yq" "$managed_completion_pattern"
	success "selected yq $version_name"
	exit 0
fi

if [[ -e "$install_dir" || -L "$install_dir" ]]
then
	info "$install_dir exists but is incomplete; leaving it unchanged"
	exit 1
fi

if ! command -v curl >/dev/null 2>&1 || ! command -v sha256sum >/dev/null 2>&1
then
	info 'curl and sha256sum are required to install yq'
	exit 1
fi

expected_checksum="$(yq_checksum "$version" "$asset")" || exit 1
if [[ ! "$expected_checksum" =~ ^[[:xdigit:]]{64}$ ]]
then
	info 'the configured yq SHA-256 is invalid'
	exit 1
fi
expected_checksum="${expected_checksum,,}"

tmp_dir="$(mktemp -d "$install_root/.yq-install-$version_name.XXXXXX")"
stage_dir="$tmp_dir/yq-$version_name"
download="$tmp_dir/$asset"
url="https://github.com/mikefarah/yq/releases/download/$version/$asset"
mkdir -p "$stage_dir/completions"

info "installing yq $version_name from the official release"
curl -fsSL --connect-timeout 15 --max-time 300 "$url" -o "$download"
actual_checksum="$(sha256sum "$download")"
actual_checksum="${actual_checksum%% *}"
if [[ "$actual_checksum" != "$expected_checksum" ]]
then
	info "yq binary checksum mismatch for $asset"
	exit 1
fi

mv "$download" "$stage_dir/yq"
chmod 0755 "$stage_dir/yq"
actual_version="$("$stage_dir/yq" --version 2>&1)"
if [[ "$actual_version" != "yq (https://github.com/mikefarah/yq/) version $version" ]]
then
	info "downloaded yq did not report version $version"
	exit 1
fi

if ! "$stage_dir/yq" completion zsh > "$stage_dir/completions/_yq" ||
	[[ ! -s "$stage_dir/completions/_yq" ]]
then
	info 'failed to generate the yq Zsh completion'
	exit 1
fi

mv "$stage_dir" "$install_dir"
replace_managed_symlink "$install_dir" "$current_link" \
	"$managed_current_pattern"
replace_managed_symlink "$current_link/yq" "$binary_link" \
	"$current_link/yq" "$managed_binary_pattern"
replace_managed_symlink "$current_link/completions/_yq" "$completion_link" \
	"$current_link/completions/_yq" "$managed_completion_pattern"
hash -r 2>/dev/null || true

success "installed yq $version_name"
