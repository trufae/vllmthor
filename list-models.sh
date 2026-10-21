#!/usr/bin/env bash
#
# List every downloaded Hugging Face model and its actual disk usage.
# Use the same HF_CACHE value that was used when starting a model.

set -euo pipefail
IFS=$'\n\t'

usage() {
	cat <<'EOF'
Usage: ./list-models.sh

Lists downloaded Hugging Face models, largest first. Set HF_CACHE when the
models are stored outside the default location:

  HF_CACHE=/mnt/nvme/huggingface ./list-models.sh
EOF
}

if [ "$#" -gt 0 ]; then
	case "$1" in
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "Unknown argument: $1" >&2
		usage >&2
		exit 2
		;;
	esac
fi

HF_CACHE="${HF_CACHE:-${HOME:?HOME must be set}/.cache/huggingface}"
if ! HF_CACHE="$(realpath -m -- "$HF_CACHE")"; then
	echo "ERROR: could not resolve HF_CACHE." >&2
	exit 1
fi

HUB_CACHE="$HF_CACHE/hub"

human_size() {
	numfmt --to=iec-i --suffix=B --format='%.1f' "$1"
}

model_id_from_cache_name() {
	local encoded="${1#models--}"

	if [[ "$encoded" == *--* ]]; then
		printf '%s/%s\n' "${encoded%%--*}" "${encoded#*--}"
	else
		printf '%s\n' "$encoded"
	fi
}

echo "Hugging Face cache: $HF_CACHE"
echo

if [ ! -d "$HUB_CACHE" ]; then
	echo "No Hugging Face hub cache found."
	exit 0
fi

records=()
total_bytes=0

while IFS= read -r -d '' model_dir; do
	cache_name="${model_dir##*/}"
	model_id="$(model_id_from_cache_name "$cache_name")"
	bytes="$(du --summarize --block-size=1 -- "$model_dir" | cut -f1)"
	records+=("$bytes"$'\t'"$model_id")
	total_bytes=$((total_bytes + bytes))
done < <(find "$HUB_CACHE" -mindepth 1 -maxdepth 1 -type d \
	-name 'models--*' -print0)

if [ "${#records[@]}" -eq 0 ]; then
	echo "No downloaded models found."
else
	printf '%10s  %s\n' "SIZE" "MODEL"
	printf '%10s  %s\n' "----------" "-----"
	while IFS=$'\t' read -r bytes model_id; do
		printf '%10s  %s\n' "$(human_size "$bytes")" "$model_id"
	done < <(printf '%s\n' "${records[@]}" | sort -t $'\t' -k1,1nr)
	printf '%10s  %s\n' "----------" "-----"
	printf '%10s  %s\n' "$(human_size "$total_bytes")" "TOTAL MODEL CACHE"
fi

if [ -d "$HF_CACHE/xet" ]; then
	xet_bytes="$(du --summarize --block-size=1 -- "$HF_CACHE/xet" | cut -f1)"
	echo
	printf '%10s  %s\n' "$(human_size "$xet_bytes")" \
		"shared Xet cache (not attributable to one model)"
fi
