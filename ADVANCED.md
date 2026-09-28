# Advanced configuration and tuning

This guide contains the model-specific details and tuning options for the
launchers documented in the [README](README.md). The defaults are intended to
start reliably; change one setting at a time and compare both speed and output
quality.

## Hardware assumptions

The target tested here is the 128 GB Jetson AGX Thor Developer Kit. NVIDIA
specifies a Blackwell GPU, 128 GB of unified LPDDR5X at 273 GB/s, native FP4
acceleration, and a power envelope up to 130 W.

Unified memory means model weights, KV cache, CUDA graphs, the OS, and other
applications use the same pool. A 20 GB model download can require much more
than 20 GB while serving.

## Configuration variables

Every launcher selects a profile and then executes `run.sh`. Environment
variables override that profile's defaults:

| Variable | Qwen3.8 default | Purpose |
| --- | --- | --- |
| `MODEL_PROFILE` | `qwen` | Internal profile selected by the wrapper |
| `SERVER_IMAGE` | `vllm/vllm-openai:v0.28.0` | Profile-specific Docker image |
| `MODEL` | `Inferact/Qwen3.8-27B-NVFP4` | Hugging Face target repository |
| `DRAFT_MODEL` | `incoai/Qwen3.8-27B-DFlash2` | Matching speculative-draft repository |
| `SERVED_MODEL` | `qwen38` | Model name exposed by the API |
| `MAX_MODEL_LEN` | `131072` | Combined prompt and output-token limit |
| `GPU_MEMORY_UTILIZATION` | `0.35` | Unified-memory fraction available to vLLM |
| `MAX_CONCURRENT_REQUESTS` | `4` | Active generation slots (`--max-num-seqs`) |
| `MAX_NUM_SEQS` | unset | Backwards-compatible alias for `MAX_CONCURRENT_REQUESTS` |
| `PORT` | `8000` | OpenAI-compatible API port |
| `HF_CACHE` | `$HOME/.cache/huggingface` | Host model-cache directory |
| `HF_TOKEN` | empty | Optional Hugging Face access token |
| `CONTAINER_NAME` | profile-specific | Docker container name |
| `MUSE_MODEL_FILE` | `Muse-Glimmer-30B-KQuant-17GB-Q4_K_M.gguf` | Muse GGUF target selected by llama.cpp |

The table shows the default Qwen3.8 values. Each wrapper selects its own model,
draft, image, context, concurrency, memory fraction, and container name before
applying overrides. `GPU_MEMORY_UTILIZATION` is ignored by Muse because that
profile uses llama.cpp. The older `VLLM_IMAGE` variable remains accepted as an
alias for `SERVER_IMAGE`.

Multiple overrides can be combined:

```bash
MAX_MODEL_LEN=65536 MAX_CONCURRENT_REQUESTS=2 PORT=8080 ./run.sh
```

## Context and concurrency

A smaller context leaves more KV-cache headroom and usually starts more
reliably:

```bash
# Interactive, low-memory configuration
MAX_MODEL_LEN=32768 MAX_CONCURRENT_REQUESTS=1 ./run.sh

# Balanced long-context configuration
MAX_MODEL_LEN=65536 MAX_CONCURRENT_REQUESTS=2 ./run.sh
```

Current vLLM versions can profile memory and select the largest context that
fits:

```bash
MAX_MODEL_LEN=auto MAX_CONCURRENT_REQUESTS=1 ./run.sh
```

Qwen3.8 supports up to 262,144 tokens. Trying the full window requires
substantially more KV-cache memory:

```bash
MAX_MODEL_LEN=262144 MAX_CONCURRENT_REQUESTS=1 \
GPU_MEMORY_UTILIZATION=0.50 ./run.sh
```

Treat that memory fraction as an experiment. If the process is killed or CUDA
reports an out-of-memory error, lower context or concurrency before raising the
fraction further.

vLLM's HTTP server can accept more requests than this setting. It queues
requests beyond the active slots; `MAX_CONCURRENT_REQUESTS` controls how many
sequences can be processed in one scheduler iteration, not the number of TCP
connections. The pinned vLLM profiles do not impose a separate hard queue
limit.

For latency and throughput:

- `MAX_CONCURRENT_REQUESTS=1` favors one interactive request and reduces graph
  capacity.
- `MAX_CONCURRENT_REQUESTS=4` is the default for all regular vLLM profiles.
- `MAX_CONCURRENT_REQUESTS=8` may improve aggregate throughput but uses more
  memory and can increase individual-request latency.
- Prefix caching is already enabled and helps when requests share a long,
  identical prefix.
- Speculative decoding uses extra memory for a draft model in exchange for
  faster target-model decoding.

Muse is different: llama.cpp divides `--ctx-size` across its parallel slots.
The default is one 131,072-token slot. Four parallel clients receive roughly
32K tokens each:

```bash
MAX_CONCURRENT_REQUESTS=4 ./run-muse-glimmer.sh
```

## Storage and downloads

Put the Hugging Face cache on a fast NVMe drive to improve download and model
load times:

```bash
HF_CACHE=/mnt/nvme/huggingface ./run.sh
```

Use the same value when cleaning:

```bash
HF_CACHE=/mnt/nvme/huggingface ./clean.sh
```

Download sizes in the README are decimal GB and exclude the Docker image,
Hugging Face/Xet metadata, KV cache, CUDA graphs, and runtime allocations. A
plus sign separates target, projector, or speculative-draft artifacts. Muse's
19.8 GB total includes the selected 17 GB target, vision projector, and DFlash
drafter rather than every quantization in its 39.4 GB repository.

## Power and benchmarking

Inspect the active mode before benchmarking:

```bash
sudo /usr/sbin/nvpmodel -q
```

On the T5000 development kit, mode `1` is NVIDIA's sustained 120 W profile and
mode `0` is experimental MAXN. MAXN is not guaranteed to be faster under every
workload and is not recommended for prolonged heavy use. For a short,
controlled benchmark, choose the power mode first and then pin clocks and
cooling:

```bash
sudo /usr/bin/jetson_clocks --fan
sudo tegrastats
```

Changing power modes after clocks have been pinned requires a reboot. Restore
the previous clock settings with:

```bash
sudo /usr/bin/jetson_clocks --restore
```

The speeds in the README are published output/decode figures, not a controlled
comparison across every model. Qwen3.8 and Nemotron Lightning are NVIDIA
Jetson workload ranges. Qwen3.6 is a community single-Thor, 120 W,
concurrency-1 coding result. Nemotron Nano and Gemma 4 are NVIDIA Thor T5000
vLLM results; Gemma's concurrency-8 value is aggregate throughput. Muse is
NVIDIA's “up to” result with DFlash. Prompt length, output length, power mode,
software version, and speculative-token acceptance all affect performance.

There is no defensible published Thor result for either GLM profile, so no
estimate is presented as a benchmark.

## Benchmark script

`bench.sh` sends four sequential chat-completion requests through curl. It
auto-detects the first model returned by `/v1/models`, performs one warm-up
request, and reads `usage.prompt_tokens` and `usage.completion_tokens` from
each response.

```bash
./bench.sh
```

The reported rate is:

```text
completion_tokens / curl time_total
```

This is end-to-end output throughput. It includes HTTP handling, prompt
prefill, and generation, so it is more representative of client-observed speed
than raw decode throughput. The standard OpenAI response provides token counts
but not a portable per-request decode timer. Using curl timing also keeps the
script compatible with the llama.cpp Muse profile.

Available overrides:

| Variable | Default | Purpose |
| --- | --- | --- |
| `BASE_URL` | `http://localhost:8000/v1` | OpenAI-compatible API base URL |
| `MODEL` | auto-detected | API model name to request |
| `API_KEY` | empty | Optional bearer token |
| `RUNS` | `1` | Repetitions of each of the four prompts |
| `MAX_TOKENS` | `256` | Maximum completion tokens per request |
| `TEMPERATURE` | `0` | Sampling temperature |
| `REQUEST_TIMEOUT` | `600` | Curl timeout in seconds |
| `WARMUP` | `1` | Set to `0` to skip the warm-up request |

Examples:

```bash
RUNS=3 MAX_TOKENS=512 ./bench.sh
MODEL=gemma4 ./bench.sh
BASE_URL=http://192.168.1.20:8000/v1 ./bench.sh
```

For comparable results, keep power mode, clocks, context size, concurrency,
and background load constant. The script is sequential and measures
single-request behavior; it does not measure multi-client aggregate
throughput.

## Model-specific notes

### Bonsai 2 status

Bonsai 2 is attractive for Thor: the official 27B ternary model is only 5.95
GB in PTQ1_0 or 7.21 GB in PQ2_0, and Prism recommends PQ2_0 for Blackwell.
However, it is not currently a drop-in model for either runtime in this
repository:

- The GGUF files require Prism ML's llama.cpp fork. Stock llama.cpp rejects the
  fork-specific formats, so NVIDIA's standard Thor llama.cpp image cannot load
  them.
- Prism's prebuilt matrix includes Linux ARM64 CPU and Linux x64 CUDA, but not
  Linux ARM64 CUDA. Thor would currently require an unvalidated source build of
  the custom CUDA runtime.
- The separate Bonsai 2 vLLM plugin requires vLLM 0.29.0 and has only been
  validated on Linux x86_64 with one A100 and one executing request. Its own
  documentation says simultaneous GPU batching is not validated.

For those reasons there is no `run-bonsai2.sh` yet. Merely pointing `MODEL` at
the repository would either fail to load or use the wrong kernels. Once Prism
publishes a Linux ARM64 CUDA build or confirms the vLLM plugin on Jetson Thor,
the 7.21 GB PQ2_0 path is the first one to revisit. There is currently no
published Thor tokens/s result.

### Qwen3.8-27B

The default profile uses an NVFP4 target, FP8 KV cache, DFlash2 with seven
speculative tokens, a 131K context, and four sequences. It is text-only even if
a compatible target repository contains multimodal components.

NVIDIA also publishes `nvidia/Qwen3.8-27B-NVFP4`. It is compatible enough to
test as a target override:

```bash
MODEL=nvidia/Qwen3.8-27B-NVFP4 ./run.sh
MODEL=nvidia/Qwen3.8-27B-NVFP4 ./clean.sh
```

Compare both correctness and throughput before changing the permanent default.

### Qwen3.6-35B-A3B

This profile uses NVIDIA's NVFP4 target and the matching Z-Lab DFlash draft.
The Thor configuration uses Marlin MoE, FlashAttention, a 65K context, four
sequences, and 12 speculative tokens. Its draft KV cache stays at `auto`
because quantized draft KV has caused compatibility failures in tested builds.

```bash
./run-qwen36.sh
```

It is configured for text-only serving. A community single-Thor configuration
reported 116.5 output tok/s averaged across four coding workloads and a 139.1
tok/s peak.

### Nemotron Nano 9B v2

The official model card lists Jetson AGX Thor as tested hardware. This is the
smallest profile and is useful when latency and memory headroom matter most.
The runner enables the float32 Mamba SSM cache required by the model card.

```bash
MAX_MODEL_LEN=65536 MAX_CONCURRENT_REQUESTS=2 ./run-nemotron.sh
```

Its tool-call parser is a Python plugin shipped in the model repository rather
than the Qwen parser.

### Nemotron 3.5 Lightning

This profile follows NVIDIA's Jetson recipe: NVFP4 target, matching DSpark
draft, FP8 KV cache, Marlin MoE, FlashInfer Mamba, stochastic rounding, and the
Nemotron reasoning parser. It defaults to a 128K context and four sequences.

```bash
MAX_MODEL_LEN=65536 MAX_CONCURRENT_REQUESTS=1 ./run-nemotron-lightning.sh
```

NVIDIA measured 123.01–138.02 output tok/s across representative writing,
reasoning, summarization, and RAG workloads.

### Gemma 4 26B-A4B

This is the useful high-end Gemma 4 choice for Thor: it has roughly 25.8B total
parameters but activates about 3.8B per token. The profile follows NVIDIA
Jetson AI Lab's Thor recipe with the Red Hat NVFP4 target, Google's 0.87 GB MTP
assistant, Gemma reasoning and tool parsers, and thinking enabled in the chat
template.

The model supports text and images and advertises a 256K context, but the
launcher starts with NVIDIA's validated 8K setting:

```bash
MAX_MODEL_LEN=32768 MAX_CONCURRENT_REQUESTS=1 ./run-gemma4.sh
```

Access to Google's assistant repository may require accepting its Hugging Face
terms and exporting `HF_TOKEN`. NVIDIA reports 50 output tok/s at concurrency
1 and 180 aggregate tok/s at concurrency 8 on its Thor T5000 workload.

### Muse Glimmer 30B

Muse uses NVIDIA's Thor-optimized llama.cpp container instead of vLLM. The
profile loads Meta's 16.8 GB K-Quant target and automatically discovers the
vision projector and DFlash drafter in the same repository. NVIDIA reports up
to 36 output tok/s on Thor with DFlash.

Reasoning is always active. Add one of these lines to the system prompt to
control its depth:

```text
Reasoning strength: low
Reasoning strength: medium
Reasoning strength: high
Reasoning strength: xhigh
```

The launcher uses port 8000 for consistency with the vLLM profiles, although a
standalone llama.cpp server commonly defaults to 8080.

### GLM-4.7-Flash

`GadflyII/GLM-4.7-Flash-NVFP4` is a community mixed-precision quantization of
the 30B-A3B model. Feed-forward experts use FP4 while attention remains BF16.
The checkpoint is about 20.5 GB and targets vLLM on Blackwell-class GPUs, but
this exact build has no published Jetson Thor validation.

The profile uses the GLM 4.7 tool parser, GLM 4.5 reasoning parser, its built-in
one-token MTP head, and disables the unsupported FlashInfer FP4 MoE path on
Thor's SM110a GPU. It starts at 32K context:

```bash
MAX_MODEL_LEN=65536 MAX_CONCURRENT_REQUESTS=1 ./run-glm47flash.sh
```

Treat it as experimental until it passes representative prompts, tool calls,
and sustained-load testing on the board.

### GLM-4.5-Air

`Firworks/GLM-4.5-Air-nvfp4` is a community checkpoint whose model card
contains a single-device DGX Spark recipe. It was tested on B200 rather than
Jetson Thor, so kernel compatibility, memory use, and speed are not guaranteed.
The profile starts eagerly at 32K context and two active sequences.

If it fails while loading, avoid repeatedly raising the memory fraction until
the OS swaps. Use GLM-4.7-Flash, Nemotron, or Qwen instead.

## Advanced cleanup

`clean.sh` removes the selected profile's container, server image, model
repository caches, remote-code cache, and shared Xet cache. The Xet cache can
be shared by unrelated Hugging Face repositories; preserve it when needed:

```bash
KEEP_XET_CACHE=1 ./clean.sh
```

If the server was launched with overrides, pass the same values to the cleaner:

```bash
MODEL=org/target-model \
DRAFT_MODEL=org/matching-draft-model \
SERVER_IMAGE=some/image:tag \
HF_CACHE=/mnt/nvme/huggingface \
CONTAINER_NAME=custom-server \
./clean.sh
```

The cleaner removes only the selected Hugging Face model repositories, but it
does remove the selected Docker image even if another project uses the same
tag.

## Network exposure

The containers use host networking and listen on `0.0.0.0`. No API key is
configured, so the service may be reachable from the LAN. Use a firewall or
add the server's API-key option before exposing it beyond a trusted network.

## Troubleshooting

### Docker cannot see NVIDIA

Confirm that `docker info` reports the NVIDIA runtime. Repair the JetPack or
NVIDIA container-runtime installation before changing model settings.

### CUDA runs out of memory or the process is killed

Try, in order:

1. Lower `MAX_MODEL_LEN`.
2. Set `MAX_CONCURRENT_REQUESTS=1`.
3. Close other GPU and memory-heavy applications.
4. Lower `GPU_MEMORY_UTILIZATION` if the OS is under memory pressure.
5. Raise it slightly only if vLLM reports that its configured fraction is too
   small while the rest of the system has enough free memory.

### Port 8000 is already in use

```bash
PORT=8080 ./run.sh
```

Host networking means no Docker `-p` mapping is required.

### Startup appears stuck

The first run can download tens of gigabytes. Check storage and network
activity, and inspect the cache size from another terminal:

```bash
du -sh "${HF_CACHE:-$HOME/.cache/huggingface}"
```

## References

- [NVIDIA Jetson Thor specifications](https://www.nvidia.com/en-us/autonomous-machines/embedded-systems/jetson-thor/)
- [Jetson Thor power and performance guide](https://docs.nvidia.com/jetson/archives/r38.4/DeveloperGuide/SD/PlatformPowerAndPerformance/JetsonThor.html)
- [vLLM serve options](https://docs.vllm.ai/en/latest/cli/serve/)
- [vLLM 0.28 `max-num-seqs` documentation](https://docs.vllm.ai/en/v0.28.0/cli/serve/)
- [Jetson AI Lab benchmark data](https://github.com/NVIDIA-AI-IOT/jetson-ai-lab/blob/main/src/data/benchmarks.json)
- [Default Qwen3.8 NVFP4 checkpoint](https://huggingface.co/Inferact/Qwen3.8-27B-NVFP4)
- [NVIDIA Qwen3.8 NVFP4 checkpoint](https://huggingface.co/nvidia/Qwen3.8-27B-NVFP4)
- [Qwen3.8 DFlash2 draft](https://huggingface.co/incoai/Qwen3.8-27B-DFlash2)
- [NVIDIA Qwen3.6-35B-A3B NVFP4](https://huggingface.co/nvidia/Qwen3.6-35B-A3B-NVFP4)
- [Qwen3.6 DFlash draft](https://huggingface.co/z-lab/Qwen3.6-35B-A3B-DFlash)
- [Thor Qwen3.6 deployment notes](https://huggingface.co/patrickbdevaney/qwen-3.6-35b-a3b-dflash-jetson-agx-thor)
- [NVIDIA Nemotron Nano 9B v2 NVFP4](https://huggingface.co/nvidia/NVIDIA-Nemotron-Nano-9B-v2-NVFP4)
- [NVIDIA Nemotron 3.5 Lightning NVFP4](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4)
- [NVIDIA Jetson reasoning-model deployment guide](https://developer.nvidia.com/blog/frontier-reasoning-reaches-the-edge-how-to-deploy-and-optimize-models-on-nvidia-jetson/)
- [Jetson AI Lab Gemma 4 recipe](https://github.com/NVIDIA-AI-IOT/jetson-ai-lab/blob/main/src/content/models/gemma4-26b-a4b.md)
- [Gemma 4 NVFP4 checkpoint](https://huggingface.co/RedHatAI/gemma-4-26B-A4B-it-NVFP4)
- [Gemma 4 MTP assistant](https://huggingface.co/google/gemma-4-26B-A4B-it-assistant)
- [Jetson AI Lab Muse Glimmer recipe](https://www.jetson-ai-lab.com/models/muse-glimmer-30b/)
- [Official Muse Glimmer GGUF repository](https://huggingface.co/meta-models/Muse-Glimmer-30B-GGUF)
- [GLM-4.7-Flash model card](https://huggingface.co/zai-org/GLM-4.7-Flash)
- [Experimental GLM-4.7-Flash NVFP4 checkpoint](https://huggingface.co/GadflyII/GLM-4.7-Flash-NVFP4)
- [Experimental GLM-4.5-Air NVFP4 checkpoint](https://huggingface.co/Firworks/GLM-4.5-Air-nvfp4)
- [Official Bonsai 2 GGUF model](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf)
- [Prism ML Bonsai demo and runtime matrix](https://github.com/PrismML-Eng/Bonsai-demo)
- [Experimental Bonsai 2 vLLM plugin](https://github.com/wonder-dot-ai/bonsai2-vllm-plugin)

Model cards and runtime flags were last checked on 2026-09-28. Recheck the
linked source before downloading a large checkpoint after upgrading vLLM or
JetPack.
