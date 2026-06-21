//// Relative date formatting for display.
//// Ported from the Elixir FeedreaderWeb.TimeHelpers.

import birl
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/string

/// Format a datetime as a human-readable relative time.
/// "just now", "3m ago", "2h ago", "yesterday", "3d ago", "1w ago", "Mon DD, YYYY"
pub fn humanize_date(dt: Option(String)) -> String {
  case dt {
    None -> ""
    Some(ts) ->
      case birl.parse(ts) {
        Ok(parsed) -> {
          let now = birl.utc_now()
          let diff_seconds = birl.to_unix(now) - birl.to_unix(parsed)
          cond_format(diff_seconds, parsed)
        }
        Error(_) -> ""
      }
  }
}

fn cond_format(diff_seconds: Int, dt: birl.Time) -> String {
  case diff_seconds {
    d if d < 60 -> "just now"
    d if d < 3600 -> int.to_string(d / 60) <> "m ago"
    d if d < 86_400 -> int.to_string(d / 3600) <> "h ago"
    d if d < 172_800 -> "yesterday"
    d if d < 604_800 -> int.to_string(d / 86_400) <> "d ago"
    d if d < 2_592_000 -> int.to_string(d / 604_800) <> "w ago"
    _ -> format_full_date(dt)
  }
}

fn format_full_date(dt: birl.Time) -> String {
  let date_str = birl.to_naive_date_string(dt)
  // Format is "YYYY-MM-DD" — convert to "Mon DD, YYYY"
  let parts = string.split(date_str, "-")
  case parts {
    [year, month_str, day] -> {
      let assert Ok(m) = int.parse(month_str)
      month_name(m) <> " " <> strip_leading_zero(day) <> ", " <> year
    }
    _ -> date_str
  }
}

fn month_name(m: Int) -> String {
  case m {
    1 -> "Jan"
    2 -> "Feb"
    3 -> "Mar"
    4 -> "Apr"
    5 -> "May"
    6 -> "Jun"
    7 -> "Jul"
    8 -> "Aug"
    9 -> "Sep"
    10 -> "Oct"
    11 -> "Nov"
    _ -> "Dec"
  }
}

fn strip_leading_zero(s: String) -> String {
  case string.pop_grapheme(s) {
    Ok(#("0", rest)) -> rest
    _ -> s
  }
}
