#!/usr/bin/env bash
#
# Install oh-my-zsh and common plugins used by this setup.

set -euo pipefail

info () {
	printf "\r  [ \033[00;34m..\033[0m ] %s\n" "$1"
}

success () {
	printf "\r\033[2K  [ \033[00;32mOK\033[0m ] %s\n" "$1"
}

clone_repo_if_missing () {
	local repo_url=$1
	local target_dir=$2
	local label=$3

	if [[ -d "$target_dir/.git" ]]
	then
		success "$label already installed"
		return
	fi

	if [[ -e "$target_dir" ]]
	then
		info "$target_dir exists and is not a git checkout; skipping $label"
		return
	fi

	mkdir -p "$(dirname "$target_dir")"
	info "cloning $label"
	git clone --depth=1 "$repo_url" "$target_dir"
	success "installed $label"
}

if ! command -v git >/dev/null 2>&1
then
	info 'git is required to install oh-my-zsh; skipping'
	exit 0
fi

ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$ZSH_DIR/custom}"

clone_repo_if_missing "https://github.com/ohmyzsh/ohmyzsh.git" "$ZSH_DIR" "oh-my-zsh"
clone_repo_if_missing "https://github.com/zsh-users/zsh-autosuggestions" "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions" "zsh-autosuggestions"
clone_repo_if_missing "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting" "zsh-syntax-highlighting"

if command -v zsh >/dev/null 2>&1 && [[ "${SHELL:-}" != "$(command -v zsh)" ]]
then
	info "current login shell is ${SHELL:-unknown}; run 'chsh -s $(command -v zsh)' if you want zsh by default"
fi
