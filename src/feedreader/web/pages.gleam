//// Full-page render functions.
////
//// Each function returns a complete HTML document via `element.to_document_string`.
//// Routes call these for full page loads (non-HTMX navigation).

import feedreader/db.{type Entry, type Feed}
import feedreader/web/html as view
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import hx
import lustre/element
import lustre_pipes/attribute as a
import lustre_pipes/element as lp
import lustre_pipes/element/html as h

/// Page size for pagination.
pub const page_size = 50

// ═══════════════════════════════════════════════════════════════
// Entry listing pages
// ═══════════════════════════════════════════════════════════════

pub fn unread_page(
  entries: List(Entry),
  offset: Int,
  has_more: Bool,
) -> String {
  render(
    "Unread",
    entry_list_page(
      "Unread",
      entries,
      offset,
      has_more,
      "",
      EmptyMsg("Nothing left to read", "Touch grass 🌿"),
    ),
  )
}

pub fn starred_page(
  entries: List(Entry),
  offset: Int,
  has_more: Bool,
) -> String {
  render(
    "Starred",
    entry_list_page(
      "Starred",
      entries,
      offset,
      has_more,
      "/starred",
      EmptyMsg("Nothing starred yet", "Star entries to save them for later"),
    ),
  )
}

pub fn history_page(
  entries: List(Entry),
  offset: Int,
  has_more: Bool,
) -> String {
  render(
    "History",
    entry_list_page(
      "History",
      entries,
      offset,
      has_more,
      "/history",
      EmptyMsg("No history yet", "Entries will appear here after fetching"),
    ),
  )
}

fn entry_list_page(
  heading: String,
  entries: List(Entry),
  offset: Int,
  has_more: Bool,
  base_path: String,
  empty: EmptyMsg,
) -> element.Element(msg) {
  h.div()
  |> a.class("max-w-4xl mx-auto p-4")
  |> lp.children([
    h.div()
      |> a.class("mb-6")
      |> lp.children([
        h.h1() |> a.class("text-2xl font-bold") |> lp.text_content(heading),
      ]),
    h.div()
      |> a.id("entries")
      |> a.class("space-y-4")
      |> lp.children(list.map(entries, view.entry_card)),
    // Load more button or empty state
    case has_more {
      True -> load_more_button(offset, base_path)
      False ->
        case list.is_empty(entries) {
          True -> empty_state(empty)
          False -> element.none()
        }
    },
  ])
}

/// Build the URL for the load-more endpoint.
/// base_path is "" for unread, "/starred" for starred, "/history" for history.
fn load_more_url(offset: Int, base_path: String) -> String {
  base_path <> "?after=" <> int.to_string(offset + page_size)
}

fn load_more_button(offset: Int, base_path: String) -> element.Element(msg) {
  h.div()
  |> a.id("load-more-container")
  |> a.class("text-center py-4")
  |> lp.children([
    h.button()
    |> a.id("load-more-btn")
    |> a.class("btn btn-outline btn-sm")
    |> a.add(hx.get(url: load_more_url(offset, base_path)))
    |> a.add(hx.target(hx.Selector("#entries")))
    |> a.add(hx.swap(hx.Beforeend))
    |> lp.text_content("Load More"),
  ])
}

/// Generate the Load More button HTML string for HTMX OOB swap responses.
/// Includes `hx-swap-oob="true"` so HTMX replaces the existing button.
pub fn load_more_button_html(offset: Int, base_path: String) -> String {
  let url = load_more_url(offset, base_path)
  "<div id=\"load-more-container\" class=\"text-center py-4\" hx-swap-oob=\"true\">"
  <> "<button id=\"load-more-btn\" class=\"btn btn-outline btn-sm\" "
  <> "hx-get=\""
  <> url
  <> "\" hx-target=\"#entries\" hx-swap=\"beforeend\">Load More</button>"
  <> "</div>"
}

fn empty_state(msg: EmptyMsg) -> element.Element(msg) {
  h.div()
  |> a.id("empty-state")
  |> a.class("text-center py-8 text-base-content/60")
  |> lp.children([
    h.p() |> lp.text_content(msg.primary),
    h.p() |> a.class("mt-2") |> lp.text_content(msg.secondary),
  ])
}

type EmptyMsg {
  EmptyMsg(primary: String, secondary: String)
}

// ═══════════════════════════════════════════════════════════════
// Feeds page
// ═══════════════════════════════════════════════════════════════

pub fn feeds_page(
  feeds: List(Feed),
  flash_msg: option.Option(#(view.FlashKind, String)),
) -> String {
  render("Feeds", feeds_page_inner(feeds, flash_msg))
}

fn feeds_page_inner(
  feeds: List(Feed),
  flash_msg: option.Option(#(view.FlashKind, String)),
) -> element.Element(msg) {
  h.div()
  |> a.class("max-w-4xl mx-auto p-4")
  |> lp.children([
    h.div()
      |> a.class("mb-6")
      |> lp.children([
        h.h1() |> a.class("text-2xl font-bold mb-4") |> lp.text_content("Feeds"),
        // Flash message
        case flash_msg {
          Some(#(kind, msg)) -> view.flash(kind, msg)
          None -> element.none()
        },
        // Add feed form
        add_feed_form(),
        // OPML import form
        opml_import_form(),
      ]),
    // Feed list
    h.div()
      |> a.class("space-y-4")
      |> lp.children([
        case list.is_empty(feeds) {
          True ->
            h.div()
            |> a.class("text-center py-8 text-gray-500")
            |> lp.text_content("No feeds yet. Add your first feed above.")
          False -> element.fragment(list.map(feeds, view.feed_card))
        },
      ]),
  ])
}

fn add_feed_form() -> element.Element(msg) {
  h.div()
  |> a.class("card bg-base-100 shadow-xl border border-base-200 mb-6")
  |> lp.children([
    h.div()
    |> a.class("card-body")
    |> lp.children([
      h.h2() |> a.class("card-title text-lg") |> lp.text_content("Add New Feed"),
      h.form()
        |> a.attribute("method", "post")
        |> a.attribute("action", "/feeds")
        |> a.add(hx.post(url: "/feeds"))
        |> a.add(hx.target(hx.Closest("body")))
        |> a.add(hx.swap(hx.OuterHTML))
        |> lp.children([
          form_input(
            "feed_url",
            "Feed URL",
            "https://example.com/feed.xml",
            True,
          ),
          form_input("name", "Name (optional)", "Feed Name", False),
          form_input(
            "site_url",
            "Site URL (optional)",
            "https://example.com",
            False,
          ),
          form_input("category", "Category (optional)", "Tech", False),
          h.div()
            |> a.class("mt-6")
            |> lp.children([
              h.button()
              |> a.attribute("type", "submit")
              |> a.class("btn btn-primary")
              |> lp.text_content("Add Feed"),
            ]),
        ]),
    ]),
  ])
}

fn opml_import_form() -> element.Element(msg) {
  h.div()
  |> a.class("card bg-base-100 shadow-xl border border-base-200 mb-6")
  |> lp.children([
    h.div()
    |> a.class("card-body")
    |> lp.children([
      h.h2()
        |> a.class("card-title text-lg")
        |> lp.text_content("Import OPML"),
      h.form()
        |> a.attribute("method", "post")
        |> a.attribute("action", "/feeds/import")
        |> a.attribute("enctype", "multipart/form-data")
        |> a.add(hx.post(url: "/feeds/import"))
        |> a.add(hx.encoding("multipart/form-data"))
        |> a.add(hx.target(hx.Closest("body")))
        |> a.add(hx.swap(hx.OuterHTML))
        |> lp.children([
          h.div()
            |> a.class("form-control")
            |> lp.children([
              h.label()
                |> a.class("label")
                |> lp.children([
                  h.span()
                  |> a.class("label-text")
                  |> lp.text_content("Select OPML file"),
                ]),
              h.input()
                |> a.attribute("type", "file")
                |> a.attribute("name", "opml")
                |> a.attribute("accept", ".opml,text/xml,application/xml")
                |> a.class("file-input file-input-bordered w-full")
                |> lp.empty(),
            ]),
          h.div()
            |> a.class("mt-6")
            |> lp.children([
              h.button()
              |> a.attribute("type", "submit")
              |> a.class("btn btn-secondary")
              |> lp.text_content("Import Feeds"),
            ]),
        ]),
    ]),
  ])
}

fn form_input(
  name: String,
  label: String,
  placeholder: String,
  required: Bool,
) -> element.Element(msg) {
  h.div()
  |> a.class("form-control mt-4")
  |> lp.children([
    h.label()
      |> a.class("label")
      |> lp.children([
        h.span() |> a.class("label-text") |> lp.text_content(label),
      ]),
    h.input()
      |> a.attribute("type", "text")
      |> a.attribute("name", name)
      |> a.attribute("placeholder", placeholder)
      |> add_required_if(required)
      |> a.class("input input-bordered w-full")
      |> lp.empty(),
  ])
}

fn add_required_if(required: Bool) -> fn(lp.Scaffold(msg)) -> lp.Scaffold(msg) {
  fn(s) {
    case required {
      True -> a.attribute(s, "required", "")
      False -> s
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// Render helper
// ═══════════════════════════════════════════════════════════════

fn render(title: String, inner: element.Element(msg)) -> String {
  view.layout(title, inner) |> element.to_document_string
}
