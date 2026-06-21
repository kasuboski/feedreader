import birl
import birl/duration
import feedreader/db
import feedreader/scheduler
import gleam/list
import gleam/option.{type Option, None, Some}
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

// ═══════════════════════════════════════════════════════════════
// feeds_due pure decision function tests
// ═══════════════════════════════════════════════════════════════

pub fn never_fetched_feed_is_due_test() {
  with_db(fn(conn) {
    let assert Ok(feed) =
      db.insert_feed(
        conn,
        name: Some("A"),
        site_url: None,
        feed_url: "https://a.com/rss",
        category: "Tech",
      )
    let now = birl.utc_now()
    let due = scheduler.feeds_due([feed], now)
    assert list.length(due) == 1
  })
}

pub fn recently_fetched_feed_is_not_due_test() {
  with_db(fn(conn) {
    let assert Ok(feed) =
      db.insert_feed(
        conn,
        name: Some("A"),
        site_url: None,
        feed_url: "https://a.com/rss",
        category: "Tech",
      )
    // Mark as fetched 2 minutes ago
    let two_min_ago =
      birl.utc_now()
      |> birl.subtract(duration.minutes(2))
      |> birl.to_iso8601
    let assert Ok(Nil) = db.log_fetch_success(conn, feed.id, two_min_ago)
    let assert Ok(updated) = db.get_feed(conn, feed.id)
    let feed_with_ts = result_unwrap(updated)

    let now = birl.utc_now()
    let due = scheduler.feeds_due([feed_with_ts], now)
    assert due == []
  })
}

pub fn old_fetched_feed_is_due_test() {
  with_db(fn(conn) {
    let assert Ok(feed) =
      db.insert_feed(
        conn,
        name: Some("A"),
        site_url: None,
        feed_url: "https://a.com/rss",
        category: "Tech",
      )
    // Mark as fetched 15 minutes ago (> 10 min threshold)
    let fifteen_min_ago =
      birl.utc_now()
      |> birl.subtract(duration.minutes(15))
      |> birl.to_iso8601
    let assert Ok(Nil) = db.log_fetch_success(conn, feed.id, fifteen_min_ago)
    let assert Ok(updated) = db.get_feed(conn, feed.id)
    let feed_with_ts = result_unwrap(updated)

    let now = birl.utc_now()
    let due = scheduler.feeds_due([feed_with_ts], now)
    assert list.length(due) == 1
  })
}

pub fn mixed_feeds_filters_correctly_test() {
  with_db(fn(conn) {
    let assert Ok(_feed_a) =
      db.insert_feed(
        conn,
        name: Some("A"),
        site_url: None,
        feed_url: "https://a.com/rss",
        category: "Tech",
      )
    let assert Ok(feed_b) =
      db.insert_feed(
        conn,
        name: Some("B"),
        site_url: None,
        feed_url: "https://b.com/rss",
        category: "Tech",
      )
    let assert Ok(feed_c) =
      db.insert_feed(
        conn,
        name: Some("C"),
        site_url: None,
        feed_url: "https://c.com/rss",
        category: "Tech",
      )

    // Feed B: fetched 2 min ago (not due)
    let two_min_ago =
      birl.utc_now()
      |> birl.subtract(duration.minutes(2))
      |> birl.to_iso8601
    let assert Ok(Nil) = db.log_fetch_success(conn, feed_b.id, two_min_ago)

    // Feed C: fetched 20 min ago (due)
    let twenty_min_ago =
      birl.utc_now()
      |> birl.subtract(duration.minutes(20))
      |> birl.to_iso8601
    let assert Ok(Nil) = db.log_fetch_success(conn, feed_c.id, twenty_min_ago)

    let assert Ok(feeds) = db.list_feeds(conn)
    let now = birl.utc_now()
    let due = scheduler.feeds_due(feeds, now)
    // Feed A (never fetched) + Feed C (old) = 2 due; Feed B (recent) = not due
    assert list.length(due) == 2
  })
}

fn result_unwrap(opt: Option(a)) -> a {
  let assert Some(v) = opt
  v
}
