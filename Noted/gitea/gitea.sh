#!/usr/bin/env bash

set -e

# ===== CHECK ARGUMENT =====

if [ -z "$1" ]; then
echo "Usage: $0 /path/to/folder/gitea"
exit 1
fi

# ===== CONFIG =====

CONTAINER_NAME="gitea"
BASE_DIR="$1"
DATA_DIR="$BASE_DIR/gitea-data"
IMAGE="docker.gitea.com/gitea:1.26.1"

# ===== PREPARE DIRECTORY =====

echo "[INFO] Base directory: $BASE_DIR"
mkdir -p "$DATA_DIR"

# Convert to absolute path

DATA_DIR="$(realpath "$DATA_DIR")"

echo "[INFO] Data directory: $DATA_DIR"

# ===== RUN CONTAINER =====

echo "[INFO] Starting Gitea container..."

podman run -d \
  --name "$CONTAINER_NAME" \
  -p 8090:3000 \
  -p 8092:22 \
  -e USER_UID=1000 \
  -e USER_GID=1000 \
  -v "$DATA_DIR:/data:Z" \
  -v /etc/localtime:/etc/localtime:ro \
  "$IMAGE"

echo "[SUCCESS] Gitea is running!"
echo "Web UI : http://localhost:8090"
echo "SSH    : ssh://user@localhost:8092"

podman ps