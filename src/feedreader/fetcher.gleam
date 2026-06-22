//// Feed fetcher: HTTP fetch + RSS parse + DB upsert.
////
//// The core logic is a pure synchronous function (`process_feed`) that's easy
//// to test without actors or process.sleep. The actor wrapper (`start`)
//// dispatches Fetch messages to this function.

import feedreader/db
import feedreader/http
import feedreader/rss
import gleam/erlang/process
import gleam/list
import gleam/option.{Some}
import gleam/otp/actor
import gleam/result
import sqlight

// ═══════════════════════════════════════════════════════════════
// Core fetch logic (synchronous, testable)
// ═══════════════════════════════════════════════════════════════

pub type FetchResult {
  Fetched(count: Int)
  FetchFailed(error: String)
}

/// Process a single feed: fetch → parse → upsert entries → log result.
/// This is the pure synchronous core, callable from tests and the actor.
pub fn process_feed(
  conn: sqlight.Connection,
  feed_id: String,
  fetch_fn: fn(String) -> Result(String, String),
) -> FetchResult {
  case db.get_feed(conn, feed_id) {
    Ok(Some(feed)) -> do_process(conn, feed_id, feed.feed_url, fetch_fn)
    _ -> FetchFailed(error: "Feed not found")
  }
}

fn do_process(
  conn: sqlight.Connection,
  feed_id: String,
  feed_url: String,
  fetch_fn: fn(String) -> Result(String, String),
) -> FetchResult {
  let now = db.now_ts()

  // Fetch → parse: a Result chain that flattens with `use <- result.try`, so
  // each step is one indent level instead of three nested `case` arms.
  let result = {
    use body <- result.try(fetch_fn(feed_url))
    use entries <- result.try(rss.parse_feed(body))

    // Success path: upsert every entry, then log and report the count.
    list.each(entries, fn(entry: rss.EntryAttrs) {
      let _ =
        db.upsert_entry(
          conn,
          external_id: entry.external_id,
          title: Some(entry.title),
          content_link: Some(entry.content_link),
          comments_link: entry.comments_link,
          published_at: entry.published_at,
          feed_id: feed_id,
        )
    })
    let _ = db.log_fetch_success(conn, feed_id, now)
    Ok(Fetched(count: list.length(entries)))
  }

  // Single error handler for the whole chain, instead of one per nested arm.
  case result {
    Ok(result) -> result
    Error(error) -> {
      let _ = db.log_fetch_error(conn, feed_id, now, error)
      FetchFailed(error:)
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// Actor wrapper
// ═══════════════════════════════════════════════════════════════

/// Messages that can be sent to the fetcher actor.
pub type Message {
  Fetch(feed_id: String)
  Stop
}

/// The fetcher actor state.
pub type State {
  State(
    conn: sqlight.Connection,
    fetch_fn: fn(String) -> Result(String, String),
  )
}

/// Start a fetcher actor with the given database connection and HTTP fetch function.
pub fn start(
  conn: sqlight.Connection,
  fetch_fn: fn(String) -> Result(String, String),
) -> Result(actor.Started(process.Subject(Message)), actor.StartError) {
  actor.new(State(conn:, fetch_fn:))
  |> actor.on_message(handle_message)
  |> actor.start
}

/// Start a fetcher actor with the real HTTP client.
pub fn start_with_http(
  conn: sqlight.Connection,
) -> Result(actor.Started(process.Subject(Message)), actor.StartError) {
  start(conn, http.fetch)
}

fn handle_message(
  state: State,
  message: Message,
) -> actor.Next(State, Message) {
  case message {
    Fetch(feed_id) -> {
      let _ = process_feed(state.conn, feed_id, state.fetch_fn)
      actor.continue(state)
    }
    Stop -> actor.stop()
  }
}
