#!/usr/bin/env bash

profile_java () {
	local java_version="${DOTFILES_JAVA_VERSION:-21-tem}"
	local java_tools="${DOTFILES_JAVA_TOOLS:-maven gradle kotlin}"
	local tool

	install_sdkman || return 1
	source_sdkman || {
		info 'sdkman is not available after install'
		return 1
	}

	info "installing Java $java_version"
	sdk install java "$java_version"
	sdk default java "$java_version"
	success "Java $java_version is ready"

	for tool in $java_tools
	do
		info "installing $tool with sdkman"
		sdk install "$tool"
	done
	success 'Java build tools are ready'
}
