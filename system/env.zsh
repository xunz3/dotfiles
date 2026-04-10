if (( $+commands[nvim] )); then
	export EDITOR='nvim'
elif (( $+commands[vim] )); then
	export EDITOR='vim'
elif (( $+commands[code] )); then
	export EDITOR='code'
else
	export EDITOR='vi'
fi

export VISUAL="$EDITOR"
export GIT_EDITOR="$EDITOR"
