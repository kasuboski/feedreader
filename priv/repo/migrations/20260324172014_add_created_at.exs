defmodule Feedreader.Repo.Migrations.AddCreatedAt do
  @moduledoc """
  Updates resources based on their most recent snapshots.
  """

  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS entries_new (
      id TEXT PRIMARY KEY NOT NULL,
      feed_id TEXT NOT NULL,
      external_id TEXT NOT NULL,
      title TEXT,
      content_link TEXT,
      comments_link TEXT,
      published_at TEXT,
      is_read INTEGER DEFAULT 0 NOT NULL,
      is_starred INTEGER DEFAULT 0 NOT NULL,
      created_at TEXT NOT NULL
    )
    """)

    execute("""
    INSERT INTO entries_new (id, feed_id, external_id, title, content_link, comments_link, published_at, is_read, is_starred, created_at)
    SELECT id, feed_id, external_id, title, content_link, comments_link, published_at, is_read, is_starred, COALESCE(published_at, datetime('now'))
    FROM entries
    """)

    execute("DROP TABLE IF EXISTS entries")
    execute("ALTER TABLE entries_new RENAME TO entries")

    execute("CREATE INDEX IF NOT EXISTS entries_feed_id_index ON entries(feed_id)")

    execute(
      "CREATE INDEX IF NOT EXISTS entries_is_read_is_starred_index ON entries(is_read, is_starred)"
    )

    execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS entries_unique_entry_per_feed_index ON entries(feed_id, external_id)"
    )
  end

  def down do
    execute("""
    CREATE TABLE IF NOT EXISTS entries_old (
      id TEXT PRIMARY KEY NOT NULL,
      feed_id TEXT NOT NULL,
      external_id TEXT NOT NULL,
      title TEXT,
      content_link TEXT,
      comments_link TEXT,
      published_at TEXT,
      is_read INTEGER DEFAULT 0 NOT NULL,
      is_starred INTEGER DEFAULT 0 NOT NULL
    )
    """)

    execute("""
    INSERT INTO entries_old (id, feed_id, external_id, title, content_link, comments_link, published_at, is_read, is_starred)
    SELECT id, feed_id, external_id, title, content_link, comments_link, published_at, is_read, is_starred
    FROM entries
    """)

    execute("DROP TABLE entries")
    execute("ALTER TABLE entries_old RENAME TO entries")

    execute("CREATE INDEX IF NOT EXISTS entries_feed_id_index ON entries(feed_id)")

    execute(
      "CREATE INDEX IF NOT EXISTS entries_is_read_is_starred_index ON entries(is_read, is_starred)"
    )

    execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS entries_unique_entry_per_feed_index ON entries(feed_id, external_id)"
    )
  end
end
