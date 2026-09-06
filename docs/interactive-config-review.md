# Interactive configuration review

Reviewed on 2026-08-13 against the checked-out configuration and the current Ubuntu 24.04 WSL host; modernization decisions were revisited on 2026-09-03.

## Baseline

The host had Zsh 5.9, tmux 3.4, Git 2.43.0, fzf 0.44.1, ripgrep 15.2.0, Vim 9.1, and htop 3.3.0. Oh My Zsh, zsh-autosuggestions, and zsh-syntax-highlighting were installed. `zoxide`, `fzf-tab`, Starship, and TPM were not installed.

At the start of the review there was minor host/profile drift: `packages/common.txt` declared `btop` and a package named `yq`, but neither command was present on this host. Further inspection found that Ubuntu 24.04 resolves that `yq` name to the Python/jq-wrapper implementation rather than the commonly expected Mike Farah v4 CLI. Debian's `fdfind` and `batcat` names were present and were already normalized by shell aliases.

With an already-generated completion dump, representative warm interactive Zsh starts took 0.33-0.37 seconds. `zprof` attributed about 173 ms, or 82% of profiled function time, to eager NVM initialization. The first completion-cache build is naturally slower and was measured separately from steady state.

The tmux config parsed against tmux 3.4 but advertised `screen-256color` even though the richer `tmux-256color` terminfo entry is installed. Copy-mode bound the same `y` key up to three times; when both Wayland and X11 helpers existed, the last matching binding won rather than the intended provider. Pane deletion also bypassed tmux's normal confirmation prompt.

The editor configuration was later narrowed to a plugin-free Vim setup for terminal work, leaving IDE features to VS Code. htop remains a straightforward generated configuration.

## Decisions

| Area | Alternatives | Benefits | Costs and risks | Decision |
| --- | --- | --- | --- | --- |
| Zsh framework | Keep targeted Oh My Zsh plugins; switch to raw Zsh, Zim, or another manager | A framework switch can reduce parsing and offer more aggressive caching | Rewrites plugin loading, aliases, themes, update behavior, and fallback paths | Keep Oh My Zsh; the measured bottleneck was NVM, not the framework |
| Node runtime | Eagerly source NVM; hand-roll lazy functions; use Oh My Zsh's NVM lazy mode | Lazy loading removes runtime discovery from every shell while keeping normal commands | First Node command pays the initialization cost; hand-written shims drift as commands change | Use the maintained Oh My Zsh lazy mode, with an eager fallback only when Oh My Zsh is disabled |
| Fuzzy shell UI | Native completion only; Oh My Zsh fzf integration; install fzf-tab | fzf adds fuzzy history, path insertion, directory changes, and `**` completion | fzf-tab replaces the normal Tab UI, adds another checkout, and has strict widget load-order requirements | Enable the built-in fzf integration on real TTYs; retain native grouped Tab completion |
| Directory jumping | Keep Oh My Zsh `z`; migrate to zoxide | zoxide has a maintained binary, predictable frecency ranking, and interactive `zi` | It adds a binary and a second database; distro packages can lag upstream | Install zoxide in the base profile, let it own `z`/`zi`, and retain the OMZ plugin only as a no-binary fallback |
| Syntax highlighting | Load as an Oh My Zsh plugin; source after all widgets | End-of-file loading lets the highlighter observe the final ZLE hook and keymap state | One explicit source line is less framework-managed | Source it last, as upstream requires |
| History | Keep `APPEND_HISTORY`, `INC_APPEND_HISTORY`, and `SHARE_HISTORY`; choose one sharing policy | A single policy is predictable; duplicate filtering and `fcntl` locking improve long-running multi-shell use | Shared history intentionally exposes commands from other open shells | Keep `SHARE_HISTORY`, remove redundant incremental append, preserve 40k unique entries, and omit space-prefixed commands |
| tmux terminal model | Force `screen-256color`; force `tmux-256color`; detect terminfo | `tmux-256color` carries more key and display capabilities | Minimal remote systems may not install its terminfo entry | Prefer `tmux-256color` when `infocmp` finds it, otherwise fall back to `screen-256color`; declare RGB with `terminal-features` |
| tmux plugins | Add TPM plus sensible/yank/resurrect/navigator; stay native | TPM makes optional features easy to install and update | Adds Git/Bash/network bootstrap, more update state, and plugin key conflicts | Stay native because current needs fit in a small config and one portable clipboard helper |
| tmux copy | Multiple load-time bindings; OSC 52 only; one runtime provider | Runtime detection works across Wayland, X11, macOS, and WSL and avoids binding overwrite | Remote system clipboard behavior still depends on the terminal and tmux's `set-clipboard` capability | Use one `clipboard-copy` helper and retain tmux's own buffer/OSC 52 support |
| tmux Escape timing | `0`, default `500`, or a small delay | Zero is fastest locally; a small delay preserves fast Vim Escape handling while tolerating split Meta sequences on slower links | Any non-zero value adds that many milliseconds to a lone Escape | Use 10 ms as a conservative local/SSH compromise |
| Git typo handling | Immediate autocorrect; prompt; suggestion only | Prompt keeps convenience without silently running the wrong subcommand | Adds one confirmation for a corrected typo | Replace `help.autocorrect=1` (immediate execution) with `prompt` |
| Git review flow | Existing diff and conflict defaults; moved-line color plus `zdiff3` | Moved lines are visible and conflicts include the base while trimming matching edges | Conflict markers contain more context | Enable both, plus verbose commits and first-push upstream setup |
| Git pager | Native Git/less; Delta directly; a runtime wrapper around Delta | Delta adds syntax highlighting and cross-file navigation; a wrapper keeps Git usable after a partial or user-only install | A pager changes interactive presentation and adds one small dispatch script | Use Delta without side-by-side mode, through a fallback wrapper |
| Project environments | Keep variables in `.localrc`; add direnv | Project variables load and unload automatically, and `.envrc` requires explicit authorization | Reviewed `.envrc` files execute shell code and the hook runs at each prompt | Install direnv in the base profile and initialize its official Zsh hook late |
| File listing | Keep GNU/BSD `ls`; replace it globally; use eza for explicit views | eza adds Git status, headers, grouping, and trees | Its flags are not fully `ls` compatible; icons depend on fonts | Preserve `ls`; use eza only for `l`, `ll`, `la`, and `lt`, without icons |
| YAML CLI | Install the distro package named `yq`; pin Mike Farah yq | A pinned v4 binary gives consistent syntax on every supported distro | The repository owns another versioned user binary | Remove ambiguous distro `yq`; install the official v4 release with SHA-256 validation |
| System fetch UI | Keep Neofetch; migrate to Fastfetch | Fastfetch is maintained, faster, and more structured | Fastfetch is absent from the Ubuntu 24.04 repository, so the project must own its update lifecycle | Use a pinned official archive with architecture-specific SHA-256 validation and keep `neofetch` only as a compatibility alias |

## Implemented behavior

### Zsh

- NVM is represented by lightweight functions until the first Node-related command. The non-Oh-My-Zsh path retains the previous eager behavior.
- The Oh My Zsh fzf plugin supplies `Ctrl-R`, `Ctrl-T`, `Alt-C`, and fuzzy completion only when stdin and stdout are terminals. Non-interactive validation stays quiet.
- Completion tries exact matches before a single broader case/separator-insensitive pass. It groups descriptions, enables selection for ambiguous results, and puts caches under the configured XDG/Oh My Zsh cache root.
- History now uses one multi-session write policy, `fcntl` locking, duplicate-aware retention, and `HISTSIZE > SAVEHIST` as required for useful duplicate expiry.
- Syntax highlighting loads after every completion, widget, and key binding. Common Home, End, Alt-word, Ctrl-word, Delete, and Shift-Tab terminal sequences are covered.
- The redundant manual Git completion source was removed; `compinit` already autoloads the packaged `_git` entry from `fpath`.
- Docker aliases no longer interpolate the interactive shell's `$*`, and Compose v2 is the default when the legacy executable is absent.
- `reload!` replaces the current Zsh process instead of sourcing `.zshrc` repeatedly and accumulating plugin hooks.
- zoxide initializes after completion and replaces the older `z` implementation when installed; the OMZ plugin remains available on link-only/minimal hosts.
- Modern tools have distinct, discoverable aliases by default. Incompatible replacements for `grep`, `find`, `df`, and `top` require an explicit machine-local opt-in.

### tmux

- Terminal selection is terminfo-aware, true color uses the current `terminal-features` API, and Escape timing is 10 ms.
- Status now exposes window flags, current directory, prefix/copy/zoom/synchronize modes, host, and time. Activity and bell windows have distinct styles.
- Pane and window deletion require confirmation. Session/window trees use the whole pane, synchronized input reports its resulting state, and destroying one session prefers another session over detaching.
- Copy mode has consistent vi selection, rectangle selection, keyboard copy, and mouse copy. One helper chooses Wayland, X11, macOS, or WSL clipboard support at execution time.

### Git and other CLI configuration

- Typo correction prompts instead of executing immediately.
- First push establishes its upstream in the existing `simple` workflow.
- `zdiff3`, moved-line coloring, and verbose commit editing make review context more visible.
- Whitespace errors are warned about rather than suppressed.
- `pubkey` shares the portable clipboard helper with tmux.
- Delta formats human-facing Git output and interactive staging, with `n`/`N` navigation and a `less`/plain-output fallback when Delta is absent.
- eza powers explicit interactive listing aliases while the platform `ls` command retains its normal compatibility.
- direnv uses its official late Zsh hook and retains the visible, explicit `direnv allow` trust step.
- Hyperfine and btop are part of the base workstation profile; neither adds shell startup work.
- zoxide, duf, tealdeer, and just are part of the base profile; bat, tealdeer, and Fastfetch have managed XDG configuration.
- Fastfetch 2.67.1 replaces the archived Neofetch package through a pinned amd64/arm64 archive, SHA-256 verification, versioned installation, and managed completion/man-page links.
- Mike Farah yq v4.53.3 is installed from its official release with pinned amd64/arm64 SHA-256 values and a generated Zsh completion. The incompatible Ubuntu `yq` package is no longer requested.

After the change, warm TTY startup measured 0.08-0.12 seconds with the same configuration and cache setup. NVM remained unloaded at the prompt and loaded successfully on the first `node` invocation. These are local measurements rather than a promise for every machine, but they confirm that the selected bottleneck was real.

## Deferred options

- **fzf-tab:** its full-screen completion selector is attractive for very large completion sets, but it must load after `compinit` and before widget-wrapping plugins, and it competes with both fzf's and `z`'s Tab wrappers. Native menu completion plus explicit fzf keys has fewer moving parts.
- **Starship:** useful when a shared cross-shell prompt with language/tool context is wanted. The current Lambda prompt is small and did not appear in the startup profile, so adding a binary and more prompt subprocess work has no measured payoff here.
- **TPM, tmux-resurrect, and seamless Vim/tmux navigation:** worthwhile when session restoration or prefix-free pane crossing is explicitly desired. The latter also takes over global `Ctrl-H/J/K/L` behavior inside tmux, including `Ctrl-L`'s usual clear-screen action.

## Primary references

- [Oh My Zsh NVM plugin and lazy mode](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/nvm)
- [Oh My Zsh fzf integration](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/fzf)
- [Zsh history options](https://zsh.sourceforge.io/Doc/Release/Options.html#History)
- [Zsh completion matcher-list](https://zsh.sourceforge.io/Doc/Release/Completion-System.html)
- [zsh-syntax-highlighting load-order requirement](https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/INSTALL.md)
- [fzf-tab load order and compatibility notes](https://github.com/Aloxaf/fzf-tab)
- [zoxide behavior and installation matrix](https://github.com/ajeetdsouza/zoxide)
- [tmux terminal and Escape guidance](https://github.com/tmux/tmux/wiki/FAQ)
- [tmux copy and clipboard guidance](https://github.com/tmux/tmux/wiki/Clipboard)
- [tmux options and copy-mode behavior](https://github.com/tmux/tmux/wiki/Getting-Started)
- [TPM requirements and workflow](https://github.com/tmux-plugins/tpm)
- [Git configuration reference](https://git-scm.com/docs/git-config)
- [Delta setup and navigation](https://dandavison.github.io/delta/get-started.html)
- [direnv hook and authorization model](https://direnv.net/)
- [eza features and options](https://github.com/eza-community/eza)
- [bat configuration](https://github.com/sharkdp/bat#configuration-file)
- [duf usage and packages](https://github.com/muesli/duf)
- [tealdeer configuration](https://docs.tealdeer.org/latest/config.html)
- [just installation and recipes](https://github.com/casey/just)
- [Hyperfine measurement model](https://github.com/sharkdp/hyperfine)
- [Mike Farah yq releases and installation](https://github.com/mikefarah/yq)
- [Ubuntu 24.04's different yq package](https://packages.ubuntu.com/noble/amd64/utils/yq)
- [Neofetch archived repository](https://github.com/dylanaraps/neofetch)
- [Fastfetch support and installation matrix](https://github.com/fastfetch-cli/fastfetch)
