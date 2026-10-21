#!/usr/bin/env bash
#
# Serve an optimized language model on Jetson AGX Thor through vLLM or llama.cpp.
#
# Profiles:
#   qwen       Qwen3.8-27B NVFP4 + DFlash2 (default)
#   qwen36     Qwen3.6-35B-A3B NVFP4 + DFlash
#   ornith     Ornith 1.5 35B-A3B NVFP4 + DFlash
#   nemotron   NVIDIA Nemotron Nano 9B v2 NVFP4
#   nemotron35 NVIDIA Nemotron 3.5 Lightning NVFP4 + DSpark
#   glm45air   GLM-4.5-Air NVFP4 (experimental on Thor)
#   gemma4     Gemma 4 26B-A4B NVFP4 + MTP
#   glm47flash GLM-4.7-Flash NVFP4 (experimental on Thor)
#   lfm25      LFM2.5 24B-A2B FP8 (experimental on Thor)
#   muse       Muse Glimmer 30B K-Quant + DFlash (llama.cpp)
#
# The profile wrappers are the easiest entry points:
#   ./run.sh
#   ./run-qwen36.sh
#   ./run-ornith.sh
#   ./run-nemotron.sh
#   ./run-nemotron-lightning.sh
#   ./run-glm45air.sh
#   ./run-gemma4.sh
#   ./run-glm47flash.sh
#   ./run-lfm25.sh
#   ./run-muse-glimmer.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || exit 1
source "$SCRIPT_DIR/profiles.sh" || exit 1
load_profile "${MODEL_PROFILE:-qwen}" || exit 1

ENGINE="$DEFAULT_ENGINE"
SERVED_MODEL="${SERVED_MODEL:-$DEFAULT_SERVED_MODEL}"

MAX_MODEL_LEN="${MAX_MODEL_LEN:-$DEFAULT_MAX_MODEL_LEN}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-$DEFAULT_GPU_MEMORY_UTILIZATION}"
# MAX_CONCURRENT_REQUESTS is the user-facing name. MAX_NUM_SEQS remains an
# alias because it maps directly to vLLM's --max-num-seqs option.
MAX_CONCURRENT_REQUESTS="${MAX_CONCURRENT_REQUESTS:-${MAX_NUM_SEQS:-$DEFAULT_MAX_NUM_SEQS}}"
MAX_NUM_SEQS="$MAX_CONCURRENT_REQUESTS"
MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS:-$DEFAULT_MAX_NUM_BATCHED_TOKENS}"
PORT="${PORT:-8000}"

HF_CACHE="${HF_CACHE:-$HOME/.cache/huggingface}"
VLLM_CACHE="${VLLM_CACHE:-$HOME/.cache/vllm/$MODEL_PROFILE}"

if [[ ! "$MAX_CONCURRENT_REQUESTS" =~ ^[1-9][0-9]*$ ]]; then
	echo "MAX_CONCURRENT_REQUESTS must be a positive integer, got: $MAX_CONCURRENT_REQUESTS" >&2
	exit 1
fi
if [ -n "$MAX_NUM_BATCHED_TOKENS" ] &&
	[[ ! "$MAX_NUM_BATCHED_TOKENS" =~ ^[1-9][0-9]*$ ]]; then
	echo "MAX_NUM_BATCHED_TOKENS must be a positive integer, got: $MAX_NUM_BATCHED_TOKENS" >&2
	exit 1
fi

if [[ ! "$MODEL" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)?$ ]]; then
	echo "Unsupported Hugging Face model ID: $MODEL" >&2
	exit 1
fi
if [ -n "$DRAFT_MODEL" ] &&
	[[ ! "$DRAFT_MODEL" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)?$ ]]; then
	echo "Unsupported Hugging Face draft model ID: $DRAFT_MODEL" >&2
	exit 1
fi
if [[ "$MODEL_PROFILE" =~ ^(qwen|qwen36|ornith|nemotron35|gemma4)$ ]] && [ -z "$DRAFT_MODEL" ]; then
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
if [ -n "$MAX_NUM_BATCHED_TOKENS" ]; then
	model_args+=(--max-num-batched-tokens "$MAX_NUM_BATCHED_TOKENS")
fi

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
	ornith)
		# Ornith's official NVFP4 checkpoint is W4A16: its weights are FP4,
		# but its activations are BF16. vLLM therefore uses weight-only Marlin;
		# native FP4 MoE kernels require a W4A4 checkpoint. Override the
		# checkpoint's FP8 KV-cache metadata because FlashAttention only
		# supports it on SM90/SM100, not Thor's SM110a GPU.
		container_env+=(
			-e VLLM_USE_FLASHINFER_MOE_FP4=0
			-e "VLLM_MARLIN_USE_ATOMIC_ADD=${VLLM_MARLIN_USE_ATOMIC_ADD:-1}"
			-e LD_PRELOAD=/usr/lib/aarch64-linux-gnu/nvidia/libcuda.so.1
		)
		model_args+=(
			--quantization modelopt
			--kv-cache-dtype bfloat16
			--language-model-only
			--attention-backend flash_attn
			--moe-backend marlin
			--reasoning-parser qwen3
			--enable-auto-tool-choice
			--tool-call-parser qwen3_xml
			--speculative-config
			"{\"method\":\"dflash\",\"model\":\"$DRAFT_MODEL\",\"num_speculative_tokens\":8}"
		)
		;;
	nemotron)
		# NVIDIA specifies float32 here to avoid degrading model quality.
		model_args+=(--mamba_ssm_cache_dtype float32)
		;;
	nemotron35)
		model_args+=(
			--kv-cache-dtype fp8
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
	gemma4)
		model_args+=(
			--reasoning-parser gemma4
			--enable-auto-tool-choice
			--tool-call-parser gemma4
			--default-chat-template-kwargs '{"enable_thinking":true}'
			--speculative-config
			"{\"method\":\"mtp\",\"model\":\"$DRAFT_MODEL\",\"num_speculative_tokens\":3}"
		)
		;;
	glm47flash)
		# This community mixed-precision checkpoint is Blackwell-compatible,
		# but has not been benchmarked on Thor. Avoid the unsupported SM110a
		# FlashInfer FP4 MoE path and let vLLM use its fallback kernels.
		container_env+=(-e VLLM_USE_FLASHINFER_MOE_FP4=0)
		model_args+=(
			--dtype auto
			--reasoning-parser glm45
			--tool-call-parser glm47
			--enable-auto-tool-choice
			--speculative-config
			'{"method":"mtp","num_speculative_tokens":1}'
		)
		;;
	lfm25)
		# Use Liquid AI's block-quantized W8A8 checkpoint. vLLM selects the best
		# compressed-tensors kernels for Hopper or Blackwell at load time. The
		# qwen3 reasoning parser extracts <think> blocks, while the LFM2 parser
		# converts Pythonic function calls into OpenAI-compatible tool_calls.
		model_args+=(
			--dtype auto
			--quantization compressed-tensors
			--reasoning-parser qwen3
			--enable-auto-tool-choice
			--tool-call-parser lfm2
		)
		# No verifier-specific DSpark or EAGLE checkpoint exists for this model
		# yet. This opt-in accepts target-only n-gram speculation now and a
		# compatible trained draft later without baking an unverified pairing
		# into the profile.
		if [ -n "${LFM25_SPECULATIVE_CONFIG:-}" ]; then
			model_args+=(--speculative-config "$LFM25_SPECULATIVE_CONFIG")
		fi
		;;
	muse)
		# Muse is started below with NVIDIA's Thor llama.cpp container.
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
if [ "$ENGINE" = "vllm" ]; then
	mkdir -p "$VLLM_CACHE"
fi

echo
echo "==> Hugging Face cache:"
echo "    $HF_CACHE"
if [ "$ENGINE" = "vllm" ]; then
	echo "==> vLLM compile cache:"
	echo "    $VLLM_CACHE"
fi

echo
echo "==> Pulling $ENGINE server image $SERVER_IMAGE..."
docker pull "$SERVER_IMAGE"

echo
if [ "$ENGINE" = "vllm" ]; then
	echo "==> Checking CUDA from inside the vLLM container..."

	docker run --rm \
		--runtime nvidia \
		--network host \
		--ipc=host \
		--entrypoint python3 \
		"$SERVER_IMAGE" \
		-c '
import torch
print("PyTorch:", torch.__version__)
print("CUDA available:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("CUDA:", torch.version.cuda)
    print("GPU:", torch.cuda.get_device_name(0))
'
else
	echo "==> Checking the llama.cpp build..."
	docker run --rm \
		--runtime nvidia \
		--entrypoint llama-server \
		"$SERVER_IMAGE" \
		--version
fi

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
		"$SERVER_IMAGE" \
		-c '
import os
from huggingface_hub import snapshot_download
snapshot_download(os.environ["MODEL_ID"])
'
}

if [ "$ENGINE" = "vllm" ]; then
	download_model "target model" "$MODEL"
	if [ -n "$DRAFT_MODEL" ]; then
		download_model "speculative draft model" "$DRAFT_MODEL"
	fi
else
	echo
	echo "==> llama.cpp will download the selected GGUF and companions on first start."
fi

echo
echo "================================================================"
echo " $PROFILE_TITLE / Jetson AGX Thor"
echo "================================================================"
echo
echo " Profile:      $MODEL_PROFILE"
echo " Engine:       $ENGINE"
echo " Model:        $MODEL"
if [ -n "$DRAFT_MODEL" ]; then
	echo " Draft:        $DRAFT_MODEL"
fi
echo " Context:      $MAX_MODEL_LEN"
echo " Active slots: $MAX_CONCURRENT_REQUESTS"
if [ -n "$MAX_NUM_BATCHED_TOKENS" ]; then
	echo " Batch tokens: $MAX_NUM_BATCHED_TOKENS"
fi
if [ "$ENGINE" = "vllm" ]; then
	echo " GPU memory:   $GPU_MEMORY_UTILIZATION of total"
fi
echo " API:          http://localhost:$PORT/v1"
echo " Model name:   $SERVED_MODEL"
echo " Container:    $CONTAINER_NAME"
echo
echo " Ctrl-C stops the server."
echo "================================================================"
echo

if [ "$ENGINE" = "llama.cpp" ]; then
	exec docker run --rm -it \
		--name "$CONTAINER_NAME" \
		--label "$SERVER_LABEL=$MODEL_PROFILE" \
		--runtime nvidia \
		--network host \
		--ipc=host \
		-v "$HF_CACHE:/root/.cache/huggingface" \
		-e "HF_TOKEN=${HF_TOKEN:-}" \
		"$SERVER_IMAGE" \
		llama-server \
		-hf "$MODEL" \
		-hff "${MUSE_MODEL_FILE:-Muse-Glimmer-30B-KQuant-17GB-Q4_K_M.gguf}" \
		--alias "$SERVED_MODEL" \
		--spec-type draft-dflash \
		--n-gpu-layers 999 \
		--spec-draft-ngl 999 \
		--ctx-size "$MAX_MODEL_LEN" \
		--flash-attn on \
		--parallel "$MAX_NUM_SEQS" \
		--jinja \
		--temp 1.0 \
		--top-p 0.95 \
		--top-k 64 \
		--host 0.0.0.0 \
		--port "$PORT"
fi

exec docker run --rm -it \
	--name "$CONTAINER_NAME" \
	--label "$SERVER_LABEL=$MODEL_PROFILE" \
	--runtime nvidia \
	--network host \
	--ipc=host \
	-v "$HF_CACHE:/root/.cache/huggingface" \
	-v "$VLLM_CACHE:/root/.cache/vllm" \
	"${container_env[@]}" \
	"$SERVER_IMAGE" \
	"$MODEL" \
	"${model_args[@]}"
