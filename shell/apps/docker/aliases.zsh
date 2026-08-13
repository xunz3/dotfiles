alias d='docker'

if (( $+commands[docker-compose] ))
then
  alias d-c='docker-compose'
else
  # Docker Compose v2 is a Docker subcommand rather than a separate binary.
  alias d-c='docker compose'
fi
