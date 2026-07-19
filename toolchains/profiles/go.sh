#!/usr/bin/env bash

profile_go () {
	local go_tools="${DOTFILES_GO_TOOLS:-golang.org/x/tools/gopls@latest mvdan.cc/gofumpt@latest golang.org/x/tools/cmd/goimports@latest github.com/go-delve/delve/cmd/dlv@latest}"
	local tool

	if ! have_command go
	then
		info 'go is not installed yet; install system packages or rerun without --user'
		return 1
	fi

	for tool in $go_tools
	do
		info "installing Go tool: $tool"
		go install "$tool"
	done
	success 'Go tools are ready'
}
