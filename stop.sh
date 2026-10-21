#!/usr/bin/env bash
# Find and stop running project servers, keeping their images and model caches.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || exit 1
source "$SCRIPT_DIR/profiles.sh" || exit 1

if ! command -v docker >/dev/null 2>&1; then
	echo "ERROR: Docker is not installed." >&2
	exit 1
fi
if ! running="$(docker ps --format "{{.ID}} {{.Names}} {{.Label \"$SERVER_LABEL\"}}")"; then
	echo "ERROR: cannot list running containers." >&2
	exit 1
fi

# Recognize containers started before profile labels were added, too.
declare -A profiles_by_container=()
for profile in "${MODEL_PROFILES[@]}"; do
	load_profile "$profile"
	profiles_by_container["$DEFAULT_CONTAINER_NAME"]="$profile"
done

server_ids=()
while read -r id name profile; do
	[[ -n "$id" && -n "$name" ]] || continue
	profile="${profile:-${profiles_by_container[$name]:-}}"
	if [ -n "$profile" ]; then
		echo "==> Stopping $name ($profile)..."
		server_ids+=("$id")
	fi
done <<< "$running"

if [ "${#server_ids[@]}" -eq 0 ]; then
	echo "==> No model server is running."
	exit 0
fi

docker stop -- "${server_ids[@]}"
