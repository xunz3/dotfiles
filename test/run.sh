#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_TMP_ROOT="$(mktemp -d /tmp/dotfiles-tests.XXXXXX)"
passed=0
failed=0

cleanup () {
	rm -rf -- "$TEST_TMP_ROOT"
}
trap cleanup EXIT

fail_test () {
	printf '    %s\n' "$1" >&2
	exit 1
}

assert_contains () {
	local haystack=$1 needle=$2
	[[ "$haystack" == *"$needle"* ]] || fail_test "expected output to contain: $needle"
}

assert_nul_args () {
	local file=$1
	shift
	local expected=("$@")
	local actual=()
	local index

	[[ -f "$file" ]] || fail_test "argument log was not created: $file"
	mapfile -d '' -t actual < "$file"
	[[ ${#actual[@]} -eq ${#expected[@]} ]] || \
		fail_test "expected ${#expected[@]} arguments, got ${#actual[@]}"
	for index in "${!expected[@]}"
	do
		[[ "${actual[$index]}" == "${expected[$index]}" ]] || \
			fail_test "argument $index did not match: expected $(printf '%q' "${expected[$index]}"), got $(printf '%q' "${actual[$index]}")"
	done
}

run_test () {
	local name=$1
	shift

	printf 'TEST %s\n' "$name"
	if (trap - EXIT; "$@")
	then
		printf '  PASS\n'
		passed=$((passed + 1))
	else
		printf '  FAIL\n' >&2
		failed=$((failed + 1))
	fi
}

test_bootstrap_backups_are_unique () {
	local fixture="$TEST_TMP_ROOT/bootstrap-repo"
	local test_home="$TEST_TMP_ROOT/bootstrap-home"
	local backup_root backup_dir output second_preserved=false
	local -a backup_dirs

	mkdir -p "$fixture/script" "$fixture/topic" "$test_home"
	cp "$ROOT/script/bootstrap" "$fixture/script/bootstrap"
	cp "$ROOT/script/cache-env.sh" "$fixture/script/cache-env.sh"
	printf 'tracked\n' > "$fixture/topic/foo.symlink"
	printf 'original\n' > "$test_home/.foo"
	printf 'legacy backup\n' > "$test_home/.foo.backup"

	output="$(HOME="$test_home" "$fixture/script/bootstrap" --backup --skip-gitconfig 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}

	[[ -L "$test_home/.foo" ]] || fail_test '~/.foo was not linked'
	[[ "$(readlink "$test_home/.foo")" == "$fixture/topic/foo.symlink" ]] || fail_test '~/.foo points to the wrong source'
	[[ "$(< "$test_home/.foo.backup")" == 'legacy backup' ]] || fail_test 'legacy *.backup file was changed'

	backup_root="$test_home/.local/state/dotfiles/backups"
	mapfile -t backup_dirs < <(find "$backup_root" -mindepth 1 -maxdepth 1 -type d | sort)
	[[ ${#backup_dirs[@]} -eq 1 ]] || fail_test 'expected one backup session'
	backup_dir="${backup_dirs[0]}"
	[[ "$(< "$backup_dir/.foo")" == 'original' ]] || fail_test 'original file was not preserved'
	grep -Fq "$test_home/.foo" "$backup_dir/manifest.tsv" || fail_test 'manifest is missing the original path'
	grep -Fq $'\tfile\t' "$backup_dir/manifest.tsv" || fail_test 'manifest is missing the file type'

	rm "$test_home/.foo"
	printf 'second original\n' > "$test_home/.foo"
	output="$(HOME="$test_home" "$fixture/script/bootstrap" --backup --skip-gitconfig 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}

	mapfile -t backup_dirs < <(find "$backup_root" -mindepth 1 -maxdepth 1 -type d | sort)
	[[ ${#backup_dirs[@]} -eq 2 ]] || fail_test 'repeated bootstrap reused a backup session'
	for backup_dir in "${backup_dirs[@]}"
	do
		if [[ -f "$backup_dir/.foo" && "$(< "$backup_dir/.foo")" == 'second original' ]]
		then
			second_preserved=true
		fi
	done
	[[ "$second_preserved" == true ]] || fail_test 'second conflict was not preserved in a new session'
}

test_bootstrap_preserves_dangling_local_link () {
	local fixture="$TEST_TMP_ROOT/local-repo"
	local test_home="$TEST_TMP_ROOT/local-home"
	local output

	mkdir -p "$fixture/script" "$fixture/local" "$test_home"
	cp "$ROOT/script/bootstrap" "$fixture/script/bootstrap"
	cp "$ROOT/script/cache-env.sh" "$fixture/script/cache-env.sh"
	printf 'template\n' > "$fixture/local/localrc.example"
	ln -s "$test_home/missing-localrc" "$test_home/.localrc"

	output="$(HOME="$test_home" "$fixture/script/bootstrap" --skip --skip-gitconfig 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}

	[[ -L "$test_home/.localrc" ]] || fail_test 'dangling local link was replaced'
	[[ ! -e "$test_home/missing-localrc" ]] || fail_test 'template was written through a dangling link'
	assert_contains "$output" 'exists but is not a regular file'
}

test_cache_env_generates_expected_environment () {
	local test_home="$TEST_TMP_ROOT/cache-env-home"
	local config_home="$test_home/config"
	local workspace="$TEST_TMP_ROOT/cache-env-workspace"
	local env_file="$config_home/dotfiles/cache-env.sh"
	local directory tmp_probe
	local -a expected_directories

	mkdir -p "$test_home"
	HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
		"$ROOT/script/cache-env.sh" "$workspace" >/dev/null 2>&1 || \
		fail_test 'cache environment generation failed'

	[[ -f "$env_file" ]] || fail_test 'cache environment file was not created'
	[[ "$(stat -c '%a' "$env_file")" == 600 ]] || fail_test 'cache environment file permissions are not 0600'
	export XDG_CONFIG_HOME="$config_home"
	# shellcheck source=/dev/null
	source "$env_file" || fail_test 'generated cache environment could not be sourced'

	[[ "${WORKSPACE:-}" == "$workspace" ]] || fail_test 'WORKSPACE has the wrong value'
	[[ "${CACHE_HOME:-}" == "$workspace/cache" ]] || fail_test 'CACHE_HOME has the wrong value'
	[[ "${TMPDIR:-}" == "$CACHE_HOME/tmp" ]] || fail_test 'TMPDIR has the wrong value'
	[[ "${TORCH_HOME:-}" == "$CACHE_HOME/torch" ]] || fail_test 'TORCH_HOME has the wrong value'
	[[ "${TORCH_EXTENSIONS_DIR:-}" == "$CACHE_HOME/torch_extensions" ]] || fail_test 'TORCH_EXTENSIONS_DIR has the wrong value'
	[[ "${TORCHINDUCTOR_CACHE_DIR:-}" == "$CACHE_HOME/torch_inductor" ]] || fail_test 'TORCHINDUCTOR_CACHE_DIR has the wrong value'
	[[ "${HF_HOME:-}" == "$CACHE_HOME/huggingface" ]] || fail_test 'HF_HOME has the wrong value'
	[[ "${HF_HUB_CACHE:-}" == "$HF_HOME/hub" ]] || fail_test 'HF_HUB_CACHE has the wrong value'
	[[ "${HF_DATASETS_CACHE:-}" == "$HF_HOME/datasets" ]] || fail_test 'HF_DATASETS_CACHE has the wrong value'
	[[ "${HF_ASSETS_CACHE:-}" == "$HF_HOME/assets" ]] || fail_test 'HF_ASSETS_CACHE has the wrong value'
	[[ "${HF_XET_CACHE:-}" == "$HF_HOME/xet" ]] || fail_test 'HF_XET_CACHE has the wrong value'
	[[ "${HF_TOKEN_PATH:-}" == "$config_home/huggingface/token" ]] || fail_test 'HF_TOKEN_PATH has the wrong value'
	[[ "${PIP_CACHE_DIR:-}" == "$CACHE_HOME/pip" ]] || fail_test 'PIP_CACHE_DIR has the wrong value'
	[[ "${UV_CACHE_DIR:-}" == "$CACHE_HOME/uv" ]] || fail_test 'UV_CACHE_DIR has the wrong value'
	[[ "${PIXI_CACHE_DIR:-}" == "$CACHE_HOME/pixi" ]] || fail_test 'PIXI_CACHE_DIR has the wrong value'
	[[ "${CUDA_CACHE_PATH:-}" == "$CACHE_HOME/cuda" ]] || fail_test 'CUDA_CACHE_PATH has the wrong value'
	[[ "${TRITON_CACHE_DIR:-}" == "$CACHE_HOME/triton" ]] || fail_test 'TRITON_CACHE_DIR has the wrong value'
	[[ "${GOCACHE:-}" == "$CACHE_HOME/go/build" ]] || fail_test 'GOCACHE has the wrong value'
	[[ "${GOMODCACHE:-}" == "$CACHE_HOME/go/modules" ]] || fail_test 'GOMODCACHE has the wrong value'
	[[ "${XDG_CACHE_HOME:-}" == "$CACHE_HOME/xdg" ]] || fail_test 'XDG_CACHE_HOME has the wrong value'
	[[ "${WANDB_CACHE_DIR:-}" == "$CACHE_HOME/wandb" ]] || fail_test 'WANDB_CACHE_DIR has the wrong value'
	[[ "${WANDB_DATA_DIR:-}" == "$CACHE_HOME/wandb/data" ]] || fail_test 'WANDB_DATA_DIR has the wrong value'
	[[ "${MPLCONFIGDIR:-}" == "$CACHE_HOME/matplotlib" ]] || fail_test 'MPLCONFIGDIR has the wrong value'
	[[ "${npm_config_cache:-}" == "$CACHE_HOME/npm" ]] || fail_test 'npm_config_cache has the wrong value'

	expected_directories=(
		"$WORKSPACE"
		"$CACHE_HOME"
		"$TMPDIR"
		"$TORCH_HOME"
		"$TORCH_EXTENSIONS_DIR"
		"$TORCHINDUCTOR_CACHE_DIR"
		"$HF_HOME"
		"$HF_HUB_CACHE"
		"$HF_DATASETS_CACHE"
		"$HF_ASSETS_CACHE"
		"$HF_XET_CACHE"
		"${HF_TOKEN_PATH%/*}"
		"$PIP_CACHE_DIR"
		"$UV_CACHE_DIR"
		"$PIXI_CACHE_DIR"
		"$CUDA_CACHE_PATH"
		"$TRITON_CACHE_DIR"
		"$GOCACHE"
		"$GOMODCACHE"
		"$XDG_CACHE_HOME"
		"$WANDB_CACHE_DIR"
		"$WANDB_DATA_DIR"
		"$MPLCONFIGDIR"
		"$npm_config_cache"
	)
	for directory in "${expected_directories[@]}"
	do
		[[ -d "$directory" ]] || fail_test "cache directory was not created: $directory"
		[[ -w "$directory" ]] || fail_test "cache directory is not writable: $directory"
	done

	tmp_probe="$(mktemp)" || fail_test 'TMPDIR is not usable by mktemp'
	[[ "$tmp_probe" == "$TMPDIR/"* ]] || fail_test 'mktemp did not use the configured TMPDIR'

	rm -rf -- "$TMPDIR"
	TMPDIR="$TMPDIR" bash -uc 'source "$1"; [[ -z "${TMPDIR:-}" ]]' _ "$env_file" || \
		fail_test 'a removed cache TMPDIR did not fall back to the system default'
}

test_cache_env_quotes_special_workspace_paths () {
	local test_home="$TEST_TMP_ROOT/cache-special-home"
	local config_home="$test_home/config"
	local marker="$TEST_TMP_ROOT/cache-env-injected"
	local workspace="$TEST_TMP_ROOT/cache special 'quoted' \$HOME \$(touch cache-env-injected)"
	local env_file="$config_home/dotfiles/cache-env.sh"

	mkdir -p "$test_home"
	HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
		"$ROOT/script/cache-env.sh" "$workspace" >/dev/null 2>&1 || \
		fail_test 'cache environment generation failed for a special-character path'

	cd "$TEST_TMP_ROOT" || fail_test 'could not enter the test temporary directory'
	# shellcheck source=/dev/null
	source "$env_file" || fail_test 'special-character cache environment could not be sourced'

	[[ "${WORKSPACE:-}" == "$workspace" ]] || fail_test 'special characters were not preserved in WORKSPACE'
	[[ ! -e "$marker" ]] || fail_test 'generated cache environment executed workspace contents'
}

test_cache_env_generation_is_idempotent () {
	local test_home="$TEST_TMP_ROOT/cache-idempotent-home"
	local config_home="$test_home/.config"
	local workspace="$TEST_TMP_ROOT/cache-idempotent-workspace"
	local env_file="$config_home/dotfiles/cache-env.sh"
	local first_content second_content version_count

	mkdir -p "$test_home"
	(
		unset XDG_CONFIG_HOME
		HOME="$test_home" "$ROOT/script/cache-env.sh" "$workspace"
	) >/dev/null 2>&1 || \
		fail_test 'initial cache environment generation failed'
	first_content="$(< "$env_file")"

	(
		unset XDG_CONFIG_HOME
		HOME="$test_home" "$ROOT/script/cache-env.sh" "$workspace"
	) >/dev/null 2>&1 || \
		fail_test 'repeated cache environment generation failed'
	second_content="$(< "$env_file")"

	[[ "$second_content" == "$first_content" ]] || fail_test 'repeated generation changed or duplicated the cache environment'
	[[ "$(grep -c '^export WORKSPACE=' "$env_file")" -eq 1 ]] || fail_test 'WORKSPACE was emitted more than once'
	version_count="$(find "$config_home/dotfiles/cache-env.d" -maxdepth 1 \
		-type f -name 'v*.sh' | wc -l)"
	[[ "$version_count" -eq 1 ]] || \
		fail_test 'repeated generation published a redundant immutable profile'
}

test_cache_env_compatibility_entry_is_independent () {
	local test_home="$TEST_TMP_ROOT/cache-independent-home"
	local config_home="$test_home/config"
	local workspace="$TEST_TMP_ROOT/cache-independent-workspace"
	local config_file="$config_home/dotfiles/cache-env.sh"
	local version_dir="$config_home/dotfiles/cache-env.d"
	local version_file version_content
	local -a versions

	mkdir -p "$test_home"
	HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
		"$ROOT/script/cache-env.sh" "$workspace" >/dev/null 2>&1 || \
		fail_test 'initial cache generation failed for inode isolation'

	mapfile -t versions < <(
		find "$version_dir" -maxdepth 1 -type f -name 'v*.sh' -printf '%f\n' |
			sort
	)
	[[ ${#versions[@]} -eq 1 ]] || fail_test 'initial generation did not publish exactly one version'
	version_file="$version_dir/${versions[0]}"
	[[ -f "$config_file" && ! -L "$config_file" ]] || fail_test 'compatibility entry is not a regular file'
	[[ -f "$version_file" && ! -L "$version_file" ]] || fail_test 'published cache version is not a regular file'
	cmp -s -- "$config_file" "$version_file" || fail_test 'initial compatibility entry differs from the published version'
	[[ ! "$config_file" -ef "$version_file" ]] || \
		fail_test 'compatibility entry aliases the immutable published version inode'

	version_content="$(< "$version_file")"
	printf 'direct compatibility edit\n' > "$config_file"
	[[ "$(< "$version_file")" == "$version_content" ]] || \
		fail_test 'editing the compatibility entry changed the published version'
}

test_cache_env_migrates_legacy_compatibility_entry () {
	local test_home="$TEST_TMP_ROOT/cache-legacy-migration-home"
	local config_home="$test_home/config"
	local config_dir="$config_home/dotfiles"
	local config_file="$config_dir/cache-env.sh"
	local version_dir="$config_dir/cache-env.d"
	local old_workspace="$TEST_TMP_ROOT/cache-legacy-old"
	local new_workspace="$TEST_TMP_ROOT/cache-legacy-new"
	local version_file
	local -a versions

	mkdir -p "$config_dir"
	printf '%s\n' \
		'# Managed by dotfiles script/cache-env.sh.' \
		"export WORKSPACE='$old_workspace'" \
		'export CACHE_HOME="$WORKSPACE/cache"' \
		'# End managed dotfiles cache environment.' \
		> "$config_file"
	chmod 600 "$config_file"

	HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
		"$ROOT/script/cache-env.sh" "$new_workspace" >/dev/null 2>&1 || \
		fail_test 'cache generation failed while migrating a legacy compatibility entry'

	mapfile -t versions < <(
		find "$version_dir" -maxdepth 1 -type f -name 'v*.sh' -printf '%f\n' |
			sort
	)
	[[ ${#versions[@]} -eq 1 ]] || fail_test 'legacy migration did not publish exactly one version'
	version_file="$version_dir/${versions[0]}"
	[[ ! "$config_file" -ef "$version_file" ]] || \
		fail_test 'migrated compatibility entry aliases the published version inode'
	cmp -s -- "$config_file" "$version_file" || \
		fail_test 'legacy compatibility entry was not updated to the current generated content'
	HOME="$test_home" bash -uc \
		'source "$1"; [[ "$WORKSPACE" == "$2" ]]' _ "$config_file" "$new_workspace" || \
		fail_test 'migrated compatibility entry still selects the legacy workspace'
}

test_cache_env_rejects_invalid_inputs_and_unmanaged_targets () {
	local test_home="$TEST_TMP_ROOT/cache-reject-home"
	local relative_config="$test_home/relative-config"
	local unmanaged_config="$test_home/unmanaged-config"
	local unmanaged_file="$unmanaged_config/dotfiles/cache-env.sh"
	local workspace="$TEST_TMP_ROOT/cache-reject-workspace"
	local output status

	mkdir -p "$test_home"
	output="$(HOME="$test_home" XDG_CONFIG_HOME="$relative_config" \
		"$ROOT/script/cache-env.sh" 'relative/workspace' 2>&1)"
	status=$?

	[[ $status -ne 0 ]] || fail_test 'relative workspace path was accepted'
	[[ ! -e "$relative_config/dotfiles/cache-env.sh" ]] || fail_test 'relative path failure left a cache environment file'

	output="$(HOME="$test_home" XDG_CONFIG_HOME="$relative_config" \
		"$ROOT/script/cache-env.sh" '/tmp/..' 2>&1)"
	status=$?

	[[ $status -ne 0 ]] || fail_test 'a normalized root workspace path was accepted'
	[[ ! -e "$relative_config/dotfiles/cache-env.sh" ]] || fail_test 'root path failure left a cache environment file'

	ln -s / "$test_home/root-link"
	output="$(HOME="$test_home" XDG_CONFIG_HOME="$relative_config" \
		"$ROOT/script/cache-env.sh" "$test_home/root-link" 2>&1)"
	status=$?

	[[ $status -ne 0 ]] || fail_test 'a workspace symlink resolving to root was accepted'
	[[ ! -e "$relative_config/dotfiles/cache-env.sh" ]] || fail_test 'root symlink failure left a cache environment file'

	(
		cd "$test_home" || exit 1
		HOME="$test_home" XDG_CONFIG_HOME='relative-config' \
			"$ROOT/script/cache-env.sh" "$workspace"
	) >/dev/null 2>&1
	status=$?

	[[ $status -ne 0 ]] || fail_test 'a relative XDG_CONFIG_HOME was accepted'
	[[ ! -e "$test_home/relative-config/dotfiles/cache-env.sh" ]] || \
		fail_test 'relative XDG_CONFIG_HOME wrote a cache environment file'

	mkdir -p "$(dirname "$unmanaged_file")"
	printf 'unmanaged sentinel\n' > "$unmanaged_file"
	output="$(HOME="$test_home" XDG_CONFIG_HOME="$unmanaged_config" \
		"$ROOT/script/cache-env.sh" "$workspace" 2>&1)"
	status=$?

	[[ $status -ne 0 ]] || fail_test 'an unmanaged cache environment target was overwritten'
	[[ "$(< "$unmanaged_file")" == 'unmanaged sentinel' ]] || fail_test 'unmanaged cache environment contents changed'
}

test_tui_recognizes_long_cache_workspace_metadata () {
	local test_home="$TEST_TMP_ROOT/cache-metadata-home"
	local config_home="$test_home/config"
	local events="$TEST_TMP_ROOT/cache-metadata-events"
	local repeated workspace output

	printf -v repeated '%192s' ''
	repeated=${repeated// /a}
	workspace="$TEST_TMP_ROOT/cache-$repeated"
	mkdir -p "$test_home"
	HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
		"$ROOT/script/cache-env.sh" "$workspace" >/dev/null 2>&1 || \
		fail_test 'could not generate a long cache workspace profile'
	printf '%s\n' quit > "$events"

	output="$(HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
		"$ROOT/script/setup-tui.sh" --events "$events" --plain 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}

	assert_contains "$output" "$workspace/cache"
}

test_cache_env_does_not_overwrite_racing_targets () {
	local test_home="$TEST_TMP_ROOT/cache-race-home"
	local fake_bin="$TEST_TMP_ROOT/cache-race-bin"
	local real_od kind config_home workspace target destination output status

	mkdir -p "$test_home" "$fake_bin"
	real_od="$(command -v od)"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'case "$DOTFILES_TEST_RACE_KIND" in' \
		'  file)' \
		'    printf "racing sentinel\n" > "$DOTFILES_TEST_CACHE_TARGET"' \
		'    ;;' \
		'  link)' \
		'    ln -s -- "$DOTFILES_TEST_RACE_DESTINATION" "$DOTFILES_TEST_CACHE_TARGET"' \
		'    ;;' \
		'esac' \
		'exec "$DOTFILES_TEST_REAL_OD" "$@"' > "$fake_bin/od"
	chmod +x "$fake_bin/od"

	for kind in file link
	do
		config_home="$test_home/$kind-config"
		workspace="$TEST_TMP_ROOT/cache-race-$kind-workspace"
		target="$config_home/dotfiles/cache-env.sh"
		destination="$test_home/$kind-destination"
		printf 'destination sentinel\n' > "$destination"

		output="$(HOME="$test_home" XDG_CONFIG_HOME="$config_home" PATH="$fake_bin:$PATH" \
			DOTFILES_TEST_REAL_OD="$real_od" DOTFILES_TEST_RACE_KIND="$kind" \
			DOTFILES_TEST_CACHE_TARGET="$target" \
			DOTFILES_TEST_RACE_DESTINATION="$destination" \
			"$ROOT/script/cache-env.sh" "$workspace" 2>&1)"
		status=$?

		[[ $status -ne 0 ]] || fail_test "cache generation overwrote a racing $kind target"
		assert_contains "$output" 'appeared while it was being created'
		if [[ "$kind" == "file" ]]
		then
			[[ -f "$target" && ! -L "$target" ]] || fail_test 'racing cache target is no longer a regular file'
			[[ "$(< "$target")" == 'racing sentinel' ]] || fail_test 'racing cache file contents changed'
		else
			[[ -L "$target" ]] || fail_test 'racing cache symlink was replaced'
			[[ "$(readlink "$target")" == "$destination" ]] || fail_test 'racing cache symlink target changed'
			[[ "$(< "$destination")" == 'destination sentinel' ]] || fail_test 'racing cache symlink destination changed'
		fi
		[[ ! -e "$config_home/dotfiles/.cache-env.lock" ]] || fail_test 'cache race left its lock directory behind'
	done
}

test_cache_env_does_not_overwrite_replaced_managed_targets () {
	local test_home="$TEST_TMP_ROOT/cache-managed-race-home"
	local fake_bin="$TEST_TMP_ROOT/cache-managed-race-bin"
	local real_od kind config_home old_workspace new_workspace target destination
	local version_dir output status

	mkdir -p "$test_home" "$fake_bin"
	real_od="$(command -v od)"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'rm -f -- "$DOTFILES_TEST_CACHE_TARGET"' \
		'case "$DOTFILES_TEST_RACE_KIND" in' \
		'  file)' \
		'    printf "replacement sentinel\n" > "$DOTFILES_TEST_CACHE_TARGET"' \
		'    ;;' \
		'  link)' \
		'    ln -s -- "$DOTFILES_TEST_RACE_DESTINATION" "$DOTFILES_TEST_CACHE_TARGET"' \
		'    ;;' \
		'esac' \
		'exec "$DOTFILES_TEST_REAL_OD" "$@"' > "$fake_bin/od"
	chmod +x "$fake_bin/od"

	for kind in file link
	do
		config_home="$test_home/$kind-config"
		old_workspace="$TEST_TMP_ROOT/cache-managed-race-$kind-old"
		new_workspace="$TEST_TMP_ROOT/cache-managed-race-$kind-new"
		target="$config_home/dotfiles/cache-env.sh"
		version_dir="$config_home/dotfiles/cache-env.d"
		destination="$test_home/$kind-replacement-destination"
		printf 'replacement destination\n' > "$destination"

		HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
			"$ROOT/script/cache-env.sh" "$old_workspace" >/dev/null 2>&1 || \
			fail_test "could not create the initial managed cache profile for $kind"
		rm -rf -- "$version_dir"

		output="$(HOME="$test_home" XDG_CONFIG_HOME="$config_home" PATH="$fake_bin:$PATH" \
			DOTFILES_TEST_REAL_OD="$real_od" DOTFILES_TEST_RACE_KIND="$kind" \
			DOTFILES_TEST_CACHE_TARGET="$target" \
			DOTFILES_TEST_RACE_DESTINATION="$destination" \
			"$ROOT/script/cache-env.sh" "$new_workspace" 2>&1)"
		status=$?

		[[ $status -ne 0 ]] || fail_test "cache generation overwrote a replaced managed $kind target"
		assert_contains "$output" 'changed while it was being generated'
		if [[ "$kind" == "file" ]]
		then
			[[ -f "$target" && ! -L "$target" ]] || fail_test 'replacement cache target is no longer a regular file'
			[[ "$(< "$target")" == 'replacement sentinel' ]] || fail_test 'replacement cache file contents changed'
		else
			[[ -L "$target" ]] || fail_test 'replacement cache symlink was overwritten'
			[[ "$(readlink "$target")" == "$destination" ]] || fail_test 'replacement cache symlink target changed'
			[[ "$(< "$destination")" == 'replacement destination' ]] || \
				fail_test 'replacement cache symlink destination changed'
		fi
		[[ -z "$(find "$version_dir" -maxdepth 1 -type f -name '*.sh' -print -quit)" ]] || \
			fail_test 'legacy replacement race published a cache profile'
		[[ -z "$(find "$version_dir" -maxdepth 1 -type f -name '.cache-env.sh.*' -print -quit)" ]] || \
			fail_test "legacy replacement race left a temporary profile: $(find "$version_dir" -maxdepth 1 -type f -name '.cache-env.sh.*' -printf '%f ')"
	done
}

test_cache_env_activates_version_after_compatibility_replacement () {
	local test_home="$TEST_TMP_ROOT/cache-version-race-home"
	local fake_bin="$TEST_TMP_ROOT/cache-version-race-bin"
	local real_od kind config_home old_workspace new_workspace target destination
	local version_dir newest output status
	local -a profiles

	mkdir -p "$test_home" "$fake_bin"
	real_od="$(command -v od)"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'rm -f -- "$DOTFILES_TEST_CACHE_TARGET"' \
		'case "$DOTFILES_TEST_RACE_KIND" in' \
		'  file)' \
		'    printf "replacement sentinel\n" > "$DOTFILES_TEST_CACHE_TARGET"' \
		'    ;;' \
		'  link)' \
		'    ln -s -- "$DOTFILES_TEST_RACE_DESTINATION" "$DOTFILES_TEST_CACHE_TARGET"' \
		'    ;;' \
		'esac' \
		'exec "$DOTFILES_TEST_REAL_OD" "$@"' > "$fake_bin/od"
	chmod +x "$fake_bin/od"

	for kind in file link
	do
		config_home="$test_home/$kind-config"
		old_workspace="$TEST_TMP_ROOT/cache-version-race-$kind-old"
		new_workspace="$TEST_TMP_ROOT/cache-version-race-$kind-new"
		target="$config_home/dotfiles/cache-env.sh"
		version_dir="$config_home/dotfiles/cache-env.d"
		destination="$test_home/$kind-replacement-destination"
		printf 'replacement destination\n' > "$destination"

		HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
			"$ROOT/script/cache-env.sh" "$old_workspace" >/dev/null 2>&1 || \
			fail_test "could not create the initial versioned cache profile for $kind"

		output="$(HOME="$test_home" XDG_CONFIG_HOME="$config_home" PATH="$fake_bin:$PATH" \
			DOTFILES_TEST_REAL_OD="$real_od" DOTFILES_TEST_RACE_KIND="$kind" \
			DOTFILES_TEST_CACHE_TARGET="$target" \
			DOTFILES_TEST_RACE_DESTINATION="$destination" \
			"$ROOT/script/cache-env.sh" "$new_workspace" 2>&1)"
		status=$?

		[[ $status -eq 0 ]] || {
			printf '%s\n' "$output" >&2
			fail_test "cache generation failed after a compatibility $kind replacement"
		}
		if [[ "$kind" == "file" ]]
		then
			[[ -f "$target" && ! -L "$target" ]] || fail_test 'replacement compatibility target is no longer a regular file'
			[[ "$(< "$target")" == 'replacement sentinel' ]] || fail_test 'replacement compatibility file contents changed'
		else
			[[ -L "$target" ]] || fail_test 'replacement compatibility symlink was overwritten'
			[[ "$(readlink "$target")" == "$destination" ]] || fail_test 'replacement compatibility symlink target changed'
			[[ "$(< "$destination")" == 'replacement destination' ]] || \
				fail_test 'replacement compatibility symlink destination changed'
		fi

		mapfile -t profiles < <(
			find "$version_dir" -maxdepth 1 -type f -name '*.sh' -printf '%f\n' |
				sort
		)
		[[ ${#profiles[@]} -eq 2 ]] || fail_test "expected two immutable profiles after the $kind replacement"
		newest="$version_dir/${profiles[-1]}"
		HOME="$test_home" bash -uc \
			'source "$1"; [[ "$WORKSPACE" == "$2" ]]' _ "$newest" "$new_workspace" || \
			fail_test "newest profile did not activate the new workspace after the $kind replacement"
	done
}

test_cache_env_preserves_final_compatibility_replacement () {
	local kind=$1
	local test_home="$TEST_TMP_ROOT/cache-final-replacement-$kind-home"
	local config_home="$test_home/config"
	local fake_bin="$TEST_TMP_ROOT/cache-final-replacement-$kind-bin"
	local old_workspace="$TEST_TMP_ROOT/cache-final-replacement-$kind-old"
	local new_workspace="$TEST_TMP_ROOT/cache-final-replacement-$kind-new"
	local target="$config_home/dotfiles/cache-env.sh"
	local version_dir="$config_home/dotfiles/cache-env.d"
	local destination="$test_home/replacement-destination"
	local trigger="$test_home/fake-mv-triggered"
	local real_mv newest selected_workspace output status
	local -a profiles

	mkdir -p "$test_home" "$fake_bin"
	real_mv="$(command -v mv)"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		': > "$DOTFILES_TEST_MV_TRIGGER"' \
		'rm -f -- "$DOTFILES_TEST_CACHE_TARGET"' \
		'case "$DOTFILES_TEST_RACE_KIND" in' \
		'  file)' \
		'    printf "final replacement sentinel\n" > "$DOTFILES_TEST_CACHE_TARGET"' \
		'    ;;' \
		'  link)' \
		'    ln -s -- "$DOTFILES_TEST_RACE_DESTINATION" "$DOTFILES_TEST_CACHE_TARGET"' \
		'    ;;' \
		'esac' \
		'exec "$DOTFILES_TEST_REAL_MV" "$@"' > "$fake_bin/mv"
	chmod +x "$fake_bin/mv"
	printf 'replacement destination sentinel\n' > "$destination"

	HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
		"$ROOT/script/cache-env.sh" "$old_workspace" >/dev/null 2>&1 || \
		fail_test "could not create the initial cache profile for the final $kind race"

	output="$(HOME="$test_home" XDG_CONFIG_HOME="$config_home" PATH="$fake_bin:$PATH" \
		DOTFILES_TEST_REAL_MV="$real_mv" \
		DOTFILES_TEST_MV_TRIGGER="$trigger" \
		DOTFILES_TEST_RACE_KIND="$kind" \
		DOTFILES_TEST_CACHE_TARGET="$target" \
		DOTFILES_TEST_RACE_DESTINATION="$destination" \
		"$ROOT/script/cache-env.sh" "$new_workspace" 2>&1)"
	status=$?

	[[ $status -eq 0 ]] || {
		printf '%s\n' "$output" >&2
		fail_test "cache generation failed during the final compatibility $kind race"
	}
	[[ -e "$trigger" ]] || fail_test "fake mv did not reach the final compatibility $kind window"

	mapfile -t profiles < <(
		find "$version_dir" -maxdepth 1 -type f -name 'v*.sh' -printf '%f\n' |
			sort
	)
	[[ ${#profiles[@]} -eq 2 ]] || \
		fail_test "final compatibility $kind race did not leave two immutable versions"
	newest="$version_dir/${profiles[-1]}"
	HOME="$test_home" bash -uc \
		'source "$1"; [[ "$WORKSPACE" == "$2" ]]' _ "$newest" "$new_workspace" || \
		fail_test "new immutable version was not complete after the final compatibility $kind race"
	selected_workspace="$(HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
		zsh -f -c 'source "$1"; print -r -- "${WORKSPACE:-missing}"' \
		_ "$ROOT/zsh/zshenv.symlink")" || \
		fail_test "zshenv could not activate the new version after the final compatibility $kind race"
	[[ "$selected_workspace" == "$new_workspace" ]] || \
		fail_test "zshenv did not activate the new version after the final compatibility $kind race"

	if [[ "$kind" == "file" ]]
	then
		[[ -f "$target" && ! -L "$target" ]] || \
			fail_test 'final replacement target is no longer a regular file'
		[[ "$(< "$target")" == 'final replacement sentinel' ]] || \
			fail_test 'final compatibility move overwrote the replacement file'
	else
		[[ -L "$target" ]] || fail_test 'final compatibility move replaced the replacement symlink'
		[[ "$(readlink "$target")" == "$destination" ]] || \
			fail_test 'final compatibility move changed the replacement symlink target'
		[[ "$(< "$destination")" == 'replacement destination sentinel' ]] || \
			fail_test 'final compatibility move changed the replacement symlink destination'
	fi
}

test_cache_env_version_publication_is_atomic () {
	local fixture="$TEST_TMP_ROOT/cache-atomic-repo"
	local test_home="$TEST_TMP_ROOT/cache-atomic-home"
	local config_home="$test_home/config"
	local fake_bin="$TEST_TMP_ROOT/cache-atomic-bin"
	local version_dir="$config_home/dotfiles/cache-env.d"
	local compatibility_file="$config_home/dotfiles/cache-env.sh"
	local old_workspace="$TEST_TMP_ROOT/cache-atomic-old"
	local failed_workspace="$TEST_TMP_ROOT/cache-atomic-failed"
	local interrupted_workspace="$TEST_TMP_ROOT/cache-atomic-interrupted"
	local new_workspace="$TEST_TMP_ROOT/cache-atomic-new"
	local incomplete_sentinel="$test_home/incomplete-profile-sourced"
	local violation="$test_home/precommit-profile-visible"
	local output status mode attempt_workspace zsh_workspace
	local -a profiles

	mkdir -p "$fixture/script" "$fixture/probe" "$test_home" "$fake_bin"
	cp "$ROOT/script/install" "$fixture/script/install"
	cp "$ROOT/script/cache-env.sh" "$fixture/script/cache-env.sh"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'printf "%s\n" "${WORKSPACE:-missing}" > "$HOME/install-workspace.log"' \
		> "$fixture/probe/install.sh"
	chmod +x "$fixture/probe/install.sh"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'shopt -s nullglob' \
		'profiles=("$DOTFILES_TEST_VERSION_DIR"/*.sh)' \
		'if [[ ${#profiles[@]} -ne "$DOTFILES_TEST_EXPECTED_COUNT" ]]; then' \
		'  : > "$DOTFILES_TEST_VISIBILITY_VIOLATION"' \
		'fi' \
		'if [[ "$DOTFILES_TEST_COMMIT_MODE" == "interrupt" ]]; then' \
		'  kill -TERM "$PPID"' \
		'  exit 143' \
		'fi' \
		'exit 1' > "$fake_bin/ln"
	chmod +x "$fake_bin/ln"

	assert_cache_consumers_use_workspace () {
		local expected=$1 context=$2 install_output

		install_output="$(HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
			"$fixture/script/install" --user 2>&1)" || {
			printf '%s\n' "$install_output" >&2
			fail_test "script/install failed while checking $context"
		}
		[[ "$(< "$test_home/install-workspace.log")" == "$expected" ]] || \
			fail_test "script/install selected the wrong cache profile for $context"

		zsh_workspace="$(HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
			zsh -f -c 'source "$1"; print -r -- "${WORKSPACE:-missing}"' \
			_ "$ROOT/zsh/zshenv.symlink")" || \
			fail_test "zshenv failed while checking $context"
		[[ "$zsh_workspace" == "$expected" ]] || \
			fail_test "zshenv selected the wrong cache profile for $context"
	}

	HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
		"$ROOT/script/cache-env.sh" "$old_workspace" >/dev/null 2>&1 || \
		fail_test 'could not create the initial atomic cache profile'
	mapfile -t profiles < <(
		find "$version_dir" -maxdepth 1 -type f -name '*.sh' -printf '%f\n' |
			sort
	)
	[[ ${#profiles[@]} -eq 1 ]] || fail_test 'initial generation did not publish exactly one profile'
	HOME="$test_home" bash -uc \
		'source "$1"; [[ "$WORKSPACE" == "$2" ]]' _ "$compatibility_file" "$old_workspace" || \
		fail_test 'compatibility cache profile does not contain the initial workspace'

	for mode in fail interrupt
	do
		if [[ "$mode" == "fail" ]]
		then
			attempt_workspace=$failed_workspace
		else
			attempt_workspace=$interrupted_workspace
		fi
		output="$(HOME="$test_home" XDG_CONFIG_HOME="$config_home" PATH="$fake_bin:$PATH" \
			DOTFILES_TEST_VERSION_DIR="$version_dir" \
			DOTFILES_TEST_EXPECTED_COUNT=1 \
			DOTFILES_TEST_VISIBILITY_VIOLATION="$violation" \
			DOTFILES_TEST_COMMIT_MODE="$mode" \
			"$ROOT/script/cache-env.sh" "$attempt_workspace" \
			2>&1)"
		status=$?

		[[ $status -ne 0 ]] || fail_test "cache generation unexpectedly survived a precommit $mode"
		if [[ "$mode" == "fail" ]]
		then
			assert_contains "$output" 'could not commit a unique cache environment version'
		else
			[[ $status -eq 130 ]] || fail_test "precommit interruption returned status $status instead of 130"
		fi
		[[ ! -e "$violation" ]] || fail_test "a selectable profile appeared before the $mode"
		mapfile -t profiles < <(
			find "$version_dir" -maxdepth 1 -type f -name '*.sh' -printf '%f\n' |
				sort
		)
		[[ ${#profiles[@]} -eq 1 ]] || fail_test "precommit $mode changed the published profile set"
		[[ -z "$(find "$version_dir" -maxdepth 1 -type f -name '.cache-env.sh.*' -print -quit)" ]] || \
			fail_test "precommit $mode left a temporary cache profile: $(find "$version_dir" -maxdepth 1 -type f -name '.cache-env.sh.*' -printf '%f ')"
		assert_cache_consumers_use_workspace "$old_workspace" "precommit $mode"
	done

	HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
		"$ROOT/script/cache-env.sh" "$new_workspace" >/dev/null 2>&1 || \
		fail_test 'cache generation did not recover after precommit failures'
	assert_cache_consumers_use_workspace "$new_workspace" 'newest complete version'

	printf '%s\n' \
		'# Managed by dotfiles script/cache-env.sh.' \
		'export WORKSPACE="/should/not/be/selected"' \
		'touch "$HOME/incomplete-profile-sourced"' \
		'# Missing the managed end marker.' \
		> "$version_dir/v999999999999999999.sh"
	assert_cache_consumers_use_workspace "$new_workspace" 'a lexically later incomplete version'
	[[ ! -e "$incomplete_sentinel" ]] || fail_test 'a consumer sourced the incomplete cache profile'
}

test_cache_environment_consumers_reject_symlink_targets () {
	local fixture="$TEST_TMP_ROOT/cache-consumer-symlink-repo"
	local test_home="$TEST_TMP_ROOT/cache-consumer-symlink-home"
	local config_home="$test_home/config"
	local payload="$test_home/cache-env-payload"
	local sentinel="$test_home/cache-env-sourced"
	local output

	mkdir -p "$fixture/script" "$config_home/dotfiles" "$test_home"
	cp "$ROOT/script/install" "$fixture/script/install"
	cp "$ROOT/script/cache-env.sh" "$fixture/script/cache-env.sh"
	printf '%s\n' \
		'# Managed by dotfiles script/cache-env.sh.' \
		'touch "$HOME/cache-env-sourced"' > "$payload"
	ln -s "$payload" "$config_home/dotfiles/cache-env.sh"

	output="$(HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
		"$fixture/script/install" --user 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}
	[[ ! -e "$sentinel" ]] || fail_test 'script/install sourced a symlink cache environment'

	HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
		zsh -f -c 'source "$1"' _ "$ROOT/zsh/zshenv.symlink" || \
		fail_test 'zshenv symlink guard could not be evaluated'
	[[ ! -e "$sentinel" ]] || fail_test 'zshenv sourced a symlink cache environment'
}

test_shell_defaults_do_not_enable_proxies () {
	local test_home="$TEST_TMP_ROOT/proxy-defaults-home"
	local config_home="$test_home/config"
	local source_file label proxy_name

	mkdir -p "$test_home"
	for source_file in "$ROOT/zsh/zshenv.symlink" "$ROOT/local/localrc.example"
	do
		if [[ "$source_file" == "$ROOT/zsh/zshenv.symlink" ]]
		then
			label='zshenv'
		else
			label='localrc example'
		fi
		env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
			-u NO_PROXY -u no_proxy \
			HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
			zsh -f -c '
				source "$1"
				(( ${+HTTP_PROXY} == 0 && ${+HTTPS_PROXY} == 0 &&
					${+http_proxy} == 0 && ${+https_proxy} == 0 &&
					${+NO_PROXY} == 0 && ${+no_proxy} == 0 ))
			' _ "$source_file" || \
			fail_test "$label enabled proxy variables by default"
	done

	HTTP_PROXY='http://user-upper-http' \
	HTTPS_PROXY='http://user-upper-https' \
	http_proxy='http://user-lower-http' \
	https_proxy='http://user-lower-https' \
	NO_PROXY='user-upper-no-proxy' \
	no_proxy='user-lower-no-proxy' \
	HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
		zsh -f -c '
			source "$1"
			[[ "$HTTP_PROXY" == "http://user-upper-http" &&
				"$HTTPS_PROXY" == "http://user-upper-https" &&
				"$http_proxy" == "http://user-lower-http" &&
				"$https_proxy" == "http://user-lower-https" &&
				"$NO_PROXY" == "user-upper-no-proxy" &&
				"$no_proxy" == "user-lower-no-proxy" ]]
		' _ "$ROOT/zsh/zshenv.symlink" || \
		fail_test 'zshenv overwrote explicitly configured proxy variables'

	for proxy_name in HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
	do
		grep -Eq "^[[:space:]]*#[[:space:]]+export[[:space:]]+$proxy_name=" \
			"$ROOT/local/localrc.example" || \
			fail_test "localrc example is missing the commented $proxy_name opt-in"
	done
}

test_clipboard_copy_selects_runtime_provider () {
	local fake_bin="$TEST_TMP_ROOT/clipboard-bin"
	local capture="$TEST_TMP_ROOT/clipboard-capture"
	local args="$TEST_TMP_ROOT/clipboard-args"
	local output copy_status

	mkdir -p "$fake_bin"
	printf '%s\n' \
		'#!/usr/bin/env sh' \
		'command cat > "$CLIPBOARD_CAPTURE"' > "$fake_bin/wl-copy"
	printf '%s\n' \
		'#!/usr/bin/env sh' \
		'printf "%s\\n" "$*" > "$CLIPBOARD_ARGS"' \
		'command cat > "$CLIPBOARD_CAPTURE"' > "$fake_bin/xclip"
	chmod +x "$fake_bin/wl-copy" "$fake_bin/xclip"

	printf 'wayland-copy' | PATH="$fake_bin:/usr/bin:/bin" \
		WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 \
		CLIPBOARD_CAPTURE="$capture" CLIPBOARD_ARGS="$args" \
		"$ROOT/bin/clipboard-copy" || fail_test 'Wayland clipboard provider failed'
	[[ "$(< "$capture")" == 'wayland-copy' ]] || \
		fail_test 'Wayland clipboard provider received the wrong content'
	[[ ! -e "$args" ]] || fail_test 'X11 provider overrode the Wayland provider'

	printf 'x11-copy' | env -u WAYLAND_DISPLAY \
		PATH="$fake_bin:/usr/bin:/bin" DISPLAY=:0 \
		CLIPBOARD_CAPTURE="$capture" CLIPBOARD_ARGS="$args" \
		"$ROOT/bin/clipboard-copy" || fail_test 'X11 clipboard provider failed'
	[[ "$(< "$capture")" == 'x11-copy' ]] || \
		fail_test 'X11 clipboard provider received the wrong content'
	[[ "$(< "$args")" == '-selection clipboard -in' ]] || \
		fail_test 'xclip did not receive clipboard-selection arguments'

	output="$(printf 'discarded' | env -u WAYLAND_DISPLAY -u DISPLAY \
		-u WSL_INTEROP -u WSL_DISTRO_NAME PATH="$fake_bin:/usr/bin:/bin" \
		"$ROOT/bin/clipboard-copy" 2>&1)"
	copy_status=$?
	[[ $copy_status -eq 1 ]] || fail_test 'missing clipboard provider did not return status 1'
	[[ -z "$output" ]] || fail_test 'missing clipboard provider emitted unexpected output'
}

test_bootstrap_cache_environment_is_opt_in () {
	local fixture="$TEST_TMP_ROOT/cache-bootstrap-repo"
	local test_home="$TEST_TMP_ROOT/cache-bootstrap-home"
	local config_home="$test_home/config"
	local workspace="$TEST_TMP_ROOT/cache-bootstrap-workspace"
	local env_file="$config_home/dotfiles/cache-env.sh"
	local output

	mkdir -p "$fixture/script" "$test_home"
	cp "$ROOT/script/bootstrap" "$fixture/script/bootstrap"
	cp "$ROOT/script/cache-env.sh" "$fixture/script/cache-env.sh"

	output="$(HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
		"$fixture/script/bootstrap" --skip --skip-gitconfig 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}
	[[ ! -e "$env_file" ]] || fail_test 'bootstrap configured cache variables without an opt-in'

	output="$(HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
		"$fixture/script/bootstrap" --skip --skip-gitconfig --cache-workspace "$workspace" 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}
	[[ -f "$env_file" ]] || fail_test 'bootstrap did not create the opted-in cache environment'
}

test_bootstrap_rejects_invalid_cache_workspace_before_mutation () {
	local fixture="$TEST_TMP_ROOT/cache-bootstrap-invalid-repo"
	local kind workspace test_home config_home output status forbidden

	mkdir -p "$fixture/script" "$fixture/git" "$fixture/local"
	cp "$ROOT/script/bootstrap" "$fixture/script/bootstrap"
	cp "$ROOT/script/cache-env.sh" "$fixture/script/cache-env.sh"
	cp "$ROOT/git/gitconfig.local.symlink.example" \
		"$fixture/git/gitconfig.local.symlink.example"
	cp "$ROOT/local/localrc.example" "$fixture/local/localrc.example"
	cp "$ROOT/local/toolchainsrc.example" "$fixture/local/toolchainsrc.example"

	for kind in relative root
	do
		test_home="$TEST_TMP_ROOT/cache-bootstrap-invalid-$kind-home"
		config_home="$test_home/config"
		mkdir -p "$test_home"
		if [[ "$kind" == "relative" ]]
		then
			workspace='relative/workspace'
		else
			workspace='/'
		fi

		output="$(HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
			XDG_STATE_HOME="$test_home/state" \
			DOTFILES_GIT_AUTHORNAME='Mutation Sentinel' \
			DOTFILES_GIT_AUTHOREMAIL='mutation@example.com' \
			"$fixture/script/bootstrap" --skip --cache-workspace "$workspace" 2>&1)"
		status=$?

		[[ $status -ne 0 ]] || fail_test "bootstrap accepted the $kind cache workspace"
		if [[ "$kind" == "relative" ]]
		then
			assert_contains "$output" 'absolute'
		else
			assert_contains "$output" 'cannot be /'
		fi
		for forbidden in \
			"$test_home/.dotfiles" \
			"$test_home/.gitconfig.local" \
			"$test_home/.localrc" \
			"$test_home/.toolchainsrc" \
			"$config_home/dotfiles"
		do
			[[ ! -e "$forbidden" && ! -L "$forbidden" ]] || \
				fail_test "bootstrap created $forbidden before rejecting the $kind cache workspace"
		done
	done
}

test_install_cache_workspace_generates_and_loads_environment () {
	local fixture="$TEST_TMP_ROOT/cache-install-repo"
	local test_home="$TEST_TMP_ROOT/cache-install-home"
	local config_home="$test_home/config"
	local workspace="$TEST_TMP_ROOT/cache-install-workspace"
	local output

	mkdir -p "$fixture/script" "$fixture/probe" "$test_home"
	cp "$ROOT/script/install" "$fixture/script/install"
	cp "$ROOT/script/cache-env.sh" "$fixture/script/cache-env.sh"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'printf "%s\n" "${CACHE_HOME:-missing}" > "$HOME/cache-home.log"' > "$fixture/probe/install.sh"
	chmod +x "$fixture/probe/install.sh"

	output="$(HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
		"$fixture/script/install" --user --cache-workspace "$workspace" 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}

	[[ -f "$config_home/dotfiles/cache-env.sh" ]] || fail_test 'install did not generate the cache environment'
	[[ "$(< "$test_home/cache-home.log")" == "$workspace/cache" ]] || fail_test 'topic installer did not inherit CACHE_HOME'
}

test_setup_routes_cache_workspace_before_install () {
	local fixture="$TEST_TMP_ROOT/cache-setup-repo"
	local test_home="$TEST_TMP_ROOT/cache-setup-home"
	local config_home="$test_home/config"
	local workspace="$TEST_TMP_ROOT/cache-setup-workspace"
	local output version_count

	mkdir -p "$fixture/bin" "$fixture/script" "$fixture/probe" "$test_home"
	cp "$ROOT/bin/dot" "$fixture/bin/dot"
	cp "$ROOT/script/bootstrap" "$fixture/script/bootstrap"
	cp "$ROOT/script/install" "$fixture/script/install"
	cp "$ROOT/script/cache-env.sh" "$fixture/script/cache-env.sh"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'printf "%s\n" "${CACHE_HOME:-missing}" > "$HOME/setup-cache-home.log"' > "$fixture/probe/install.sh"
	chmod +x "$fixture/probe/install.sh"

	output="$(HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
		"$fixture/bin/dot" setup --cache-workspace "$workspace" --user --skip-gitconfig 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}

	[[ -f "$config_home/dotfiles/cache-env.sh" ]] || fail_test 'setup did not route cache workspace to bootstrap'
	[[ "$(< "$test_home/setup-cache-home.log")" == "$workspace/cache" ]] || \
		fail_test 'install did not load the cache environment generated by setup'

	output="$(HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
		"$fixture/bin/dot" setup --cache-workspace "$workspace" --user --skip-gitconfig 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}
	version_count="$(find "$config_home/dotfiles/cache-env.d" -maxdepth 1 \
		-type f -name 'v*.sh' | wc -l)"
	[[ "$version_count" -eq 1 ]] || \
		fail_test 'repeated setup accumulated duplicate cache profiles'
}

test_setup_invokes_cache_generator_once () {
	local fixture="$TEST_TMP_ROOT/cache-single-call-repo"
	local test_home="$TEST_TMP_ROOT/cache-single-call-home"
	local workspace="$TEST_TMP_ROOT/cache-single-call-workspace"
	local output

	mkdir -p "$fixture/bin" "$fixture/script" "$test_home"
	cp "$ROOT/bin/dot" "$fixture/bin/dot"
	cp "$ROOT/script/bootstrap" "$fixture/script/bootstrap"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'printf "%s\0" "$@" >> "$HOME/cache-env-args"' > \
		"$fixture/script/cache-env.sh"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fixture/script/install"
	chmod +x "$fixture/script/cache-env.sh" "$fixture/script/install"

	output="$(HOME="$test_home" "$fixture/bin/dot" setup --skip --user \
		--skip-gitconfig --cache-workspace "$workspace" 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}
	assert_nul_args "$test_home/cache-env-args" "$workspace"
}

test_setup_tui_accepts_user_in_any_position () {
	local fixture="$TEST_TMP_ROOT/tui-option-repo"
	local test_home="$TEST_TMP_ROOT/tui-option-home"
	local fake_bin="$TEST_TMP_ROOT/tui-option-bin"
	local events="$TEST_TMP_ROOT/tui-option-events"
	local output order

	mkdir -p "$fixture/bin" "$fixture/script" "$fixture/toolchains/lib" \
		"$test_home" "$fake_bin"
	cp "$ROOT/bin/dot" "$fixture/bin/dot"
	cp "$ROOT/script/setup-tui.sh" "$fixture/script/setup-tui.sh"
	cp "$ROOT/toolchains/lib/profiles.sh" "$fixture/toolchains/lib/profiles.sh"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/apt-get"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/sudo"
	chmod +x "$fake_bin/apt-get" "$fake_bin/sudo"
	printf 'existing git config\n' > "$test_home/.gitconfig.local"

	for order in before after
	do
		printf '%s\n' enter enter enter none enter enter > "$events"
		if [[ "$order" == "before" ]]
		then
			output="$(HOME="$test_home" PATH="$fake_bin:$PATH" \
				"$fixture/bin/dot" setup --user --tui --dry-run \
				--events "$events" --plain 2>&1)" || {
				printf '%s\n' "$output" >&2
				return 1
			}
		else
			output="$(HOME="$test_home" PATH="$fake_bin:$PATH" \
				"$fixture/bin/dot" setup --tui --user --dry-run \
				--events "$events" --plain 2>&1)" || {
				printf '%s\n' "$output" >&2
				return 1
			}
		fi
		assert_contains "$output" 'Equivalent command: bin/dot setup --backup --user'
		assert_contains "$output" 'Dry run only; no changes were made.'
	done
}

test_tui_event_flow_executes_exact_setup_arguments () {
	local fixture="$TEST_TMP_ROOT/tui-repo"
	local test_home="$TEST_TMP_ROOT/tui-home"
	local fake_bin="$TEST_TMP_ROOT/tui-bin"
	local events="$TEST_TMP_ROOT/tui-events"
	local cache_workspace="$TEST_TMP_ROOT/tui cache \$(touch tui-injected)"
	local output

	mkdir -p "$fixture/bin" "$fixture/script" "$fixture/toolchains/lib" \
		"$fixture/sample" "$test_home" "$fake_bin"
	cp "$ROOT/script/setup-tui.sh" "$fixture/script/setup-tui.sh"
	cp "$ROOT/toolchains/lib/profiles.sh" "$fixture/toolchains/lib/profiles.sh"
	printf 'managed\n' > "$fixture/sample/sample.symlink"
	printf 'existing\n' > "$test_home/.sample"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'printf "%s\0" "$@" > "$HOME/tui-args"' > "$fixture/bin/dot"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/apt-get"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/sudo"
	chmod +x "$fixture/bin/dot" "$fake_bin/apt-get" "$fake_bin/sudo"
	printf 'existing git config\n' > "$test_home/.gitconfig.local"
	{
		printf '%s\n' enter
		printf '%s\n' down enter
		printf '%s\n' down down enter
		printf '%s\n' down enter
		printf 'text:%s\n' "$cache_workspace"
		printf '%s\n' none enter
		printf '%s\n' enter
	} > "$events"

	output="$(HOME="$test_home" PATH="$fake_bin:$PATH" \
		"$fixture/script/setup-tui.sh" --events "$events" --plain 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}

	assert_nul_args "$test_home/tui-args" \
		setup --skip --user --cache-workspace "$cache_workspace"
	[[ ! -e "$fixture/tui-injected" ]] || fail_test 'TUI cache path executed command substitution'
}

test_tui_does_not_source_local_configuration () {
	local test_home="$TEST_TMP_ROOT/tui-safe-config-home"
	local config_home="$test_home/config"
	local fake_bin="$TEST_TMP_ROOT/tui-safe-config-bin"
	local events="$TEST_TMP_ROOT/tui-safe-config-events"
	local cache_sentinel="$test_home/cache-env-executed"
	local toolchain_sentinel="$test_home/toolchainsrc-executed"
	local output

	mkdir -p "$config_home/dotfiles" "$fake_bin"
	printf '%s\n' \
		'# Managed by dotfiles script/cache-env.sh.' \
		'# Workspace-Hex: 2f746d702f7475692d736166652d776f726b7370616365' \
		'touch "$HOME/cache-env-executed"' > "$config_home/dotfiles/cache-env.sh"
	printf '%s\n' \
		'touch "$HOME/toolchainsrc-executed"' \
		'export DOTFILES_TOOLCHAINS="node"' > "$test_home/.toolchainsrc"
	printf 'existing git config\n' > "$test_home/.gitconfig.local"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/apt-get"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/sudo"
	chmod +x "$fake_bin/apt-get" "$fake_bin/sudo"

	printf '%s\n' quit > "$events"
	output="$(HOME="$test_home" XDG_CONFIG_HOME="$config_home" PATH="$fake_bin:$PATH" \
		"$ROOT/script/setup-tui.sh" --events "$events" --plain 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}
	assert_contains "$output" 'Setup cancelled; no changes were made.'
	[[ ! -e "$cache_sentinel" ]] || fail_test 'TUI sourced the managed cache environment during startup'
	[[ ! -e "$toolchain_sentinel" ]] || fail_test 'TUI sourced ~/.toolchainsrc during startup'

	{
		printf '%s\n' enter
		printf '%s\n' down enter
		printf '%s\n' enter
		printf '%s\n' enter
		printf '%s\n' enter
	} > "$events"

	output="$(HOME="$test_home" XDG_CONFIG_HOME="$config_home" PATH="$fake_bin:$PATH" \
		"$ROOT/script/setup-tui.sh" --events "$events" --plain --dry-run 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}

	assert_contains "$output" 'Dry run only; no changes were made.'
	[[ ! -e "$cache_sentinel" ]] || fail_test 'TUI sourced the managed cache environment during preview'
	[[ ! -e "$toolchain_sentinel" ]] || fail_test 'TUI sourced ~/.toolchainsrc during preview'
}

test_tui_toolchain_defaults_use_last_safe_assignment () {
	local test_home="$TEST_TMP_ROOT/tui-toolchain-defaults-home"
	local config_home="$test_home/config"
	local fake_bin="$TEST_TMP_ROOT/tui-toolchain-defaults-bin"
	local events="$TEST_TMP_ROOT/tui-toolchain-defaults-events"
	local sentinel="$test_home/toolchainsrc-ran"
	local output

	mkdir -p "$test_home" "$fake_bin"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/apt-get"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/sudo"
	chmod +x "$fake_bin/apt-get" "$fake_bin/sudo"
	printf '%s\n' enter enter enter quit > "$events"

	printf '%s\n' \
		"DOTFILES_TOOLCHAINS='go' # earlier value" \
		'export DOTFILES_TOOLCHAINS="node python" # final profiles' > "$test_home/.toolchainsrc"
	output="$(
		unset DOTFILES_TOOLCHAINS
		HOME="$test_home" XDG_CONFIG_HOME="$config_home" PATH="$fake_bin:$PATH" \
			"$ROOT/script/setup-tui.sh" --events "$events" --plain 2>&1
	)" || {
		printf '%s\n' "$output" >&2
		return 1
	}

	assert_contains "$output" '[✓] node'
	assert_contains "$output" '[✓] python'
	[[ "$output" != *'[✓] go'* ]] || fail_test 'TUI used an earlier DOTFILES_TOOLCHAINS assignment'

	output="$(HOME="$test_home" XDG_CONFIG_HOME="$config_home" PATH="$fake_bin:$PATH" \
		DOTFILES_TOOLCHAINS='' \
		"$ROOT/script/setup-tui.sh" --events "$events" --plain 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}
	[[ "$output" != *'[✓]'* ]] || \
		fail_test 'TUI let ~/.toolchainsrc override an explicitly empty environment selection'

	printf '%s\n' \
		'DOTFILES_TOOLCHAINS="node python" # earlier safe value' \
		'export DOTFILES_TOOLCHAINS="$(touch "$HOME/toolchainsrc-ran")" # unsafe final value' > "$test_home/.toolchainsrc"
	output="$(
		unset DOTFILES_TOOLCHAINS
		HOME="$test_home" XDG_CONFIG_HOME="$config_home" PATH="$fake_bin:$PATH" \
			"$ROOT/script/setup-tui.sh" --events "$events" --plain 2>&1
	)" || {
		printf '%s\n' "$output" >&2
		return 1
	}

	assert_contains "$output" 'Could not safely read DOTFILES_TOOLCHAINS; no profiles were preselected.'
	[[ "$output" != *'[✓]'* ]] || fail_test 'TUI preselected a profile after an unsafe final assignment'
	[[ ! -e "$sentinel" ]] || fail_test 'TUI executed the unsafe toolchain assignment'
}

test_tui_warns_on_ambiguous_toolchain_directives () {
	local test_home="$TEST_TMP_ROOT/tui-toolchain-warning-home"
	local config_home="$test_home/config"
	local fake_bin="$TEST_TMP_ROOT/tui-toolchain-warning-bin"
	local events="$TEST_TMP_ROOT/tui-toolchain-warning-events"
	local case_name output

	mkdir -p "$test_home" "$fake_bin"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/apt-get"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/sudo"
	chmod +x "$fake_bin/apt-get" "$fake_bin/sudo"
	printf '%s\n' enter enter enter quit > "$events"

	for case_name in adjacent-comment unset append
	do
		case "$case_name" in
			adjacent-comment)
				printf '%s\n' 'export DOTFILES_TOOLCHAINS="node"#x' > "$test_home/.toolchainsrc"
				;;
			unset)
				printf '%s\n' \
					'DOTFILES_TOOLCHAINS="node"' \
					'unset DOTFILES_TOOLCHAINS' > "$test_home/.toolchainsrc"
				;;
			append)
				printf '%s\n' \
					'DOTFILES_TOOLCHAINS="python"' \
					'DOTFILES_TOOLCHAINS+=node' > "$test_home/.toolchainsrc"
				;;
		esac

		output="$(
			unset DOTFILES_TOOLCHAINS
			HOME="$test_home" XDG_CONFIG_HOME="$config_home" PATH="$fake_bin:$PATH" \
				"$ROOT/script/setup-tui.sh" --events "$events" --plain 2>&1
		)" || {
			printf '%s\n' "$output" >&2
			return 1
		}

		assert_contains "$output" 'Could not safely read DOTFILES_TOOLCHAINS; no profiles were preselected.'
		[[ "$output" != *'[✓]'* ]] || fail_test "$case_name directive caused a toolchain preselection"
	done
}

test_tui_overwrite_uses_confirmed_force_paths () {
	local fixture="$TEST_TMP_ROOT/tui-overwrite-repo"
	local test_home="$TEST_TMP_ROOT/tui-overwrite-home"
	local fake_bin="$TEST_TMP_ROOT/tui-overwrite-bin"
	local events="$TEST_TMP_ROOT/tui-overwrite-events"
	local first_target="$test_home/.first"
	local second_target="$test_home/.second"
	local output argument
	local -a actual=()

	mkdir -p "$fixture/bin" "$fixture/script" "$fixture/toolchains/lib" \
		"$fixture/first" "$fixture/second" "$test_home" "$fake_bin"
	cp "$ROOT/script/setup-tui.sh" "$fixture/script/setup-tui.sh"
	cp "$ROOT/toolchains/lib/profiles.sh" "$fixture/toolchains/lib/profiles.sh"
	printf 'managed first\n' > "$fixture/first/first.symlink"
	printf 'managed second\n' > "$fixture/second/second.symlink"
	printf 'original first\n' > "$first_target"
	printf 'original second\n' > "$second_target"
	printf 'existing git config\n' > "$test_home/.gitconfig.local"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'printf "%s\0" "$@" > "$HOME/tui-overwrite-args"' > "$fixture/bin/dot"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/apt-get"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/sudo"
	chmod +x "$fixture/bin/dot" "$fake_bin/apt-get" "$fake_bin/sudo"
	{
		printf '%s\n' enter
		printf '%s\n' enter
		printf '%s\n' down down down enter
		printf '%s\n' enter
		printf '%s\n' none enter
		printf '%s\n' enter
		printf '%s\n' 'text:OVERWRITE'
	} > "$events"

	output="$(HOME="$test_home" PATH="$fake_bin:$PATH" \
		"$fixture/script/setup-tui.sh" --events "$events" --plain 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}

	mapfile -d '' -t actual < "$test_home/tui-overwrite-args"
	[[ ${#actual[@]} -eq 5 ]] || fail_test "expected 5 overwrite arguments, got ${#actual[@]}"
	[[ "${actual[0]}" == setup ]] || fail_test 'TUI overwrite did not invoke setup'
	[[ "${actual[1]}" == --force-path && "${actual[3]}" == --force-path ]] || \
		fail_test 'TUI overwrite did not emit one --force-path per conflict'
	if [[ "${actual[2]}" == "$first_target" ]]
	then
		[[ "${actual[4]}" == "$second_target" ]] || fail_test 'second confirmed force path is missing'
	else
		[[ "${actual[2]}" == "$second_target" && "${actual[4]}" == "$first_target" ]] || \
			fail_test 'confirmed force paths do not match the detected conflicts'
	fi
	for argument in "${actual[@]}"
	do
		[[ "$argument" != "--force" ]] || fail_test 'TUI overwrite emitted the global --force option'
	done
}

test_tui_sudo_failure_returns_to_user_only_scope () {
	local fixture="$TEST_TMP_ROOT/tui-sudo-repo"
	local test_home="$TEST_TMP_ROOT/tui-sudo-home"
	local fake_bin="$TEST_TMP_ROOT/tui-sudo-bin"
	local events="$TEST_TMP_ROOT/tui-sudo-events"
	local output

	mkdir -p "$fixture/bin" "$fixture/script" "$fixture/toolchains/lib" "$test_home" "$fake_bin"
	cp "$ROOT/script/setup-tui.sh" "$fixture/script/setup-tui.sh"
	cp "$ROOT/toolchains/lib/profiles.sh" "$fixture/toolchains/lib/profiles.sh"
	printf 'existing git config\n' > "$test_home/.gitconfig.local"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'printf "%s\0" "$@" > "$HOME/tui-sudo-args"' > "$fixture/bin/dot"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/apt-get"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'count=0' \
		'[[ ! -f "$HOME/sudo-count" ]] || IFS= read -r count < "$HOME/sudo-count"' \
		'count=$((count + 1))' \
		'printf "%d\n" "$count" > "$HOME/sudo-count"' \
		'exit 1' > "$fake_bin/sudo"
	chmod +x "$fixture/bin/dot" "$fake_bin/apt-get" "$fake_bin/sudo"
	{
		printf '%s\n' enter
		printf '%s\n' enter
		printf '%s\n' enter
		printf '%s\n' none enter
		printf '%s\n' enter
		printf '%s\n' enter
		printf '%s\n' enter
		printf '%s\n' enter
		printf '%s\n' enter
	} > "$events"

	output="$(HOME="$test_home" PATH="$fake_bin:$PATH" \
		"$fixture/script/setup-tui.sh" --events "$events" --plain 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}

	assert_contains "$output" 'Sudo authentication failed; returning to installation scope.'
	assert_contains "$output" 'Sudo failed. User-only is selected; retry system packages if appropriate.'
	assert_nul_args "$test_home/tui-sudo-args" setup --backup --user
	[[ "$(< "$test_home/sudo-count")" == 1 ]] || fail_test 'TUI retried sudo after switching to user-only'
}

test_init_without_tty_fails_clearly () {
	local test_home="$TEST_TMP_ROOT/tui-no-tty-home"
	local output status

	mkdir -p "$test_home"
	output="$(HOME="$test_home" "$ROOT/bin/dot" init </dev/null 2>&1)"
	status=$?

	[[ $status -ne 0 ]] || fail_test 'init succeeded without an interactive terminal'
	assert_contains "$output" 'an interactive terminal is required'
	assert_contains "$output" 'bin/dot setup --help'
}

test_bootstrap_rejects_multiple_conflict_modes () {
	local fixture="$TEST_TMP_ROOT/conflict-mode-repo"
	local test_home="$TEST_TMP_ROOT/conflict-mode-home"
	local output status index
	local -a first_modes=(--backup --backup --force)
	local -a second_modes=(--force --skip --skip)

	mkdir -p "$fixture/script" "$test_home"
	cp "$ROOT/script/bootstrap" "$fixture/script/bootstrap"
	cp "$ROOT/script/cache-env.sh" "$fixture/script/cache-env.sh"

	for index in "${!first_modes[@]}"
	do
		output="$(HOME="$test_home" "$fixture/script/bootstrap" \
			"${first_modes[$index]}" "${second_modes[$index]}" --skip-gitconfig 2>&1)"
		status=$?

		[[ $status -ne 0 ]] || \
			fail_test "${first_modes[$index]} and ${second_modes[$index]} were accepted together"
		assert_contains "$output" 'mutually exclusive'
	done
	[[ ! -e "$test_home/.dotfiles" ]] || fail_test 'conflicting bootstrap modes changed the test home'
}

test_bootstrap_rejects_relative_state_home_before_mutation () {
	local fixture="$TEST_TMP_ROOT/relative-state-repo"
	local test_home="$TEST_TMP_ROOT/relative-state-home"
	local config_home="$test_home/config"
	local conflict="$test_home/.foo"
	local original_inode output status forbidden

	mkdir -p "$fixture/script" "$fixture/topic" "$fixture/git" "$fixture/local" \
		"$test_home"
	cp "$ROOT/script/bootstrap" "$fixture/script/bootstrap"
	cp "$ROOT/script/cache-env.sh" "$fixture/script/cache-env.sh"
	cp "$ROOT/git/gitconfig.local.symlink.example" \
		"$fixture/git/gitconfig.local.symlink.example"
	cp "$ROOT/local/localrc.example" "$fixture/local/localrc.example"
	cp "$ROOT/local/toolchainsrc.example" "$fixture/local/toolchainsrc.example"
	printf 'managed foo\n' > "$fixture/topic/foo.symlink"
	printf 'original conflict\n' > "$conflict"
	original_inode="$(stat -c '%d:%i' "$conflict")"

	output="$(HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
		XDG_STATE_HOME='relative/path' \
		DOTFILES_GIT_AUTHORNAME='State Validation' \
		DOTFILES_GIT_AUTHOREMAIL='state-validation@example.com' \
		"$fixture/script/bootstrap" --backup 2>&1)"
	status=$?

	[[ $status -ne 0 ]] || fail_test 'bootstrap accepted a relative XDG_STATE_HOME for --backup'
	assert_contains "$output" 'XDG_STATE_HOME'
	assert_contains "$output" 'absolute'
	[[ -f "$conflict" && ! -L "$conflict" ]] || \
		fail_test 'relative XDG_STATE_HOME caused the conflict file to be moved or replaced'
	[[ "$(< "$conflict")" == 'original conflict' ]] || \
		fail_test 'relative XDG_STATE_HOME changed the conflict file contents'
	[[ "$(stat -c '%d:%i' "$conflict")" == "$original_inode" ]] || \
		fail_test 'relative XDG_STATE_HOME replaced the conflict file inode'
	for forbidden in \
		"$test_home/.dotfiles" \
		"$test_home/.gitconfig.local" \
		"$test_home/.localrc" \
		"$test_home/.toolchainsrc" \
		"$config_home" \
		"$test_home/relative/path" \
		"$fixture/relative/path"
	do
		[[ ! -e "$forbidden" && ! -L "$forbidden" ]] || \
			fail_test "bootstrap created $forbidden before rejecting relative XDG_STATE_HOME"
	done

	output="$(HOME="$test_home" XDG_CONFIG_HOME="$config_home" \
		XDG_STATE_HOME='relative/path' \
		"$fixture/script/bootstrap" --skip --skip-gitconfig 2>&1)"
	status=$?

	[[ $status -eq 0 ]] || {
		printf '%s\n' "$output" >&2
		fail_test 'relative XDG_STATE_HOME blocked the non-backup update-style bootstrap path'
	}
	[[ "$output" != *'XDG_STATE_HOME must be an absolute path'* ]] || \
		fail_test 'non-backup bootstrap unnecessarily validated relative XDG_STATE_HOME'
	[[ -f "$conflict" && ! -L "$conflict" ]] || \
		fail_test 'non-backup bootstrap moved or replaced the skipped conflict'
	[[ "$(< "$conflict")" == 'original conflict' ]] || \
		fail_test 'non-backup bootstrap changed the skipped conflict contents'
	[[ "$(stat -c '%d:%i' "$conflict")" == "$original_inode" ]] || \
		fail_test 'non-backup bootstrap replaced the skipped conflict inode'
	for forbidden in "$test_home/relative/path" "$fixture/relative/path"
	do
		[[ ! -e "$forbidden" && ! -L "$forbidden" ]] || \
			fail_test "non-backup bootstrap created an unused relative state path: $forbidden"
	done
}

test_bootstrap_does_not_follow_racing_dotfiles_alias () {
	local fixture="$TEST_TMP_ROOT/dotfiles-alias-race-repo"
	local test_home="$TEST_TMP_ROOT/dotfiles-alias-race-home"
	local fake_bin="$TEST_TMP_ROOT/dotfiles-alias-race-bin"
	local race_dir="$test_home/race-dir"
	local target="$test_home/.dotfiles"
	local trigger="$test_home/fake-ln-triggered"
	local real_ln output status

	mkdir -p "$fixture/script" "$test_home" "$fake_bin" "$race_dir"
	cp "$ROOT/script/bootstrap" "$fixture/script/bootstrap"
	cp "$ROOT/script/cache-env.sh" "$fixture/script/cache-env.sh"
	printf 'race destination sentinel\n' > "$race_dir/sentinel"

	real_ln="$(command -v ln)"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'last_argument=${!#}' \
		'if [[ "$last_argument" == "$HOME/.dotfiles" && ! -e "$DOTFILES_TEST_LN_TRIGGER" ]]' \
		'then' \
		'  : > "$DOTFILES_TEST_LN_TRIGGER"' \
		'  "$DOTFILES_TEST_REAL_LN" -s -- "$DOTFILES_TEST_RACE_DIR" "$HOME/.dotfiles"' \
		'fi' \
		'exec "$DOTFILES_TEST_REAL_LN" "$@"' > "$fake_bin/ln"
	chmod +x "$fake_bin/ln"

	output="$(HOME="$test_home" PATH="$fake_bin:$PATH" \
		DOTFILES_TEST_REAL_LN="$real_ln" \
		DOTFILES_TEST_LN_TRIGGER="$trigger" \
		DOTFILES_TEST_RACE_DIR="$race_dir" \
		"$fixture/script/bootstrap" --skip --skip-gitconfig 2>&1)"
	status=$?

	[[ -e "$trigger" ]] || fail_test 'fake ln did not reach the final ~/.dotfiles link window'
	[[ -L "$target" ]] || fail_test 'bootstrap replaced the racing ~/.dotfiles symlink'
	[[ "$(readlink "$target")" == "$race_dir" ]] || \
		fail_test 'bootstrap changed the racing ~/.dotfiles symlink destination'
	[[ "$(< "$race_dir/sentinel")" == 'race destination sentinel' ]] || \
		fail_test 'bootstrap changed the race directory sentinel'
	if find "$race_dir" -mindepth 1 -maxdepth 1 -type l -print -quit | grep -q .
	then
		fail_test 'bootstrap created a repository link inside the racing symlink destination'
	fi
	if [[ $status -eq 0 && "$output" != *'leaving it unchanged'* &&
		"$output" != *'skipped'* ]]
	then
		fail_test 'bootstrap silently succeeded after losing the ~/.dotfiles link race'
	fi
}

test_bootstrap_force_path_only_overwrites_confirmed_target () {
	local fixture="$TEST_TMP_ROOT/force-path-repo"
	local test_home="$TEST_TMP_ROOT/force-path-home"
	local confirmed_target="$test_home/.confirmed"
	local unconfirmed_target="$test_home/.config/unconfirmed"
	local output

	mkdir -p "$fixture/script" "$fixture/topic" "$fixture/xdg/config/unconfirmed" \
		"$test_home/.config/unconfirmed"
	cp "$ROOT/script/bootstrap" "$fixture/script/bootstrap"
	cp "$ROOT/script/cache-env.sh" "$fixture/script/cache-env.sh"
	printf 'managed confirmed\n' > "$fixture/topic/confirmed.symlink"
	printf 'managed unconfirmed\n' > "$fixture/xdg/config/unconfirmed/config"
	printf 'original confirmed\n' > "$confirmed_target"
	printf 'original unconfirmed\n' > "$unconfirmed_target/keep"

	output="$(HOME="$test_home" "$fixture/script/bootstrap" \
		--force-path "$confirmed_target" --skip-gitconfig </dev/null 2>&1)"

	[[ -L "$confirmed_target" ]] || fail_test 'confirmed force path was not replaced with a managed link'
	[[ "$(readlink "$confirmed_target")" == "$fixture/topic/confirmed.symlink" ]] || \
		fail_test 'confirmed force path points to the wrong managed source'
	[[ -d "$unconfirmed_target" && ! -L "$unconfirmed_target" ]] || \
		fail_test 'unconfirmed managed target was replaced'
	[[ "$(< "$unconfirmed_target/keep")" == 'original unconfirmed' ]] || \
		fail_test 'unconfirmed managed target contents were changed'
	assert_contains "$output" "File already exists: $unconfirmed_target"
}

test_bootstrap_preserves_git_identity_characters () {
	local fixture="$TEST_TMP_ROOT/git-identity-repo"
	local test_home="$TEST_TMP_ROOT/git-identity-home"
	local author_name="Alice & Bob \"Ops\" O'Neil"
	local author_email='alice+bob@example.com'
	local output actual_name actual_email

	mkdir -p "$fixture/script" "$fixture/git" "$test_home"
	cp "$ROOT/script/bootstrap" "$fixture/script/bootstrap"
	cp "$ROOT/script/cache-env.sh" "$fixture/script/cache-env.sh"
	cp "$ROOT/git/gitconfig.local.symlink.example" "$fixture/git/gitconfig.local.symlink.example"

	output="$(HOME="$test_home" DOTFILES_GIT_AUTHORNAME="$author_name" \
		DOTFILES_GIT_AUTHOREMAIL="$author_email" \
		"$fixture/script/bootstrap" --skip 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}

	actual_name="$(git config --file "$test_home/.gitconfig.local" --get user.name)" || \
		fail_test 'generated Git config is missing user.name'
	actual_email="$(git config --file "$test_home/.gitconfig.local" --get user.email)" || \
		fail_test 'generated Git config is missing user.email'
	[[ "$actual_name" == "$author_name" ]] || fail_test 'Git author name was not preserved exactly'
	[[ "$actual_email" == "$author_email" ]] || fail_test 'Git author email was not preserved exactly'
}

test_bootstrap_does_not_overwrite_racing_gitconfig () {
	local fixture="$TEST_TMP_ROOT/git-race-repo"
	local test_home="$TEST_TMP_ROOT/git-race-home"
	local fake_bin="$TEST_TMP_ROOT/git-race-bin"
	local real_git output

	mkdir -p "$fixture/script" "$fixture/git" "$test_home" "$fake_bin"
	cp "$ROOT/script/bootstrap" "$fixture/script/bootstrap"
	cp "$ROOT/script/cache-env.sh" "$fixture/script/cache-env.sh"
	cp "$ROOT/git/gitconfig.local.symlink.example" "$fixture/git/gitconfig.local.symlink.example"

	real_git="$(command -v git)"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'target="$HOME/.gitconfig.local"' \
		'if [[ ! -e "$target" && ! -L "$target" ]]' \
		'then' \
		'  printf "racing sentinel\n" > "$target"' \
		'fi' \
		'exec "$DOTFILES_TEST_REAL_GIT" "$@"' > "$fake_bin/git"
	chmod +x "$fake_bin/git"

	output="$(HOME="$test_home" PATH="$fake_bin:$PATH" DOTFILES_TEST_REAL_GIT="$real_git" \
		DOTFILES_GIT_AUTHORNAME='Generated Name' \
		DOTFILES_GIT_AUTHOREMAIL='generated@example.com' \
		"$fixture/script/bootstrap" --skip 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}

	[[ "$(< "$test_home/.gitconfig.local")" == 'racing sentinel' ]] || \
		fail_test 'a concurrently created Git config was overwritten'
	assert_contains "$output" '~/.gitconfig.local appeared while it was being created; leaving it unchanged'
	if find "$test_home" -maxdepth 1 -name '.gitconfig.local.*' -print -quit | grep -q .
	then
		fail_test 'the losing Git config temporary file was not removed'
	fi
}

test_setup_forwards_skip_to_bootstrap () {
	local fixture="$TEST_TMP_ROOT/setup-skip-repo"
	local test_home="$TEST_TMP_ROOT/setup-skip-home"
	local output

	mkdir -p "$fixture/bin" "$fixture/script" "$test_home"
	cp "$ROOT/bin/dot" "$fixture/bin/dot"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'printf "%s\0" "$@" > "$HOME/bootstrap-args"' > "$fixture/script/bootstrap"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'printf "%s\0" "$@" > "$HOME/install-args"' > "$fixture/script/install"
	chmod +x "$fixture/script/bootstrap" "$fixture/script/install"

	output="$(HOME="$test_home" "$fixture/bin/dot" setup --skip --user 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}

	assert_nul_args "$test_home/bootstrap-args" --skip
	assert_nul_args "$test_home/install-args" --user
}

test_setup_routes_flags_after_toolchain_profiles () {
	local fixture="$TEST_TMP_ROOT/setup-toolchain-options-repo"
	local test_home="$TEST_TMP_ROOT/setup-toolchain-options-home"
	local output status

	mkdir -p "$fixture/bin" "$fixture/script" "$test_home"
	cp "$ROOT/bin/dot" "$fixture/bin/dot"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'printf "%s\0" "$@" > "$HOME/bootstrap-args"' > "$fixture/script/bootstrap"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'printf "%s\0" "$@" > "$HOME/install-args"' > "$fixture/script/install"
	chmod +x "$fixture/script/bootstrap" "$fixture/script/install"

	output="$(HOME="$test_home" "$fixture/bin/dot" setup \
		--toolchains node -b --user 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}
	assert_nul_args "$test_home/bootstrap-args" -b
	assert_nul_args "$test_home/install-args" --toolchains node --user

	rm -f -- "$test_home/bootstrap-args" "$test_home/install-args"
	output="$(HOME="$test_home" "$fixture/bin/dot" setup \
		--toolchains node --unknown-setup-flag 2>&1)"
	status=$?
	[[ $status -ne 0 ]] || fail_test 'unknown setup flag was accepted as a toolchain profile'
	assert_contains "$output" 'Unknown setup option: --unknown-setup-flag'
	[[ ! -e "$test_home/bootstrap-args" && ! -e "$test_home/install-args" ]] || \
		fail_test 'setup mutated files before rejecting an unknown flag'
}

test_user_mode_skips_manager_and_reports_topics () {
	local fixture="$TEST_TMP_ROOT/user-repo"
	local test_home="$TEST_TMP_ROOT/user-home"
	local isolated_bin="$TEST_TMP_ROOT/user-bin"
	local command_name output status

	mkdir -p "$fixture/script" "$fixture/alpha" "$fixture/beta" "$test_home" "$isolated_bin"
	cp "$ROOT/script/install" "$fixture/script/install"
	cp "$ROOT/script/cache-env.sh" "$fixture/script/cache-env.sh"
	for command_name in bash dirname find sort uname
	do
		ln -s "$(command -v "$command_name")" "$isolated_bin/$command_name"
	done

	printf '%s\n' '#!/usr/bin/env bash' 'printf "alpha\\n" >> "$HOME/topic.log"' 'exit 1' > "$fixture/alpha/install.sh"
	printf '%s\n' '#!/usr/bin/env bash' 'printf "beta\\n" >> "$HOME/topic.log"' > "$fixture/beta/install.sh"
	chmod +x "$fixture/alpha/install.sh" "$fixture/beta/install.sh"

	output="$(HOME="$test_home" PATH="$isolated_bin" "$fixture/script/install" --user 2>&1)"
	status=$?

	[[ $status -eq 1 ]] || fail_test "expected status 1, got $status"
	[[ "$(< "$test_home/topic.log")" == $'alpha\nbeta' ]] || fail_test 'remaining topics did not continue after a failure'
	assert_contains "$output" 'packages: skipped (user-only mode)'
	assert_contains "$output" 'topics:   1 succeeded, 1 failed'
	assert_contains "$output" 'topic: alpha/install.sh'
}

test_package_failure_reaches_exit_status () {
	local fixture="$TEST_TMP_ROOT/package-repo"
	local test_home="$TEST_TMP_ROOT/package-home"
	local fake_bin="$TEST_TMP_ROOT/package-bin"
	local command_name output status

	mkdir -p "$fixture/script" "$fixture/packages" "$test_home" "$fake_bin"
	cp "$ROOT/script/install" "$fixture/script/install"
	cp "$ROOT/script/cache-env.sh" "$fixture/script/cache-env.sh"
	printf 'good\nbad\n' > "$fixture/packages/common.txt"
	for command_name in awk bash dirname find grep sort uname
	do
		ln -s "$(command -v "$command_name")" "$fake_bin/$command_name"
	done

	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'if [[ "${1:-}" == update ]]; then exit 0; fi' \
		'for argument in "$@"; do [[ "$argument" == bad ]] && exit 1; done' \
		'exit 0' > "$fake_bin/apt-get"
	printf '%s\n' '#!/usr/bin/env bash' 'exec "$@"' > "$fake_bin/sudo"
	chmod +x "$fake_bin/apt-get" "$fake_bin/sudo"

	output="$(HOME="$test_home" PATH="$fake_bin" "$fixture/script/install" 2>&1)"
	status=$?

	[[ $status -eq 1 ]] || fail_test "expected status 1, got $status"
	assert_contains "$output" 'packages: 1 succeeded, 1 failed (apt)'
	assert_contains "$output" 'package: bad'
}

test_base_packages_include_interactive_tools () {
	local output package

	output="$("$ROOT/script/install" --print 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}

	for package in btop direnv eza git-delta hyperfine vim
	do
		grep -Fxq "$package" <<< "$output" || \
			fail_test "base package profile is missing $package"
	done
	if grep -Fxq 'yq' <<< "$output"
	then
		fail_test 'ambiguous distro yq package remains in the system package profile'
	fi
}

test_vim_config_loads_standalone () {
	local test_home="$TEST_TMP_ROOT/vim-home"
	local output status

	command -v vim >/dev/null 2>&1 || return 0

	mkdir -p "$test_home"
	output="$(HOME="$test_home" vim -Nu "$ROOT/vim/vimrc.symlink" -i NONE -n -es \
		+'if !&number || &relativenumber || &tabstop != 4 || !&expandtab | cquit 20 | endif' \
		+qall 2>&1)"
	status=$?

	[[ $status -eq 0 ]] || {
		printf '%s\n' "$output" >&2
		fail_test "Vim config failed to load with status $status"
	}
	[[ ! -e "$test_home/.vim" ]] || \
		fail_test 'Vim config created a plugin or runtime directory in a clean home'
}

test_terminal_editor_defaults_to_vim () {
	local fake_bin="$TEST_TMP_ROOT/editor-bin"
	local fallback_bin="$TEST_TMP_ROOT/vi-fallback-bin"
	local output git_editor
	local zsh_bin

	mkdir -p "$fake_bin" "$fallback_bin"
	zsh_bin="$(command -v zsh)" || fail_test 'zsh is required for editor default tests'
	printf '%s\n' '#!/bin/sh' 'exit 0' > "$fake_bin/vim"
	printf '%s\n' '#!/bin/sh' 'exit 0' > "$fake_bin/code"
	chmod +x "$fake_bin/vim" "$fake_bin/code"

	output="$(PATH="$fake_bin:/usr/bin:/bin" "$zsh_bin" -f -c \
		'source "$1"; print -r -- "$EDITOR:$VISUAL:$GIT_EDITOR"' \
		_ "$ROOT/shell/core/env.zsh")" || {
		printf '%s\n' "$output" >&2
		return 1
	}
	[[ "$output" == 'vim:vim:vim' ]] || \
		fail_test "terminal editor defaults were not Vim: $output"

	git_editor="$(git config --file "$ROOT/git/gitconfig.symlink" --get core.editor)" || \
		fail_test 'tracked Git config has no core.editor'
	[[ "$git_editor" == 'vim' ]] || fail_test "Git editor is not Vim: $git_editor"

	printf '%s\n' '#!/bin/sh' 'exit 0' > "$fallback_bin/vi"
	chmod +x "$fallback_bin/vi"
	output="$(PATH="$fallback_bin" "$zsh_bin" -f -c \
		'source "$1"; print -r -- "$EDITOR:$VISUAL:$GIT_EDITOR"' \
		_ "$ROOT/shell/core/env.zsh")" || {
		printf '%s\n' "$output" >&2
		return 1
	}
	[[ "$output" == 'vi:vi:vi' ]] || \
		fail_test "system vi fallback was not selected: $output"
}

test_toolchains_have_no_implicit_default () {
	local defaults profiles

	defaults="$(
		unset DOTFILES_TOOLCHAINS
		source "$ROOT/toolchains/lib/profiles.sh"
		dotfiles_toolchain_resolve_profiles
	)" || {
		printf '%s\n' "$defaults" >&2
		return 1
	}
	[[ -z "$defaults" ]] || fail_test "unexpected default toolchain profiles: $defaults"

	profiles="$(source "$ROOT/toolchains/lib/profiles.sh"; dotfiles_toolchain_all_profiles)"
	[[ "$profiles" == $'node\njava\nrust\ngo\npython\nbun' ]] || \
		fail_test "unexpected toolchain profile list: $profiles"
}

test_legacy_toolchain_selection_is_upgrade_safe () {
	local test_home="$TEST_TMP_ROOT/legacy-toolchains-home"
	local output status

	mkdir -p "$test_home"
	printf '%s\n' 'export DOTFILES_TOOLCHAINS="nvim"' > "$test_home/.toolchainsrc"

	output="$(env -u DOTFILES_TOOLCHAINS HOME="$test_home" \
		"$ROOT/script/install" --print --toolchains 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}
	assert_contains "$output" 'profile: toolchains:none'

	output="$(env -u DOTFILES_TOOLCHAINS HOME="$test_home" \
		"$ROOT/toolchains/install.sh" 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}
	assert_contains "$output" 'no toolchain profiles selected; skipping'

	output="$(HOME="$test_home" "$ROOT/toolchains/install.sh" nvim 2>&1)"
	status=$?
	[[ $status -eq 1 ]] || fail_test "explicit retired profile returned status $status"
	assert_contains "$output" 'unknown toolchain profile: nvim'
}

test_empty_toolchain_environment_overrides_file () {
	local test_home="$TEST_TMP_ROOT/empty-toolchains-home"
	local output

	mkdir -p "$test_home"
	printf '%s\n' 'export DOTFILES_TOOLCHAINS="node"' > "$test_home/.toolchainsrc"

	output="$(HOME="$test_home" DOTFILES_TOOLCHAINS='' \
		"$ROOT/script/install" --print --toolchains 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}
	assert_contains "$output" 'profile: toolchains:none'

	output="$(HOME="$test_home" DOTFILES_TOOLCHAINS='' \
		"$ROOT/toolchains/install.sh" 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}
	assert_contains "$output" 'no toolchain profiles selected; skipping'
}

test_eza_aliases_preserve_platform_ls () {
	local fake_bin="$TEST_TMP_ROOT/eza-alias-bin"
	local output

	mkdir -p "$fake_bin"
	printf '%s\n' '#!/bin/sh' 'exit 0' > "$fake_bin/eza"
	chmod +x "$fake_bin/eza"

	output="$(PATH="$fake_bin:/usr/bin:/bin" zsh -f -c \
		'source "$1"; alias ls; alias l; alias ll; alias la; alias lt' \
		_ "$ROOT/shell/core/aliases.zsh")" || {
		printf '%s\n' "$output" >&2
		return 1
	}

	assert_contains "$output" "ls='ls -F --color=auto'"
	assert_contains "$output" "l='eza --long --all --header --group-directories-first --git'"
	assert_contains "$output" "ll='eza --long --header --group-directories-first --git'"
	assert_contains "$output" "la='eza --all --group-directories-first'"
	assert_contains "$output" "lt='eza --tree --level=2 --group-directories-first'"
}

test_direnv_hook_loads_in_fallback_zsh () {
	local test_home="$TEST_TMP_ROOT/direnv-home"
	local fake_bin="$TEST_TMP_ROOT/direnv-bin"
	local output

	mkdir -p "$test_home" "$fake_bin"
	printf '%s\n' \
		'#!/bin/sh' \
		'if [ "${1:-}" = hook ] && [ "${2:-}" = zsh ]; then' \
		'  printf "typeset -g DOTFILES_DIRENV_TEST=loaded\\n"' \
		'fi' > "$fake_bin/direnv"
	chmod +x "$fake_bin/direnv"

	output="$(HOME="$test_home" PATH="$fake_bin:/usr/bin:/bin" \
		DOTFILES="$ROOT" DOTFILES_USE_OH_MY_ZSH=0 \
		ZDOTDIR="$test_home" ZSH_CACHE_DIR="$test_home/cache" \
		zsh -f -c 'source "$1"; print -r -- "${DOTFILES_DIRENV_TEST:-missing}"' \
		_ "$ROOT/zsh/zshrc.symlink")" || {
		printf '%s\n' "$output" >&2
		return 1
	}

	[[ "${output##*$'\n'}" == 'loaded' ]] || \
		fail_test 'direnv hook was not evaluated by the fallback Zsh configuration'
}

test_git_pager_prefers_delta_and_has_filter_fallback () {
	local fake_bin="$TEST_TMP_ROOT/git-pager-bin"
	local args_file="$TEST_TMP_ROOT/git-pager-args"
	local output

	mkdir -p "$fake_bin"
	ln -s "$(command -v cat)" "$fake_bin/cat"
	printf '%s\n' \
		'#!/bin/sh' \
		'printf "%s\\n" "$*" > "$DOTFILES_GIT_PAGER_ARGS"' \
		'cat' > "$fake_bin/delta"
	chmod +x "$fake_bin/delta"

	output="$(printf 'delta input\n' | PATH="$fake_bin" \
		DOTFILES_GIT_PAGER_ARGS="$args_file" "$ROOT/bin/git-pager" --color-only)" || \
		fail_test 'Git pager failed with Delta available'
	[[ "$output" == 'delta input' ]] || fail_test 'Delta pager did not preserve its input'
	[[ "$(< "$args_file")" == '--color-only' ]] || fail_test 'Git pager did not forward Delta arguments'

	rm "$fake_bin/delta"
	output="$(printf 'fallback input\n' | PATH="$fake_bin" \
		"$ROOT/bin/git-pager" --color-only)" || \
		fail_test 'Git diff-filter fallback failed without Delta'
	[[ "$output" == 'fallback input' ]] || fail_test 'Git diff-filter fallback changed its input'
}

test_toolchain_profile_failure_reaches_exit_status () {
	local test_home="$TEST_TMP_ROOT/toolchain-home"
	local fake_bin="$TEST_TMP_ROOT/toolchain-bin"
	local output status

	mkdir -p "$test_home" "$fake_bin"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$fake_bin/go"
	chmod +x "$fake_bin/go"

	output="$(HOME="$test_home" PATH="$fake_bin:$PATH" DOTFILES_GO_TOOLS='example.invalid/tool@v1' "$ROOT/toolchains/install.sh" go 2>&1)"
	status=$?

	[[ $status -eq 1 ]] || fail_test "expected status 1, got $status"
	assert_contains "$output" 'profiles: 0 succeeded, 1 failed'
	assert_contains "$output" 'profile: go'
}

test_remote_script_runner_propagates_status () {
	local fake_bin="$TEST_TMP_ROOT/remote-script-bin"
	local status

	mkdir -p "$fake_bin"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'output=' \
		'while [[ $# -gt 0 ]]; do' \
		'  if [[ "$1" == -o ]]; then output=$2; shift 2; else shift; fi' \
		'done' \
		'printf "exit 23\\n" > "$output"' > "$fake_bin/curl"
	chmod +x "$fake_bin/curl"

	PATH="$fake_bin:$PATH" bash -c 'source "$1"; run_remote_script https://example.invalid/install.sh bash' \
		_ "$ROOT/toolchains/lib/common.sh"
	status=$?

	[[ $status -eq 23 ]] || fail_test "expected status 23, got $status"
}

test_yq_reconciles_existing_target_version () {
	local test_home="$TEST_TMP_ROOT/yq-home"
	local install_root="$test_home/.local/opt"
	local completion_root="$test_home/.local/share/zsh/site-functions"
	local output

	mkdir -p "$install_root/yq-4.53.2/completions" \
		"$install_root/yq-4.53.3/completions" "$test_home/.local/bin" \
		"$completion_root"
	printf '%s\n' '#!/bin/sh' 'exit 0' > "$install_root/yq-4.53.3/yq"
	printf '#compdef yq\n' > "$install_root/yq-4.53.3/completions/_yq"
	chmod +x "$install_root/yq-4.53.3/yq"
	ln -s "$install_root/yq-4.53.2" "$install_root/yq-current"
	ln -s "$install_root/yq-4.53.2/yq" "$test_home/.local/bin/yq"
	ln -s "$install_root/yq-4.53.2/completions/_yq" "$completion_root/_yq"

	output="$(HOME="$test_home" "$ROOT/yq/install.sh" 2>&1)" || {
		printf '%s\n' "$output" >&2
		return 1
	}

	[[ "$(readlink "$install_root/yq-current")" == "$install_root/yq-4.53.3" ]] || \
		fail_test 'yq-current did not switch to the requested version'
	[[ "$(readlink "$test_home/.local/bin/yq")" == "$install_root/yq-current/yq" ]] || \
		fail_test '~/.local/bin/yq was not reconciled'
	[[ "$(readlink "$completion_root/_yq")" == \
		"$install_root/yq-current/completions/_yq" ]] || \
		fail_test 'the yq Zsh completion was not reconciled'
	assert_contains "$output" 'selected yq 4.53.3'
}

test_yq_preserves_unmanaged_binary_symlink () {
	local test_home="$TEST_TMP_ROOT/yq-unmanaged-home"
	local install_root="$test_home/.local/opt"
	local custom_bin="$test_home/custom/yq"
	local output status

	mkdir -p "$install_root/yq-4.53.3/completions" "$test_home/.local/bin" \
		"$(dirname "$custom_bin")"
	printf '%s\n' '#!/bin/sh' 'exit 0' > "$install_root/yq-4.53.3/yq"
	printf '#compdef yq\n' > "$install_root/yq-4.53.3/completions/_yq"
	printf '%s\n' '#!/bin/sh' 'exit 0' > "$custom_bin"
	chmod +x "$install_root/yq-4.53.3/yq" "$custom_bin"
	ln -s "$custom_bin" "$test_home/.local/bin/yq"

	output="$(HOME="$test_home" "$ROOT/yq/install.sh" 2>&1)"
	status=$?
	[[ $status -ne 0 ]] || fail_test 'yq install silently accepted an unmanaged binary link'
	[[ "$(readlink "$test_home/.local/bin/yq")" == "$custom_bin" ]] || \
		fail_test 'yq install replaced the unmanaged binary link'
	[[ ! -e "$install_root/yq-current" && ! -L "$install_root/yq-current" ]] || \
		fail_test 'yq install partially changed the selected version before refusing the custom binary'
	assert_contains "$output" 'points to an unmanaged target; leaving it unchanged'
}

test_yq_rejects_checksum_mismatch () {
	local test_home="$TEST_TMP_ROOT/yq-checksum-home"
	local fake_bin="$TEST_TMP_ROOT/yq-checksum-bin"
	local output status

	mkdir -p "$test_home" "$fake_bin"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'output=' \
		'while [[ $# -gt 0 ]]; do' \
		'  if [[ "$1" == -o ]]; then output=$2; shift 2; else shift; fi' \
		'done' \
		'printf "not a yq binary\\n" > "$output"' > "$fake_bin/curl"
	chmod +x "$fake_bin/curl"

	output="$(HOME="$test_home" PATH="$fake_bin:$PATH" DOTFILES_YQ_VERSION=v9.9.9 \
		DOTFILES_YQ_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
		"$ROOT/yq/install.sh" 2>&1)"
	status=$?

	[[ $status -eq 1 ]] || fail_test "expected status 1, got $status"
	assert_contains "$output" 'binary checksum mismatch'
	[[ ! -e "$test_home/.local/opt/yq-9.9.9" ]] || fail_test 'invalid yq binary was installed'
}

run_test 'bootstrap creates unique backup sessions' test_bootstrap_backups_are_unique
run_test 'bootstrap preserves dangling local links' test_bootstrap_preserves_dangling_local_link
run_test 'cache env exports variables and creates directories' test_cache_env_generates_expected_environment
run_test 'cache env safely quotes special workspace paths' test_cache_env_quotes_special_workspace_paths
run_test 'cache env generation is idempotent' test_cache_env_generation_is_idempotent
run_test 'cache env keeps compatibility and versions on separate inodes' test_cache_env_compatibility_entry_is_independent
run_test 'cache env migrates legacy compatibility content independently' test_cache_env_migrates_legacy_compatibility_entry
run_test 'cache env rejects invalid inputs and unmanaged targets' test_cache_env_rejects_invalid_inputs_and_unmanaged_targets
run_test 'TUI recognizes long cache workspace metadata' test_tui_recognizes_long_cache_workspace_metadata
run_test 'cache env preserves racing file and link targets' test_cache_env_does_not_overwrite_racing_targets
run_test 'cache env preserves replacements of managed targets' test_cache_env_does_not_overwrite_replaced_managed_targets
run_test 'cache env activates versions after compatibility replacement' test_cache_env_activates_version_after_compatibility_replacement
run_test 'cache env preserves a final compatibility file replacement' test_cache_env_preserves_final_compatibility_replacement file
run_test 'cache env preserves a final compatibility symlink replacement' test_cache_env_preserves_final_compatibility_replacement link
run_test 'cache env publishes versions atomically' test_cache_env_version_publication_is_atomic
run_test 'cache environment consumers reject symlink targets' test_cache_environment_consumers_reject_symlink_targets
run_test 'shell defaults do not enable proxies' test_shell_defaults_do_not_enable_proxies
run_test 'clipboard copy selects a runtime provider' test_clipboard_copy_selects_runtime_provider
run_test 'bootstrap cache configuration is opt-in' test_bootstrap_cache_environment_is_opt_in
run_test 'bootstrap rejects invalid cache workspaces before mutation' test_bootstrap_rejects_invalid_cache_workspace_before_mutation
run_test 'install generates and loads cache environment' test_install_cache_workspace_generates_and_loads_environment
run_test 'setup generates cache environment before install' test_setup_routes_cache_workspace_before_install
run_test 'setup invokes the cache generator once' test_setup_invokes_cache_generator_once
run_test 'setup TUI accepts user mode in either argument position' test_setup_tui_accepts_user_in_any_position
run_test 'TUI events execute exact setup arguments' test_tui_event_flow_executes_exact_setup_arguments
run_test 'TUI preview does not source local configuration' test_tui_does_not_source_local_configuration
run_test 'TUI toolchain defaults use the final safe assignment' test_tui_toolchain_defaults_use_last_safe_assignment
run_test 'TUI warns on ambiguous toolchain directives' test_tui_warns_on_ambiguous_toolchain_directives
run_test 'TUI overwrite emits confirmed force paths only' test_tui_overwrite_uses_confirmed_force_paths
run_test 'TUI sudo failure falls back to user-only scope' test_tui_sudo_failure_returns_to_user_only_scope
run_test 'init without a TTY fails clearly' test_init_without_tty_fails_clearly
run_test 'bootstrap rejects multiple conflict modes' test_bootstrap_rejects_multiple_conflict_modes
run_test 'bootstrap rejects relative state home before mutation' test_bootstrap_rejects_relative_state_home_before_mutation
run_test 'bootstrap does not follow a racing dotfiles alias' test_bootstrap_does_not_follow_racing_dotfiles_alias
run_test 'bootstrap force path only overwrites confirmed target' test_bootstrap_force_path_only_overwrites_confirmed_target
run_test 'bootstrap preserves special Git identity characters' test_bootstrap_preserves_git_identity_characters
run_test 'bootstrap preserves a concurrently created Git config' test_bootstrap_does_not_overwrite_racing_gitconfig
run_test 'setup forwards skip mode to bootstrap' test_setup_forwards_skip_to_bootstrap
run_test 'setup routes flags after toolchain profiles' test_setup_routes_flags_after_toolchain_profiles
run_test 'user mode skips manager and aggregates topics' test_user_mode_skips_manager_and_reports_topics
run_test 'package failures reach the top-level status' test_package_failure_reaches_exit_status
run_test 'base package profile includes interactive tools' test_base_packages_include_interactive_tools
run_test 'Vim config loads standalone' test_vim_config_loads_standalone
run_test 'terminal editor defaults use Vim' test_terminal_editor_defaults_to_vim
run_test 'toolchains have no implicit default' test_toolchains_have_no_implicit_default
run_test 'legacy toolchain selection remains upgrade-safe' test_legacy_toolchain_selection_is_upgrade_safe
run_test 'empty toolchain environment overrides local config' test_empty_toolchain_environment_overrides_file
run_test 'eza aliases preserve the platform ls command' test_eza_aliases_preserve_platform_ls
run_test 'direnv hook loads in fallback Zsh' test_direnv_hook_loads_in_fallback_zsh
run_test 'Git pager prefers Delta and falls back for filters' test_git_pager_prefers_delta_and_has_filter_fallback
run_test 'toolchain profile failures reach the top-level status' test_toolchain_profile_failure_reaches_exit_status
run_test 'downloaded script failures reach the profile' test_remote_script_runner_propagates_status
run_test 'yq reconciles an existing target version' test_yq_reconciles_existing_target_version
run_test 'yq preserves an unmanaged binary symlink' test_yq_preserves_unmanaged_binary_symlink
run_test 'yq rejects checksum mismatches' test_yq_rejects_checksum_mismatch

printf '\nResult: %d passed, %d failed\n' "$passed" "$failed"
[[ $failed -eq 0 ]]
