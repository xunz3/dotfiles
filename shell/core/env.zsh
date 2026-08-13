if (( $+commands[vim] )); then
	export EDITOR='vim'
elif (( $+commands[vi] )); then
	export EDITOR='vi'
elif (( $+commands[code] )); then
	export EDITOR='code'
else
	export EDITOR='vi'
fi

export VISUAL="$EDITOR"
export GIT_EDITOR="$EDITOR"
