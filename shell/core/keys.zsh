copy_pubkey() {
  local key_file="${PUBKEY_PATH:-$HOME/.ssh/id_rsa.pub}"

  if [[ ! -f "$key_file" ]]; then
    echo "Public key not found: $key_file"
    return 1
  fi

  if (( $+commands[clipboard-copy] )) && clipboard-copy < "$key_file"; then
    echo "=> Public key copied to clipboard."
  else
    command cat "$key_file"
    echo "=> No clipboard tool found; printed public key instead."
    return 0
  fi
}

alias pubkey='copy_pubkey'
