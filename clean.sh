#!/usr/bin/env bash
#
# Remove the containers, image, and caches created by run.sh.
#
# Select the same profile used to start the server:
#   MODEL_PROFILE=qwen36 ./clean.sh
#   MODEL_PROFILE=nemotron ./clean.sh
#   MODEL_PROFILE=nemotron35 ./clean.sh
#   MODEL_PROFILE=glm45air ./clean.sh
#
# The Hugging Face Xet cache is shared between repositories. It is removed by
# default because run.sh can populate it. Set KEEP_XET_CACHE=1 to preserve it.

set -uo pipefail
IFS=$'\n\t'

MODEL_PROFILE="${MODEL_PROFILE:-qwen}"

case "$MODEL_PROFILE" in
	qwen)
		DEFAULT_VLLM_IMAGE="vllm/vllm-openai:v0.28.0"
		DEFAULT_MODEL="Inferact/Qwen3.8-27B-NVFP4"
		DEFAULT_DRAFT_MODEL="incoai/Qwen3.8-27B-DFlash2"
		DEFAULT_CONTAINER_NAME="qwen38-vllm"
		;;
	qwen36)
		DEFAULT_VLLM_IMAGE="vllm/vllm-openai:v0.28.0"
		DEFAULT_MODEL="nvidia/Qwen3.6-35B-A3B-NVFP4"
		DEFAULT_DRAFT_MODEL="z-lab/Qwen3.6-35B-A3B-DFlash"
		DEFAULT_CONTAINER_NAME="qwen36-vllm"
		;;
	nemotron)
		DEFAULT_VLLM_IMAGE="vllm/vllm-openai:v0.28.0"
		DEFAULT_MODEL="nvidia/NVIDIA-Nemotron-Nano-9B-v2-NVFP4"
		DEFAULT_DRAFT_MODEL=""
		DEFAULT_CONTAINER_NAME="nemotron-vllm"
		;;
	nemotron35)
		DEFAULT_VLLM_IMAGE="vllm/vllm-openai:v0.28.0"
		DEFAULT_MODEL="nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4"
		DEFAULT_DRAFT_MODEL="nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4-DSpark"
		DEFAULT_CONTAINER_NAME="nemotron35-vllm"
		;;
	glm45air)
		DEFAULT_VLLM_IMAGE="vllm/vllm-openai:nightly"
		DEFAULT_MODEL="Firworks/GLM-4.5-Air-nvfp4"
		DEFAULT_DRAFT_MODEL=""
		DEFAULT_CONTAINER_NAME="glm45air-vllm"
		;;
	*)
		echo "Unknown MODEL_PROFILE: $MODEL_PROFILE" >&2
		echo "Expected one of: qwen, qwen36, nemotron, nemotron35, glm45air" >&2
		exit 1
		;;
esac

VLLM_IMAGE="${VLLM_IMAGE:-$DEFAULT_VLLM_IMAGE}"
MODEL="${MODEL:-$DEFAULT_MODEL}"
DRAFT_MODEL="${DRAFT_MODEL-$DEFAULT_DRAFT_MODEL}"

HF_CACHE="${HF_CACHE:-${HOME:?HOME must be set}/.cache/huggingface}"
KEEP_XET_CACHE="${KEEP_XET_CACHE:-0}"

CONTAINER_NAME="${CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"
failures=0

if ! HF_CACHE="$(realpath -m -- "$HF_CACHE")"; then
	echo "ERROR: could not resolve HF_CACHE." >&2
	exit 1
fi

if [ -z "$HF_CACHE" ] || [ "$HF_CACHE" = "/" ]; then
	echo "ERROR: refusing to clean unsafe HF_CACHE value: '$HF_CACHE'" >&2
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

echo "==> Removing the vLLM container and image..."

if ! command -v docker >/dev/null 2>&1; then
	echo "ERROR: Docker is not installed; cannot remove $VLLM_IMAGE." >&2
	failures=$((failures + 1))
elif ! docker info >/dev/null 2>&1; then
	echo "ERROR: cannot connect to Docker; cannot remove $VLLM_IMAGE." >&2
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

	if docker image inspect "$VLLM_IMAGE" >/dev/null 2>&1; then
		if ! docker image rm --force "$VLLM_IMAGE"; then
			echo "ERROR: could not remove image $VLLM_IMAGE." >&2
			failures=$((failures + 1))
		fi
	else
		echo "==> Image already absent: $VLLM_IMAGE"
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
