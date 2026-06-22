import feedreader/opml
import gleam/list
import gleam/option.{Some}
import gleeunit
import simplifile

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn parse_small_opml_test() {
  let body =
    "
  <opml version=\"2.0\">
    <head><title>Test</title></head>
    <body>
      <outline text=\"Tech\">
        <outline title=\"Blog A\" text=\"Blog A\" xmlUrl=\"https://a.com/rss\" htmlUrl=\"https://a.com\"/>
        <outline title=\"Blog B\" text=\"Blog B\" xmlUrl=\"https://b.com/rss\" htmlUrl=\"https://b.com\"/>
      </outline>
    </body>
  </opml>"

  let assert Ok(feeds) = opml.parse_opml(body)
  assert list.length(feeds) == 2

  let assert Ok(first) = list.first(feeds)
  assert first.feed_url == "https://a.com/rss"
  assert first.name == Some("Blog A")
  assert first.site_url == Some("https://a.com")
  assert first.category == "Tech"
}

pub fn parse_multiple_categories_test() {
  let body =
    "
  <opml version=\"2.0\">
    <body>
      <outline text=\"Tech\">
        <outline title=\"A\" text=\"A\" xmlUrl=\"https://a.com/rss\" htmlUrl=\"https://a.com\"/>
      </outline>
      <outline text=\"News\">
        <outline title=\"B\" text=\"B\" xmlUrl=\"https://b.com/rss\" htmlUrl=\"https://b.com\"/>
      </outline>
    </body>
  </opml>"

  let assert Ok(feeds) = opml.parse_opml(body)
  assert list.length(feeds) == 2

  let categories = list.map(feeds, fn(f) { f.category })
  assert list.contains(categories, "Tech")
  assert list.contains(categories, "News")
}

pub fn empty_category_defaults_to_uncategorized_test() {
  let body =
    "
  <opml version=\"2.0\">
    <body>
      <outline text=\"\">
        <outline title=\"A\" text=\"A\" xmlUrl=\"https://a.com/rss\" htmlUrl=\"https://a.com\"/>
      </outline>
    </body>
  </opml>"

  let assert Ok(feeds) = opml.parse_opml(body)
  let assert Ok(first) = list.first(feeds)
  assert first.category == "Uncategorized"
}

pub fn parse_real_feeds_opml_test() {
  let assert Ok(content) = simplifile.read("test/fixtures/feeds.opml")

  let assert Ok(feeds) = opml.parse_opml(content)
  assert list.length(feeds) == 77

  // Check categories
  let categories = list.map(feeds, fn(f) { f.category })
  assert list.contains(categories, "All")
  assert list.contains(categories, "Austin")
  assert list.contains(categories, "Tech")
}

pub fn unicode_in_titles_preserved_test() {
  let body =
    "
  <opml version=\"2.0\">
    <body>
      <outline text=\"Tech\">
        <outline title=\"Ariadne\u{2019}s Space\" text=\"Ariadne\u{2019}s Space\" xmlUrl=\"https://ariadne.space/feed/\" htmlUrl=\"https://ariadne.space\"/>
      </outline>
    </body>
  </opml>"

  let assert Ok(feeds) = opml.parse_opml(body)
  let assert Ok(first) = list.first(feeds)
  assert first.name == Some("Ariadne\u{2019}s Space")
}

pub fn html_entity_in_title_decoded_test() {
  let body =
    "
  <opml version=\"2.0\">
    <body>
      <outline text=\"Tech\">
        <outline title=\"Ariadne&#39;s Space\" text=\"Ariadne&#39;s Space\" xmlUrl=\"https://a.com/rss\" htmlUrl=\"https://a.com\"/>
      </outline>
    </body>
  </opml>"

  let assert Ok(feeds) = opml.parse_opml(body)
  let assert Ok(first) = list.first(feeds)
  assert first.name == Some("Ariadne's Space")
}

pub fn malformed_opml_returns_error_test() {
  let assert Error(_) = opml.parse_opml("<not>valid<xml")
}
