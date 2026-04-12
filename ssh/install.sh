#!/usr/bin/env bash
#
# Initialize a conservative OpenSSH client baseline.

set -euo pipefail

info () {
	printf "\r  [ \033[00;34m..\033[0m ] %s\n" "$1"
}

success () {
	printf "\r\033[2K  [ \033[00;32mOK\033[0m ] %s\n" "$1"
}

ssh_dir="${HOME}/.ssh"
config_file="${ssh_dir}/config"

mkdir -p "$ssh_dir"
chmod 700 "$ssh_dir"

fix_file_permissions () {
	local file

	for file in "$ssh_dir"/id_* "$config_file" "$ssh_dir/known_hosts" "$ssh_dir/authorized_keys"
	do
		[[ -e "$file" ]] || continue

		case "$file" in
			*.pub)
				chmod 644 "$file"
				;;
			*)
				chmod 600 "$file"
				;;
		esac
	done
}

detect_identity_file () {
	local key

	for key in id_ed25519 id_ecdsa id_rsa
	do
		if [[ -f "$ssh_dir/$key" ]]
		then
			printf '~/.ssh/%s\n' "$key"
			return 0
		fi
	done

	return 1
}

write_default_config () {
	local identity_file

	cat > "$config_file" <<'EOF'
# Baseline OpenSSH client config.
# Add machine-specific hosts below this block.

Host *
  AddKeysToAgent yes
  ServerAliveInterval 60
  ServerAliveCountMax 3
  HashKnownHosts yes
EOF

	if identity_file="$(detect_identity_file)"
	then
		cat >> "$config_file" <<EOF

Host github.com
  HostName github.com
  User git
  IdentityFile ${identity_file}
  IdentitiesOnly yes
EOF
	fi

	chmod 600 "$config_file"
}

validate_config () {
	if ! command -v ssh >/dev/null 2>&1
	then
		info 'ssh command not found; install OpenSSH client before validating config'
		return 0
	fi

	if ssh -G github.com >/dev/null 2>&1
	then
		success 'ssh config is valid'
	else
		info 'ssh config validation failed; inspect ~/.ssh/config'
	fi
}

if [[ -s "$config_file" ]]
then
	fix_file_permissions
	success 'ssh config already exists'
	validate_config
	exit 0
fi

info 'creating baseline ssh config'
write_default_config
fix_file_permissions
success 'created ~/.ssh/config'
validate_config
