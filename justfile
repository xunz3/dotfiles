set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# Show the available repository workflows.
default:
    @just --list

# Run the isolated test suite.
test:
    bash test/run.sh

# Validate shell syntax without installing anything.
lint:
    @while IFS= read -r -d '' file; do case "$(head -n 1 "$file")" in *sh) bash -n "$file" ;; esac; done < <(find bin script ssh toolchains fastfetch tealdeer yq zsh test -type f -print0)
    @find shell zsh -type f \( -name '*.zsh' -o -name '*.symlink' -o -path 'shell/functions/*' \) -print0 | xargs -0 -r -n 1 zsh -n

# Inspect managed links and the preferred CLI toolbox.
doctor:
    bin/dot doctor

# Print packages resolved for this machine.
packages:
    bin/dot packages
