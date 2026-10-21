#!/usr/bin/env bash
#
# Remove the container, server image, and caches created by run.sh.
#
# Select the same profile used to start the server:
#   MODEL_PROFILE=qwen36 ./clean.sh
#   MODEL_PROFILE=ornith ./clean.sh
#   MODEL_PROFILE=nemotron ./clean.sh
#   MODEL_PROFILE=nemotron35 ./clean.sh
#   MODEL_PROFILE=glm45air ./clean.sh
#   MODEL_PROFILE=gemma4 ./clean.sh
#   MODEL_PROFILE=glm47flash ./clean.sh
#   MODEL_PROFILE=lfm25 ./clean.sh
#   MODEL_PROFILE=muse ./clean.sh
#
# The Hugging Face Xet cache is shared between repositories. It is removed by
# default because run.sh can populate it. Set KEEP_XET_CACHE=1 to preserve it.

set -uo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || exit 1
source "$SCRIPT_DIR/profiles.sh" || exit 1
load_profile "${MODEL_PROFILE:-qwen}" || exit 1

HF_CACHE="${HF_CACHE:-${HOME:?HOME must be set}/.cache/huggingface}"
DEFAULT_VLLM_CACHE="${HOME:?HOME must be set}/.cache/vllm/$MODEL_PROFILE"
VLLM_CACHE="${VLLM_CACHE:-$DEFAULT_VLLM_CACHE}"
KEEP_XET_CACHE="${KEEP_XET_CACHE:-0}"

failures=0

if ! HF_CACHE="$(realpath -m -- "$HF_CACHE")"; then
	echo "ERROR: could not resolve HF_CACHE." >&2
	exit 1
fi
if ! VLLM_CACHE="$(realpath -m -- "$VLLM_CACHE")"; then
	echo "ERROR: could not resolve VLLM_CACHE." >&2
	exit 1
fi
DEFAULT_VLLM_CACHE="$(realpath -m -- "$DEFAULT_VLLM_CACHE")"

if [ -z "$HF_CACHE" ] || [ "$HF_CACHE" = "/" ]; then
	echo "ERROR: refusing to clean unsafe HF_CACHE value: '$HF_CACHE'" >&2
	exit 1
fi
if [ -z "$VLLM_CACHE" ] || [ "$VLLM_CACHE" = "/" ]; then
	echo "ERROR: refusing to clean unsafe VLLM_CACHE value: '$VLLM_CACHE'" >&2
	exit 1
fi

remove_path() {
	local path="$1"

	if [ -e "$path" ] || [ -L "$path" ]; then
		echo "==> Removing $path"
		if ! rm -rf -- "$path"; then
			echo "ERROR: could not remove $path" >&2
			failures=$((failures + 1))
		fi
	else
		echo "==> Already absent: $path"
	fi
}

repo_cache_name() {
	local repo="$1"

	# Hugging Face repository IDs become models--ORG--NAME in the hub cache.
	# Restrict the accepted form so an environment override cannot escape it.
	if [[ ! "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)?$ ]]; then
		echo "ERROR: unsafe or unsupported Hugging Face repository ID: $repo" >&2
		return 1
	fi

	printf 'models--%s\n' "${repo//\//--}"
}

remove_model_cache() {
	local repo="$1"
	local cache_name

	if ! cache_name="$(repo_cache_name "$repo")"; then
		failures=$((failures + 1))
		return
	fi

	remove_path "$HF_CACHE/hub/$cache_name"
	remove_path "$HF_CACHE/hub/.locks/$cache_name"

	# --trust-remote-code can create a Python module cache for a repository.
	remove_path "$HF_CACHE/modules/transformers_modules/$repo"
}

remove_empty_python_package() {
	local path="$1"
	local extra

	[ -d "$path" ] || return

	extra="$(find "$path" -mindepth 1 -maxdepth 1 \
		! -name '__init__.py' ! -name '__pycache__' -print -quit)"
	if [ -z "$extra" ]; then
		remove_path "$path"
	fi
}

echo "==> Removing the model-server container and image..."

if ! command -v docker >/dev/null 2>&1; then
	echo "ERROR: Docker is not installed; cannot remove $SERVER_IMAGE." >&2
	failures=$((failures + 1))
elif ! docker info >/dev/null 2>&1; then
	echo "ERROR: cannot connect to Docker; cannot remove $SERVER_IMAGE." >&2
	failures=$((failures + 1))
else
	if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
		if ! docker container rm --force "$CONTAINER_NAME"; then
			echo "ERROR: could not remove container $CONTAINER_NAME." >&2
			failures=$((failures + 1))
		fi
	else
		echo "==> Container already absent: $CONTAINER_NAME"
	fi

	if docker image inspect "$SERVER_IMAGE" >/dev/null 2>&1; then
		if ! docker image rm --force "$SERVER_IMAGE"; then
			echo "ERROR: could not remove image $SERVER_IMAGE." >&2
			failures=$((failures + 1))
		fi
	else
		echo "==> Image already absent: $SERVER_IMAGE"
	fi
fi

echo
echo "==> Removing Hugging Face model caches..."
remove_model_cache "$MODEL"
if [ -n "$DRAFT_MODEL" ] && [ "$DRAFT_MODEL" != "$MODEL" ]; then
	remove_model_cache "$DRAFT_MODEL"
fi

if [ "$KEEP_XET_CACHE" = "1" ]; then
	echo "==> Preserving shared Xet cache: $HF_CACHE/xet"
else
	remove_path "$HF_CACHE/xet"
fi

echo
echo "==> Removing the vLLM compile cache..."
if [ "$VLLM_CACHE" = "$DEFAULT_VLLM_CACHE" ]; then
	remove_path "$VLLM_CACHE"
else
	echo "==> Preserving custom vLLM cache: $VLLM_CACHE"
fi

# Remove package scaffolding and cache directories only when nothing else uses
# them. rmdir deliberately leaves any unrelated Hugging Face data untouched.
if [[ "$MODEL" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
	remove_empty_python_package "$HF_CACHE/modules/transformers_modules/${MODEL%%/*}"
fi
if [ -n "$DRAFT_MODEL" ] &&
	[[ "$DRAFT_MODEL" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
	remove_empty_python_package "$HF_CACHE/modules/transformers_modules/${DRAFT_MODEL%%/*}"
fi
remove_empty_python_package "$HF_CACHE/modules/transformers_modules"
remove_empty_python_package "$HF_CACHE/modules"
rmdir -- "$HF_CACHE/hub/.locks" "$HF_CACHE/hub" "$HF_CACHE" 2>/dev/null || true

echo
if [ "$failures" -ne 0 ]; then
	echo "Cleanup finished with $failures error(s)." >&2
	exit 1
fi

echo "Cleanup complete."
