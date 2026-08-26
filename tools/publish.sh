#!/usr/bin/env bash
# Files -> published place version, no Studio (S-02).
set -euo pipefail

SIZE_LIMIT=$((10 * 1024 * 1024))
VERSION_TYPE="${1:-Saved}" # Saved = staging dry-run, Published = live release

if [[ "$VERSION_TYPE" != "Saved" && "$VERSION_TYPE" != "Published" ]]; then
	echo "usage: $0 [Saved|Published]" >&2
	exit 1
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.."

for var in ROBLOX_API_KEY ROBLOX_UNIVERSE_ID ROBLOX_PLACE_ID; do
	if [[ -z "${!var:-}" ]]; then
		echo "missing $var. Create an Open Cloud key with scope universe-places:write" >&2
		echo "in Creator Dashboard -> Open Cloud -> API Keys, then export the three vars." >&2
		exit 2
	fi
done

# BUILD=path skips the build to check an existing file — used to prove the size gate
# refuses before anything reaches the network.
BUILD="${BUILD:-build.rbxl}"
if [[ "$BUILD" == "build.rbxl" ]]; then
	rojo build -o build.rbxl
fi

size=$(wc -c < "$BUILD")
if (( size > SIZE_LIMIT )); then
	echo "$BUILD is $size bytes, over the $SIZE_LIMIT place limit (S-02)" >&2
	exit 3
fi
echo "$BUILD $size bytes, under the ${SIZE_LIMIT} limit"

curl --fail-with-body -sS -X POST \
	"https://apis.roblox.com/universes/v1/${ROBLOX_UNIVERSE_ID}/places/${ROBLOX_PLACE_ID}/versions?versionType=${VERSION_TYPE}" \
	-H "x-api-key: ${ROBLOX_API_KEY}" \
	-H "Content-Type: application/octet-stream" \
	--data-binary "@$BUILD"
