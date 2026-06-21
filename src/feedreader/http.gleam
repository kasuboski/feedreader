import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int

/// Fetch a feed from the given URL.
///
/// Returns the body on 200 status, or an error message on non-200 or failure.
/// Uses a 30-second timeout.
///
/// The HTTP request runs in an isolated, unlinked process because
/// `gleam_httpc`'s FFI can raise uncatchable Erlang exceptions (e.g.
/// `socket_closed_remotely`) for error shapes it doesn't recognise. We
/// monitor the worker: if it crashes we return an error instead of dying.
pub fn fetch(url: String) -> Result(String, String) {
  let reply_subject = process.new_subject()

  let worker =
    process.spawn_unlinked(fn() {
      let result = do_http_request(url)
      process.send(reply_subject, result)
    })

  let monitor = process.monitor(worker)

  let selector =
    process.new_selector()
    |> process.select_map(reply_subject, HttpResult)
    |> process.select_specific_monitor(monitor, fn(_down) { MonitorDown })

  case process.selector_receive(selector, 35_000) {
    Ok(HttpResult(result)) -> {
      process.demonitor_process(monitor)
      result
    }
    Ok(MonitorDown) -> Error("Connection error (worker process crashed)")
    Error(Nil) -> {
      process.demonitor_process(monitor)
      process.kill(worker)
      Error("Request timeout")
    }
  }
}

fn do_http_request(url: String) -> Result(String, String) {
  let assert Ok(req) = request.to(url)
  let req = request.set_method(req, http.Get)

  let config =
    httpc.configure()
    |> httpc.timeout(30_000)

  case httpc.dispatch(config, req) {
    Ok(resp) ->
      case resp.status {
        200 -> Ok(resp.body)
        status -> Error("HTTP status: " <> int.to_string(status))
      }
    Error(e) -> Error("HTTP error: " <> httpc_error_to_string(e))
  }
}

fn httpc_error_to_string(e: httpc.HttpError) -> String {
  case e {
    httpc.InvalidUtf8Response -> "Invalid UTF-8 response"
    httpc.FailedToConnect(_, _) -> "Failed to connect"
    httpc.ResponseTimeout -> "Response timeout"
  }
}

/// Internal message type for the selector.
type SelectorMsg {
  HttpResult(result: Result(String, String))
  MonitorDown
}
