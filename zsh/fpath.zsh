# add explicit function roots to fpath for autoload and completion.
typeset dotfiles_data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
[[ "$dotfiles_data_home" == /* ]] || dotfiles_data_home="$HOME/.local/share"
typeset dotfiles_site_functions="$dotfiles_data_home/zsh/site-functions"
fpath=(
  $DOTFILES/shell/functions
  $DOTFILES/zsh
  $dotfiles_site_functions
  $fpath
)
unset dotfiles_data_home dotfiles_site_functions
