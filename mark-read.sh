#!/bin/bash
# Mark all entries older than 6 hours as read.
# Usage: ./mark-read.sh [db_path]
# This directly modifies the SQLite database.

set -euo pipefail

DB_PATH="${1:-${DATABASE_PATH:-feedreader.db}}"
CUTOFF=$(date -u -v-6H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "6 hours ago" +"%Y-%m-%dT%H:%M:%SZ")

echo "Marking entries older than $CUTOFF as read in $DB_PATH..."

sqlite3 "$DB_PATH" "
  UPDATE entries
  SET is_read = 1
  WHERE is_read = 0
    AND published_at IS NOT NULL
    AND published_at != ''
    AND published_at < '$CUTOFF';
"

echo "Done."
