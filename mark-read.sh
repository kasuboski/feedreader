#!/bin/bash
# Mark all feed entries as read except those from the last 6 hours.
# Run this on the server (where docker compose is deployed).
set -euo pipefail

CONTAINER=$(docker compose ps -q feedreader 2>/dev/null || docker ps --filter "ancestor=ghcr.io/kasuboski/feedreader:main" -q | head -1)

if [ -z "$CONTAINER" ]; then
  echo "ERROR: Could not find feedreader container"
  exit 1
fi

echo "Using container: $CONTAINER"

docker exec "$CONTAINER" /app/bin/feedreader eval '
  cutoff = DateTime.add(DateTime.utc_now(), -6, :hour) |> DateTime.to_iso8601()
  {:ok, %Exqlite.Result{num_rows: count}} = Feedreader.Repo.query(
    "UPDATE entries SET is_read = 1 WHERE published_at < ?",
    [cutoff]
  )
  IO.puts("Marked #{count} entries as read (kept last 6 hours unread)")
'
