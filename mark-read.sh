#!/bin/bash
# Mark all entries older than 6 hours as read.
# Usage: ./mark-read.sh [container_name]
#
# Runs the UPDATE inside the container so it works with Docker volumes.
# Defaults to the feedreader service from docker compose.

set -euo pipefail

CONTAINER="${1:-$(docker compose ps -q feedreader 2>/dev/null || docker ps --filter "ancestor=ghcr.io/kasuboski/feedreader:main" -q | head -1)}"

if [ -z "$CONTAINER" ]; then
  echo "ERROR: Could not find feedreader container"
  echo "Usage: $0 [container_name|container_id]"
  exit 1
fi

CUTOFF=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "Marking entries older than $CUTOFF as read in container $CONTAINER..."

docker exec "$CONTAINER" sqlite3 /data/feedreader.db "
  UPDATE entries
  SET is_read = 1
  WHERE is_read = 0
    AND published_at IS NOT NULL
    AND published_at != ''
    AND published_at < '$CUTOFF';
"

echo "Done."
