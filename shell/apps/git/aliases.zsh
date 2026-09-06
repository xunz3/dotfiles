alias gl='git pull --prune'
alias glog="git log --graph --pretty=format:'%Cred%h%Creset %an: %s - %Creset %C(yellow)%d%Creset %Cgreen(%cr)%Creset' --abbrev-commit --date=relative"
alias gp='git push origin HEAD'

# The tracked Git pager already selects Delta when available and falls back to
# less, so keep diffs composable instead of piping them through sed manually.
alias gd='git diff'
alias gds='git diff --staged'

alias gc='git commit'
alias gca='git commit -a'
alias gco='git checkout'
alias gsw='git switch'
alias grs='git restore'
alias gcb='git copy-branch-name'
alias gb='git branch'
alias gs='git status -sb' # upgrade your git if -sb breaks for you. it's fun.
alias gac='git add -A && git commit -m'
alias ge='git-edit-new'
