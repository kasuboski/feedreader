//// Wisp router — all HTTP request handlers.
////
//// Full pages return complete HTML documents.
//// HTMX endpoints return HTML fragments with appropriate hx headers.
//// Static assets served from priv/static.

import feedreader/db
import feedreader/opml
import feedreader/web/fragments
import feedreader/web/html as view
import feedreader/web/pages
import gleam/http
import gleam/http/request
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile
import sqlight
import wisp

/// The request handler. Takes a DB connection and a Wisp request.
pub fn handle_request(conn: sqlight.Connection, req: wisp.Request) {
  use <- wisp.log_request(req)
  use req <- wisp.handle_head(req)
  use <- wisp.serve_static(req, under: "static", from: "priv/static")

  let method = req.method
  let query_params = wisp.get_query(req)
  case method, wisp.path_segments(req) {
    // ═══ Entry listing pages (full HTML) ═══
    http.Get, [] -> unread_page(conn, req, query_params)
    http.Get, ["starred"] -> starred_page(conn, req, query_params)
    http.Get, ["history"] -> history_page(conn, req, query_params)
    http.Get, ["feeds"] -> feeds_page(conn, None)

    // ═══ Entry toggle endpoints (HTMX fragments) ═══
    http.Post, ["entry", id, "toggle-read"] ->
      toggle_read_handler(conn, req, id)
    http.Post, ["entry", id, "toggle-star"] ->
      toggle_star_handler(conn, req, id)

    // ═══ Feed management ═══
    http.Post, ["feeds"] -> add_feed_handler(conn, req)
    http.Post, ["feeds", "import"] -> import_opml_handler(conn, req)
    http.Delete, ["feeds", id] -> delete_feed_handler(conn, id)

    _, _ -> wisp.not_found()
  }
}

// ═══════════════════════════════════════════════════════════════
// Full page handlers (with pagination support via query params)
// ═══════════════════════════════════════════════════════════════

fn unread_page(
  conn: sqlight.Connection,
  req: wisp.Request,
  query: List(#(String, String)),
) {
  let offset = get_offset(query)
  let assert Ok(entries) = db.list_unread(conn, limit: pages.page_size, offset:)
  let has_more = list.length(entries) >= pages.page_size
  // HTMX requests get fragments; full page loads get the full document.
  case is_htmx_request(req), offset > 0 {
    True, True -> load_more_fragment_response(entries, offset, has_more, "")
    _, _ -> {
      let body = pages.unread_page(entries, offset, has_more)
      html_response(body)
    }
  }
}

fn starred_page(
  conn: sqlight.Connection,
  req: wisp.Request,
  query: List(#(String, String)),
) {
  let offset = get_offset(query)
  let assert Ok(entries) =
    db.list_starred(conn, limit: pages.page_size, offset:)
  let has_more = list.length(entries) >= pages.page_size
  case is_htmx_request(req), offset > 0 {
    True, True ->
      load_more_fragment_response(entries, offset, has_more, "/starred")
    _, _ -> {
      let body = pages.starred_page(entries, offset, has_more)
      html_response(body)
    }
  }
}

fn history_page(
  conn: sqlight.Connection,
  req: wisp.Request,
  query: List(#(String, String)),
) {
  let offset = get_offset(query)
  let assert Ok(entries) =
    db.list_history(conn, limit: pages.page_size, offset:)
  let has_more = list.length(entries) >= pages.page_size
  case is_htmx_request(req), offset > 0 {
    True, True ->
      load_more_fragment_response(entries, offset, has_more, "/history")
    _, _ -> {
      let body = pages.history_page(entries, offset, has_more)
      html_response(body)
    }
  }
}

fn feeds_page(
  conn: sqlight.Connection,
  flash: Option(#(view.FlashKind, String)),
) {
  let assert Ok(feeds) = db.list_feeds(conn)
  let body = pages.feeds_page(feeds, flash)
  html_response(body)
}

// ═══════════════════════════════════════════════════════════════
// Toggle handlers (HTMX — return card fragment or empty)
// ═══════════════════════════════════════════════════════════════
//
// On filtered pages, entries that no longer match the filter should
// disappear. This mirrors the old Elixir app's stream_delete logic:
//   - Unread page + mark read → entry removed
//   - Starred page + un-star → entry removed
//   - Everything else → card updated in place

/// Extract the page view from the Referer header.
/// Returns "unread", "starred", "history", or "other".
fn referer_view(req: wisp.Request) -> String {
  let ref = result.unwrap(request.get_header(req, "referer"), "")
  let is_unread = string.ends_with(ref, "/")
  let is_starred = string.ends_with(ref, "/starred")
  let is_history = string.ends_with(ref, "/history")
  case is_unread, is_starred, is_history {
    True, _, _ -> "unread"
    _, True, _ -> "starred"
    _, _, True -> "history"
    _, _, _ -> "other"
  }
}

fn toggle_read_handler(
  conn: sqlight.Connection,
  req: wisp.Request,
  id: String,
) {
  let _ = db.toggle_read(conn, id)
  case db.get_entry(conn, id) {
    Ok(Some(entry)) -> {
      // On the unread page, marking as read removes the entry.
      case referer_view(req), entry.is_read {
        "unread", True -> empty_fragment_response()
        _, _ -> {
          let body = fragments.entry_card_fragment(entry)
          fragment_response(body)
        }
      }
    }
    _ -> wisp.not_found()
  }
}

fn toggle_star_handler(
  conn: sqlight.Connection,
  req: wisp.Request,
  id: String,
) {
  let _ = db.toggle_starred(conn, id)
  case db.get_entry(conn, id) {
    Ok(Some(entry)) -> {
      // On the starred page, un-starring removes the entry.
      case referer_view(req), entry.is_starred {
        "starred", False -> empty_fragment_response()
        _, _ -> {
          let body = fragments.entry_card_fragment(entry)
          fragment_response(body)
        }
      }
    }
    _ -> wisp.not_found()
  }
}

// ═══════════════════════════════════════════════════════════════
// Feed management handlers
// ═══════════════════════════════════════════════════════════════

fn add_feed_handler(conn: sqlight.Connection, req: wisp.Request) {
  use form <- wisp.require_form(req)
  let feed_url = get_form_value(form, "feed_url")
  let name = get_form_value(form, "name")
  let site_url = get_form_value(form, "site_url")
  let category = get_form_value(form, "category")

  case feed_url {
    Some(url) if url != "" -> {
      let cat = option.unwrap(category, "Uncategorized")
      let _ =
        db.insert_feed(
          conn,
          name:,
          site_url:,
          feed_url: url,
          category: case cat {
            "" -> "Uncategorized"
            other -> other
          },
        )
      feeds_page(conn, Some(#(view.Info, "Feed added successfully")))
    }
    _ -> feeds_page(conn, Some(#(view.Error, "Feed URL is required")))
  }
}

fn import_opml_handler(conn: sqlight.Connection, req: wisp.Request) {
  use form <- wisp.require_form(req)
  case get_form_file(form, "opml") {
    Some(path) ->
      case simplifile.read(path) {
        Ok(content) ->
          case opml.parse_opml(content) {
            Ok(feed_attrs) -> {
              let _ =
                list.map(feed_attrs, fn(attrs) {
                  let _ =
                    db.insert_feed(
                      conn,
                      name: attrs.name,
                      site_url: attrs.site_url,
                      feed_url: attrs.feed_url,
                      category: attrs.category,
                    )
                })
              let count = list.length(feed_attrs)
              feeds_page(
                conn,
                Some(#(
                  view.Info,
                  "Imported " <> int.to_string(count) <> " feeds",
                )),
              )
            }
            Error(_) ->
              feeds_page(conn, Some(#(view.Error, "Failed to parse OPML file")))
          }
        Error(_) ->
          feeds_page(conn, Some(#(view.Error, "Failed to read uploaded file")))
      }
    None -> feeds_page(conn, Some(#(view.Error, "No file uploaded")))
  }
}

fn delete_feed_handler(conn: sqlight.Connection, id: String) {
  let _ = db.delete_feed(conn, id)
  wisp.ok()
  |> wisp.html_body("")
}

// ═══════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════

fn html_response(body: String) -> wisp.Response {
  wisp.ok()
  |> wisp.html_body(body)
}

fn fragment_response(body: String) -> wisp.Response {
  wisp.ok()
  |> wisp.html_body(body)
}

/// Return an empty fragment response. HTMX replaces the target element with
/// empty content, effectively removing it from the DOM.
fn empty_fragment_response() -> wisp.Response {
  wisp.ok()
  |> wisp.html_body("")
}

/// Check if the request was made by HTMX (sends HX-Request: true header).
fn is_htmx_request(req: wisp.Request) -> Bool {
  result.is_ok(request.get_header(req, "hx-request"))
}

/// Build a load-more fragment response: entry cards + OOB-updated Load More button.
/// The entry cards get appended to #entries (beforeend swap).
/// The Load More button is replaced via hx-swap-oob so it points to the next batch.
fn load_more_fragment_response(
  entries: List(db.Entry),
  offset: Int,
  has_more: Bool,
  base_path: String,
) -> wisp.Response {
  let cards = fragments.entry_list_fragment(entries)
  let next_btn = case has_more {
    True -> pages.load_more_button_html(offset + pages.page_size, base_path)
    False -> "<div id=\"load-more-container\" hx-swap-oob=\"true\"></div>"
  }
  // The entry cards go inline (appended to #entries by hx-swap="beforeend").
  // The load-more-container is swapped OOB.
  let body = cards <> next_btn
  fragment_response(body)
}

fn get_offset(query: List(#(String, String))) -> Int {
  case list.key_find(query, "after") {
    Ok(val) -> result.unwrap(int.parse(val), 0)
    Error(_) -> 0
  }
}

fn get_form_value(form: wisp.FormData, key: String) -> Option(String) {
  case list.key_find(form.values, key) {
    Ok(val) ->
      case val {
        "" -> None
        other -> Some(other)
      }
    Error(_) -> None
  }
}

fn get_form_file(form: wisp.FormData, key: String) -> Option(String) {
  case list.key_find(form.files, key) {
    Ok(file) -> Some(file.path)
    Error(_) -> None
  }
}
