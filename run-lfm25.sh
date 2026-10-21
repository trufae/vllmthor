#!/usr/bin/env bash

set -euo pipefail

# export LFM25_SPECULATIVE_CONFIG='{"method":"ngram","num_speculative_tokens":3,"prompt_lookup_min":2,"prompt_lookup_max":5}'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export MODEL_PROFILE=lfm25
exec "$SCRIPT_DIR/run.sh"
