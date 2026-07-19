#!/usr/bin/env bash

profile_nvim () {
	local nvim_bin="${HOME}/.local/bin/nvim"

	if [[ ! -x "$nvim_bin" ]] && have_command nvim
	then
		nvim_bin="$(command -v nvim)"
	fi

	if [[ ! -x "$nvim_bin" ]]
	then
		info 'neovim is not installed yet; skipping Mason tools'
		return 0
	fi

	info 'installing Neovim Mason language tools'
	if "$nvim_bin" --headless "+MasonToolsInstallSync" +qa >/dev/null 2>&1
	then
		success 'installed Neovim Mason language tools'
	else
		info 'Mason tool installation failed; run :MasonToolsInstallSync manually after network is available'
		return 1
	fi
}
