# dotfiles

Linux-first dotfiles for bootstrapping a new workstation quickly.

This repo manages:

- shell: `zsh`, `oh-my-zsh`, aliases, completions, paths
- terminal: `tmux`
- editors: `vim`, `neovim`
- CLI config: `git`, `htop`, `neofetch`
- optional toolchain profiles: `nvim`, `node`, `java`, `rust`, `go`, `python`, `bun`

## Fresh Machine Setup

Install at least `git` and `zsh` first, then:

```sh
git clone <your-repo-url> ~/dotfiles
cd ~/dotfiles
bin/dot init
exec zsh
```

`bin/dot init` opens the guided terminal setup. It previews the machine, then lets you choose package scope, conflict handling, a cache workspace, Git identity, and toolchain profiles. Nothing is changed until the final confirmation, where the equivalent `bin/dot setup ...` command is shown.

The TUI is implemented in Bash and has no pre-install dependency on Python, `dialog`, `whiptail`, or `gum`. Use arrow keys or `j`/`k` to move, Space to toggle toolchains, Enter to continue, `b` to go back, and `q` to quit. Choosing overwrite lists the conflicting paths, requires typing `OVERWRITE`, and authorizes only those exact targets. `bin/dot init --dry-run` walks through the same choices without executing setup; `bin/dot setup --tui` is an alias.

For scripts, remote provisioning, and other non-interactive environments, the existing CLI remains available:

```sh
bin/dot packages
bin/dot setup --backup
```

`setup --backup` moves conflicts into a unique session under `${XDG_STATE_HOME:-~/.local/state}/dotfiles/backups/` instead of replacing them in place. Each session includes a `manifest.tsv` with the original path, backup path, file type, and UTC timestamp; existing `*.backup` files are never reused or overwritten. When set, `XDG_STATE_HOME` must be absolute and must not resolve to `/`; invalid values are rejected before bootstrap changes anything.

To put application caches on a dedicated data volume, opt in with a workspace:

```sh
bin/dot setup --backup --cache-workspace /data4/zhangxun
```

Without `--cache-workspace`, setup does not create cache directories or change cache environment variables.

For non-interactive server bootstrap, provide Git identity through environment variables:

```sh
DOTFILES_GIT_AUTHORNAME="Your Name" DOTFILES_GIT_AUTHOREMAIL="you@example.com" bin/dot setup --backup
```

`script/bootstrap` also creates these local-only files when they do not exist:

- `~/.gitconfig.local` from `git/gitconfig.local.symlink.example` if identity is provided interactively or through environment variables
- `~/.localrc` from `local/localrc.example` if it does not exist
- `~/.toolchainsrc` from `local/toolchainsrc.example` if it does not exist

That keeps identity, secrets, proxies, and machine-specific paths out of the tracked repo.

## Daily Commands

```sh
bin/dot init              # interactive guided setup
bin/dot init --dry-run    # review TUI choices without installing
bin/dot setup             # bootstrap + package install
bin/dot setup --tui       # alias for the guided setup
bin/dot setup --backup    # bootstrap with backups + package install
bin/dot setup --user      # bootstrap and skip system packages
bin/dot setup --cache-workspace /data4/zhangxun # configure centralized caches
bin/dot bootstrap         # only manage symlinks
bin/dot install           # only install packages and topic extras
bin/dot install --user    # install topic extras and skip system packages
bin/dot install --cache-workspace /data4/zhangxun # configure caches, then install
bin/dot install --toolchains node java # install selected toolchain profiles
bin/dot packages          # print package list for this machine
bin/dot packages --toolchains node # print package list for selected toolchains
bin/dot ssh               # initialize ~/.ssh permissions and baseline config
bin/dot toolchains list   # print available toolchain profiles
bin/dot toolchains        # install default profiles from ~/.toolchainsrc
bin/dot toolchains node java # install selected profiles
bin/dot update            # git pull + non-interactive link reconcile + install
bin/dot edit              # open the repo in $EDITOR
```

Useful bootstrap flags:

```sh
script/bootstrap --backup
script/bootstrap --force
script/bootstrap --skip-gitconfig
script/bootstrap --cache-workspace /data4/zhangxun
```

## Optional Cache Workspace

`--cache-workspace DIR` is an explicit machine-local profile. It creates the cache tree under `DIR/cache` and writes a mode-`0600` immutable profile under `${XDG_CONFIG_HOME:-~/.config}/dotfiles/cache-env.d/`. It also maintains an independent `cache-env.sh` compatibility copy while that path remains managed, without overwriting a concurrently replaced path. `~/.zshenv` and `script/install` select the newest complete immutable profile, so activation is atomic and the first setup run already uses the selected locations.

The profile configures:

- general: `WORKSPACE`, `CACHE_HOME`, `TMPDIR`, `XDG_CACHE_HOME`
- PyTorch: `TORCH_HOME`, `TORCH_EXTENSIONS_DIR`, `TORCHINDUCTOR_CACHE_DIR`
- Hugging Face: `HF_HOME`, `HF_HUB_CACHE`, `HF_DATASETS_CACHE`, `HF_ASSETS_CACHE`, `HF_XET_CACHE`
- package managers: `PIP_CACHE_DIR`, `UV_CACHE_DIR`, `PIXI_CACHE_DIR`, `npm_config_cache`
- GPU and compiler caches: `CUDA_CACHE_PATH`, `TRITON_CACHE_DIR`, `GOCACHE`, `GOMODCACHE`
- experiment and visualization tools: `WANDB_CACHE_DIR`, `WANDB_DATA_DIR`, `MPLCONFIGDIR`

Because `HF_HOME` normally also contains authentication state, the generated profile sets `HF_TOKEN_PATH` to `${XDG_CONFIG_HOME:-~/.config}/huggingface/token`, outside the disposable cache tree.

The workspace must be an absolute path other than `/`; it is resolved before use so `..` and symbolic links cannot bypass the root-directory guard. `XDG_CONFIG_HOME`, when set, must also be absolute. Paths with spaces and shell metacharacters are quoted safely. Re-running the command appends a complete profile version, creates the new tree, and leaves both prior profiles and the old cache tree in place. It never overwrites an unrelated file or symbolic link at the compatibility path.

`TMPDIR`, Torch extensions, Triton, and uv can be sensitive to mount behavior. Prefer a local, writable filesystem; a `noexec` or slow network mount can break compiled extensions or reduce cache performance. If the configured `tmp` directory later disappears or becomes unwritable, new shells stop exporting that `TMPDIR` and fall back to the system default.

## Profiles

`script/install` is Linux-only and does two things:

1. Installs packages from `packages/common.txt` plus the current distro file.
2. Runs each topic `install.sh`.

By default, package installation uses the system package manager through `sudo` when needed. It installs in bulk first, then retries packages one by one if a distro mirror or package name causes the bulk install to fail. Use `bin/dot setup --user` or `bin/dot install --user` when you explicitly want to skip system packages; user-only mode does not require or probe for a supported system package manager.

Package and topic failures are accumulated so the remaining independent installers can run. The final summary lists failures, and `dot install` / `dot setup` returns a non-zero status if any required package, topic, or selected toolchain profile failed.

The base profile includes a practical server/workstation baseline: Git, zsh, Vim, tmux, htop, Neovim support tools, GitHub CLI, ripgrep/fzf, JSON/YAML tools, archive tools, rsync, tree, file, lsof, ncdu, btop, OpenSSH client, DNS/IP/ping/netcat utilities, Python 3, and build essentials for the current distro.

Base install hooks:

- `zsh/install.sh`: `oh-my-zsh`, `zsh-autosuggestions`, `zsh-syntax-highlighting`
- `vim/install.sh`: `vim-plug` and Vim plugins
- `nvim/install.sh`: installs the official Neovim release into `~/.local/opt`, links `~/.local/bin/nvim`, and runs headless `Lazy sync`
- `ssh/install.sh`: initializes `~/.ssh` permissions and a baseline client config
- `toolchains/install.sh`: dispatches selected toolchain profiles

Base topic installers run in this order: `ssh`, `zsh`, `vim`, then `nvim`. In toolchain mode, `toolchains/install.sh` runs after those base installers. A failed topic installer is reported and does not prevent the remaining topics from running, but the top-level command ultimately returns a non-zero status.

Toolchain profiles are independent. Select only what a machine needs:

```sh
bin/dot toolchains list
bin/dot packages --toolchains node java
bin/dot toolchains node java
```

When no profile is passed, `bin/dot toolchains` uses `DOTFILES_TOOLCHAINS` from `~/.toolchainsrc`. The template defaults to `nvim`.

Available profiles:

- `nvim`: installs Neovim Mason language tools from `nvim/config/nvim/lua/plugins/lsp.lua`
- `node`: installs `nvm`, Node.js LTS, Corepack, `pnpm`, `yarn`, and npm global tools
- `java`: installs `sdkman`, JDK 21 Temurin, Maven, Gradle, and Kotlin
- `rust`: installs `rustup`, stable Rust, `rustfmt`, and `clippy`
- `go`: installs common Go tools with `go install`
- `python`: installs `uv` and selected Python CLI tools
- `bun`: installs Bun

Each profile can have package prerequisites under `toolchains/packages/common/<profile>.txt` and `toolchains/packages/<distro>/<profile>.txt`. The installer reads those files after the base package list and before running profile scripts.

The Neovim toolchain profile aims to cover a broad mainstream baseline:

- web: JavaScript, TypeScript, React, Vue, Svelte, Astro, HTML, CSS, Tailwind, GraphQL
- backend and systems: Python, Go, Rust, Java, PHP, Ruby, C/C++, Bash, Zig
- infra and data: Docker, Terraform, SQL, JSON, YAML, TOML, XML, Markdown

Neovim is installed from the official release tarball instead of the distro package. By default the repo pins `v0.11.5` and its architecture-specific SHA-256 through `nvim/install.sh`. Every install reconciles `neovim-current` with the requested version, so changing the target selects or installs that version even when an older `~/.local/bin/nvim` already exists.

For a version not already pinned in the script, provide both the version and the official SHA-256 for the current architecture:

```sh
DOTFILES_NEOVIM_VERSION=v0.11.6 \
DOTFILES_NEOVIM_SHA256=<sha256> \
bin/dot install --user
```

`bin/dot update` reconciles newly added managed links after pulling. It skips real-file conflicts and does not remove stale links automatically.

## Tests

The isolated test suite uses temporary homes and fake package/tool commands; it does not install packages or access the network:

```sh
bash test/run.sh
```

CI runs the suite plus `bash -n` over the shell entrypoints.

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
- `script/setup-tui.sh`: dependency-free interactive setup wizard
- `*.symlink`: linked into `$HOME` as dotfiles
- `topic/config/<app>/`: linked into `~/.config/<app>/`
- `shell/core/`: shared shell environment, aliases, path, keys, toolchains
- `shell/apps/`: app-specific shell modules such as git and docker
- `shell/functions/`: autoloaded shell functions and completion helpers
- `zsh/`: zsh entrypoints, prompt, window behavior, and installer
- `topic/install.sh`: topic-specific installers
- `packages/*.txt`: package lists by package manager
- `toolchains/profiles/`: profile scripts such as `node.sh` and `java.sh`
- `toolchains/packages/`: profile-specific package prerequisites
- `toolchains/lib/`: shared toolchain installer helpers
- `local/*.example`: local-only file templates

## Local-Only Settings

Keep anything machine-specific outside the tracked config:

- Git identity: `~/.gitconfig.local`
- secrets and tokens: `~/.localrc`
- toolchain profile defaults: `~/.toolchainsrc`
- proxy settings: `~/.localrc`
- custom paths such as `PROJECTS`: `~/.localrc`
- generated cache paths: `${XDG_CONFIG_HOME:-~/.config}/dotfiles/cache-env.d/`
- machine-specific shell hooks, such as local proxy controllers: `~/.localrc`

Examples:

```sh
export PROJECTS="$HOME/projects"
export HTTP_PROXY="http://proxy.example:8080"
export HTTPS_PROXY="$HTTP_PROXY"
export http_proxy="$HTTP_PROXY"
export https_proxy="$HTTPS_PROXY"
[[ -r "$HOME/path/to/local/tool.sh" ]] && source "$HOME/path/to/local/tool.sh"
```

## Adding More Config

Rules of thumb:

- top-level dotfile: add `name.symlink`
- XDG app config: add `topic/config/<app>/`
- reusable shell logic: add a `*.zsh` file under `shell/core/` or `shell/apps/<tool>/`
- one-time setup or tool bootstrap: add `topic/install.sh`
- toolchain profile: add `toolchains/profiles/<name>.sh` and any package files under `toolchains/packages/`

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
