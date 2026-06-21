import feedreader/db
import feedreader/fetcher
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import sqlight

pub fn main() -> Nil {
  gleeunit.main()
}

fn with_db(f: fn(sqlight.Connection) -> a) -> a {
  let assert Ok(conn) = sqlight.open("file::memory:")
  let assert Ok(Nil) = db.migrate(conn)
  let result = f(conn)
  let assert Ok(Nil) = sqlight.close(conn)
  result
}

fn seed_feed(conn: sqlight.Connection) -> db.Feed {
  let assert Ok(feed) =
    db.insert_feed(
      conn,
      name: Some("Test Feed"),
      site_url: Some("https://example.com"),
      feed_url: "https://example.com/feed.rss",
      category: "Test",
    )
  feed
}

fn mock_rss_body() -> String {
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<rss version=\"2.0\">
  <channel>
    <title>Test Feed</title>
    <item>
      <title>Test Entry</title>
      <link>https://example.com/1</link>
      <guid>test-guid-1</guid>
    </item>
  </channel>
</rss>"
}

fn mock_success(_url: String) -> Result(String, String) {
  Ok(mock_rss_body())
}

fn mock_failure(_url: String) -> Result(String, String) {
  Error("HTTP status: 503")
}

// ═══════════════════════════════════════════════════════════════
// process_feed tests (synchronous, no process.sleep)
// ═══════════════════════════════════════════════════════════════

pub fn process_feed_success_persists_entries_test() {
  with_db(fn(conn) {
    let feed = seed_feed(conn)
    let result = fetcher.process_feed(conn, feed.id, mock_success)
    assert result == fetcher.Fetched(count: 1)

    let assert Ok(entries) = db.list_unread(conn, limit: 10, offset: 0)
    assert list.length(entries) == 1
    let assert Ok(first) = list.first(entries)
    assert first.external_id == "test-guid-1"
    assert first.title == Some("Test Entry")
    assert first.feed_id == feed.id
  })
}

pub fn process_feed_success_logs_fetch_test() {
  with_db(fn(conn) {
    let feed = seed_feed(conn)
    let _ = fetcher.process_feed(conn, feed.id, mock_success)
    let assert Ok(Some(updated)) = db.get_feed(conn, feed.id)
    assert updated.last_fetched_at != None
    assert updated.fetch_error == None
  })
}

pub fn process_feed_failure_logs_error_test() {
  with_db(fn(conn) {
    let feed = seed_feed(conn)
    let result = fetcher.process_feed(conn, feed.id, mock_failure)
    assert result == fetcher.FetchFailed(error: "HTTP status: 503")

    let assert Ok(Some(updated)) = db.get_feed(conn, feed.id)
    assert updated.last_fetched_at != None
    assert updated.fetch_error == Some("HTTP status: 503")
  })
}

pub fn process_feed_unknown_feed_test() {
  with_db(fn(conn) {
    let result = fetcher.process_feed(conn, "nonexistent-id", mock_success)
    assert result == fetcher.FetchFailed(error: "Feed not found")
  })
}

pub fn process_feed_parse_error_logs_error_test() {
  with_db(fn(conn) {
    let feed = seed_feed(conn)
    let result =
      fetcher.process_feed(conn, feed.id, fn(_) { Ok("<not>valid<rss") })
    case result {
      fetcher.FetchFailed(_) -> Nil
      _ -> panic as "expected FetchFailed"
    }
  })
}

pub fn process_feed_dedup_on_refetch_test() {
  with_db(fn(conn) {
    let feed = seed_feed(conn)
    let _ = fetcher.process_feed(conn, feed.id, mock_success)
    let _ = fetcher.process_feed(conn, feed.id, mock_success)
    let assert Ok(entries) = db.list_unread(conn, limit: 10, offset: 0)
    assert list.length(entries) == 1
  })
}

pub fn process_feed_updates_changed_entry_test() {
  with_db(fn(conn) {
    let feed = seed_feed(conn)
    let _ = fetcher.process_feed(conn, feed.id, mock_success)
    let _ =
      fetcher.process_feed(conn, feed.id, fn(_) {
        Ok(
          "<?xml version=\"1.0\"?>
<rss version=\"2.0\"><channel>
  <item>
    <title>New Title</title>
    <link>https://example.com/1</link>
    <guid>test-guid-1</guid>
  </item>
</channel></rss>",
        )
      })
    let assert Ok(entries) = db.list_unread(conn, limit: 10, offset: 0)
    let assert Ok(entry) = list.first(entries)
    assert entry.title == Some("New Title")
  })
}

// ═══════════════════════════════════════════════════════════════
// Actor lifecycle tests
// ═══════════════════════════════════════════════════════════════

pub fn actor_starts_and_stops_test() {
  let assert Ok(conn) = sqlight.open("file::memory:")
  let assert Ok(Nil) = db.migrate(conn)
  let assert Ok(started) = fetcher.start(conn, mock_success)
  process.send(started.data, fetcher.Stop)
  let assert Ok(Nil) = sqlight.close(conn)
}
