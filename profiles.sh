#!/usr/bin/env bash
# Shared profile defaults and overrides for the server management scripts.

SERVER_LABEL="vllmqwen.profile"
MODEL_PROFILES=(qwen qwen36 ornith nemotron nemotron35 glm45air gemma4 glm47flash lfm25 muse)

load_profile() {
	MODEL_PROFILE="${1:-qwen}"

	DEFAULT_SERVER_IMAGE="vllm/vllm-openai:v0.32.0"
	DEFAULT_ENGINE="vllm"
	DEFAULT_DRAFT_MODEL=""
	DEFAULT_SERVED_MODEL="$MODEL_PROFILE"
	DEFAULT_MAX_MODEL_LEN="131072"
	DEFAULT_GPU_MEMORY_UTILIZATION="0.35"
	DEFAULT_MAX_NUM_SEQS="4"
	DEFAULT_MAX_NUM_BATCHED_TOKENS=""
	DEFAULT_CONTAINER_NAME="$MODEL_PROFILE-vllm"

	case "$MODEL_PROFILE" in
		qwen)
			DEFAULT_MODEL="Inferact/Qwen3.8-27B-NVFP4"
			DEFAULT_DRAFT_MODEL="incoai/Qwen3.8-27B-DFlash2"
			DEFAULT_SERVED_MODEL="qwen38"
			DEFAULT_CONTAINER_NAME="qwen38-vllm"
			PROFILE_TITLE="Qwen3.8-27B NVFP4 + DFlash2"
			;;
		qwen36)
			DEFAULT_MODEL="nvidia/Qwen3.6-35B-A3B-NVFP4"
			DEFAULT_DRAFT_MODEL="z-lab/Qwen3.6-35B-A3B-DFlash"
			DEFAULT_MAX_MODEL_LEN="65536"
			DEFAULT_GPU_MEMORY_UTILIZATION="0.78"
			PROFILE_TITLE="Qwen3.6-35B-A3B NVFP4 + DFlash"
			;;
		ornith)
			DEFAULT_MODEL="ornith-ai/Ornith-1.5-35B-A3B-NVFP4"
			DEFAULT_DRAFT_MODEL="ornith-ai/Ornith-1.5-35B-A3B-DFlash"
			DEFAULT_MAX_MODEL_LEN="65536"
			DEFAULT_GPU_MEMORY_UTILIZATION="0.78"
			DEFAULT_MAX_NUM_BATCHED_TOKENS="8192"
			PROFILE_TITLE="Ornith 1.5 35B-A3B NVFP4 + DFlash"
			;;
		nemotron)
			DEFAULT_MODEL="nvidia/NVIDIA-Nemotron-Nano-9B-v2-NVFP4"
			PROFILE_TITLE="NVIDIA Nemotron Nano NVFP4"
			;;
		nemotron35)
			DEFAULT_MODEL="nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4"
			DEFAULT_DRAFT_MODEL="nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4-DSpark"
			DEFAULT_MAX_MODEL_LEN="128000"
			DEFAULT_GPU_MEMORY_UTILIZATION="0.70"
			DEFAULT_MAX_NUM_BATCHED_TOKENS="16384"
			PROFILE_TITLE="NVIDIA Nemotron 3.5 Lightning NVFP4 + DSpark"
			;;
		glm45air)
			DEFAULT_MODEL="Firworks/GLM-4.5-Air-nvfp4"
			DEFAULT_SERVED_MODEL="glm-4.5-air"
			DEFAULT_MAX_MODEL_LEN="32768"
			DEFAULT_GPU_MEMORY_UTILIZATION="0.50"
			DEFAULT_MAX_NUM_SEQS="2"
			PROFILE_TITLE="GLM-4.5-Air NVFP4 (experimental)"
			;;
		gemma4)
			DEFAULT_MODEL="RedHatAI/gemma-4-26B-A4B-it-NVFP4"
			DEFAULT_DRAFT_MODEL="google/gemma-4-26B-A4B-it-assistant"
			DEFAULT_MAX_MODEL_LEN="8192"
			DEFAULT_GPU_MEMORY_UTILIZATION="0.70"
			PROFILE_TITLE="Gemma 4 26B-A4B NVFP4 + MTP"
			;;
		glm47flash)
			DEFAULT_MODEL="GadflyII/GLM-4.7-Flash-NVFP4"
			DEFAULT_SERVED_MODEL="glm-4.7-flash"
			DEFAULT_MAX_MODEL_LEN="32768"
			DEFAULT_GPU_MEMORY_UTILIZATION="0.60"
			PROFILE_TITLE="GLM-4.7-Flash NVFP4 (experimental)"
			;;
		lfm25)
			DEFAULT_MODEL="LiquidAI/LFM2.5-24B-A2B-FP8"
			DEFAULT_GPU_MEMORY_UTILIZATION="0.40"
			DEFAULT_MAX_NUM_BATCHED_TOKENS="8192"
			PROFILE_TITLE="LFM2.5 24B-A2B FP8 (experimental)"
			;;
		muse)
			DEFAULT_SERVER_IMAGE="ghcr.io/nvidia-ai-iot/llama_cpp:latest-jetson-thor"
			DEFAULT_ENGINE="llama.cpp"
			DEFAULT_MODEL="meta-models/Muse-Glimmer-30B-GGUF"
			DEFAULT_SERVED_MODEL="muse-glimmer-30B"
			DEFAULT_GPU_MEMORY_UTILIZATION=""
			DEFAULT_MAX_NUM_SEQS="1"
			DEFAULT_CONTAINER_NAME="muse-glimmer-llama"
			PROFILE_TITLE="Muse Glimmer 30B K-Quant + DFlash"
			;;
		*)
			echo "Unknown MODEL_PROFILE: $MODEL_PROFILE" >&2
			local supported
			printf -v supported '%s, ' "${MODEL_PROFILES[@]}"
			echo "Expected one of: ${supported%, }" >&2
			return 1
			;;
	esac

	# VLLM_IMAGE remains a backwards-compatible alias for SERVER_IMAGE.
	SERVER_IMAGE="${SERVER_IMAGE:-${VLLM_IMAGE:-$DEFAULT_SERVER_IMAGE}}"
	MODEL="${MODEL:-$DEFAULT_MODEL}"
	DRAFT_MODEL="${DRAFT_MODEL-$DEFAULT_DRAFT_MODEL}"
	CONTAINER_NAME="${CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"
}
