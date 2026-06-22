//// Scheduler actor: periodically enqueues fetch jobs for due feeds.
////
//// The pure decision function `feeds_due` is testable without actors.
//// The actor wraps it in a timer loop that sends `Tick` messages.

import birl
import feedreader/db
import feedreader/fetcher
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import sqlight

// ═══════════════════════════════════════════════════════════════
// Pure decision function (testable without actors)
// ═══════════════════════════════════════════════════════════════

/// Minimum minutes between fetches for the same feed.
pub const fetch_interval_minutes = 10

/// Determine which feeds are due for fetching.
/// A feed is due if it was never fetched, or last fetched > 10 minutes ago.
pub fn feeds_due(feeds: List(db.Feed), now: birl.Time) -> List(db.Feed) {
  let now_unix = birl.to_unix(now)
  list.filter(feeds, fn(feed) {
    case feed.last_fetched_at {
      None -> True
      Some(ts) ->
        case birl.parse(ts) {
          Ok(parsed) -> {
            let diff = now_unix - birl.to_unix(parsed)
            diff >= fetch_interval_minutes * 60
          }
          Error(_) -> True
        }
    }
  })
}

// ═══════════════════════════════════════════════════════════════
// Actor
// ═══════════════════════════════════════════════════════════════

/// Messages for the scheduler actor.
pub type Message {
  Tick
  Stop
}

/// Scheduler state.
pub type State {
  State(
    conn: sqlight.Connection,
    fetcher_subject: process.Subject(fetcher.Message),
    interval_ms: Int,
    self_subject: process.Subject(Message),
  )
}

/// Start the scheduler actor.
/// `interval_ms` controls how often the scheduler ticks (default: 3 min).
pub fn start(
  conn: sqlight.Connection,
  fetcher_subject: process.Subject(fetcher.Message),
  interval_ms: Int,
) -> Result(actor.Started(process.Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(5000, fn(self_subject) {
    // Schedule the first tick
    let _ = process.send_after(self_subject, 1000, Tick)
    Ok(actor.returning(
      actor.initialised(State(
        conn: conn,
        fetcher_subject: fetcher_subject,
        interval_ms: interval_ms,
        self_subject: self_subject,
      )),
      self_subject,
    ))
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(
  state: State,
  message: Message,
) -> actor.Next(State, Message) {
  case message {
    Tick -> {
      let _ = process.send_after(state.self_subject, state.interval_ms, Tick)
      do_tick(state)
      actor.continue(state)
    }
    Stop -> actor.stop()
  }
}

fn do_tick(state: State) {
  case db.list_feeds(state.conn) {
    Ok(feeds) -> {
      let now = birl.utc_now()
      let due = feeds_due(feeds, now)
      list.each(due, fn(feed) {
        process.send(state.fetcher_subject, fetcher.Fetch(feed.id))
      })
    }
    Error(_) -> Nil
  }
}
