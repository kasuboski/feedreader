//// Date parsing for RSS/Atom feeds.
////
//// Handles RFC822 (RSS pubDate) and ISO8601 (Atom) date formats.
//// Uses birl's built-in parsers with fallback for named timezone
//// abbreviations (EST, PST, etc.) that birl may not handle.

import birl
import gleam/option.{type Option, None, Some}
import gleam/string

/// Parse a date string in RFC822 or ISO8601 format.
/// Returns normalized ISO8601 string (UTC), or None if unparseable.
pub fn parse_date(input: Option(String)) -> Option(String) {
  case input {
    None -> None
    Some("") -> None
    Some(raw) -> {
      // Try ISO8601 first (Atom feeds)
      case birl.parse(raw) {
        Ok(dt) -> Some(birl.to_iso8601(dt))
        Error(_) -> {
          // Try HTTP/RFC822 (RSS pubDate)
          case birl.from_http(raw) {
            Ok(dt) -> Some(birl.to_iso8601(dt))
            Error(_) -> {
              // Try normalizing named TZ abbrevs to numeric offsets
              try_normalized_tz(raw)
            }
          }
        }
      }
    }
  }
}

/// Some feeds use named TZ abbrevs that birl doesn't handle.
/// Convert them to numeric offsets and try again.
fn try_normalized_tz(raw: String) -> Option(String) {
  let normalized = normalize_tz(raw)
  case normalized == raw {
    False -> {
      case birl.from_http(normalized) {
        Ok(dt) -> Some(birl.to_iso8601(dt))
        Error(_) -> None
      }
    }
    True -> None
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
