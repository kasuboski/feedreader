-- FeedReader Schema
-- SQLite DDL
--
-- Source of truth for FeedReader's database.
-- Parrot (sqlc) reads this + queries.sql to generate src/feedreader/sql.gleam.
--
-- Regenerate after changes:
--   mise run gen

CREATE TABLE IF NOT EXISTS feeds (
  id TEXT PRIMARY KEY,
  name TEXT,
  site_url TEXT,
  feed_url TEXT NOT NULL UNIQUE,
  category TEXT NOT NULL DEFAULT 'Uncategorized',
  last_fetched_at TEXT,
  fetch_error TEXT
);

CREATE TABLE IF NOT EXISTS entries (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL,
  external_id TEXT NOT NULL,
  title TEXT,
  content_link TEXT,
  comments_link TEXT,
  published_at TEXT,
  is_read INTEGER NOT NULL DEFAULT 0,
  is_starred INTEGER NOT NULL DEFAULT 0,
  feed_id TEXT NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
  UNIQUE(feed_id, external_id)
);
