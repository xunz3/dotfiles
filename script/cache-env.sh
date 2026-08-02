#!/usr/bin/env bash
#
# Generate the optional machine-local cache environment.

set -euo pipefail

managed_marker='# Managed by dotfiles script/cache-env.sh.'
managed_end_marker='# End managed dotfiles cache environment.'

fail () {
	printf 'cache env: %s\n' "$1" >&2
	exit 1
}

shell_quote () {
	local value=$1
	printf "'%s'" "${value//\'/\'\\\'\'}"
}

usage () {
	cat <<'EOF'
Usage: script/cache-env.sh [--validate] WORKSPACE

Create a machine-local cache environment under WORKSPACE/cache.
WORKSPACE must be an absolute path other than /.

Options:
  --validate  check the paths without creating files or directories
EOF
}

validate_only=false
if [[ $# -eq 2 && "$1" == "--validate" ]]
then
	validate_only=true
	shift
elif [[ $# -ne 1 ]]
then
	usage >&2
	exit 2
fi

workspace=$1

if [[ -z "$workspace" || "$workspace" != /* ]]
then
	fail 'WORKSPACE must be an absolute path'
fi

if [[ "$workspace" =~ [[:cntrl:]] ]]
then
	fail 'WORKSPACE must not contain control characters'
fi

while [[ "$workspace" != "/" && "$workspace" == */ ]]
do
	workspace=${workspace%/}
done

if ! workspace="$(realpath -m -- "$workspace")"
then
	fail 'could not resolve WORKSPACE'
fi

if [[ "$workspace" == "/" ]]
then
	fail 'WORKSPACE cannot be /'
fi

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
if [[ "$config_home" != /* ]]
then
	fail 'XDG_CONFIG_HOME must be an absolute path when set'
fi

if ! config_home="$(realpath -m -- "$config_home")"
then
	fail 'could not resolve XDG_CONFIG_HOME'
fi

if [[ "$config_home" == "/" ]]
then
	fail 'XDG_CONFIG_HOME cannot be /'
fi

config_dir="$config_home/dotfiles"
config_file="$config_dir/cache-env.sh"
version_dir="$config_dir/cache-env.d"
existing_marker=''
temporary_file=''
compatibility_temp=''
existing_fd=''
existing_fd_path=''
lock_fd=''
version_file=''
compatibility_action='none'
managed_versions_present=false
replacement_dir=''
replacement_path=''
replacement_is_expected=false
max_version=0

path_or_parent_is_writable () {
	local path=$1 parent=$1

	if [[ -e "$path" || -L "$path" ]]
	then
		[[ -d "$path" && -w "$path" && -x "$path" ]]
		return
	fi

	while [[ "$parent" != "/" && ! -e "$parent" && ! -L "$parent" ]]
	do
		parent=${parent%/*}
		[[ -n "$parent" ]] || parent='/'
	done

	[[ -d "$parent" && -w "$parent" && -x "$parent" ]]
}

if ! path_or_parent_is_writable "$workspace"
then
	fail 'WORKSPACE or its nearest existing parent must be a writable directory'
fi
if ! path_or_parent_is_writable "$config_dir"
then
	fail 'the cache configuration directory or its nearest existing parent must be writable'
fi
if ! command -v flock >/dev/null 2>&1
then
	fail 'flock is required to update the cache environment safely'
fi
if [[ "$validate_only" == "true" ]]
then
	exit 0
fi

umask 077
if ! mkdir -p -- "$config_dir"
then
	fail "could not create cache configuration directory: $config_dir"
fi
if ! exec {lock_fd}< "$config_dir" || ! flock -n "$lock_fd"
then
	fail "another cache environment update is already running for $config_dir"
fi

path_exists () {
	[[ -e "$1" || -L "$1" ]]
}

settle_replacement_hold () {
	local restored=false

	[[ -n "${replacement_dir:-}" ]] || return 0
	if path_exists "$replacement_path"
	then
		if ! path_exists "$config_file"
		then
			if [[ -d "$replacement_path" && ! -L "$replacement_path" ]]
			then
				mv -nT -- "$replacement_path" "$config_file" 2>/dev/null || true
				! path_exists "$replacement_path" && restored=true
			elif ln -P -T -- "$replacement_path" "$config_file" 2>/dev/null
			then
				rm -f -- "$replacement_path"
				restored=true
			fi
		fi

		if path_exists "$replacement_path"
		then
			if [[ "$replacement_is_expected" == "true" ]] &&
				path_exists "$config_file"
			then
				rm -f -- "$replacement_path"
			else
				printf 'cache env: preserved a concurrently replaced compatibility path at %s\n' \
					"$replacement_path" >&2
				replacement_dir=''
				replacement_path=''
				replacement_is_expected=false
				return
			fi
		elif [[ "$restored" == "true" ]]
		then
			printf 'cache env: restored a concurrently replaced compatibility path: %s\n' \
				"$config_file" >&2
		fi
	fi

	rmdir -- "$replacement_dir" 2>/dev/null || true
	replacement_dir=''
	replacement_path=''
	replacement_is_expected=false
}

cleanup () {
	settle_replacement_hold
	if [[ -n "${temporary_file:-}" && -e "$temporary_file" ]]
	then
		rm -f -- "$temporary_file"
	fi
	if [[ -n "${compatibility_temp:-}" && -e "$compatibility_temp" ]]
	then
		rm -f -- "$compatibility_temp"
	fi
	if [[ -n "${existing_fd:-}" ]]
	then
		exec {existing_fd}<&-
	fi
	if [[ -n "${lock_fd:-}" ]]
	then
		exec {lock_fd}<&-
	fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

replace_compatibility_if_unchanged () {
	replacement_dir="$(mktemp -d "$config_dir/.cache-env.swap.XXXXXX")"
	chmod 700 "$replacement_dir"
	replacement_path="$replacement_dir/original"
	replacement_is_expected=false

	# Moving the current entry to an empty path in a private directory never
	# overwrites it. The inode check happens after the move, closing the usual
	# check-then-rename race before the no-clobber publication below.
	mv -nT -- "$config_file" "$replacement_path" 2>/dev/null || true
	if ! path_exists "$replacement_path"
	then
		printf 'cache env: compatibility path changed after version publication; left it unchanged: %s\n' \
			"$config_file" >&2
		settle_replacement_hold
		return 1
	fi

	if [[ -L "$replacement_path" ||
		! "$replacement_path" -ef "$existing_fd_path" ]]
	then
		printf 'cache env: compatibility path changed during publication; restoring it: %s\n' \
			"$config_file" >&2
		settle_replacement_hold
		return 1
	fi
	replacement_is_expected=true

	if ln -T -- "$compatibility_temp" "$config_file" 2>/dev/null
	then
		rm -f -- "$compatibility_temp"
		compatibility_temp=''
		settle_replacement_hold
		return 0
	fi

	printf 'cache env: compatibility path appeared during publication; left it unchanged: %s\n' \
		"$config_file" >&2
	settle_replacement_hold
	return 1
}

if [[ -L "$version_dir" || ( -e "$version_dir" && ! -d "$version_dir" ) ]]
then
	fail "$version_dir is not a regular directory; leaving it unchanged"
fi
if ! mkdir -p -- "$version_dir"
then
	fail "could not create cache environment version directory: $version_dir"
fi

managed_version_file_is_complete () {
	local candidate=$1
	local marker='' end_marker='' line='' first_line=true

	[[ -e "$candidate" && ! -L "$candidate" && -f "$candidate" &&
		-r "$candidate" ]] || return 1
	while IFS= read -r line || [[ -n "$line" ]]
	do
		if [[ "$first_line" == "true" ]]
		then
			marker=$line
			first_line=false
		fi
		end_marker=$line
	done < "$candidate"

	[[ "$marker" == "$managed_marker" &&
		"$end_marker" == "$managed_end_marker" ]]
}

managed_version_exists () {
	local candidate candidate_name version_digits

	for candidate in "$version_dir"/v*.sh
	do
		candidate_name=${candidate##*/}
		version_digits=${candidate_name#v}
		version_digits=${version_digits%.sh}
		[[ ${#version_digits} -eq 18 &&
			"$version_digits" != *[!0-9]* ]] || continue
		managed_version_file_is_complete "$candidate" && return 0
	done

	return 1
}

if managed_version_exists
then
	managed_versions_present=true
fi

if [[ ! -e "$config_file" && ! -L "$config_file" ]]
then
	compatibility_action='create'
elif [[ "$managed_versions_present" == "true" ]]
then
	# Once an immutable version exists, it is authoritative. Refresh an older
	# managed compatibility copy, but never replace an unmanaged path.
	if [[ ! -L "$config_file" && -f "$config_file" ]] &&
		exec {existing_fd}< "$config_file"
	then
		existing_fd_path="/proc/self/fd/$existing_fd"
		if [[ ! -L "$config_file" && "$config_file" -ef "$existing_fd_path" ]] &&
			IFS= read -r -u "$existing_fd" existing_marker &&
			[[ "$existing_marker" == "$managed_marker" ]]
		then
			compatibility_action='replace'
		else
			exec {existing_fd}<&-
			existing_fd=''
			existing_fd_path=''
		fi
	fi
else
	if [[ -L "$config_file" ]]
	then
		fail "$config_file is a symbolic link; leaving it unchanged"
	fi

	if [[ -e "$config_file" ]]
	then
		if [[ ! -f "$config_file" ]]
		then
			fail "$config_file is not a regular file; leaving it unchanged"
		fi

		if ! exec {existing_fd}< "$config_file"
		then
			fail "$config_file changed while it was being opened; leaving it unchanged"
		fi
		existing_fd_path="/proc/self/fd/$existing_fd"
		if [[ -L "$config_file" || ! "$config_file" -ef "$existing_fd_path" ]] ||
			! IFS= read -r -u "$existing_fd" existing_marker ||
			[[ "$existing_marker" != "$managed_marker" ]]
		then
			fail "$config_file is not managed by dotfiles; leaving it unchanged"
		fi
		compatibility_action='replace'
	else
		compatibility_action='create'
	fi
fi

cache_home="$workspace/cache"
hf_config_home="$config_home/huggingface"
directories=(
	"$cache_home/tmp"
	"$cache_home/torch"
	"$cache_home/torch_extensions"
	"$cache_home/torch_inductor"
	"$cache_home/huggingface/hub"
	"$cache_home/huggingface/datasets"
	"$cache_home/huggingface/assets"
	"$cache_home/huggingface/xet"
	"$cache_home/pip"
	"$cache_home/uv"
	"$cache_home/pixi"
	"$cache_home/cuda"
	"$cache_home/triton"
	"$cache_home/go/build"
	"$cache_home/go/modules"
	"$cache_home/xdg"
	"$cache_home/wandb/data"
	"$cache_home/matplotlib"
	"$cache_home/npm"
	"$hf_config_home"
)

for directory in "${directories[@]}"
do
	mkdir -p -- "$directory"
	if [[ ! -d "$directory" || ! -w "$directory" || ! -x "$directory" ]]
	then
		fail "cache directory is not writable: $directory"
	fi
done

temporary_file="$(mktemp "$version_dir/.cache-env.sh.XXXXXX")"

workspace_quoted="$(shell_quote "$workspace")"
hf_token_path_quoted="$(shell_quote "$hf_config_home/token")"
workspace_hex="$(
	printf '%s' "$workspace" |
		LC_ALL=C od -An -v -tx1 |
		tr -d '[:space:]'
)"

{
	printf '%s\n' "$managed_marker"
	printf '# Workspace-Hex: %s\n' "$workspace_hex"
	cat <<'EOF'
# Re-run `bin/dot setup --cache-workspace WORKSPACE` to create a newer profile.

# ==============================
# Cache roots
# ==============================
EOF
	printf 'export WORKSPACE=%s\n' "$workspace_quoted"
	cat <<'EOF'
export CACHE_HOME="$WORKSPACE/cache"
# A missing TMPDIR breaks mktemp. Fall back to the system default if the
# configured cache tree was removed or its data volume is unavailable.
if [ -d "$CACHE_HOME/tmp" ] && [ -w "$CACHE_HOME/tmp" ]; then
  export TMPDIR="$CACHE_HOME/tmp"
elif [ "${TMPDIR:-}" = "$CACHE_HOME/tmp" ]; then
  unset TMPDIR
fi
export XDG_CACHE_HOME="$CACHE_HOME/xdg"

# Torch
export TORCH_HOME="$CACHE_HOME/torch"
export TORCH_EXTENSIONS_DIR="$CACHE_HOME/torch_extensions"
export TORCHINDUCTOR_CACHE_DIR="$CACHE_HOME/torch_inductor"

# Hugging Face
export HF_HOME="$CACHE_HOME/huggingface"
export HF_HUB_CACHE="$HF_HOME/hub"
export HF_DATASETS_CACHE="$HF_HOME/datasets"
export HF_ASSETS_CACHE="$HF_HOME/assets"
export HF_XET_CACHE="$HF_HOME/xet"
# Keep the authentication token outside the disposable cache tree.
EOF
	printf 'export HF_TOKEN_PATH=%s\n' "$hf_token_path_quoted"
	cat <<'EOF'

# Python package managers
export PIP_CACHE_DIR="$CACHE_HOME/pip"
export UV_CACHE_DIR="$CACHE_HOME/uv"
export PIXI_CACHE_DIR="$CACHE_HOME/pixi"

# GPU compilers
export CUDA_CACHE_PATH="$CACHE_HOME/cuda"
export TRITON_CACHE_DIR="$CACHE_HOME/triton"

# Go
export GOCACHE="$CACHE_HOME/go/build"
export GOMODCACHE="$CACHE_HOME/go/modules"

# Weights & Biases
export WANDB_CACHE_DIR="$CACHE_HOME/wandb"
export WANDB_DATA_DIR="$CACHE_HOME/wandb/data"

# Visualization
export MPLCONFIGDIR="$CACHE_HOME/matplotlib"

# Node.js
export npm_config_cache="$CACHE_HOME/npm"
EOF
	printf '%s\n' "$managed_end_marker"
} > "$temporary_file"

chmod 600 "$temporary_file"
compatibility_temp="$(mktemp "$config_dir/.cache-env.compat.XXXXXX")"
cp -- "$temporary_file" "$compatibility_temp"
chmod 600 "$compatibility_temp"

if [[ "$compatibility_action" == "replace" ]]
then
	if [[ -L "$config_file" || ! "$config_file" -ef "$existing_fd_path" ]]
	then
		if [[ "$managed_versions_present" == "true" ]]
		then
			printf 'cache env: compatibility path changed; left it unchanged: %s\n' \
				"$config_file" >&2
			compatibility_action='none'
			exec {existing_fd}<&-
			existing_fd=''
			existing_fd_path=''
		else
			fail "$config_file changed while it was being generated; leaving it unchanged"
		fi
	fi
elif [[ "$compatibility_action" == "create" &&
	( -e "$config_file" || -L "$config_file" ) ]]
then
	if [[ "$managed_versions_present" == "true" ]]
	then
		printf 'cache env: compatibility path appeared; left it unchanged: %s\n' \
			"$config_file" >&2
		compatibility_action='none'
	else
		fail "$config_file appeared while it was being created; leaving it unchanged"
	fi
fi

for candidate in "$version_dir"/v*.sh
do
	[[ -e "$candidate" || -L "$candidate" ]] || continue
	candidate_name=${candidate##*/}
	if [[ "$candidate_name" =~ ^v([0-9]{18})\.sh$ ]] &&
		managed_version_file_is_complete "$candidate"
	then
		version_number=$((10#${BASH_REMATCH[1]}))
		[[ "$version_number" -gt "$max_version" ]] &&
			max_version=$version_number
	fi
done

for attempt in {1..10}
do
	if [[ "$max_version" -ge 999999999999999999 ]]
	then
		version_file=''
		break
	fi
	max_version=$((max_version + 1))
	printf -v candidate_name 'v%018d.sh' "$max_version"
	version_file="$version_dir/$candidate_name"
	if ln -T -- "$temporary_file" "$version_file" 2>/dev/null
	then
		break
	fi
	version_file=''
done
if [[ -z "$version_file" ]]
then
	fail 'could not commit a unique cache environment version'
fi

if [[ "$compatibility_action" == "replace" ]]
then
	replace_compatibility_if_unchanged || true
elif [[ "$compatibility_action" == "create" ]]
then
	if ln -T -- "$compatibility_temp" "$config_file" 2>/dev/null
	then
		rm -f -- "$compatibility_temp"
		compatibility_temp=''
	else
		printf 'cache env: compatibility path appeared; left it unchanged: %s\n' \
			"$config_file" >&2
	fi
fi
if [[ -n "$compatibility_temp" ]]
then
	if ! rm -f -- "$compatibility_temp"
	then
		printf 'cache env: could not remove temporary compatibility file: %s\n' \
			"$compatibility_temp" >&2
	fi
	compatibility_temp=''
fi
rm -f -- "$temporary_file"
temporary_file=''
if [[ -n "$existing_fd" ]]
then
	exec {existing_fd}<&-
	existing_fd=''
fi
exec {lock_fd}<&-
lock_fd=''
trap - EXIT HUP INT TERM

printf 'cache env: wrote %s\n' "$version_file"
printf 'cache env: workspace %s\n' "$workspace"
