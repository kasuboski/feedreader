import feedreader/db
import feedreader/web/html
import feedreader/web/pages
import gleam/list
import gleam/option.{None, Some}
import gleam/string
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

fn sample_entry(conn: sqlight.Connection) -> db.Entry {
  let assert Ok(feed) =
    db.insert_feed(
      conn,
      name: Some("Test Blog"),
      site_url: None,
      feed_url: "https://example.com/rss",
      category: "Tech",
    )
  let assert Ok(Nil) =
    db.upsert_entry(
      conn,
      external_id: "guid-1",
      title: Some("Test Entry"),
      content_link: Some("https://example.com/1"),
      comments_link: None,
      published_at: None,
      feed_id: feed.id,
    )
  let assert Ok(entries) = db.list_unread(conn, limit: 10, offset: 0)
  let assert Ok(entry) = list.first(entries)
  entry
}

// ═══════════════════════════════════════════════════════════════
// Page render tests
// ═══════════════════════════════════════════════════════════════

pub fn unread_page_renders_entry_test() {
  with_db(fn(conn) {
    let entry = sample_entry(conn)
    let html = pages.unread_page([entry], 0, False)
    assert string.contains(html, "Unread")
    assert string.contains(html, "Test Entry")
    assert string.contains(html, "entry-")
  })
}

pub fn starred_page_renders_heading_test() {
  with_db(fn(_conn) {
    let html = pages.starred_page([], 0, False)
    assert string.contains(html, "Starred")
  })
}

pub fn history_page_renders_entry_test() {
  with_db(fn(conn) {
    let entry = sample_entry(conn)
    let html = pages.history_page([entry], 0, False)
    assert string.contains(html, "History")
    assert string.contains(html, "Test Entry")
  })
}

pub fn feeds_page_renders_feed_test() {
  with_db(fn(conn) {
    let assert Ok(feed) =
      db.insert_feed(
        conn,
        name: Some("My Blog"),
        site_url: None,
        feed_url: "https://blog.example.com/rss",
        category: "Tech",
      )
    let html = pages.feeds_page([feed], None)
    assert string.contains(html, "Feeds")
    assert string.contains(html, "My Blog")
    assert string.contains(html, "https://blog.example.com/rss")
  })
}

pub fn empty_unread_page_test() {
  let html = pages.unread_page([], 0, False)
  assert string.contains(html, "Nothing left to read")
}

pub fn empty_starred_page_test() {
  let html = pages.starred_page([], 0, False)
  assert string.contains(html, "Nothing starred yet")
}

pub fn dark_theme_hardcoded_test() {
  let html = pages.unread_page([], 0, False)
  assert string.contains(html, "data-theme=\"dark\"")
}

pub fn htmx_scripts_loaded_test() {
  let html = pages.unread_page([], 0, False)
  assert string.contains(html, "htmx.min.js")
}

pub fn nav_links_present_test() {
  let html = pages.unread_page([], 0, False)
  assert string.contains(html, "href=\"/\"")
  assert string.contains(html, "href=\"/starred\"")
  assert string.contains(html, "href=\"/history\"")
  assert string.contains(html, "href=\"/feeds\"")
}

pub fn htmx_toggle_attrs_present_test() {
  with_db(fn(conn) {
    let entry = sample_entry(conn)
    let html = pages.unread_page([entry], 0, False)
    assert string.contains(html, "hx-post")
    assert string.contains(html, "toggle-read")
    assert string.contains(html, "toggle-star")
  })
}

pub fn feed_add_form_present_test() {
  let html = pages.feeds_page([], None)
  assert string.contains(html, "Add New Feed")
  assert string.contains(html, "feed_url")
}

pub fn opml_import_form_present_test() {
  let html = pages.feeds_page([], None)
  assert string.contains(html, "Import OPML")
}

pub fn load_more_shown_when_has_more_test() {
  with_db(fn(conn) {
    let entry = sample_entry(conn)
    let html = pages.unread_page([entry], 0, True)
    assert string.contains(html, "Load More")
  })
}

pub fn load_more_hidden_when_no_more_test() {
  with_db(fn(conn) {
    let entry = sample_entry(conn)
    let html = pages.unread_page([entry], 0, False)
    assert !string.contains(html, "Load More")
  })
}

pub fn flash_message_shown_test() {
  let html_doc = pages.feeds_page([], Some(#(info_flash(), "Feed added")))
  assert string.contains(html_doc, "Feed added")
  assert string.contains(html_doc, "alert-info")
}

fn info_flash() -> html.FlashKind {
  html.Info
}
