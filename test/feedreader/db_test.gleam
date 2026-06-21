import feedreader/db
import gleam/list
import gleam/option.{None, Some}
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

fn first_entry_id(entries: List(db.Entry)) -> String {
  let assert Ok(entry) = list.first(entries)
  entry.id
}
