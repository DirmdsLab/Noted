#!/usr/bin/env bash

set -u

TARGET_DIR="${1:-}"

if [[ -z "$TARGET_DIR" ]]; then
    echo "Usage: $0 \"directory\""
    exit 1
fi

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: directory does not exist: $TARGET_DIR"
    exit 1
fi

TARGET_DIR="$(realpath "$TARGET_DIR")"

# Find and unlink all symbolic links directly inside the directory
find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type l -print0 |
while IFS= read -r -d '' LINK; do
    NAME="$(basename "$LINK")"

    if unlink -- "$LINK"; then
        echo "UNLINK: $NAME"
    else
        echo "ERROR: failed to unlink $NAME"
    fi
done