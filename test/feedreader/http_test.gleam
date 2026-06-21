import feedreader/http as fh
import gleam/http
import gleam/int
import gleam/string
import http_server_mock
import http_server_mock/matcher
import http_server_mock/response
import http_server_mock/stub_builder
import http_server_mock_erlang

// ═══════════════════════════════════════════════════════════════
// http.fetch tests
// ═══════════════════════════════════════════════════════════════

pub fn fetch_success_test() {
  // Stub a mock HTTP server returning 200 with RSS content
  let rss_body =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<rss version=\"2.0\">
  <channel>
    <title>Test Feed</title>
    <item>
      <title>Test Entry</title>
      <link>https://example.com/1</link>
      <guid>guid-1</guid>
    </item>
  </channel>
</rss>"

  let stub =
    stub_builder.new()
    |> stub_builder.matching(matcher.new() |> matcher.method(http.Get))
    |> stub_builder.responding_with(
      response.new()
      |> response.body(rss_body),
    )
    |> stub_builder.build()

  let server =
    http_server_mock.new(http_server_mock_erlang.server())
    |> http_server_mock.start()
    |> http_server_mock.with_stub(stub)

  let url = http_server_mock.base_url(server) <> "/"
  let assert Ok(body) = fh.fetch(url)
  assert body == rss_body

  let _stopped = http_server_mock.stop(server)
}

pub fn fetch_404_test() {
  // Stub a mock HTTP server returning 404
  let stub =
    stub_builder.new()
    |> stub_builder.matching(matcher.new() |> matcher.method(http.Get))
    |> stub_builder.responding_with(response.new() |> response.status(404))
    |> stub_builder.build()

  let server =
    http_server_mock.new(http_server_mock_erlang.server())
    |> http_server_mock.start()
    |> http_server_mock.with_stub(stub)

  let url = http_server_mock.base_url(server) <> "/"
  let assert Error(msg) = fh.fetch(url)
  assert string.starts_with(msg, "HTTP status:")

  let _stopped = http_server_mock.stop(server)
}

pub fn fetch_timeout_test() {
  // Stub a mock HTTP server that delays >30s (should timeout)
  let stub =
    stub_builder.new()
    |> stub_builder.matching(matcher.new() |> matcher.method(http.Get))
    |> stub_builder.responding_with(
      response.new()
      |> response.body("delayed")
      |> response.delay(35_000),
      // 35 seconds > 30 second timeout
    )
    |> stub_builder.build()

  let server =
    http_server_mock.new(http_server_mock_erlang.server())
    |> http_server_mock.start()
    |> http_server_mock.with_stub(stub)

  let url = http_server_mock.base_url(server) <> "/"
  let assert Error(msg) = fh.fetch(url)
  assert msg == "HTTP error: Response timeout"

  let _stopped = http_server_mock.stop(server)
}

// ═══════════════════════════════════════════════════════════════
// Crash resilience test
// ═══════════════════════════════════════════════════════════════
//
// gleam_httpc's FFI crashes (erlang:error) on unrecognized error shapes
// like socket_closed_remotely. http.fetch runs the request in an isolated
// unlinked worker process and monitors it, so a crash returns Error instead
// of killing the caller. This test verifies that isolation.

/// External FFI to start a TCP server that accepts and immediately closes
/// connections, triggering socket_closed_remotely in httpc.
@external(erlang, "feedreader_tcp_ffi", "start_close_server")
pub fn start_close_server() -> Result(#(Int, a), b)

@external(erlang, "feedreader_tcp_ffi", "stop_server")
pub fn stop_server(socket: a) -> Nil

pub fn fetch_survives_connection_crash_test() {
  // Start a TCP server that accepts connections and closes them immediately.
  // This triggers gleam_httpc's erlang:error({unexpected_httpc_error, ...})
  // because httpc gets socket_closed_remotely.
  let assert Ok(#(port, socket)) = start_close_server()
  let url = "http://localhost:" <> int.to_string(port) <> "/"

  // Before the fix, this would crash the test process. Now it returns Error.
  let result = fh.fetch(url)

  case result {
    Error(_) -> Nil
    Ok(_) -> panic as "expected Error, got Ok from crashing connection"
  }

  stop_server(socket)
}

pub fn fetch_survives_multiple_crashes_test() {
  // Verify the caller process stays alive across multiple crashing fetches.
  let assert Ok(#(port, socket)) = start_close_server()
  let url = "http://localhost:" <> int.to_string(port) <> "/"

  let _result1 = fh.fetch(url)
  let _result2 = fh.fetch(url)
  let result3 = fh.fetch(url)

  // If we got here, the caller process survived all three crashes.
  case result3 {
    Error(_) -> Nil
    Ok(_) -> panic as "expected Error, got Ok from crashing connection"
  }

  stop_server(socket)
}
