#!/usr/bin/env bash
#
# Run a small sequential benchmark against an OpenAI-compatible local server.
# Output tok/s is usage.completion_tokens divided by curl's total request time.

set -euo pipefail
LC_ALL=C

BASE_URL="${BASE_URL:-http://localhost:8000/v1}"
BASE_URL="${BASE_URL%/}"
MODEL="${MODEL:-}"
API_KEY="${API_KEY:-}"
RUNS="${RUNS:-1}"
MAX_TOKENS="${MAX_TOKENS:-256}"
TEMPERATURE="${TEMPERATURE:-0}"
REQUEST_TIMEOUT="${REQUEST_TIMEOUT:-600}"
WARMUP="${WARMUP:-1}"

require_unsigned_integer() {
	local name="$1"
	local value="$2"

	if [[ ! "$value" =~ ^[0-9]+$ ]]; then
		echo "$name must be an unsigned integer, got: $value" >&2
		exit 2
	fi
}

require_unsigned_integer RUNS "$RUNS"
require_unsigned_integer MAX_TOKENS "$MAX_TOKENS"
require_unsigned_integer REQUEST_TIMEOUT "$REQUEST_TIMEOUT"

if [ "$RUNS" -lt 1 ] || [ "$MAX_TOKENS" -lt 1 ] || [ "$REQUEST_TIMEOUT" -lt 1 ]; then
	echo "RUNS, MAX_TOKENS, and REQUEST_TIMEOUT must be greater than zero." >&2
	exit 2
fi
if [[ ! "$TEMPERATURE" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
	echo "TEMPERATURE must be a non-negative number, got: $TEMPERATURE" >&2
	exit 2
fi
if [ "$WARMUP" != "0" ] && [ "$WARMUP" != "1" ]; then
	echo "WARMUP must be 0 or 1, got: $WARMUP" >&2
	exit 2
fi

for command_name in curl jq awk mktemp; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		echo "Required command not found: $command_name" >&2
		exit 1
	fi
done

curl_args=(
	--silent
	--show-error
	--fail-with-body
	--connect-timeout 5
	--max-time "$REQUEST_TIMEOUT"
)
auth_args=()
if [ -n "$API_KEY" ]; then
	auth_args=(-H "Authorization: Bearer $API_KEY")
fi

echo "==> Checking $BASE_URL..."
if ! models_json="$(curl "${curl_args[@]}" "${auth_args[@]}" "$BASE_URL/models")"; then
	echo "Could not reach the models endpoint. Is the server running?" >&2
	exit 1
fi

if [ -z "$MODEL" ]; then
	MODEL="$(jq -r '.data[0].id // empty' <<<"$models_json")"
fi
if [ -z "$MODEL" ]; then
	echo "No served model was returned by $BASE_URL/models." >&2
	echo "Set MODEL explicitly and try again." >&2
	exit 1
fi

bench_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/vllmqwen-bench.XXXXXX")"
cleanup() {
	if [ -n "${bench_tmp_dir:-}" ] && [ -d "$bench_tmp_dir" ]; then
		rm -rf -- "$bench_tmp_dir"
	fi
}
trap cleanup EXIT HUP INT TERM

response_file="$bench_tmp_dir/response.json"

request() {
	local prompt="$1"
	local max_tokens="$2"
	local payload elapsed error_message

	payload="$(jq -cn \
		--arg model "$MODEL" \
		--arg prompt "$prompt" \
		--argjson max_tokens "$max_tokens" \
		--argjson temperature "$TEMPERATURE" \
		'{
			model: $model,
			messages: [{role: "user", content: $prompt}],
			max_tokens: $max_tokens,
			temperature: $temperature,
			stream: false
		}')"

	if ! elapsed="$(curl \
		"${curl_args[@]}" \
		"${auth_args[@]}" \
		-H 'Content-Type: application/json' \
		--output "$response_file" \
		--write-out '%{time_total}' \
		--data-binary "$payload" \
		"$BASE_URL/chat/completions")"; then
		echo "Request failed." >&2
		if [ -s "$response_file" ]; then
			jq -r '.error.message // "Server returned a non-success response."' \
				"$response_file" >&2 2>/dev/null || true
		fi
		return 1
	fi

	error_message="$(jq -r '.error.message // empty' "$response_file")"
	if [ -n "$error_message" ]; then
		echo "Server error: $error_message" >&2
		return 1
	fi

	printf '%s\n' "$elapsed"
}

if [ "$WARMUP" = "1" ]; then
	echo "==> Warming up $MODEL..."
	request "Reply with the single word ready." 32 >/dev/null
fi

test_names=(
	"thor_explanation"
	"python_coding"
	"reasoning_plan"
	"debug_checklist"
)
test_prompts=(
	"Write a detailed technical explanation of how unified memory affects local LLM inference on Jetson AGX Thor. Cover model weights, KV cache, concurrency, and operating-system headroom. Aim for at least 300 words."
	"Implement an LRU cache in Python without external packages. Include type hints, clear comments, complexity analysis, and a few assert-based tests. Explain the important design choices."
	"Design a migration plan for moving a production REST API from one large server to three redundant edge nodes. Discuss rollout stages, data consistency, observability, rollback, and the major tradeoffs."
	"Create a detailed checklist for diagnosing unexpectedly low language-model tokens per second on an NVIDIA Jetson. Cover power mode, clocks, thermals, memory pressure, context length, batching, quantization, and speculative decoding."
)

echo
echo "Model:       $MODEL"
echo "Endpoint:    $BASE_URL/chat/completions"
echo "Runs/test:   $RUNS"
echo "Max tokens:  $MAX_TOKENS"
echo "Temperature: $TEMPERATURE"
echo
printf '%-24s %9s %9s %10s %13s %s\n' \
	"Test" "Prompt" "Output" "Seconds" "Output tok/s" "Finish"
printf '%-24s %9s %9s %10s %13s %s\n' \
	"------------------------" "---------" "---------" "----------" "-------------" "------"

total_prompt_tokens=0
total_output_tokens=0
total_seconds="0"
request_count=0

for index in "${!test_names[@]}"; do
	for ((run = 1; run <= RUNS; run++)); do
		label="${test_names[$index]}"
		if [ "$RUNS" -gt 1 ]; then
			label="$label #$run"
		fi

		elapsed="$(request "${test_prompts[$index]}" "$MAX_TOKENS")"
		if ! prompt_tokens="$(jq -er '.usage.prompt_tokens | numbers' "$response_file")" ||
			! output_tokens="$(jq -er '.usage.completion_tokens | numbers' "$response_file")"; then
			echo "Response did not include token usage; cannot calculate tok/s." >&2
			exit 1
		fi
		finish_reason="$(jq -r '.choices[0].finish_reason // "unknown"' "$response_file")"
		output_rate="$(awk -v tokens="$output_tokens" -v seconds="$elapsed" \
			'BEGIN { if (seconds > 0) printf "%.2f", tokens / seconds; else print "n/a" }')"

		printf '%-24s %9d %9d %10.2f %13s %s\n' \
			"$label" "$prompt_tokens" "$output_tokens" "$elapsed" \
			"$output_rate" "$finish_reason"

		total_prompt_tokens=$((total_prompt_tokens + prompt_tokens))
		total_output_tokens=$((total_output_tokens + output_tokens))
		total_seconds="$(awk -v total="$total_seconds" -v elapsed="$elapsed" \
			'BEGIN { printf "%.6f", total + elapsed }')"
		request_count=$((request_count + 1))
	done
done

overall_rate="$(awk -v tokens="$total_output_tokens" -v seconds="$total_seconds" \
	'BEGIN { if (seconds > 0) printf "%.2f", tokens / seconds; else print "n/a" }')"

echo
echo "Requests:          $request_count"
echo "Prompt tokens:     $total_prompt_tokens"
echo "Completion tokens: $total_output_tokens"
printf 'Total time:        %.2f s\n' "$total_seconds"
echo "Overall output:    $overall_rate tok/s"
echo
echo "This is end-to-end output throughput: completion tokens divided by curl"
echo "time_total. It includes request handling, prompt prefill, and generation."
