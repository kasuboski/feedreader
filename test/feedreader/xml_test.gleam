import feedreader/xml
import gleam/option.{type Option, None, Some}
import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn parse_simple_xml_test() {
  let assert Ok(node) = xml.parse("<root><name>Hello</name></root>")
  assert xml.text_of(xml.child_by_tag(node, "name") |> unwrap) == "Hello"
}

pub fn parse_rss_items_test() {
  let assert Ok(node) =
    xml.parse(
      "
    <rss><channel>
      <item><title>Item 1</title><link>http://a.com/1</link></item>
      <item><title>Item 2</title><link>http://a.com/2</link></item>
    </channel></rss>
  ",
    )
  let items = xml.elements_by_tag(node, "item")
  assert list_length(items) == 2
}

pub fn parse_attributes_test() {
  let assert Ok(node) =
    xml.parse("<feed><entry><link href=\"http://example.com\"/></entry></feed>")
  let entries = xml.elements_by_tag(node, "entry")
  let assert Ok(entry) = list_first(entries)
  let links = xml.children_by_tag(entry, "link")
  let assert Ok(link) = list_first(links)
  assert xml.attr(link, "href") == Some("http://example.com")
}

pub fn parse_unicode_test() {
  let assert Ok(node) =
    xml.parse(
      "<feed><item><title>GitHub\u{2019}s Blog — café</title></item></feed>",
    )
  let items = xml.elements_by_tag(node, "item")
  let assert Ok(item) = list_first(items)
  assert xml.child_text(item, "title") == Some("GitHub\u{2019}s Blog — café")
}

pub fn parse_numeric_entities_test() {
  let assert Ok(node) =
    xml.parse("<feed><item><title>GitHub&#8217;s Blog</title></item></feed>")
  let items = xml.elements_by_tag(node, "item")
  let assert Ok(item) = list_first(items)
  assert xml.child_text(item, "title") == Some("GitHub\u{2019}s Blog")
}

pub fn parse_wordpress_namespace_test() {
  let assert Ok(node) =
    xml.parse(
      "
    <rss xmlns:wp=\"com-wordpress:feed-additions:1\">
      <channel>
        <item><title>Test</title></item>
      </channel>
    </rss>
  ",
    )
  let items = xml.elements_by_tag(node, "item")
  let assert Ok(item) = list_first(items)
  assert xml.child_text(item, "title") == Some("Test")
}

pub fn parse_malformed_xml_fails_test() {
  let assert Error(_) = xml.parse("<not><valid>rss")
}

pub fn child_text_missing_returns_none_test() {
  let assert Ok(node) = xml.parse("<feed><item><title>X</title></item></feed>")
  let items = xml.elements_by_tag(node, "item")
  let assert Ok(item) = list_first(items)
  assert xml.child_text(item, "nonexistent") == None
}

pub fn child_text_empty_returns_none_test() {
  let assert Ok(node) = xml.parse("<feed><item><title></title></item></feed>")
  let items = xml.elements_by_tag(node, "item")
  let assert Ok(item) = list_first(items)
  assert xml.child_text(item, "title") == None
}

fn unwrap(opt: Option(a)) -> a {
  let assert Some(v) = opt
  v
}

fn list_length(list: List(a)) -> Int {
  case list {
    [] -> 0
    [_, ..rest] -> 1 + list_length(rest)
  }
}

fn list_first(list: List(a)) -> Result(a, Nil) {
  case list {
    [] -> Error(Nil)
    [first, ..] -> Ok(first)
  }
}
