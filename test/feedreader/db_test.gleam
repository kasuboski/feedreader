import feedreader/db
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import sqlight

fn with_db(f: fn(sqlight.Connection) -> a) -> a {
  let assert Ok(conn) = sqlight.open("file::memory:")
  let assert Ok(Nil) = db.migrate(conn)
  let result = f(conn)
  let assert Ok(Nil) = sqlight.close(conn)
  result
}

// ═══════════════════════════════════════════════════════════════
// Schema / Migration tests
// ═══════════════════════════════════════════════════════════════

pub fn migrate_creates_feeds_table_test() {
  with_db(fn(conn) {
    // If the table didn't exist, this query would error
    let assert Ok(Nil) =
      sqlight.exec(
        "INSERT INTO feeds (id, name, site_url, feed_url, category, last_fetched_at, fetch_error) VALUES ('test', '', '', 'test-url', 'X', '', '')",
        on: conn,
      )
    let assert Ok(Nil) =
      sqlight.exec("DELETE FROM feeds WHERE id = 'test'", on: conn)
  })
}

pub fn migrate_creates_entries_table_test() {
  with_db(fn(conn) {
    let assert Ok(Nil) =
      sqlight.exec(
        "INSERT INTO feeds (id, name, site_url, feed_url, category, last_fetched_at, fetch_error) VALUES ('f', '', '', 'f-url', 'X', '', '')",
        on: conn,
      )
    let assert Ok(Nil) =
      sqlight.exec(
        "INSERT INTO entries (id, created_at, external_id, title, content_link, comments_link, published_at, is_read, is_starred, feed_id) VALUES ('e', '2025', 'ext', '', '', '', '', 0, 0, 'f')",
        on: conn,
      )
    let assert Ok(Nil) =
      sqlight.exec("DELETE FROM entries WHERE id = 'e'", on: conn)
    let assert Ok(Nil) =
      sqlight.exec("DELETE FROM feeds WHERE id = 'f'", on: conn)
  })
}

pub fn migrate_is_idempotent_test() {
  with_db(fn(conn) {
    let assert Ok(Nil) = db.migrate(conn)
    let assert Ok(Nil) = db.migrate(conn)
    // still works fine
  })
}

pub fn migrate_upgrades_legacy_entries_and_preserves_data_test() {
  let assert Ok(conn) = sqlight.open("file::memory:")
  let assert Ok(Nil) =
    sqlight.exec(
      "CREATE TABLE feeds (id TEXT PRIMARY KEY, name TEXT, site_url TEXT, feed_url TEXT NOT NULL UNIQUE, category TEXT NOT NULL DEFAULT 'Uncategorized', last_fetched_at TEXT, fetch_error TEXT); CREATE TABLE entries (id TEXT PRIMARY KEY, created_at TEXT NOT NULL, external_id TEXT NOT NULL, title TEXT, content_link TEXT, comments_link TEXT, published_at TEXT, is_read INTEGER NOT NULL DEFAULT 0, is_starred INTEGER NOT NULL DEFAULT 0, feed_id TEXT NOT NULL REFERENCES feeds(id) ON DELETE CASCADE, UNIQUE(feed_id, external_id)); INSERT INTO feeds VALUES ('legacy-feed', 'Legacy', 'https://legacy.example', 'https://legacy.example/rss', 'Tech', NULL, NULL); INSERT INTO entries VALUES ('legacy-entry', '2024-01-01', 'legacy-guid', 'Preserved title', 'https://legacy.example/article', NULL, '2024-01-02', 1, 1, 'legacy-feed');",
      on: conn,
    )
  let assert Ok(Nil) = db.migrate(conn)
  let assert Ok(Some(entry)) = db.get_entry(conn, "legacy-entry")
  assert entry.title == Some("Preserved title")
  assert entry.is_read == True
  assert entry.is_starred == True
  assert entry.content_opened_at == None
  assert entry.comments_opened_at == None
  let assert Ok(Nil) = db.migrate(conn)
  let assert Ok(Some(still_there)) = db.get_entry(conn, "legacy-entry")
  assert still_there.external_id == "legacy-guid"
  let assert Ok(Nil) = sqlight.close(conn)
}

// ═══════════════════════════════════════════════════════════════
// Feed CRUD tests
// ═══════════════════════════════════════════════════════════════

pub fn insert_and_get_feed_test() {
  with_db(fn(conn) {
    let assert Ok(feed) =
      db.insert_feed(
        conn,
        name: Some("Test Blog"),
        site_url: Some("https://example.com"),
        feed_url: "https://example.com/rss",
        category: "Tech",
      )
    assert feed.feed_url == "https://example.com/rss"
    assert feed.category == "Tech"

    let assert Ok(Some(fetched)) = db.get_feed(conn, feed.id)
    assert fetched.feed_url == "https://example.com/rss"
    assert fetched.category == "Tech"
  })
}

pub fn insert_feed_with_defaults_test() {
  with_db(fn(conn) {
    let assert Ok(feed) =
      db.insert_feed(
        conn,
        name: None,
        site_url: None,
        feed_url: "https://example.com/rss",
        category: "Uncategorized",
      )
    assert feed.category == "Uncategorized"
    assert feed.name == None
    assert feed.site_url == None
  })
}

pub fn insert_duplicate_feed_url_fails_test() {
  with_db(fn(conn) {
    let assert Ok(_) =
      db.insert_feed(
        conn,
        name: None,
        site_url: None,
        feed_url: "https://a.com/rss",
        category: "Tech",
      )
    let assert Error(Nil) =
      db.insert_feed(
        conn,
        name: None,
        site_url: None,
        feed_url: "https://a.com/rss",
        category: "Tech",
      )
  })
}

pub fn list_feeds_test() {
  with_db(fn(conn) {
    let assert Ok(_) =
      db.insert_feed(
        conn,
        name: Some("B"),
        site_url: None,
        feed_url: "https://b.com/rss",
        category: "Tech",
      )
    let assert Ok(_) =
      db.insert_feed(
        conn,
        name: Some("A"),
        site_url: None,
        feed_url: "https://a.com/rss",
        category: "Tech",
      )
    let assert Ok(feeds) = db.list_feeds(conn)
    assert list.length(feeds) == 2
  })
}

pub fn delete_feed_cascades_to_entries_test() {
  with_db(fn(conn) {
    let assert Ok(feed) =
      db.insert_feed(
        conn,
        name: Some("Test"),
        site_url: None,
        feed_url: "https://example.com/rss",
        category: "Tech",
      )
    let assert Ok(Nil) =
      db.upsert_entry(
        conn,
        external_id: "guid-1",
        title: Some("Entry 1"),
        content_link: Some("https://example.com/1"),
        comments_link: None,
        published_at: None,
        feed_id: feed.id,
      )
    let assert Ok(Nil) = db.delete_feed(conn, feed.id)
    let assert Ok(None) = db.get_feed(conn, feed.id)
    // entries should be gone via cascade
    let assert Ok([]) = db.list_unread(conn, limit: 100, offset: 0)
  })
}

pub fn get_feed_by_url_test() {
  with_db(fn(conn) {
    let assert Ok(_) =
      db.insert_feed(
        conn,
        name: Some("Test"),
        site_url: None,
        feed_url: "https://unique.example.com/rss",
        category: "Tech",
      )
    let assert Ok(Some(feed)) =
      db.get_feed_by_url(conn, "https://unique.example.com/rss")
    assert feed.feed_url == "https://unique.example.com/rss"
  })
}

// ═══════════════════════════════════════════════════════════════
// Entry CRUD tests
// ═══════════════════════════════════════════════════════════════

pub fn upsert_and_list_unread_test() {
  with_db(fn(conn) {
    let assert Ok(feed) =
      db.insert_feed(
        conn,
        name: Some("Test"),
        site_url: None,
        feed_url: "https://example.com/rss",
        category: "Tech",
      )
    let assert Ok(Nil) =
      db.upsert_entry(
        conn,
        external_id: "guid-1",
        title: Some("Entry 1"),
        content_link: Some("https://example.com/1"),
        comments_link: None,
        published_at: None,
        feed_id: feed.id,
      )
    let assert Ok(entries) = db.list_unread(conn, limit: 50, offset: 0)
    assert list.length(entries) == 1
    let assert Ok(Some(entry)) = db.get_entry(conn, first_entry_id(entries))
    assert entry.external_id == "guid-1"
    assert entry.content_opened_at == None
    assert entry.comments_opened_at == None
  })
}

pub fn upsert_is_idempotent_test() {
  with_db(fn(conn) {
    let assert Ok(feed) =
      db.insert_feed(
        conn,
        name: Some("Test"),
        site_url: None,
        feed_url: "https://example.com/rss",
        category: "Tech",
      )
    let assert Ok(Nil) =
      db.upsert_entry(
        conn,
        external_id: "guid-1",
        title: Some("Entry 1"),
        content_link: Some("https://example.com/1"),
        comments_link: None,
        published_at: None,
        feed_id: feed.id,
      )
    // Upsert same entry again — should not duplicate
    let assert Ok(Nil) =
      db.upsert_entry(
        conn,
        external_id: "guid-1",
        title: Some("Entry 1 Updated"),
        content_link: Some("https://example.com/1"),
        comments_link: None,
        published_at: None,
        feed_id: feed.id,
      )
    let assert Ok(entries) = db.list_unread(conn, limit: 50, offset: 0)
    assert list.length(entries) == 1
  })
}

pub fn record_open_is_first_only_independent_and_preserves_read_state_test() {
  with_db(fn(conn) {
    let #(id, feed_id, external_id) =
      create_entry(
        conn,
        Some("https://example.com/article"),
        Some("https://example.com/comments"),
      )
    let assert Ok(Nil) = db.toggle_read(conn, id)
    let assert Ok(Nil) = db.toggle_starred(conn, id)

    let assert Ok(Nil) = db.record_open(conn, id, db.Content)
    let assert Ok(Some(after_content)) = db.get_entry(conn, id)
    let assert Some(content_time) = after_content.content_opened_at
    assert after_content.comments_opened_at == None
    assert after_content.is_read == True

    let assert Ok(Nil) = db.record_open(conn, id, db.Comments)
    let assert Ok(Some(after_both)) = db.get_entry(conn, id)
    let assert Some(comments_time) = after_both.comments_opened_at
    assert after_both.content_opened_at == Some(content_time)
    assert after_both.is_read == True
    assert after_both.is_starred == True

    let assert Ok(Nil) = db.record_open(conn, id, db.Content)
    let assert Ok(Nil) = db.record_open(conn, id, db.Comments)
    let assert Ok(Nil) =
      db.upsert_entry(
        conn,
        external_id: external_id,
        title: Some("Updated title"),
        content_link: Some("https://example.com/article"),
        comments_link: Some("https://example.com/comments"),
        published_at: None,
        feed_id: feed_id,
      )
    let assert Ok(Some(after_upsert)) = db.get_entry(conn, id)
    assert after_upsert.content_opened_at == Some(content_time)
    assert after_upsert.comments_opened_at == Some(comments_time)
    assert after_upsert.is_read == True
    assert after_upsert.is_starred == True

    let assert Ok(starred) = db.list_starred(conn, limit: 10, offset: 0)
    assert list.length(starred) == 1
    let assert Ok(starred_entry) = list.first(starred)
    assert starred_entry.content_opened_at == Some(content_time)
    assert starred_entry.comments_opened_at == Some(comments_time)
    let assert Ok(history) = db.list_history(conn, limit: 10, offset: 0)
    let assert Ok(history_entry) = list.first(history)
    assert history_entry.content_opened_at == Some(content_time)
    assert history_entry.comments_opened_at == Some(comments_time)
  })
}

pub fn record_open_preserves_existing_timestamps_test() {
  with_db(fn(conn) {
    let #(id, _, _) =
      create_entry(
        conn,
        Some("https://example.com/article"),
        Some("https://example.com/comments"),
      )
    let assert Ok(Nil) =
      sqlight.exec(
        "UPDATE entries SET content_opened_at = '2020-01-01T00:00:00Z', comments_opened_at = '2020-01-02T00:00:00Z'",
        on: conn,
      )
    let assert Ok(Nil) = db.record_open(conn, id, db.Content)
    let assert Ok(Nil) = db.record_open(conn, id, db.Comments)
    let assert Ok(Nil) = db.toggle_read(conn, id)
    let assert Ok(Nil) = db.toggle_read(conn, id)
    let assert Ok(Some(entry)) = db.get_entry(conn, id)
    assert entry.content_opened_at == Some("2020-01-01T00:00:00Z")
    assert entry.comments_opened_at == Some("2020-01-02T00:00:00Z")
    assert entry.is_read == False
  })
}

pub fn record_open_fails_for_missing_entry_or_destination_test() {
  with_db(fn(conn) {
    let #(missing_links, _, _) = create_entry(conn, None, None)
    let #(content_only, _, _) =
      create_entry(conn, Some("https://example.com/article"), None)
    assert db.record_open(conn, "no-such-entry", db.Content) == Error(Nil)
    assert db.record_open(conn, missing_links, db.Content) == Error(Nil)
    assert db.record_open(conn, missing_links, db.Comments) == Error(Nil)
    assert db.record_open(conn, content_only, db.Comments) == Error(Nil)
    assert db.record_open(conn, content_only, db.Content) == Ok(Nil)
    let assert Ok(Some(entry)) = db.get_entry(conn, content_only)
    assert entry.content_opened_at != None
    assert entry.comments_opened_at == None
    assert entry.is_read == False
    let assert Ok(unread) = db.list_unread(conn, limit: 10, offset: 0)
    let assert Ok(unread_entry) =
      list.find(unread, fn(candidate) { candidate.id == content_only })
    assert unread_entry.content_opened_at == entry.content_opened_at
  })
}

pub fn toggle_read_test() {
  with_db(fn(conn) {
    let assert Ok(feed) =
      db.insert_feed(
        conn,
        name: Some("Test"),
        site_url: None,
        feed_url: "https://example.com/rss",
        category: "Tech",
      )
    let assert Ok(Nil) =
      db.upsert_entry(
        conn,
        external_id: "guid-1",
        title: Some("Entry 1"),
        content_link: None,
        comments_link: None,
        published_at: None,
        feed_id: feed.id,
      )
    let assert Ok(entries) = db.list_unread(conn, limit: 50, offset: 0)
    let assert Ok(Some(entry)) = db.get_entry(conn, first_entry_id(entries))
    assert entry.is_read == False

    let assert Ok(Nil) = db.toggle_read(conn, entry.id)
    let assert Ok(Some(updated)) = db.get_entry(conn, entry.id)
    assert updated.is_read == True

    // Toggle back
    let assert Ok(Nil) = db.toggle_read(conn, entry.id)
    let assert Ok(Some(again)) = db.get_entry(conn, entry.id)
    assert again.is_read == False
  })
}

pub fn toggle_starred_test() {
  with_db(fn(conn) {
    let assert Ok(feed) =
      db.insert_feed(
        conn,
        name: Some("Test"),
        site_url: None,
        feed_url: "https://example.com/rss",
        category: "Tech",
      )
    let assert Ok(Nil) =
      db.upsert_entry(
        conn,
        external_id: "guid-1",
        title: Some("Entry 1"),
        content_link: None,
        comments_link: None,
        published_at: None,
        feed_id: feed.id,
      )
    let assert Ok(entries) = db.list_unread(conn, limit: 50, offset: 0)
    let entry_id = first_entry_id(entries)

    let assert Ok(Nil) = db.toggle_starred(conn, entry_id)
    let assert Ok(Some(starred)) = db.get_entry(conn, entry_id)
    assert starred.is_starred == True

    let assert Ok(starred_entries) = db.list_starred(conn, limit: 50, offset: 0)
    assert list.length(starred_entries) == 1

    let assert Ok(Nil) = db.toggle_starred(conn, entry_id)
    let assert Ok(Some(unstarred)) = db.get_entry(conn, entry_id)
    assert unstarred.is_starred == False
  })
}

pub fn unread_excludes_read_entries_test() {
  with_db(fn(conn) {
    let assert Ok(feed) =
      db.insert_feed(
        conn,
        name: Some("Test"),
        site_url: None,
        feed_url: "https://example.com/rss",
        category: "Tech",
      )
    let assert Ok(Nil) =
      db.upsert_entry(
        conn,
        external_id: "g1",
        title: Some("E1"),
        content_link: None,
        comments_link: None,
        published_at: None,
        feed_id: feed.id,
      )
    let assert Ok(Nil) =
      db.upsert_entry(
        conn,
        external_id: "g2",
        title: Some("E2"),
        content_link: None,
        comments_link: None,
        published_at: None,
        feed_id: feed.id,
      )

    let assert Ok(entries) = db.list_unread(conn, limit: 50, offset: 0)
    assert list.length(entries) == 2

    let assert Ok(Nil) = db.toggle_read(conn, first_entry_id(entries))
    let assert Ok(unread) = db.list_unread(conn, limit: 50, offset: 0)
    assert list.length(unread) == 1
  })
}

pub fn unread_count_test() {
  with_db(fn(conn) {
    let assert Ok(feed) =
      db.insert_feed(
        conn,
        name: Some("Test"),
        site_url: None,
        feed_url: "https://example.com/rss",
        category: "Tech",
      )
    let assert Ok(Nil) =
      db.upsert_entry(
        conn,
        external_id: "g1",
        title: Some("E1"),
        content_link: None,
        comments_link: None,
        published_at: None,
        feed_id: feed.id,
      )
    let assert Ok(Nil) =
      db.upsert_entry(
        conn,
        external_id: "g2",
        title: Some("E2"),
        content_link: None,
        comments_link: None,
        published_at: None,
        feed_id: feed.id,
      )

    let assert Ok(count) = db.unread_count(conn)
    assert count == 2

    let assert Ok(entries) = db.list_unread(conn, limit: 50, offset: 0)
    let assert Ok(Nil) = db.toggle_read(conn, first_entry_id(entries))
    let assert Ok(count2) = db.unread_count(conn)
    assert count2 == 1
  })
}

pub fn log_fetch_success_test() {
  with_db(fn(conn) {
    let assert Ok(feed) =
      db.insert_feed(
        conn,
        name: Some("Test"),
        site_url: None,
        feed_url: "https://example.com/rss",
        category: "Tech",
      )
    let assert Ok(Nil) =
      db.log_fetch_success(conn, feed.id, "2025-06-19T00:00:00Z")
    let assert Ok(Some(updated)) = db.get_feed(conn, feed.id)
    assert updated.fetch_error == None
    assert updated.last_fetched_at == Some("2025-06-19T00:00:00Z")
  })
}

pub fn log_fetch_error_test() {
  with_db(fn(conn) {
    let assert Ok(feed) =
      db.insert_feed(
        conn,
        name: Some("Test"),
        site_url: None,
        feed_url: "https://example.com/rss",
        category: "Tech",
      )
    let assert Ok(Nil) =
      db.log_fetch_error(
        conn,
        feed.id,
        "2025-06-19T00:00:00Z",
        "HTTP status: 503",
      )
    let assert Ok(Some(updated)) = db.get_feed(conn, feed.id)
    assert updated.fetch_error == Some("HTTP status: 503")
  })
}

// ═══════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════

fn create_entry(
  conn: sqlight.Connection,
  content_link: Option(String),
  comments_link: Option(String),
) -> #(String, String, String) {
  let assert Ok(feed) =
    db.insert_feed(
      conn,
      name: Some("Tracking test"),
      site_url: None,
      feed_url: "https://example.com/" <> db.new_id() <> "/rss",
      category: "Tech",
    )
  let external_id = db.new_id()
  let assert Ok(Nil) =
    db.upsert_entry(
      conn,
      external_id: external_id,
      title: Some("Tracking entry"),
      content_link: content_link,
      comments_link: comments_link,
      published_at: None,
      feed_id: feed.id,
    )
  let assert Ok([id, ..]) =
    sqlight.query(
      "SELECT id FROM entries WHERE feed_id = ? AND external_id = ?",
      on: conn,
      with: [sqlight.text(feed.id), sqlight.text(external_id)],
      expecting: decode.at([0], decode.string),
    )
  #(id, feed.id, external_id)
}

fn first_entry_id(entries: List(db.Entry)) -> String {
  let assert Ok(entry) = list.first(entries)
  entry.id
}
