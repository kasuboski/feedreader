import feedreader/date
import gleam/option.{None, Some}
import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn parse_iso8601_test() {
  let result = date.parse_date(Some("2025-06-12T19:30:00Z"))
  assert result != None
}

pub fn parse_iso8601_with_offset_test() {
  let result = date.parse_date(Some("2025-06-12T14:30:00-05:00"))
  assert result != None
}

pub fn parse_rfc822_test() {
  let result = date.parse_date(Some("Thu, 12 Jun 2025 14:30:00 GMT"))
  assert result != None
}

pub fn parse_rfc822_with_named_tz_test() {
  let result = date.parse_date(Some("Thu, 12 Jun 2025 14:30:00 EST"))
  assert result != None
}

pub fn parse_rfc822_with_pst_test() {
  let result = date.parse_date(Some("Thu, 12 Jun 2025 14:30:00 PST"))
  assert result != None
}

pub fn parse_rfc822_with_numeric_offset_test() {
  let result = date.parse_date(Some("Thu, 12 Jun 2025 14:30:00 +0800"))
  assert result != None
}

pub fn parse_none_returns_none_test() {
  assert date.parse_date(None) == None
}

pub fn parse_empty_returns_none_test() {
  assert date.parse_date(Some("")) == None
}

pub fn parse_garbage_returns_none_test() {
  assert date.parse_date(Some("not a date")) == None
}
