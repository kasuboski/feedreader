//// Mist + Wisp server bootstrap.
////
//// Opens the database, starts the background workers (scheduler + fetcher)
//// under a supervision tree, and starts the HTTP server.
////
//// The supervision tree ensures that if a worker actor crashes (e.g. from
//// an unexpected HTTP error), it is automatically restarted rather than
//// taking down the entire application.

import feedreader/db
import feedreader/fetcher
import feedreader/scheduler
import feedreader/web/router
import gleam/erlang/process
import gleam/io
import gleam/otp/actor
import gleam/otp/static_supervisor as sup
import gleam/otp/supervision
import mist
import sqlight
import wisp/wisp_mist

/// Scheduler tick interval in milliseconds (3 minutes).
const scheduler_interval_ms = 180_000

/// Start the HTTP server with the given database path.
pub fn start(db_path: String) -> Nil {
  case db.open(db_path) {
    Ok(conn) -> {
      let _ = db.migrate(conn)

      // Start background workers under a supervision tree.
      // The supervisor traps exits and restarts crashed children.
      start_workers(conn)

      io.println("Feedreader starting on http://localhost:3000")

      let handler = router.handle_request(conn, _)

      let assert Ok(_) =
        wisp_mist.handler(
          handler,
          "feedreader-secret-key-base-not-used-for-auth",
        )
        |> mist.new
        |> mist.bind("0.0.0.0")
        |> mist.port(3000)
        |> mist.start

      process.sleep_forever()
    }
    Error(e) -> {
      io.println("Failed to open database: " <> sqlight_error_to_string(e))
      Nil
    }
  }
}

/// Start the fetcher and scheduler actors under a supervision tree.
///
/// The scheduler needs the fetcher's subject to send Fetch messages.
/// We start the fetcher first, capture its subject, then pass it to
/// the scheduler via a closure.
fn start_workers(conn: sqlight.Connection) -> Nil {
  // Start the fetcher actor and capture its subject.
  case fetcher.start_with_http(conn) {
    Ok(started) -> {
      let fetcher_subject = started.data

      // Start the scheduler under a supervisor so it restarts on crash.
      let scheduler_spec =
        supervision.worker(fn() {
          scheduler.start(conn, fetcher_subject, scheduler_interval_ms)
        })
        |> supervision.restart(supervision.Permanent)

      let supervisor_result =
        sup.new(strategy: sup.OneForOne)
        |> sup.restart_tolerance(intensity: 10, period: 60)
        |> sup.add(scheduler_spec)
        |> sup.start

      case supervisor_result {
        Ok(_) -> io.println("Background workers started (scheduler + fetcher)")
        Error(e) ->
          io.println(
            "Warning: supervisor failed to start: " <> start_error_to_string(e),
          )
      }
    }
    Error(e) ->
      io.println(
        "Warning: fetcher failed to start: " <> start_error_to_string(e),
      )
  }
}

fn sqlight_error_to_string(e: sqlight.Error) -> String {
  case e {
    sqlight.SqlightError(_, msg, _) -> msg
  }
}

fn start_error_to_string(e: actor.StartError) -> String {
  case e {
    actor.InitFailed(reason) -> "init failed: " <> reason
    actor.InitExited(_) -> "init exited"
    actor.InitTimeout -> "init timeout"
  }
}
