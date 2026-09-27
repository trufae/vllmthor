# Local LLMs on Jetson AGX Thor

Run optimized language models locally on the 128 GB Jetson AGX Thor Developer
Kit. The scripts start an OpenAI-compatible API using vLLM or NVIDIA's
Thor-optimized llama.cpp container, download the required models, and reuse the
Hugging Face cache between launches.

The default is Qwen3.8-27B with DFlash2 speculative decoding.

## Available models

| Start command | Model | Download | Published Thor speed |
| --- | --- | ---: | ---: |
| `./run.sh` | Qwen3.8-27B NVFP4 + DFlash2 | **30.3 GB** | **27.69–34.44 tok/s** |
| `./run-qwen38.sh` | Qwen3.8-27B NVFP4 + DFlash2 | **30.3 GB** | **27.69–34.44 tok/s** |
| `./run-qwen36.sh` | Qwen3.6-35B-A3B NVFP4 + DFlash | **24.3 GB** | **116.5 average; 139.1 peak tok/s** |
| `./run-nemotron.sh` | Nemotron Nano 9B v2 NVFP4 | **7.85 GB** | **30 tok/s** |
| `./run-nemotron-lightning.sh` | Nemotron 3.5 Lightning NVFP4 + DSpark | **23.0 GB** | **123.01–138.02 tok/s** |
| `./run-gemma4.sh` | Gemma 4 26B-A4B NVFP4 + MTP | **17.3 GB** | **50 tok/s** c1; **180 tok/s** aggregate c8 |
| `./run-muse-glimmer.sh` | Muse Glimmer 30B K-Quant + DFlash | **19.8 GB** | **up to 36 tok/s** |
| `./run-glm47flash.sh` | GLM-4.7-Flash 30B-A3B NVFP4 | **20.5 GB** | Not published for Thor |
| `./run-glm45air.sh` | GLM-4.5-Air NVFP4 | **62 GB** | Not published for Thor |

The GLM profiles are experimental because their exact checkpoints have not
been validated or benchmarked on Jetson Thor. Published speeds come from
different workloads and are not a controlled head-to-head comparison.

See [Advanced configuration and tuning](ADVANCED.md) for model details,
context tuning, benchmark notes, power settings, and troubleshooting.

## Requirements

- Jetson AGX Thor with JetPack 7.2
- Docker with the NVIDIA container runtime
- Internet access for the first image and model download
- At least 50 GB of free storage for most profiles
- A Hugging Face token when a selected repository is gated

Check Docker before starting:

```bash
docker --version
docker info | grep -i nvidia
```

## Start

Make the scripts executable once:

```bash
chmod +x run*.sh clean.sh
```

Start the default model:

```bash
./run.sh
```

Or select another model from the table, for example:

```bash
./run-gemma4.sh
./run-muse-glimmer.sh
./run-glm47flash.sh
```

For a gated model:

```bash
export HF_TOKEN=hf_your_token_here
./run-gemma4.sh
```

The first run pulls the server image and downloads the model. Later runs reuse
the local cache. Keep the terminal open and press `Ctrl-C` to stop the server.

## Test the API

The default endpoint is `http://localhost:8000/v1`:

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

The API model name changes with the launcher. Query `/v1/models` to see the
active name.

## Common options

Use a shorter context or a different port:

```bash
MAX_MODEL_LEN=32768 MAX_NUM_SEQS=1 ./run.sh
PORT=8080 ./run.sh
```

Store models on NVMe:

```bash
HF_CACHE=/mnt/nvme/huggingface ./run.sh
```

All available overrides and model-specific recommendations are in
[ADVANCED.md](ADVANCED.md).

## Clean

`Ctrl-C` stops the server but keeps the image and model for the next run.
Remove everything created for the default profile with:

```bash
./clean.sh
```

Select the profile used by an alternative launcher:

```bash
MODEL_PROFILE=qwen36 ./clean.sh
MODEL_PROFILE=nemotron ./clean.sh
MODEL_PROFILE=nemotron35 ./clean.sh
MODEL_PROFILE=gemma4 ./clean.sh
MODEL_PROFILE=muse ./clean.sh
MODEL_PROFILE=glm47flash ./clean.sh
MODEL_PROFILE=glm45air ./clean.sh
```

Use the same cache path when one was supplied at startup:

```bash
HF_CACHE=/mnt/nvme/huggingface MODEL_PROFILE=gemma4 ./clean.sh
```

Cleanup removes the selected container, server image, model files, remote-code
cache, and Xet cache. See [Advanced cleanup](ADVANCED.md#advanced-cleanup) when
the Xet cache is shared with other projects or startup settings were overridden.
