# dotfiles

Linux-first dotfiles for bootstrapping a new workstation quickly.

This repo manages:

- shell: `zsh`, `oh-my-zsh`, aliases, completions, paths
- terminal: `tmux`
- editors: `vim`, `neovim`
- CLI config: `git`, `htop`, `neofetch`
- optional toolchains: `rustup`, `nvm`, `bun`, `sdkman`

## Fresh Machine Setup

Install at least `git` and `zsh` first, then:

```sh
git clone <your-repo-url> ~/dotfiles
cd ~/dotfiles
bin/dot packages
bin/dot setup-safe
exec zsh
```

`setup-safe` is the recommended first run. It backs up conflicts to `*.backup` instead of replacing them in place.

`script/bootstrap` also creates these local-only files when they do not exist:

- `~/.gitconfig.local` from `git/gitconfig.local.symlink.example` if it does not exist
- `~/.localrc` from `local/localrc.example` if it does not exist
- `~/.toolchainsrc` from `local/toolchainsrc.example` if it does not exist

That keeps identity, secrets, proxies, and machine-specific paths out of the tracked repo.

## Daily Commands

```sh
bin/dot setup             # bootstrap + package install
bin/dot setup-safe        # bootstrap with backups + package install
bin/dot bootstrap         # only manage symlinks
bin/dot install           # only install packages and topic extras
bin/dot packages          # print package list for this machine
bin/dot ssh               # initialize ~/.ssh permissions and baseline config
bin/dot toolchains        # install toolchain packages, language tools, and optional runtimes
bin/dot toolchains-packages # print toolchain package list
bin/dot toolchains-runtimes # run only optional runtime installers
bin/dot update            # git pull + install
bin/dot edit              # open the repo in $EDITOR
```

Useful bootstrap flags:

```sh
script/bootstrap --backup
script/bootstrap --force
script/bootstrap --skip-gitconfig
```

## Profiles

`script/install` is Linux-only and does two things:

1. Installs packages from `packages/common.txt` plus the current distro file.
2. Runs each topic `install.sh`.

Base install hooks:

- `zsh/install.sh`: `oh-my-zsh`, `zsh-autosuggestions`, `zsh-syntax-highlighting`
- `vim/install.sh`: `vim-plug` and Vim plugins
- `nvim/install.sh`: installs the official Neovim release into `~/.local/opt`, links `~/.local/bin/nvim`, runs headless `Lazy sync`, and in toolchain mode `MasonToolsInstallSync`
- `ssh/install.sh`: initializes `~/.ssh` permissions and a baseline client config
- `toolchains/install.sh`: optional `rustup`, `nvm`, `bun`, `sdkman`

Toolchain mode adds:

- `packages/common-toolchains.txt`
- distro-specific toolchain package lists such as `packages/apt-toolchains.txt`
- Neovim Mason language tools
- optional toolchain installation for the current run

Run it separately from setup when you want a fuller development workstation:

```sh
bin/dot toolchains-packages
bin/dot toolchains
```

Runtime managers stay opt-in even in toolchain mode. Edit `~/.toolchainsrc` and set the entries you want to `1`.

The Neovim toolchain profile aims to cover a broad mainstream baseline:

- web: JavaScript, TypeScript, React, Vue, Svelte, Astro, HTML, CSS, Tailwind, GraphQL
- backend and systems: Python, Go, Rust, Java, PHP, Ruby, C/C++, Bash, Zig
- infra and data: Docker, Terraform, SQL, JSON, YAML, TOML, XML, Markdown

Neovim is installed from the official release tarball instead of the distro package. By default the repo pins `v0.11.5` through `nvim/install.sh`.

Override it for a different version with:

```sh
DOTFILES_NEOVIM_VERSION=v0.11.5 bin/dot install
```

## Managed Config

Top-level dotfiles:

- `~/.zshrc`
- `~/.zshenv`
- `~/.gitconfig`
- `~/.gitignore`
- `~/.tmux.conf`
- `~/.vimrc`

XDG config:

- `~/.config/nvim`
- `~/.config/htop`
- `~/.config/neofetch`

## Repository Layout

- `bin/`: entry points such as `bin/dot`
- `*.symlink`: linked into `$HOME` as dotfiles
- `topic/config/<app>/`: linked into `~/.config/<app>/`
- `shell/core/`: shared shell environment, aliases, path, keys, toolchains
- `shell/apps/`: app-specific shell modules such as git and docker
- `shell/functions/`: autoloaded shell functions and completion helpers
- `zsh/`: zsh entrypoints, prompt, window behavior, and installer
- `topic/install.sh`: topic-specific installers
- `packages/*.txt`: package lists by package manager
- `local/*.example`: local-only file templates

## Local-Only Settings

Keep anything machine-specific outside the tracked config:

- Git identity: `~/.gitconfig.local`
- secrets and tokens: `~/.localrc`
- toolchain install flags: `~/.toolchainsrc`
- proxy settings: `~/.localrc`
- custom paths such as `PROJECTS`: `~/.localrc`
- machine-specific shell hooks, such as local proxy controllers: `~/.localrc`

Examples:

```sh
export PROJECTS="$HOME/projects"
export http_proxy="http://proxy.example:8080"
export https_proxy="http://proxy.example:8080"
[[ -r "$HOME/path/to/local/tool.sh" ]] && source "$HOME/path/to/local/tool.sh"
```

## Adding More Config

Rules of thumb:

- top-level dotfile: add `name.symlink`
- XDG app config: add `topic/config/<app>/`
- reusable shell logic: add a `*.zsh` file under `shell/core/` or `shell/apps/<tool>/`
- one-time setup or tool bootstrap: add `topic/install.sh`

Examples:

- `tmux/tmux.conf.symlink` -> `~/.tmux.conf`
- `nvim/config/nvim/` -> `~/.config/nvim/`
- `git/gitconfig.symlink` -> `~/.gitconfig`
- `shell/core/env.zsh` -> loaded by `zsh/zshrc.symlink`

## Notes

- This repo is intended for Linux hosts.
- Zsh uses `oh-my-zsh` with the `lambda` theme by default.
- `EDITOR`, `VISUAL`, and `GIT_EDITOR` prefer `nvim`.
- `PROJECTS` defaults to `$HOME/projects`, then falls back to `$HOME/Code`.
- Cargo is loaded from `~/.cargo/env` through `~/.zshenv` when available.
- The repo can live anywhere; bootstrap refreshes `~/.dotfiles` as a symlink to the real path.
