//// Date parsing for RSS/Atom feeds.
////
//// Handles RFC822 (RSS pubDate) and ISO8601 (Atom) date formats.
//// Uses birl's built-in parsers with fallback for named timezone
//// abbreviations (EST, PST, etc.) that birl may not handle.

import birl
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// Parse a date string in RFC8601 or ISO8601 format.
/// Returns normalized ISO8601 string (UTC), or None if unparseable.
pub fn parse_date(input: Option(String)) -> Option(String) {
  case input {
    Some(raw) if raw != "" -> parse_raw(raw)
    _ -> None
  }
}

/// Try each date parser in order, returning the first success.
/// Replaces a 4-deep nested `case` pyramid with a flat list + `find_map`.
fn parse_raw(raw: String) -> Option(String) {
  [birl.parse, birl.from_http, parse_normalized]
  |> list.find_map(fn(parse) { parse(raw) })
  |> result.map(birl.to_iso8601)
  |> option.from_result
}

/// Normalize named TZ abbrevs to numeric offsets, then retry RFC822 parsing.
fn parse_normalized(raw: String) -> Result(birl.Time, Nil) {
  let normalized = normalize_tz(raw)
  case normalized == raw {
    True -> Error(Nil)
    False -> birl.from_http(normalized)
  }
}

/// Replace named timezone abbreviations with numeric offsets.
fn normalize_tz(date_str: String) -> String {
  date_str
  |> string.replace(" EST", " -0500")
  |> string.replace(" EDT", " -0400")
  |> string.replace(" CST", " -0600")
  |> string.replace(" CDT", " -0500")
  |> string.replace(" MST", " -0700")
  |> string.replace(" MDT", " -0600")
  |> string.replace(" PST", " -0800")
  |> string.replace(" PDT", " -0700")
  |> string.replace(" GMT", " +0000")
  |> string.replace(" UTC", " +0000")
}
