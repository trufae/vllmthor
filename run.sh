#!/usr/bin/env bash
#
# Serve an optimized language model on Jetson AGX Thor through vLLM.
#
# Profiles:
#   qwen       Qwen3.8-27B NVFP4 + DFlash2 (default)
#   qwen36     Qwen3.6-35B-A3B NVFP4 + DFlash
#   nemotron   NVIDIA Nemotron Nano 9B v2 NVFP4
#   nemotron35 NVIDIA Nemotron 3.5 Lightning NVFP4 + DSpark
#   glm45air   GLM-4.5-Air NVFP4 (experimental on Thor)
#
# The profile wrappers are the easiest entry points:
#   ./run.sh
#   ./run-qwen36.sh
#   ./run-nemotron.sh
#   ./run-nemotron-lightning.sh
#   ./run-glm45air.sh

set -euo pipefail

MODEL_PROFILE="${MODEL_PROFILE:-qwen}"

case "$MODEL_PROFILE" in
	qwen)
		DEFAULT_VLLM_IMAGE="vllm/vllm-openai:v0.28.0"
		DEFAULT_MODEL="Inferact/Qwen3.8-27B-NVFP4"
		DEFAULT_DRAFT_MODEL="incoai/Qwen3.8-27B-DFlash2"
		DEFAULT_SERVED_MODEL="qwen38"
		DEFAULT_MAX_MODEL_LEN="131072"
		DEFAULT_GPU_MEMORY_UTILIZATION="0.35"
		DEFAULT_MAX_NUM_SEQS="4"
		DEFAULT_CONTAINER_NAME="qwen38-vllm"
		PROFILE_TITLE="Qwen3.8-27B NVFP4 + DFlash2"
		;;
	qwen36)
		DEFAULT_VLLM_IMAGE="vllm/vllm-openai:v0.28.0"
		DEFAULT_MODEL="nvidia/Qwen3.6-35B-A3B-NVFP4"
		DEFAULT_DRAFT_MODEL="z-lab/Qwen3.6-35B-A3B-DFlash"
		DEFAULT_SERVED_MODEL="qwen36"
		DEFAULT_MAX_MODEL_LEN="65536"
		DEFAULT_GPU_MEMORY_UTILIZATION="0.78"
		DEFAULT_MAX_NUM_SEQS="4"
		DEFAULT_CONTAINER_NAME="qwen36-vllm"
		PROFILE_TITLE="Qwen3.6-35B-A3B NVFP4 + DFlash"
		;;
	nemotron)
		DEFAULT_VLLM_IMAGE="vllm/vllm-openai:v0.28.0"
		DEFAULT_MODEL="nvidia/NVIDIA-Nemotron-Nano-9B-v2-NVFP4"
		DEFAULT_DRAFT_MODEL=""
		DEFAULT_SERVED_MODEL="nemotron"
		DEFAULT_MAX_MODEL_LEN="131072"
		DEFAULT_GPU_MEMORY_UTILIZATION="0.35"
		DEFAULT_MAX_NUM_SEQS="4"
		DEFAULT_CONTAINER_NAME="nemotron-vllm"
		PROFILE_TITLE="NVIDIA Nemotron Nano NVFP4"
		;;
	nemotron35)
		DEFAULT_VLLM_IMAGE="vllm/vllm-openai:v0.28.0"
		DEFAULT_MODEL="nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4"
		DEFAULT_DRAFT_MODEL="nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4-DSpark"
		DEFAULT_SERVED_MODEL="nemotron35"
		DEFAULT_MAX_MODEL_LEN="128000"
		DEFAULT_GPU_MEMORY_UTILIZATION="0.70"
		DEFAULT_MAX_NUM_SEQS="4"
		DEFAULT_CONTAINER_NAME="nemotron35-vllm"
		PROFILE_TITLE="NVIDIA Nemotron 3.5 Lightning NVFP4 + DSpark"
		;;
	glm45air)
		DEFAULT_VLLM_IMAGE="vllm/vllm-openai:nightly"
		DEFAULT_MODEL="Firworks/GLM-4.5-Air-nvfp4"
		DEFAULT_DRAFT_MODEL=""
		DEFAULT_SERVED_MODEL="glm-4.5-air"
		DEFAULT_MAX_MODEL_LEN="32768"
		DEFAULT_GPU_MEMORY_UTILIZATION="0.50"
		DEFAULT_MAX_NUM_SEQS="1"
		DEFAULT_CONTAINER_NAME="glm45air-vllm"
		PROFILE_TITLE="GLM-4.5-Air NVFP4 (experimental)"
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
SERVED_MODEL="${SERVED_MODEL:-$DEFAULT_SERVED_MODEL}"

MAX_MODEL_LEN="${MAX_MODEL_LEN:-$DEFAULT_MAX_MODEL_LEN}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-$DEFAULT_GPU_MEMORY_UTILIZATION}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-$DEFAULT_MAX_NUM_SEQS}"
PORT="${PORT:-8000}"

HF_CACHE="${HF_CACHE:-$HOME/.cache/huggingface}"
CONTAINER_NAME="${CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"

if [[ ! "$MODEL" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)?$ ]]; then
	echo "Unsupported Hugging Face model ID: $MODEL" >&2
	exit 1
fi
if [ -n "$DRAFT_MODEL" ] &&
	[[ ! "$DRAFT_MODEL" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)?$ ]]; then
	echo "Unsupported Hugging Face draft model ID: $DRAFT_MODEL" >&2
	exit 1
fi
if [[ "$MODEL_PROFILE" =~ ^(qwen|qwen36|nemotron35)$ ]] && [ -z "$DRAFT_MODEL" ]; then
	echo "The $MODEL_PROFILE profile requires a matching DRAFT_MODEL." >&2
	exit 1
fi

# Profile-specific container environment and vLLM arguments. These are arrays
# so every value remains one argument even when an override contains spaces.
container_env=(-e "HF_TOKEN=${HF_TOKEN:-}")
model_args=(
	--served-model-name "$SERVED_MODEL"
	--host 0.0.0.0
	--port "$PORT"
	--tensor-parallel-size 1
	--max-model-len "$MAX_MODEL_LEN"
	--max-num-seqs "$MAX_NUM_SEQS"
	--gpu-memory-utilization "$GPU_MEMORY_UTILIZATION"
	--enable-prefix-caching
	--trust-remote-code
)

case "$MODEL_PROFILE" in
	qwen)
		container_env+=(-e VLLM_GDN_DECODE_KERNEL=triton)
		model_args+=(
			--kv-cache-dtype fp8
			--language-model-only
			--reasoning-parser qwen3
			--enable-auto-tool-choice
			--tool-call-parser qwen3_coder
			--speculative-config
			"{\"method\":\"dflash\",\"model\":\"$DRAFT_MODEL\",\"num_speculative_tokens\":7}"
		)
		;;
	qwen36)
		# Thor's SM110a does not have a FlashInfer FP4 MoE kernel. Marlin is
		# the fastest proven backend for this 256-expert checkpoint.
		container_env+=(
			-e VLLM_USE_FLASHINFER_MOE_FP4=0
			-e LD_PRELOAD=/usr/lib/aarch64-linux-gnu/nvidia/libcuda.so.1
		)
		model_args+=(
			--quantization modelopt
			--kv-cache-dtype auto
			--language-model-only
			--attention-backend flash_attn
			--moe-backend marlin
			--reasoning-parser qwen3
			--enable-auto-tool-choice
			--tool-call-parser qwen3_xml
			--speculative-config
			"{\"method\":\"dflash\",\"model\":\"$DRAFT_MODEL\",\"num_speculative_tokens\":12}"
		)
		;;
	nemotron)
		# NVIDIA specifies float32 here to avoid degrading model quality.
		model_args+=(--mamba_ssm_cache_dtype float32)
		;;
	nemotron35)
		model_args+=(
			--kv-cache-dtype fp8
			--max-num-batched-tokens 16384
			--moe-backend marlin
			--reasoning-parser nemotron_v3
			--enable-auto-tool-choice
			--tool-call-parser qwen3_coder
			--speculative-config
			"{\"method\":\"dspark\",\"model\":\"$DRAFT_MODEL\",\"num_speculative_tokens\":5}"
			--mamba-backend flashinfer
			--mamba-ssm-cache-dtype float16
			--enable-mamba-cache-stochastic-rounding
			--mamba-cache-philox-rounds 5
			--mamba-cache-mode align
		)
		;;
	glm45air)
		container_env+=(-e VLLM_USE_FLASHINFER_MOE_FP4=1)
		model_args+=(
			--dtype auto
			--enforce-eager
			--reasoning-parser glm45
			--tool-call-parser glm45
			--enable-auto-tool-choice
		)
		;;
esac

echo "==> Checking architecture..."

ARCH="$(uname -m)"
if [ "$ARCH" != "aarch64" ]; then
	echo "WARNING: expected aarch64/Jetson Thor, got: $ARCH"
fi

if [ -f /etc/nv_tegra_release ]; then
	echo "==> NVIDIA Jetson:"
	cat /etc/nv_tegra_release
else
	echo "WARNING: /etc/nv_tegra_release not found."
fi

echo
echo "==> Checking Docker..."

if ! command -v docker >/dev/null 2>&1; then
	echo "Docker is not installed." >&2
	echo "Install JetPack 7.2 / NVIDIA container support first." >&2
	exit 1
fi

docker --version

echo
echo "==> Checking NVIDIA container runtime..."

if ! docker info 2>/dev/null | grep -qi nvidia; then
	echo "WARNING: Docker does not report the NVIDIA runtime."
	echo "Trying anyway; --runtime=nvidia will fail if it is unavailable."
fi

mkdir -p "$HF_CACHE"

echo
echo "==> Hugging Face cache:"
echo "    $HF_CACHE"

echo
echo "==> Pulling vLLM $VLLM_IMAGE..."
docker pull "$VLLM_IMAGE"

echo
echo "==> Checking CUDA from inside the vLLM container..."

docker run --rm \
	--runtime nvidia \
	--network host \
	--ipc=host \
	--entrypoint python3 \
	"$VLLM_IMAGE" \
	-c '
import torch
print("PyTorch:", torch.__version__)
print("CUDA available:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("CUDA:", torch.version.cuda)
    print("GPU:", torch.cuda.get_device_name(0))
'

download_model() {
	local description="$1"
	local model_id="$2"

	echo
	echo "==> Downloading $description..."
	echo "    $model_id"

	docker run --rm \
		--runtime nvidia \
		--network host \
		-v "$HF_CACHE:/root/.cache/huggingface" \
		-e HF_TOKEN="${HF_TOKEN:-}" \
		-e MODEL_ID="$model_id" \
		--entrypoint python3 \
		"$VLLM_IMAGE" \
		-c '
import os
from huggingface_hub import snapshot_download
snapshot_download(os.environ["MODEL_ID"])
'
}

download_model "target model" "$MODEL"
if [ -n "$DRAFT_MODEL" ]; then
	download_model "speculative draft model" "$DRAFT_MODEL"
fi

echo
echo "================================================================"
echo " $PROFILE_TITLE / Jetson AGX Thor"
echo "================================================================"
echo
echo " Profile:      $MODEL_PROFILE"
echo " Model:        $MODEL"
if [ -n "$DRAFT_MODEL" ]; then
	echo " Draft:        $DRAFT_MODEL"
fi
echo " Context:      $MAX_MODEL_LEN"
echo " Sequences:    $MAX_NUM_SEQS"
echo " GPU memory:   $GPU_MEMORY_UTILIZATION of total"
echo " API:          http://localhost:$PORT/v1"
echo " Model name:   $SERVED_MODEL"
echo " Container:    $CONTAINER_NAME"
echo
echo " Ctrl-C stops the server."
echo "================================================================"
echo

exec docker run --rm -it \
	--name "$CONTAINER_NAME" \
	--runtime nvidia \
	--network host \
	--ipc=host \
	-v "$HF_CACHE:/root/.cache/huggingface" \
	"${container_env[@]}" \
	"$VLLM_IMAGE" \
	"$MODEL" \
	"${model_args[@]}"
