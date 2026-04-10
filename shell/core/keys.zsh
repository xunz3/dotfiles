copy_pubkey() {
  local key_file="${PUBKEY_PATH:-$HOME/.ssh/id_rsa.pub}"

  if [[ ! -f "$key_file" ]]; then
    echo "Public key not found: $key_file"
    return 1
  fi

  if (( $+commands[wl-copy] )); then
    wl-copy < "$key_file"
  elif (( $+commands[xclip] )); then
    xclip -selection clipboard < "$key_file"
  elif (( $+commands[pbcopy] )); then
    pbcopy < "$key_file"
  else
    cat "$key_file"
    echo "=> No clipboard tool found; printed public key instead."
    return 0
  fi

  echo "=> Public key copied to clipboard."
}

alias pubkey='copy_pubkey'
