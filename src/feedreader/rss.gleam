//// RSS/Atom feed parsing.
////
//// Parses an RSS or Atom XML document into a list of entry attributes.
//// Ported from the Elixir FeedReader.Workers.FetchFeed.parse_feed logic.
////
//// Handles both RSS `<item>` and Atom `<entry>` elements.
//// Extracts: guid/id, title, link, comments, published date.

import feedreader/date
import feedreader/xml.{type XmlNode}
import gleam/list
import gleam/option.{type Option, None, Some}

/// Attributes for upserting an entry from a parsed feed item.
pub type EntryAttrs {
  EntryAttrs(
    external_id: String,
    title: String,
    content_link: String,
    comments_link: Option(String),
    published_at: Option(String),
  )
}

/// Parse an RSS/Atom XML body into a list of entry attributes.
pub fn parse_feed(body: String) -> Result(List(EntryAttrs), String) {
  case xml.parse(body) {
    Ok(root) -> {
      let rss_items = xml.elements_by_tag(root, "item")
      let atom_entries = xml.elements_by_tag(root, "entry")
      let all_items = list.append(rss_items, atom_entries)
      Ok(list.map(all_items, parse_item))
    }
    Error(_) -> Error("Failed to parse feed XML")
  }
}

/// Parse a single RSS <item> or Atom <entry> into EntryAttrs.
fn parse_item(node: XmlNode) -> EntryAttrs {
  let guid = xml.child_text(node, "guid")
  let title = xml.child_text(node, "title") |> option.unwrap("")
  let link = extract_link(node)
  let comments = xml.child_text(node, "comments")
  let pub_date = xml.child_text(node, "pubDate")
  let published = xml.child_text(node, "published")
  let updated = xml.child_text(node, "updated")

  // external_id: guid > link (matches the original Elixir parser, which
  // checks only RSS <guid> and falls back to the link URL — NOT Atom <id>).
  // Using <id> would produce different external_ids than the Elixir DB,
  // causing the upsert to treat existing entries as new (and thus unread).
  let external_id = case guid {
    Some(g) -> g
    None -> link
  }

  // date: pubDate > published > updated
  let date_raw = case pub_date {
    Some(d) -> Some(d)
    None ->
      case published {
        Some(p) -> Some(p)
        None -> updated
      }
  }

  EntryAttrs(
    external_id: external_id,
    title: title,
    content_link: link,
    comments_link: comments,
    published_at: date.parse_date(date_raw),
  )
}

/// Extract the content link from an item.
/// RSS: <link>text</link>
/// Atom: <link href="..." /> (prefer rel="alternate", fallback to bare link)
fn extract_link(node: XmlNode) -> String {
  // Try Atom link with href attribute first
  let links = xml.children_by_tag(node, "link")

  // Look for rel="alternate" or rel="" (default)
  let alternate =
    links
    |> list.find(fn(link) {
      case xml.attr(link, "rel") {
        Some("alternate") -> True
        None -> True
        _ -> False
      }
    })
    |> result_to_option

  case alternate {
    Some(link) -> {
      case xml.attr(link, "href") {
        Some(href) -> href
        None -> link_text_or_empty(link)
      }
    }
    None -> {
      // Try RSS-style: text content of <link>
      case xml.child_text(node, "link") {
        Some(text) -> text
        None -> ""
      }
    }
  }
}

fn link_text_or_empty(link: XmlNode) -> String {
  case xml.text_of(link) |> string_trim() {
    Some(s) -> s
    None -> ""
  }
}

fn result_to_option(r: Result(a, b)) -> Option(a) {
  case r {
    Ok(v) -> Some(v)
    Error(_) -> None
  }
}

fn string_trim(s: String) -> Option(String) {
  let trimmed = string_trim_raw(s)
  case trimmed {
    "" -> None
    other -> Some(other)
  }
}

import gleam/string

fn string_trim_raw(s: String) -> String {
  string.trim(s)
}
