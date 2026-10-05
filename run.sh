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
#   ./run-muse-glimmer.sh

set -euo pipefail

MODEL_PROFILE="${MODEL_PROFILE:-qwen}"

case "$MODEL_PROFILE" in
	qwen)
		DEFAULT_SERVER_IMAGE="vllm/vllm-openai:v0.28.0"
		DEFAULT_ENGINE="vllm"
		DEFAULT_MODEL="Inferact/Qwen3.8-27B-NVFP4"
		DEFAULT_DRAFT_MODEL="incoai/Qwen3.8-27B-DFlash2"
		DEFAULT_SERVED_MODEL="qwen38"
		DEFAULT_MAX_MODEL_LEN="131072"
		DEFAULT_GPU_MEMORY_UTILIZATION="0.35"
		DEFAULT_MAX_NUM_SEQS="4"
		DEFAULT_MAX_NUM_BATCHED_TOKENS=""
		DEFAULT_CONTAINER_NAME="qwen38-vllm"
		PROFILE_TITLE="Qwen3.8-27B NVFP4 + DFlash2"
		;;
	qwen36)
		DEFAULT_SERVER_IMAGE="vllm/vllm-openai:v0.28.0"
		DEFAULT_ENGINE="vllm"
		DEFAULT_MODEL="nvidia/Qwen3.6-35B-A3B-NVFP4"
		DEFAULT_DRAFT_MODEL="z-lab/Qwen3.6-35B-A3B-DFlash"
		DEFAULT_SERVED_MODEL="qwen36"
		DEFAULT_MAX_MODEL_LEN="65536"
		DEFAULT_GPU_MEMORY_UTILIZATION="0.78"
		DEFAULT_MAX_NUM_SEQS="4"
		DEFAULT_MAX_NUM_BATCHED_TOKENS=""
		DEFAULT_CONTAINER_NAME="qwen36-vllm"
		PROFILE_TITLE="Qwen3.6-35B-A3B NVFP4 + DFlash"
		;;
	ornith)
		DEFAULT_SERVER_IMAGE="vllm/vllm-openai:v0.28.0"
		DEFAULT_ENGINE="vllm"
		DEFAULT_MODEL="ornith-ai/Ornith-1.5-35B-A3B-NVFP4"
		DEFAULT_DRAFT_MODEL="ornith-ai/Ornith-1.5-35B-A3B-DFlash"
		DEFAULT_SERVED_MODEL="ornith"
		DEFAULT_MAX_MODEL_LEN="65536"
		DEFAULT_GPU_MEMORY_UTILIZATION="0.78"
		DEFAULT_MAX_NUM_SEQS="4"
		DEFAULT_MAX_NUM_BATCHED_TOKENS="8192"
		DEFAULT_CONTAINER_NAME="ornith-vllm"
		PROFILE_TITLE="Ornith 1.5 35B-A3B NVFP4 + DFlash"
		;;
	nemotron)
		DEFAULT_SERVER_IMAGE="vllm/vllm-openai:v0.28.0"
		DEFAULT_ENGINE="vllm"
		DEFAULT_MODEL="nvidia/NVIDIA-Nemotron-Nano-9B-v2-NVFP4"
		DEFAULT_DRAFT_MODEL=""
		DEFAULT_SERVED_MODEL="nemotron"
		DEFAULT_MAX_MODEL_LEN="131072"
		DEFAULT_GPU_MEMORY_UTILIZATION="0.35"
		DEFAULT_MAX_NUM_SEQS="4"
		DEFAULT_MAX_NUM_BATCHED_TOKENS=""
		DEFAULT_CONTAINER_NAME="nemotron-vllm"
		PROFILE_TITLE="NVIDIA Nemotron Nano NVFP4"
		;;
	nemotron35)
		DEFAULT_SERVER_IMAGE="vllm/vllm-openai:v0.28.0"
		DEFAULT_ENGINE="vllm"
		DEFAULT_MODEL="nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4"
		DEFAULT_DRAFT_MODEL="nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4-DSpark"
		DEFAULT_SERVED_MODEL="nemotron35"
		DEFAULT_MAX_MODEL_LEN="128000"
		DEFAULT_GPU_MEMORY_UTILIZATION="0.70"
		DEFAULT_MAX_NUM_SEQS="4"
		DEFAULT_MAX_NUM_BATCHED_TOKENS="16384"
		DEFAULT_CONTAINER_NAME="nemotron35-vllm"
		PROFILE_TITLE="NVIDIA Nemotron 3.5 Lightning NVFP4 + DSpark"
		;;
	glm45air)
		DEFAULT_SERVER_IMAGE="vllm/vllm-openai:nightly"
		DEFAULT_ENGINE="vllm"
		DEFAULT_MODEL="Firworks/GLM-4.5-Air-nvfp4"
		DEFAULT_DRAFT_MODEL=""
		DEFAULT_SERVED_MODEL="glm-4.5-air"
		DEFAULT_MAX_MODEL_LEN="32768"
		DEFAULT_GPU_MEMORY_UTILIZATION="0.50"
		DEFAULT_MAX_NUM_SEQS="2"
		DEFAULT_MAX_NUM_BATCHED_TOKENS=""
		DEFAULT_CONTAINER_NAME="glm45air-vllm"
		PROFILE_TITLE="GLM-4.5-Air NVFP4 (experimental)"
		;;
	gemma4)
		DEFAULT_SERVER_IMAGE="vllm/vllm-openai:v0.24.0"
		DEFAULT_ENGINE="vllm"
		DEFAULT_MODEL="RedHatAI/gemma-4-26B-A4B-it-NVFP4"
		DEFAULT_DRAFT_MODEL="google/gemma-4-26B-A4B-it-assistant"
		DEFAULT_SERVED_MODEL="gemma4"
		DEFAULT_MAX_MODEL_LEN="8192"
		DEFAULT_GPU_MEMORY_UTILIZATION="0.70"
		DEFAULT_MAX_NUM_SEQS="4"
		DEFAULT_MAX_NUM_BATCHED_TOKENS=""
		DEFAULT_CONTAINER_NAME="gemma4-vllm"
		PROFILE_TITLE="Gemma 4 26B-A4B NVFP4 + MTP"
		;;
	glm47flash)
		DEFAULT_SERVER_IMAGE="vllm/vllm-openai:v0.28.0"
		DEFAULT_ENGINE="vllm"
		DEFAULT_MODEL="GadflyII/GLM-4.7-Flash-NVFP4"
		DEFAULT_DRAFT_MODEL=""
		DEFAULT_SERVED_MODEL="glm-4.7-flash"
		DEFAULT_MAX_MODEL_LEN="32768"
		DEFAULT_GPU_MEMORY_UTILIZATION="0.60"
		DEFAULT_MAX_NUM_SEQS="4"
		DEFAULT_MAX_NUM_BATCHED_TOKENS=""
		DEFAULT_CONTAINER_NAME="glm47flash-vllm"
		PROFILE_TITLE="GLM-4.7-Flash NVFP4 (experimental)"
		;;
	muse)
		DEFAULT_SERVER_IMAGE="ghcr.io/nvidia-ai-iot/llama_cpp:latest-jetson-thor"
		DEFAULT_ENGINE="llama.cpp"
		DEFAULT_MODEL="meta-models/Muse-Glimmer-30B-GGUF"
		DEFAULT_DRAFT_MODEL=""
		DEFAULT_SERVED_MODEL="muse-glimmer-30B"
		DEFAULT_MAX_MODEL_LEN="131072"
		DEFAULT_GPU_MEMORY_UTILIZATION=""
		DEFAULT_MAX_NUM_SEQS="1"
		DEFAULT_MAX_NUM_BATCHED_TOKENS=""
		DEFAULT_CONTAINER_NAME="muse-glimmer-llama"
		PROFILE_TITLE="Muse Glimmer 30B K-Quant + DFlash"
		;;
	*)
		echo "Unknown MODEL_PROFILE: $MODEL_PROFILE" >&2
		echo "Expected one of: qwen, qwen36, ornith, nemotron, nemotron35, glm45air, gemma4, glm47flash, muse" >&2
		exit 1
		;;
esac

# VLLM_IMAGE remains a backwards-compatible alias for SERVER_IMAGE.
SERVER_IMAGE="${SERVER_IMAGE:-${VLLM_IMAGE:-$DEFAULT_SERVER_IMAGE}}"
ENGINE="$DEFAULT_ENGINE"
MODEL="${MODEL:-$DEFAULT_MODEL}"
DRAFT_MODEL="${DRAFT_MODEL-$DEFAULT_DRAFT_MODEL}"
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
CONTAINER_NAME="${CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"
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
	--runtime nvidia \
	--network host \
	--ipc=host \
	-v "$HF_CACHE:/root/.cache/huggingface" \
	-v "$VLLM_CACHE:/root/.cache/vllm" \
	"${container_env[@]}" \
	"$SERVER_IMAGE" \
	"$MODEL" \
	"${model_args[@]}"
