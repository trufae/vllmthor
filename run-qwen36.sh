#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export MODEL_PROFILE=qwen36
exec "$SCRIPT_DIR/run.sh"
