//// OPML import parsing.
////
//// Parses an OPML document and extracts feed subscriptions with categories.
//// Ported from the Elixir FeedReader.Core.import_opml logic.
////
//// OPML structure:
////   <opml><body>
////     <outline text="Category">          ← parent (no xmlUrl)
////       <outline title="X" xmlUrl="..." htmlUrl="..."/>
////     </outline>
////   </body></opml>

import feedreader/xml.{type XmlNode}
import gleam/list
import gleam/option.{type Option, None, Some}

/// Attributes for creating a feed from an OPML outline.
pub type FeedAttrs {
  FeedAttrs(
    feed_url: String,
    name: Option(String),
    site_url: Option(String),
    category: String,
  )
}

/// Parse OPML content and extract feed attributes with categories.
/// Returns a list of FeedAttrs ready for insertion.
pub fn parse_opml(content: String) -> Result(List(FeedAttrs), String) {
  case xml.parse(content) {
    Ok(root) -> {
      // Get top-level outlines under <body> (these define categories)
      let bodies = xml.elements_by_tag(root, "body")
      case list.first(bodies) {
        Ok(body) -> {
          let category_outlines = xml.children_by_tag(body, "outline")
          Ok(extract_feeds(category_outlines))
        }
        Error(_) -> Ok([])
      }
    }
    Error(_) -> Error("Failed to parse OPML XML")
  }
}

/// Walk category outlines and extract feeds from each.
fn extract_feeds(category_outlines: List(XmlNode)) -> List(FeedAttrs) {
  category_outlines
  |> list.flat_map(fn(category_outline) {
    let category = category_name(category_outline)

    // Direct children that have xmlUrl are feeds in this category
    let children = xml.children_by_tag(category_outline, "outline")
    let feeds =
      children
      |> list.filter(fn(child) {
        case xml.attr(child, "xmlUrl") {
          Some(url) -> url != ""
          None -> False
        }
      })
      |> list.map(fn(feed_outline) { outline_to_attrs(feed_outline, category) })

    feeds
  })
}

/// Get the category name from an outline's text attribute.
fn category_name(outline: XmlNode) -> String {
  let name = case xml.attr(outline, "text") {
    Some(t) -> t
    None ->
      case xml.attr(outline, "title") {
        Some(t) -> t
        None -> ""
      }
  }
  case name {
    "" -> "Uncategorized"
    other -> other
  }
}

/// Convert an OPML outline element to FeedAttrs.
fn outline_to_attrs(outline: XmlNode, category: String) -> FeedAttrs {
  let feed_url = case xml.attr(outline, "xmlUrl") {
    Some(url) -> url
    None -> ""
  }
  let name =
    pick_first_nonempty([
      xml.attr(outline, "title"),
      xml.attr(outline, "text"),
    ])
  let site_url = case xml.attr(outline, "htmlUrl") {
    Some(u) ->
      case u {
        "" -> None
        other -> Some(other)
      }
    None -> None
  }

  FeedAttrs(
    feed_url: feed_url,
    name: name,
    site_url: site_url,
    category: category,
  )
}

/// Return the first Some(non-empty) value from a list of options.
fn pick_first_nonempty(opts: List(Option(String))) -> Option(String) {
  case opts {
    [] -> None
    [Some(s), ..rest] ->
      case s {
        "" -> pick_first_nonempty(rest)
        other -> Some(other)
      }
    [None, ..rest] -> pick_first_nonempty(rest)
  }
}
