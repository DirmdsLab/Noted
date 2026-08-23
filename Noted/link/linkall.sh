#!/usr/bin/env bash

set -u

SOURCE="${1:-}"
DEST="${2:-}"

if [[ -z "$SOURCE" || -z "$DEST" ]]; then
    echo "Usage: $0 \"source directory\" \"destination directory\""
    exit 1
fi

if [[ ! -d "$SOURCE" ]]; then
    echo "Error: source directory does not exist: $SOURCE"
    exit 1
fi

if [[ ! -d "$DEST" ]]; then
    echo "Error: destination directory does not exist: $DEST"
    exit 1
fi

SOURCE="$(realpath "$SOURCE")"
DEST="$(realpath "$DEST")"

shopt -s nullglob dotglob

for ITEM in "$SOURCE"/*; do
    NAME="$(basename "$ITEM")"
    TARGET="$DEST/$NAME"

    # Skip if the name already exists in the destination
    if [[ -e "$TARGET" || -L "$TARGET" ]]; then
        echo "SKIP: $NAME"
        continue
    fi

    # Create symbolic link
    if ln -sfnT -- "$ITEM" "$TARGET"; then
        echo "LINK: $NAME"
    else
        echo "ERROR: failed to link $NAME"
    fi
done