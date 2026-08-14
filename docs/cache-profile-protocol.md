# Cache profile protocol

Cache profiles live under `${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles` and are
selected by the shared implementation in `script/lib/cache-profile.sh`.

## Selection

1. The version directory must be a real directory, not a symbolic link.
2. Version candidates must be readable regular files named
   `vNNNNNNNNNNNNNNNNNN.sh`, where the version is exactly 18 decimal digits.
3. A complete version starts with
   `# Managed by dotfiles script/cache-env.sh.` and ends with
   `# End managed dotfiles cache environment.`.
4. The complete candidate with the lexicographically greatest filename is
   selected. Fixed-width decimal names make lexical and numeric order match.
5. If no complete version exists, consumers may use the compatibility file
   `cache-env.sh` when it is a readable, non-symlink regular file with the
   managed opening marker. A complete immutable version always takes priority.

The generator, package installer, setup TUI, and Zsh startup all use this same
selection code. Consumers may handle an invalid `XDG_CONFIG_HOME` differently:
writers and interactive diagnostics reject it, while shell startup and package
installation fall back to `$HOME/.config` to avoid breaking a login shell.

## Publication

`script/cache-env.sh` owns publication. It serializes writers with `flock`,
writes a mode-`0600` temporary file, publishes immutable versions without
clobbering an existing path, and updates the compatibility copy only when its
observed inode is still current. Readers never select temporary or incomplete
files, so an interrupted update leaves the previous complete version active.

The compatibility file exists for older consumers and migration. It is not the
source of truth once an immutable version has been published, and an unrelated
file or symbolic link at that path is never overwritten.
