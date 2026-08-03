#!/usr/bin/env bash
set -euo pipefail

FLAKENIX_PATH="flake.nix"
ARMBIAN_REPO="armbian/build"

CURRENT_HASH=$(grep -oE 'git\+https://github\.com/armbian/build\.git\?rev=[a-f0-9]{40}' "$FLAKENIX_PATH" | sed 's/.*rev=//')
[[ -z "$CURRENT_HASH" ]] && { echo "Error: Could not extract current hash" >&2; exit 1; }

LATEST_TAG=$(curl -s "https://api.github.com/repos/armbian/build/releases/latest" | jq -r '.tag_name // empty')
if [[ -z "$LATEST_TAG" ]]; then
  LATEST_HASH=$(git ls-remote "https://github.com/armbian/build.git" HEAD | awk '{print $1}')
else
  LATEST_HASH=$(git ls-remote "https://github.com/armbian/build.git" "refs/tags/${LATEST_TAG}" 2>/dev/null | awk '{print $1}')
  [[ -z "$LATEST_HASH" ]] && LATEST_HASH=$(git ls-remote "https://github.com/armbian/build.git" HEAD 2>/dev/null | awk '{print $1}')
fi
[[ -z "$LATEST_HASH" ]] && { echo "Error: Unable to determine latest Armbian reference" >&2; exit 1; }

echo "CURRENT_HASH=$CURRENT_HASH"
echo "LATEST_TAG=$LATEST_TAG"
echo "LATEST_HASH=$LATEST_HASH"
sed -i -E "s|git\+https://github\.com/${ARMBIAN_REPO}\.git\?rev=[a-f0-9]{40}|git+https://github.com/${ARMBIAN_REPO}.git?rev=${LATEST_HASH}|" "$FLAKENIX_PATH"
nix flake update

echo "flake.nix updated to armbian-build: $LATEST_HASH"