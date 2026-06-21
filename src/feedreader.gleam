//// FeedReader — main application entry point.
////
//// Starts the web server and background workers (scheduler + fetcher).

import envoy
import feedreader/web/server
import gleam/result

pub fn main() -> Nil {
  let db_path = envoy.get("DATABASE_PATH") |> result.unwrap("feedreader.db")
  server.start(db_path)
}
