-- FeedReader Queries
-- Parrot reads this + schema.sql to generate src/feedreader/sql.gleam

-- -- Feeds -----------------------------------------------------

-- name: ListFeeds :many
SELECT id, name, site_url, feed_url, category, last_fetched_at, fetch_error
FROM feeds
ORDER BY category ASC, name ASC;

-- name: GetFeed :one
SELECT id, name, site_url, feed_url, category, last_fetched_at, fetch_error
FROM feeds
WHERE id = ?;

-- name: GetFeedByUrl :one
SELECT id, name, site_url, feed_url, category, last_fetched_at, fetch_error
FROM feeds
WHERE feed_url = ?;

-- name: InsertFeed :exec
INSERT INTO feeds (id, name, site_url, feed_url, category, last_fetched_at, fetch_error)
VALUES (?, ?, ?, ?, ?, ?, ?);

-- name: DeleteFeed :exec
DELETE FROM feeds WHERE id = ?;

-- name: LogFetchSuccess :exec
UPDATE feeds SET last_fetched_at = ?, fetch_error = NULL
WHERE id = ?;

-- name: LogFetchError :exec
UPDATE feeds SET last_fetched_at = ?, fetch_error = ?
WHERE id = ?;

-- -- Entries ---------------------------------------------------

-- name: GetEntry :one
SELECT e.id, e.created_at, e.external_id, e.title, e.content_link, e.comments_link, e.published_at, e.is_read, e.is_starred, e.feed_id,
       f.name AS feed_name, f.site_url AS feed_site_url, f.feed_url AS feed_feed_url
FROM entries e
JOIN feeds f ON f.id = e.feed_id
WHERE e.id = ?;

-- name: GetEntryByFeedAndExternalId :one
SELECT id, created_at, external_id, title, content_link, comments_link, published_at, is_read, is_starred, feed_id
FROM entries
WHERE feed_id = ? AND external_id = ?;

-- name: UpsertEntry :exec
INSERT INTO entries (id, created_at, external_id, title, content_link, comments_link, published_at, is_read, is_starred, feed_id)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(feed_id, external_id) DO UPDATE SET
  title = excluded.title,
  content_link = excluded.content_link,
  comments_link = excluded.comments_link,
  published_at = excluded.published_at;

-- name: ListUnread :many
SELECT e.id, e.created_at, e.external_id, e.title, e.content_link, e.comments_link, e.published_at, e.is_read, e.is_starred, e.feed_id,
       f.name AS feed_name, f.site_url AS feed_site_url, f.feed_url AS feed_feed_url
FROM entries e
JOIN feeds f ON f.id = e.feed_id
WHERE e.is_read = 0
ORDER BY e.published_at IS NULL, e.published_at ASC
LIMIT ? OFFSET ?;

-- name: ListStarred :many
SELECT e.id, e.created_at, e.external_id, e.title, e.content_link, e.comments_link, e.published_at, e.is_read, e.is_starred, e.feed_id,
       f.name AS feed_name, f.site_url AS feed_site_url, f.feed_url AS feed_feed_url
FROM entries e
JOIN feeds f ON f.id = e.feed_id
WHERE e.is_starred = 1
ORDER BY e.published_at IS NULL, e.published_at ASC
LIMIT ? OFFSET ?;

-- name: ListHistory :many
SELECT e.id, e.created_at, e.external_id, e.title, e.content_link, e.comments_link, e.published_at, e.is_read, e.is_starred, e.feed_id,
       f.name AS feed_name, f.site_url AS feed_site_url, f.feed_url AS feed_feed_url
FROM entries e
JOIN feeds f ON f.id = e.feed_id
ORDER BY e.published_at IS NULL DESC, e.published_at DESC
LIMIT ? OFFSET ?;

-- name: ToggleRead :exec
UPDATE entries SET is_read = ?
WHERE id = ?;

-- name: ToggleStarred :exec
UPDATE entries SET is_starred = ?
WHERE id = ?;

-- name: UnreadCount :one
SELECT COUNT(*) AS count
FROM entries
WHERE is_read = 0;

-- name: CountByFeed :one
SELECT COUNT(*) AS count
FROM entries
WHERE feed_id = ?;
