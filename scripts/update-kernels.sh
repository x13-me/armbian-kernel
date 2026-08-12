#!/usr/bin/env bash
set -euo pipefail

FLAKENIX_PATH="flake.nix"
ARMBIAN_REPO="armbian/build"

# --- CI environment setup ---
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    git config user.name "${GITHUB_ACTOR:-github-actions}" 2>/dev/null || true
    git config user.email "${GITHUB_ACTOR:-github-actions}@users.noreply.github.com" 2>/dev/null || true
fi

# --- 1. Get current hash ---
CURRENT_HASH=$(grep -oE 'git\+https://github\.com/armbian/build\.git\?rev=[a-f0-9]{40}' "$FLAKENIX_PATH" | sed 's/.*rev=//')
[[ -z "$CURRENT_HASH" ]] && { echo "Error: Could not extract current hash" >&2; exit 1; }

# --- 2. Get latest Armbian reference ---
LATEST_TAG=$(curl -sfL --retry 3 --retry-delay 2 \
"https://api.github.com/repos/armbian/build/releases/latest" | jq -r '.tag_name // empty')

if [[ -z "$LATEST_TAG" ]]; then
    LATEST_HASH=$(git ls-remote "https://github.com/armbian/build.git" HEAD | awk '{print $1}')
else
    LATEST_HASH=$(git ls-remote "https://github.com/armbian/build.git" "refs/tags/${LATEST_TAG}" 2>/dev/null | awk '{print $1}')
    [[ -z "$LATEST_HASH" ]] && LATEST_HASH=$(git ls-remote "https://github.com/armbian/build.git" HEAD 2>/dev/null | awk '{print $1}')
fi
[[ -z "$LATEST_HASH" ]] && { echo "Error: Unable to determine latest Armbian reference" >&2; exit 1; }

# --- 3. Bailout if already up to date ---
if [[ "$CURRENT_HASH" == "$LATEST_HASH" ]]; then
    echo "Already at latest armbian-build: $CURRENT_HASH"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "updated=false" >> "$GITHUB_OUTPUT"
        echo "latest_hash=$LATEST_HASH" >> "$GITHUB_OUTPUT"
    fi
    exit 0
fi

# --- 4. Update flake.nix ---
sed -i -E "s|git\+https://github\.com/${ARMBIAN_REPO}\.git\?rev=[a-f0-9]{40}|git+https://github.com/${ARMBIAN_REPO}.git?rev=${LATEST_HASH}|" "$FLAKENIX_PATH"
nix flake update

# --- 5. CI outputs for downstream steps ---
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        echo "updated=true"
        echo "latest_hash=$LATEST_HASH"
        echo "previous_hash=$CURRENT_HASH"
        echo "latest_tag=${LATEST_TAG:-}"
    } >> "$GITHUB_OUTPUT"
fi

echo "flake.nix updated to armbian-build: $LATEST_HASH"