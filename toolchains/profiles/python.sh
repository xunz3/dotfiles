#!/usr/bin/env bash

profile_python () {
	local uv_tools="${DOTFILES_PYTHON_UV_TOOLS:-ruff ipython}"
	local tool

	if ! have_command uv
	then
		info 'installing uv'
		run_remote_script "https://astral.sh/uv/install.sh" sh || return 1
	fi

	if [[ -s "$HOME/.local/bin/env" ]]
	then
		set +u
		source "$HOME/.local/bin/env"
		set -u
	fi
	prepend_path_if_dir "$HOME/.local/bin"

	if ! have_command uv
	then
		info 'uv is not available after install'
		return 1
	fi

	for tool in $uv_tools
	do
		info "installing Python tool with uv: $tool"
		uv tool install "$tool"
	done
	success 'Python tools are ready'
}
