#!/usr/bin/env bash

profile_bun () {
	install_bun_runtime || return 1
	source_bun || {
		info 'bun is not available after install'
		return 1
	}
	success 'bun is ready'
}
