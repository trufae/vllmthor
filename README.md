# Qwen3.8 on Jetson AGX Thor

This repository starts a local, OpenAI-compatible [vLLM](https://docs.vllm.ai/)
server on a Jetson AGX Thor. The default setup is tuned for interactive coding
and agent workloads:

- `Inferact/Qwen3.8-27B-NVFP4` as the target model
- `incoai/Qwen3.8-27B-DFlash2` as a speculative-decoding draft model
- NVFP4 model weights and an FP8 KV cache
- 131,072-token context, four concurrent sequences, and prefix caching
- Qwen reasoning and automatic tool-call parsing
- Text-only serving through the OpenAI-compatible API

The server is exposed as `qwen38` at `http://localhost:8000/v1`. Models are
stored in the host Hugging Face cache, so they do not need to be downloaded on
every start.

Three entry points share the setup, download, and Docker logic in `run.sh`:

| Launcher | Model | API model name |
| --- | --- | --- |
| `./run.sh` | Qwen3.8-27B NVFP4 + DFlash2 | `qwen38` |
| `./run-nemotron.sh` | NVIDIA Nemotron Nano 9B v2 NVFP4 | `nemotron` |
| `./run-glm45air.sh` | GLM-4.5-Air NVFP4 (experimental) | `glm-4.5-air` |

## Requirements

- Jetson AGX Thor (`aarch64`) with JetPack 7.2
- Docker with the NVIDIA container runtime working
- Internet access for the first image pull and model download
- Tens of gigabytes of free storage; 50 GB free is a sensible starting point
- A Hugging Face token if a selected model is gated

Check Docker and the NVIDIA runtime before starting:

```bash
docker --version
docker info | grep -i nvidia
```

## Start the server

Make the launcher and cleaner scripts executable once:

```bash
chmod +x run.sh run-nemotron.sh run-glm45air.sh clean.sh
```

Start the server:

```bash
./run.sh
```

The alternative launchers are described under [Changing models](#changing-models).

For a gated model, export a Hugging Face token first:

```bash
export HF_TOKEN=hf_your_token_here
./run.sh
```

The first run pulls the vLLM image, verifies CUDA in the container, downloads
the target and draft models, and then starts the server. Later runs reuse the
Docker image and model cache. Keep the terminal open; press `Ctrl-C` to stop the
server. The server container uses `--rm`, so it is removed when it stops.

Test it from another terminal:

```bash
curl http://localhost:8000/v1/models

curl http://localhost:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "qwen38",
    "messages": [
      {"role": "user", "content": "Write a short CUDA optimization checklist."}
    ],
    "max_tokens": 256
  }'
```

The container uses host networking and listens on `0.0.0.0`. There is no API
key configured, so the service may be reachable from the local network. Use a
firewall or add vLLM's `--api-key` option before exposing it beyond a trusted
network.

## Stop and clean everything

`Ctrl-C` stops the active server but intentionally leaves the image and models
cached for the next start. To remove the container, Docker image, both model
caches, remote-code cache, and Xet download cache, run:

```bash
./clean.sh
```

The Xet cache is shared by Hugging Face repositories. Preserve it when other
cached models may rely on it:

```bash
KEEP_XET_CACHE=1 ./clean.sh
```

The cleaner removes only the configured model repository or repositories from
the Hub cache and leaves unrelated model repositories in place. It also
removes the configured vLLM image, even if another project uses that image tag.

Select the matching profile when cleaning an alternative model:

```bash
MODEL_PROFILE=nemotron ./clean.sh
MODEL_PROFILE=glm45air ./clean.sh
```

If the server was started with overrides, pass the same values to the cleaner:

```bash
MODEL=org/target-model \
DRAFT_MODEL=org/matching-draft-model \
VLLM_IMAGE=some/image:tag \
HF_CACHE=/mnt/nvme/huggingface \
CONTAINER_NAME=custom-vllm \
./clean.sh
```

## Configuration

All three launchers accept these environment variables. The small alternative
launchers select `MODEL_PROFILE` and then execute `run.sh`:

| Variable | Default | Purpose |
| --- | --- | --- |
| `MODEL_PROFILE` | `qwen` | Internal profile: `qwen`, `nemotron`, or `glm45air` |
| `VLLM_IMAGE` | `vllm/vllm-openai:v0.28.0` | Docker image to pull and run |
| `MODEL` | `Inferact/Qwen3.8-27B-NVFP4` | Hugging Face target model |
| `DRAFT_MODEL` | `incoai/Qwen3.8-27B-DFlash2` | Matching DFlash2 draft model |
| `SERVED_MODEL` | `qwen38` | Model name exposed by the API |
| `MAX_MODEL_LEN` | `131072` | Combined prompt and generated-token limit |
| `GPU_MEMORY_UTILIZATION` | `0.35` | Fraction of unified device memory available to vLLM |
| `MAX_NUM_SEQS` | `4` | Maximum sequences processed in one iteration |
| `PORT` | `8000` | OpenAI-compatible API port |
| `HF_CACHE` | `$HOME/.cache/huggingface` | Host model-cache directory |
| `HF_TOKEN` | empty | Optional Hugging Face access token |
| `CONTAINER_NAME` | profile-specific | Docker container name |

The table shows Qwen defaults. Nemotron and GLM select their own model, image,
context, concurrency, memory, API name, and container defaults before applying
any explicit environment overrides.

Multiple overrides can be combined on one command:

```bash
MAX_MODEL_LEN=65536 MAX_NUM_SEQS=2 PORT=8080 ./run.sh
```

## Thor tuning tricks

### Change the context size

Context includes both input and output tokens. A smaller limit leaves more KV
cache headroom, normally starts more easily, and is a good choice when prompts
are not enormous:

```bash
# Lightweight interactive profile
MAX_MODEL_LEN=32768 MAX_NUM_SEQS=1 ./run.sh

# Balanced long-context profile
MAX_MODEL_LEN=65536 MAX_NUM_SEQS=2 ./run.sh
```

Current vLLM versions can profile memory and select the largest context that
fits:

```bash
MAX_MODEL_LEN=auto MAX_NUM_SEQS=1 ./run.sh
```

Qwen3.8's model configuration supports up to 262,144 tokens. Trying the full
window needs substantially more KV-cache memory; reduce concurrency and raise
the vLLM memory fraction gradually on an otherwise idle board:

```bash
MAX_MODEL_LEN=262144 MAX_NUM_SEQS=1 GPU_MEMORY_UTILIZATION=0.50 ./run.sh
```

Treat `0.50` as an experiment, not a guaranteed fit. Jetson Thor uses unified
memory for the OS, applications, model weights, CUDA graphs, and KV cache. If
the process is killed or CUDA reports an out-of-memory error, lower the context
or concurrency before raising the memory fraction further.

### Tune latency versus throughput

- `MAX_NUM_SEQS=1` favors one interactive user and minimizes per-request/CUDA
  graph capacity.
- `MAX_NUM_SEQS=4` is the repository's balanced default for one user plus a few
  agent requests.
- `MAX_NUM_SEQS=8` may improve throughput for concurrent clients but consumes
  more memory and can increase latency for an individual request.
- Prefix caching is already enabled. It is most useful when requests reuse an
  identical system prompt or other long prefix.
- DFlash2 is already enabled with seven speculative tokens. It uses extra
  memory for the 2B draft model in exchange for faster target-model decoding.

Only change one setting at a time and watch the board while testing:

```bash
sudo tegrastats
```

### Use fast storage for the model cache

Putting the Hugging Face cache on a fast NVMe drive improves downloads and
model load time and keeps the root filesystem free:

```bash
HF_CACHE=/mnt/nvme/huggingface ./run.sh
```

Use the same `HF_CACHE` value with `clean.sh` later.

### Select the power mode before benchmarking

Inspect the active mode first:

```bash
sudo /usr/sbin/nvpmodel -q
```

On a T5000 development kit, mode `1` is NVIDIA's sustained 120 W profile and
mode `0` is experimental MAXN. MAXN is not guaranteed to be faster under every
workload and NVIDIA does not recommend prolonged heavy use in that mode. After
choosing a suitable power mode, clocks and cooling can be pinned for a short,
controlled benchmark:

```bash
sudo /usr/bin/jetson_clocks --fan
```

Run the power-mode command before `jetson_clocks`; changing power modes after
clocks have been pinned requires a reboot. Restore the previous clock settings
with:

```bash
sudo /usr/bin/jetson_clocks --restore
```

## Changing models

Changing only `MODEL` is safe only when the replacement is compatible with the
Qwen3.8 DFlash2 draft, tokenizer, reasoning parser, and tool parser. Arbitrary
models need their own launch flags and must not use the Qwen draft model.

### Another Qwen3.8 NVFP4 checkpoint

NVIDIA publishes a smaller, mixed-precision `nvidia/Qwen3.8-27B-NVFP4`
checkpoint. It is based on the same Qwen3.8-27B model, so it is the most natural
target-model experiment with this launcher:

```bash
MODEL=nvidia/Qwen3.8-27B-NVFP4 ./run.sh
```

Clean that checkpoint by repeating the override:

```bash
MODEL=nvidia/Qwen3.8-27B-NVFP4 ./clean.sh
```

Quantized checkpoints can differ in kernel coverage and output quality, so
compare correctness and throughput before replacing the default permanently.

### Nemotron: the safest alternative family for Thor

`nvidia/NVIDIA-Nemotron-Nano-9B-v2-NVFP4` is a 128K reasoning/chat model whose
official model card explicitly lists Jetson AGX Thor as tested hardware. It is
much smaller than the default Qwen target and is a good option when latency and
memory headroom matter more than maximum model capacity.

It is not a drop-in `MODEL=... ./run.sh` replacement because it must not inherit
Qwen's draft and parser flags. The wrapper selects the Nemotron profile in
`run.sh`, skips the draft download, and enables the float32 Mamba SSM cache
required by the model card:

```bash
./run-nemotron.sh
```

The usual tuning overrides still work:

```bash
MAX_MODEL_LEN=65536 MAX_NUM_SEQS=2 PORT=8080 ./run-nemotron.sh
```

For Nemotron tool calling, follow its model card: the parser is a Python plugin
shipped in the model repository rather than vLLM's Qwen parser. Clean the model
and shared image afterward with:

```bash
MODEL_PROFILE=nemotron ./clean.sh
```

### GLM: possible, but experimental on Thor

The community `Firworks/GLM-4.5-Air-nvfp4` checkpoint is the most plausible
single-Thor GLM experiment found: it uses NVFP4 and its model card includes a
single-device DGX Spark recipe. The card says it was tested on B200, not Jetson
Thor, so kernel compatibility, memory use, and performance are not guaranteed.
The GLM wrapper selects its nightly image, FlashInfer MoE FP4 kernel, GLM
reasoning/tool parsers, eager execution, a 32K context, and one sequence:

```bash
./run-glm45air.sh
```

If it fails during model loading, do not keep increasing the memory fraction
until the OS starts swapping; use the Nemotron option or return to Qwen. Newer
official NVIDIA GLM-5.x NVFP4 checkpoints are hundreds of gigabytes and do not
fit in a single 128 GB Thor.

To clean this experiment, select the matching profile:

```bash
MODEL_PROFILE=glm45air ./clean.sh
```

## Troubleshooting

### Docker cannot see NVIDIA

Confirm that `docker info` reports the NVIDIA runtime. Reinstall or repair the
JetPack/NVIDIA container runtime before changing vLLM settings.

### CUDA out of memory or the process is killed

Try, in order:

1. Lower `MAX_MODEL_LEN`.
2. Set `MAX_NUM_SEQS=1`.
3. Close other GPU and memory-heavy applications.
4. Lower `GPU_MEMORY_UTILIZATION` if the OS is under memory pressure.
5. Only then raise it slightly if vLLM itself reports that the requested model
   or KV cache cannot fit inside its configured fraction.

### Port 8000 is already in use

```bash
PORT=8080 ./run.sh
```

Because host networking is used, no Docker `-p` mapping is needed.

### Startup appears stuck

The first run downloads tens of gigabytes. Check storage and network activity,
and inspect the cache size in another terminal:

```bash
du -sh "${HF_CACHE:-$HOME/.cache/huggingface}"
```

## References

- [vLLM serve options](https://docs.vllm.ai/en/latest/cli/serve/)
- [Jetson Thor power and performance guide](https://docs.nvidia.com/jetson/archives/r38.4/DeveloperGuide/SD/PlatformPowerAndPerformance/JetsonThor.html)
- [Default Qwen3.8 NVFP4 checkpoint](https://huggingface.co/Inferact/Qwen3.8-27B-NVFP4)
- [NVIDIA Qwen3.8 NVFP4 checkpoint](https://huggingface.co/nvidia/Qwen3.8-27B-NVFP4)
- [Qwen3.8 DFlash2 draft model](https://huggingface.co/incoai/Qwen3.8-27B-DFlash2)
- [NVIDIA Nemotron Nano 9B v2 NVFP4](https://huggingface.co/nvidia/NVIDIA-Nemotron-Nano-9B-v2-NVFP4)
- [Experimental GLM-4.5-Air NVFP4 checkpoint](https://huggingface.co/Firworks/GLM-4.5-Air-nvfp4)

Alternative-model notes were last checked on 2026-09-27. Model cards and vLLM
flags evolve quickly; recheck the linked model card before downloading a large
checkpoint.
