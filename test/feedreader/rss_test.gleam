import feedreader/rss
import gleam/list
import gleam/option.{None, Some}
import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn parse_rss_feed_test() {
  let body =
    "
  <rss><channel>
    <title>Test Feed</title>
    <item>
      <title>Item 1</title>
      <link>http://example.com/1</link>
      <guid>guid-1</guid>
      <pubDate>Thu, 12 Jun 2025 14:30:00 GMT</pubDate>
    </item>
    <item>
      <title>Item 2</title>
      <link>http://example.com/2</link>
      <guid>guid-2</guid>
    </item>
  </channel></rss>"

  let assert Ok(entries) = rss.parse_feed(body)
  assert list.length(entries) == 2

  let assert Ok(first) = list.first(entries)
  assert first.external_id == "guid-1"
  assert first.title == "Item 1"
  assert first.content_link == "http://example.com/1"
}

pub fn parse_atom_feed_test() {
  let body =
    "
  <feed xmlns=\"http://www.w3.org/2005/Atom\">
    <title>Atom Feed</title>
    <entry>
      <title>Entry 1</title>
      <link rel=\"alternate\" href=\"http://example.com/1\"/>
      <id>tag:example.com,2025:1</id>
      <published>2025-06-12T19:30:00Z</published>
    </entry>
  </feed>"

  let assert Ok(entries) = rss.parse_feed(body)
  assert list.length(entries) == 1

  let assert Ok(first) = list.first(entries)
  assert first.external_id == "tag:example.com,2025:1"
  assert first.title == "Entry 1"
  assert first.content_link == "http://example.com/1"
}

pub fn rss_item_without_guid_uses_link_test() {
  let body =
    "
  <rss><channel>
    <item>
      <title>No GUID</title>
      <link>http://example.com/no-guid</link>
    </item>
  </channel></rss>"

  let assert Ok(entries) = rss.parse_feed(body)
  let assert Ok(first) = list.first(entries)
  assert first.external_id == "http://example.com/no-guid"
}

pub fn atom_link_multiple_selects_alternate_test() {
  let body =
    "
  <feed xmlns=\"http://www.w3.org/2005/Atom\">
    <entry>
      <title>Multi Link</title>
      <link rel=\"self\" href=\"http://example.com/self\"/>
      <link rel=\"alternate\" href=\"http://example.com/alt\"/>
      <link rel=\"enclosure\" href=\"http://example.com/enc\"/>
      <id>test-id</id>
    </entry>
  </feed>"

  let assert Ok(entries) = rss.parse_feed(body)
  let assert Ok(first) = list.first(entries)
  assert first.content_link == "http://example.com/alt"
}

pub fn comments_link_extracted_test() {
  let body =
    "
  <rss><channel>
    <item>
      <title>With Comments</title>
      <link>http://example.com/post</link>
      <guid>guid-1</guid>
      <comments>http://example.com/post/comments</comments>
    </item>
  </channel></rss>"

  let assert Ok(entries) = rss.parse_feed(body)
  let assert Ok(first) = list.first(entries)
  assert first.comments_link == Some("http://example.com/post/comments")
}

pub fn no_comments_link_returns_none_test() {
  let body =
    "
  <rss><channel>
    <item>
      <title>No Comments</title>
      <link>http://example.com/post</link>
      <guid>guid-1</guid>
    </item>
  </channel></rss>"

  let assert Ok(entries) = rss.parse_feed(body)
  let assert Ok(first) = list.first(entries)
  assert first.comments_link == None
}

pub fn malformed_feed_returns_error_test() {
  let assert Error(_) = rss.parse_feed("<not><valid>rss")
}

pub fn unicode_title_preserved_test() {
  let body =
    "
  <rss><channel>
    <item>
      <title>GitHub\u{2019}s Blog — café</title>
      <link>http://example.com/1</link>
      <guid>guid-1</guid>
    </item>
  </channel></rss>"

  let assert Ok(entries) = rss.parse_feed(body)
  let assert Ok(first) = list.first(entries)
  assert first.title == "GitHub\u{2019}s Blog — café"
}
