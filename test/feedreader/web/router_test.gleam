import feedreader/db
import feedreader/web/router
import gleam/http
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import sqlight
import wisp
import wisp/simulate

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

fn sample_entry(conn: sqlight.Connection) -> db.Entry {
  let assert Ok(feed) =
    db.insert_feed(
      conn,
      name: Some("Router Test"),
      site_url: None,
      feed_url: "https://router.example/rss",
      category: "Tech",
    )
  let assert Ok(Nil) =
    db.upsert_entry(
      conn,
      external_id: "router-entry",
      title: Some("Router Entry"),
      content_link: Some("https://router.example/article"),
      comments_link: Some("https://router.example/comments"),
      published_at: None,
      feed_id: feed.id,
    )
  let assert Ok(entries) = db.list_unread(conn, limit: 10, offset: 0)
  let assert Ok(entry) = list.first(entries)
  entry
}

fn post_open(
  conn: sqlight.Connection,
  id: String,
  destination: String,
) -> wisp.Response {
  router.handle_request(
    conn,
    simulate.request(http.Post, "/entry/" <> id <> "/open/" <> destination),
  )
}

pub fn post_content_open_records_once_without_marking_entry_read_test() {
  with_db(fn(conn) {
    let entry = sample_entry(conn)
    let first_response = post_open(conn, entry.id, "content")
    let assert Ok(Some(first_state)) = db.get_entry(conn, entry.id)
    let repeat_response = post_open(conn, entry.id, "content")
    let assert Ok(Some(repeated_state)) = db.get_entry(conn, entry.id)

    assert first_response.status == 200
    assert repeat_response.status == 200
    assert first_state.content_opened_at != None
    assert repeated_state.content_opened_at == first_state.content_opened_at
    assert first_state.comments_opened_at == None
    assert first_state.is_read == False
    assert repeated_state.is_read == False
  })
}

pub fn post_comments_open_records_only_comments_test() {
  with_db(fn(conn) {
    let entry = sample_entry(conn)
    let response = post_open(conn, entry.id, "comments")
    let assert Ok(Some(updated)) = db.get_entry(conn, entry.id)

    assert response.status == 200
    assert updated.comments_opened_at != None
    assert updated.content_opened_at == None
    assert updated.is_read == False
  })
}

pub fn invalid_open_requests_return_not_found_test() {
  with_db(fn(conn) {
    let entry = sample_entry(conn)
    let missing_entry = post_open(conn, "missing-entry", "content")
    let invalid_destination = post_open(conn, entry.id, "unknown")
    let get_request =
      router.handle_request(
        conn,
        simulate.request(http.Get, "/entry/" <> entry.id <> "/open/content"),
      )
    let assert Ok(Some(unchanged)) = db.get_entry(conn, entry.id)

    assert missing_entry.status == 404
    assert invalid_destination.status == 404
    assert get_request.status == 404
    assert unchanged.content_opened_at == None
    assert unchanged.comments_opened_at == None
    assert unchanged.is_read == False
  })
}

pub fn open_without_destination_link_returns_not_found_test() {
  with_db(fn(conn) {
    let assert Ok(feed) =
      db.insert_feed(
        conn,
        name: Some("No Comments Blog"),
        site_url: None,
        feed_url: "https://no-comments.example/rss",
        category: "Tech",
      )
    let assert Ok(Nil) =
      db.upsert_entry(
        conn,
        external_id: "no-comments",
        title: Some("No Comments"),
        content_link: Some("https://no-comments.example/article"),
        comments_link: None,
        published_at: None,
        feed_id: feed.id,
      )
    let assert Ok([entry]) = db.list_unread(conn, limit: 10, offset: 0)
    let response = post_open(conn, entry.id, "comments")
    let assert Ok(Some(unchanged)) = db.get_entry(conn, entry.id)

    assert response.status == 404
    assert unchanged.comments_opened_at == None
    assert unchanged.content_opened_at == None
  })
}
