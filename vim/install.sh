#!/usr/bin/env bash
#
# Install vim-plug for the tracked Vim config.

set -euo pipefail

info () {
	printf "\r  [ \033[00;34m..\033[0m ] %s\n" "$1"
}

success () {
	printf "\r\033[2K  [ \033[00;32mOK\033[0m ] %s\n" "$1"
}

if ! command -v curl >/dev/null 2>&1
then
	info 'curl is required to install vim-plug; skipping'
	exit 0
fi

plug_path="${HOME}/.vim/autoload/plug.vim"

if [[ -f "$plug_path" ]]
then
	success 'vim-plug already installed'
else
	mkdir -p "$(dirname "$plug_path")"
	info 'installing vim-plug'
	curl -fLo "$plug_path" --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
	success 'installed vim-plug'
fi

if ! command -v vim >/dev/null 2>&1
then
	info 'vim is not installed yet; skipping plugin install'
	exit 0
fi

info 'installing Vim plugins'
vim -E -s +'PlugInstall --sync' +qall
success 'installed Vim plugins'
