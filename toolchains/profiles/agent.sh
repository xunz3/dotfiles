#!/usr/bin/env bash

agent_node_is_supported () {
	have_command node && have_command npm &&
		node -e 'const [major, minor, patch] = process.versions.node.split(".").map(Number); process.exit(major > 22 || (major === 22 && (minor > 19 || (minor === 19 && patch >= 0))) ? 0 : 1)' >/dev/null 2>&1
}

ensure_agent_node () {
	if agent_node_is_supported
	then
		return 0
	fi

	# The Pi installer otherwise prompts for a system Node.js installation.
	# Reuse the managed runtime so user-only and unattended installs also work.
	info 'preparing Node.js for Pi Agent'
	install_nvm || return 1
	source_nvm || return 1
	if ! agent_node_is_supported
	then
		nvm install --lts || return 1
		nvm use --lts || return 1
	fi
	agent_node_is_supported
}

profile_agent () {
	local failed=()

	mkdir -p "$HOME/.local/bin" || return 1
	prepend_path_if_dir "$HOME/.local/bin"

	if have_command codex
	then
		success 'Codex CLI already installed'
	else
		info 'installing Codex CLI with the official installer'
		if CODEX_NON_INTERACTIVE=1 run_remote_script "https://chatgpt.com/codex/install.sh" sh
		then
			prepend_path_if_dir "$HOME/.local/bin"
			if have_command codex
			then
				success 'Codex CLI is ready'
			else
				info 'Codex installer completed, but codex is not available on PATH'
				failed+=(codex)
			fi
		else
			info 'Codex CLI installation failed'
			failed+=(codex)
		fi
	fi

	if have_command pi
	then
		success 'Pi Agent already installed'
	else
		info 'installing Pi Agent with the official installer'
		if ensure_agent_node && run_remote_script "https://pi.dev/install.sh" sh
		then
			prepend_path_if_dir "$HOME/.local/bin"
			if have_command pi
			then
				success 'Pi Agent is ready'
			else
				info 'Pi installer completed, but pi is not available on PATH'
				failed+=(pi)
			fi
		else
			info 'Pi Agent installation failed'
			failed+=(pi)
		fi
	fi

	if [[ ${#failed[@]} -gt 0 ]]
	then
		info "Agent tools failed: ${failed[*]}"
		return 1
	fi

	success 'Agent tools are ready'
}
