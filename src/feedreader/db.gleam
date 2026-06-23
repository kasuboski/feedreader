//// Database initialization and typed CRUD for FeedReader.
////
//// Opens SQLite, runs migrations (from schema.sql), and provides typed
//// query functions using Parrot-generated codegen.
////
//// The `Feed` and `Entry` types are the domain models. The Parrot-generated
//// types in `sql.gleam` are close to the DB shape but use `Option(String)` for
//// nullable columns and `Int` for booleans — this module normalizes to
//// idiomatic Gleam types (`Option(String)`, `Bool`).

import birl
import feedreader/sql
import gleam/bit_array
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gluid
import parrot/dev.{type Param}
import simplifile
import sqlight

// ═══════════════════════════════════════════════════════════════
// Public Types
// ═══════════════════════════════════════════════════════════════

pub type Feed {
  Feed(
    id: String,
    name: Option(String),
    site_url: Option(String),
    feed_url: String,
    category: String,
    last_fetched_at: Option(String),
    fetch_error: Option(String),
  )
}

pub type Entry {
  Entry(
    id: String,
    created_at: String,
    external_id: String,
    title: Option(String),
    content_link: Option(String),
    comments_link: Option(String),
    published_at: Option(String),
    is_read: Bool,
    is_starred: Bool,
    feed_id: String,
    feed_name: Option(String),
  )
}

// ═══════════════════════════════════════════════════════════════
// Param Conversion
// ═══════════════════════════════════════════════════════════════

fn param_to_value(p: Param) -> sqlight.Value {
  case p {
    dev.ParamString(s) -> sqlight.text(s)
    dev.ParamInt(i) -> sqlight.int(i)
    dev.ParamFloat(f) -> sqlight.float(f)
    dev.ParamBool(b) -> sqlight.bool(b)
    dev.ParamBitArray(b) -> sqlight.text(bit_array_to_string(b))
    _ -> sqlight.null()
  }
}

fn bit_array_to_string(ba: BitArray) -> String {
  case bit_array.to_string(ba) {
    Ok(s) -> s
    Error(_) -> ""
  }
}

fn params_to_values(params: List(Param)) -> List(sqlight.Value) {
  list.map(params, param_to_value)
}

/// Convert an Option(String) to an empty string for Parrot params.
/// The DB stores "" for nullable text — read side maps back to None.
fn opt_to_str(opt: Option(String)) -> String {
  case opt {
    Some(s) -> s
    None -> ""
  }
}

// ═══════════════════════════════════════════════════════════════
// Database Open & Migrate
// ═══════════════════════════════════════════════════════════════

/// Open a SQLite database at the given path.
/// Use "file::memory:" for in-memory databases (tests).
pub fn open(path: String) -> Result(sqlight.Connection, sqlight.Error) {
  sqlight.open(path)
}

/// Run all migrations to create the schema.
/// Safe to call multiple times (uses IF NOT EXISTS).
/// Also enables foreign keys for cascade delete support.
///
/// Reads the schema from `priv/schema.sql` — the single source of truth.
/// The same file is used by Parrot for codegen (`mise run gen`).
pub fn migrate(conn: sqlight.Connection) -> Result(Nil, sqlight.Error) {
  let _ = sqlight.exec("PRAGMA foreign_keys = ON", on: conn)
  let assert Ok(sql) = simplifile.read("priv/schema.sql")
  sqlight.exec(sql, on: conn)
}

/// Generate a new UUID (lowercase v4).
pub fn new_id() -> String {
  gluid.guidv4() |> string.lowercase()
}

/// Current timestamp in ISO8601 format (for DB storage).
pub fn now_ts() -> String {
  birl.utc_now() |> birl.to_iso8601()
}

// ═══════════════════════════════════════════════════════════════
// Feed Queries
// ═══════════════════════════════════════════════════════════════

/// List all feeds, ordered by category then name.
pub fn list_feeds(conn: sqlight.Connection) -> Result(List(Feed), Nil) {
  let #(sql_str, params, decoder) = sql.list_feeds()
  sqlight.query(
    sql_str,
    on: conn,
    with: params_to_values(params),
    expecting: decoder,
  )
  |> result.map(fn(rows) { list.map(rows, row_to_feed_list) })
  |> result.replace_error(Nil)
}

/// Get a feed by ID.
pub fn get_feed(
  conn: sqlight.Connection,
  id: String,
) -> Result(Option(Feed), Nil) {
  let #(sql_str, params, decoder) = sql.get_feed(id:)
  sqlight.query(
    sql_str,
    on: conn,
    with: params_to_values(params),
    expecting: decoder,
  )
  |> result.map(fn(rows) {
    case rows {
      [row] -> Some(row_to_feed(row))
      _ -> None
    }
  })
  |> result.replace_error(Nil)
}

/// Get a feed by its feed_url.
pub fn get_feed_by_url(
  conn: sqlight.Connection,
  feed_url: String,
) -> Result(Option(Feed), Nil) {
  let #(sql_str, params, decoder) = sql.get_feed_by_url(feed_url:)
  sqlight.query(
    sql_str,
    on: conn,
    with: params_to_values(params),
    expecting: decoder,
  )
  |> result.map(fn(rows) {
    case rows {
      [row] -> Some(row_to_feed_by_url(row))
      _ -> None
    }
  })
  |> result.replace_error(Nil)
}

/// Insert a new feed. Returns the feed on success, Error(Nil) on
/// constraint violation (e.g. duplicate feed_url).
pub fn insert_feed(
  conn: sqlight.Connection,
  name name: Option(String),
  site_url site_url: Option(String),
  feed_url feed_url: String,
  category category: String,
) -> Result(Feed, Nil) {
  let id = new_id()
  let #(sql_str, params) =
    sql.insert_feed(
      id: id,
      name: opt_to_str(name),
      site_url: opt_to_str(site_url),
      feed_url: feed_url,
      category: category,
      last_fetched_at: "",
      fetch_error: "",
    )
  case
    sqlight.query(
      sql_str,
      on: conn,
      with: params_to_values(params),
      expecting: decode.success(Nil),
    )
  {
    Ok(_) ->
      Ok(Feed(
        id: id,
        name: name,
        site_url: site_url,
        feed_url: feed_url,
        category: category,
        last_fetched_at: None,
        fetch_error: None,
      ))
    Error(_) -> Error(Nil)
  }
}

/// Delete a feed by ID. Cascades to entries (requires PRAGMA foreign_keys=ON).
pub fn delete_feed(conn: sqlight.Connection, id: String) -> Result(Nil, Nil) {
  let #(sql_str, params) = sql.delete_feed(id:)
  sqlight.query(
    sql_str,
    on: conn,
    with: params_to_values(params),
    expecting: decode.success(Nil),
  )
  |> result.map(fn(_) { Nil })
  |> result.replace_error(Nil)
}

/// Update feed's last_fetched_at and clear fetch_error.
pub fn log_fetch_success(
  conn: sqlight.Connection,
  id: String,
  fetched_at: String,
) -> Result(Nil, Nil) {
  let #(sql_str, params) =
    sql.log_fetch_success(last_fetched_at: fetched_at, id:)
  sqlight.query(
    sql_str,
    on: conn,
    with: params_to_values(params),
    expecting: decode.success(Nil),
  )
  |> result.map(fn(_) { Nil })
  |> result.replace_error(Nil)
}

/// Update feed's last_fetched_at and set fetch_error.
pub fn log_fetch_error(
  conn: sqlight.Connection,
  id: String,
  fetched_at: String,
  error: String,
) -> Result(Nil, Nil) {
  let #(sql_str, params) =
    sql.log_fetch_error(last_fetched_at: fetched_at, fetch_error: error, id:)
  sqlight.query(
    sql_str,
    on: conn,
    with: params_to_values(params),
    expecting: decode.success(Nil),
  )
  |> result.map(fn(_) { Nil })
  |> result.replace_error(Nil)
}

// ═══════════════════════════════════════════════════════════════
// Entry Queries
// ═══════════════════════════════════════════════════════════════

/// Get an entry by ID.
pub fn get_entry(
  conn: sqlight.Connection,
  id: String,
) -> Result(Option(Entry), Nil) {
  let #(sql_str, params, decoder) = sql.get_entry(id:)
  sqlight.query(
    sql_str,
    on: conn,
    with: params_to_values(params),
    expecting: decoder,
  )
  |> result.map(fn(rows) {
    case rows {
      [row] -> Some(row_to_entry(row))
      _ -> None
    }
  })
  |> result.replace_error(Nil)
}

/// Upsert an entry. Uses ON CONFLICT(feed_id, external_id) to deduplicate.
pub fn upsert_entry(
  conn: sqlight.Connection,
  external_id external_id: String,
  title title: Option(String),
  content_link content_link: Option(String),
  comments_link comments_link: Option(String),
  published_at published_at: Option(String),
  feed_id feed_id: String,
) -> Result(Nil, Nil) {
  let id = new_id()
  let created = now_ts()
  let #(sql_str, params) =
    sql.upsert_entry(
      id: id,
      created_at: created,
      external_id: external_id,
      title: opt_to_str(title),
      content_link: opt_to_str(content_link),
      comments_link: opt_to_str(comments_link),
      published_at: opt_to_str(published_at),
      is_read: 0,
      is_starred: 0,
      feed_id: feed_id,
    )
  sqlight.query(
    sql_str,
    on: conn,
    with: params_to_values(params),
    expecting: decode.success(Nil),
  )
  |> result.map(fn(_) { Nil })
  |> result.replace_error(Nil)
}

/// List unread entries (is_read = false), oldest first.
pub fn list_unread(
  conn: sqlight.Connection,
  limit limit: Int,
  offset offset: Int,
) -> Result(List(Entry), Nil) {
  let #(sql_str, params, decoder) = sql.list_unread(limit:, offset:)
  sqlight.query(
    sql_str,
    on: conn,
    with: params_to_values(params),
    expecting: decoder,
  )
  |> result.map(fn(rows) { list.map(rows, row_to_entry_unread) })
  |> result.replace_error(Nil)
}

/// List starred entries (is_starred = true), oldest first.
pub fn list_starred(
  conn: sqlight.Connection,
  limit limit: Int,
  offset offset: Int,
) -> Result(List(Entry), Nil) {
  let #(sql_str, params, decoder) = sql.list_starred(limit:, offset:)
  sqlight.query(
    sql_str,
    on: conn,
    with: params_to_values(params),
    expecting: decoder,
  )
  |> result.map(fn(rows) { list.map(rows, row_to_entry_starred) })
  |> result.replace_error(Nil)
}

/// List all entries (history), newest first.
pub fn list_history(
  conn: sqlight.Connection,
  limit limit: Int,
  offset offset: Int,
) -> Result(List(Entry), Nil) {
  let #(sql_str, params, decoder) = sql.list_history(limit:, offset:)
  sqlight.query(
    sql_str,
    on: conn,
    with: params_to_values(params),
    expecting: decoder,
  )
  |> result.map(fn(rows) { list.map(rows, row_to_entry_history) })
  |> result.replace_error(Nil)
}

/// Toggle the is_read flag on an entry.
pub fn toggle_read(conn: sqlight.Connection, id: String) -> Result(Nil, Nil) {
  case get_entry(conn, id) {
    Ok(Some(entry)) -> {
      let new_val = !entry.is_read
      let #(sql_str, params) =
        sql.toggle_read(is_read: bool_to_int(new_val), id:)
      sqlight.query(
        sql_str,
        on: conn,
        with: params_to_values(params),
        expecting: decode.success(Nil),
      )
      |> result.map(fn(_) { Nil })
      |> result.replace_error(Nil)
    }
    _ -> Error(Nil)
  }
}

/// Toggle the is_starred flag on an entry.
pub fn toggle_starred(
  conn: sqlight.Connection,
  id: String,
) -> Result(Nil, Nil) {
  case get_entry(conn, id) {
    Ok(Some(entry)) -> {
      let new_val = !entry.is_starred
      let #(sql_str, params) =
        sql.toggle_starred(is_starred: bool_to_int(new_val), id:)
      sqlight.query(
        sql_str,
        on: conn,
        with: params_to_values(params),
        expecting: decode.success(Nil),
      )
      |> result.map(fn(_) { Nil })
      |> result.replace_error(Nil)
    }
    _ -> Error(Nil)
  }
}

/// Count unread entries.
pub fn unread_count(conn: sqlight.Connection) -> Result(Int, Nil) {
  let #(sql_str, params, decoder) = sql.unread_count()
  sqlight.query(
    sql_str,
    on: conn,
    with: params_to_values(params),
    expecting: decoder,
  )
  |> result.map(fn(rows) {
    case rows {
      [row] -> row.count
      _ -> 0
    }
  })
  |> result.replace_error(Nil)
}

/// Count starred entries.
pub fn starred_count(conn: sqlight.Connection) -> Result(Int, Nil) {
  let #(sql_str, params, decoder) = sql.starred_count()
  sqlight.query(
    sql_str,
    on: conn,
    with: params_to_values(params),
    expecting: decoder,
  )
  |> result.map(fn(rows) {
    case rows {
      [row] -> row.count
      _ -> 0
    }
  })
  |> result.replace_error(Nil)
}

// ═══════════════════════════════════════════════════════════════
// Internal helpers
// ═══════════════════════════════════════════════════════════════

fn row_to_feed_list(row: sql.ListFeeds) -> Feed {
  Feed(
    id: row.id,
    name: row.name,
    site_url: row.site_url,
    feed_url: row.feed_url,
    category: row.category,
    last_fetched_at: row.last_fetched_at,
    fetch_error: row.fetch_error,
  )
}

fn row_to_feed(row: sql.GetFeed) -> Feed {
  Feed(
    id: row.id,
    name: row.name,
    site_url: row.site_url,
    feed_url: row.feed_url,
    category: row.category,
    last_fetched_at: row.last_fetched_at,
    fetch_error: row.fetch_error,
  )
}

fn row_to_feed_by_url(row: sql.GetFeedByUrl) -> Feed {
  Feed(
    id: row.id,
    name: row.name,
    site_url: row.site_url,
    feed_url: row.feed_url,
    category: row.category,
    last_fetched_at: row.last_fetched_at,
    fetch_error: row.fetch_error,
  )
}

fn row_to_entry_unread(row: sql.ListUnread) -> Entry {
  Entry(
    id: row.id,
    created_at: row.created_at,
    external_id: row.external_id,
    title: str_to_opt(row.title),
    content_link: str_to_opt(row.content_link),
    comments_link: str_to_opt(row.comments_link),
    published_at: str_to_opt(row.published_at),
    is_read: int_to_bool(row.is_read),
    is_starred: int_to_bool(row.is_starred),
    feed_id: row.feed_id,
    feed_name: compute_feed_name(
      row.feed_name,
      row.feed_site_url,
      row.feed_feed_url,
    ),
  )
}

fn row_to_entry_starred(row: sql.ListStarred) -> Entry {
  Entry(
    id: row.id,
    created_at: row.created_at,
    external_id: row.external_id,
    title: str_to_opt(row.title),
    content_link: str_to_opt(row.content_link),
    comments_link: str_to_opt(row.comments_link),
    published_at: str_to_opt(row.published_at),
    is_read: int_to_bool(row.is_read),
    is_starred: int_to_bool(row.is_starred),
    feed_id: row.feed_id,
    feed_name: compute_feed_name(
      row.feed_name,
      row.feed_site_url,
      row.feed_feed_url,
    ),
  )
}

fn row_to_entry_history(row: sql.ListHistory) -> Entry {
  Entry(
    id: row.id,
    created_at: row.created_at,
    external_id: row.external_id,
    title: str_to_opt(row.title),
    content_link: str_to_opt(row.content_link),
    comments_link: str_to_opt(row.comments_link),
    published_at: str_to_opt(row.published_at),
    is_read: int_to_bool(row.is_read),
    is_starred: int_to_bool(row.is_starred),
    feed_id: row.feed_id,
    feed_name: compute_feed_name(
      row.feed_name,
      row.feed_site_url,
      row.feed_feed_url,
    ),
  )
}

fn row_to_entry(row: sql.GetEntry) -> Entry {
  Entry(
    id: row.id,
    created_at: row.created_at,
    external_id: row.external_id,
    title: str_to_opt(row.title),
    content_link: str_to_opt(row.content_link),
    comments_link: str_to_opt(row.comments_link),
    published_at: str_to_opt(row.published_at),
    is_read: int_to_bool(row.is_read),
    is_starred: int_to_bool(row.is_starred),
    feed_id: row.feed_id,
    feed_name: compute_feed_name(
      row.feed_name,
      row.feed_site_url,
      row.feed_feed_url,
    ),
  )
}

/// Treat empty string as None (Parrot stores "" for nullable columns).
fn str_to_opt(s: Option(String)) -> Option(String) {
  case s {
    Some("") -> None
    other -> other
  }
}

/// Compute display name for a feed, matching the old Elixir app's
/// feed_display_name/1 logic: use name if present, else root domain of
/// site_url, else root domain of feed_url.
fn compute_feed_name(
  name: Option(String),
  site_url: Option(String),
  feed_url: String,
) -> Option(String) {
  case str_to_opt(name) {
    Some(n) -> Some(n)
    None ->
      case str_to_opt(site_url) {
        Some(u) -> root_domain(u)
        None -> root_domain(feed_url)
      }
  }
}

/// Extract root domain (e.g. "news.ycombinator.com" → "ycombinator.com")
/// from a URL string.
fn root_domain(url: String) -> Option(String) {
  let host =
    url
    |> string.replace("https://", "")
    |> string.replace("http://", "")
    |> string.split("/")
    |> list.first
    |> result.unwrap("")

  case host {
    "" -> None
    _ -> {
      let parts = string.split(host, ".") |> list.reverse()
      case parts {
        [tld, second, ..] -> Some(second <> "." <> tld)
        [single] -> Some(single)
        [] -> None
      }
    }
  }
}

fn bool_to_int(b: Bool) -> Int {
  case b {
    True -> 1
    False -> 0
  }
}

fn int_to_bool(i: Int) -> Bool {
  case i {
    0 -> False
    _ -> True
  }
}

/// Format an Int for SQL params.
pub fn int_to_param(i: Int) -> Param {
  dev.ParamInt(i)
}
