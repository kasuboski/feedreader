//// Shared Lustre element builders using lustre_pipes (pipe-style).
////
//// Layout, nav, entry cards, feed cards — all rendered server-side via
//// Lustre's element API. HTMX attributes via `hx` are added with `a.add`.
////
//// Per AGENTS.md: world-class UI with micro-interactions, smooth transitions,
//// premium look. DaisyUI classes provide the component styling; Tailwind
//// transition/hover utilities provide the micro-interactions.

import feedreader/db.{type Entry, type Feed}
import feedreader/time
import gleam/option.{None, Some}
import hx
import lustre/attribute as attr
import lustre/element.{type Element}
import lustre_pipes/attribute as a
import lustre_pipes/element as lp
import lustre_pipes/element/html as h

// ═══════════════════════════════════════════════════════════════
// HTMX helper — adapt hx Attribute to lustre_pipes pipe
// ═══════════════════════════════════════════════════════════════

/// Pipe an hx.* attribute into a scaffold.
fn hx_attr(scaffold, attr) {
  a.add(scaffold, attr)
}

// ═══════════════════════════════════════════════════════════════
// Layout
// ═══════════════════════════════════════════════════════════════

/// Full HTML document layout. Dark mode hardcoded (no theme switching).
pub fn layout(title: String, inner: Element(msg)) -> Element(msg) {
  h.html()
  |> a.attribute("lang", "en")
  |> a.attribute("data-theme", "dark")
  |> lp.children([
    h.head()
      |> lp.children([
        h.meta()
          |> a.attribute("charset", "utf-8")
          |> lp.empty(),
        h.meta()
          |> a.attribute("name", "viewport")
          |> a.attribute("content", "width=device-width, initial-scale=1")
          |> lp.empty(),
        h.link()
          |> a.attribute("rel", "icon")
          |> a.attribute("type", "image/svg+xml")
          |> a.attribute(
            "href",
            "data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' fill='%23FEC700' viewBox='0 0 24 24' stroke-width='1.5' stroke='%23FEC700'><path stroke-linecap='round' stroke-linejoin='round' d='M11.48 3.499a.562.562 0 0 1 1.04 0l2.125 5.111a.563.563 0 0 0 .475.345l5.518.442c.499.04.701.663.321.988l-4.204 3.602a.563.563 0 0 0-.182.557l1.285 5.385a.562.562 0 0 1-.84.61l-4.725-2.885a.562.562 0 0 0-.586 0L6.982 20.54a.562.562 0 0 1-.84-.61l1.285-5.386a.562.562 0 0 0-.182-.557l-4.204-3.602a.562.562 0 0 1 .321-.988l5.518-.442a.563.563 0 0 0 .475-.345L11.48 3.5Z' /></svg>",
          )
          |> lp.empty(),
        h.title() |> lp.text_content(title),
        h.link()
          |> a.attribute("rel", "stylesheet")
          |> a.attribute("href", "/static/css/app.compiled.css")
          |> lp.empty(),
        h.script()
          |> a.attribute("src", "/static/js/htmx.min.js")
          |> lp.empty(),
      ]),
    h.body()
      |> lp.children([
        h.div()
        |> a.class("min-h-screen bg-base-100")
        |> lp.children([
          nav(),
          h.main()
            |> a.class("max-w-4xl mx-auto p-4")
            |> lp.children([inner]),
        ]),
      ]),
  ])
}

// ═══════════════════════════════════════════════════════════════
// Navigation
// ═══════════════════════════════════════════════════════════════

pub fn nav() -> Element(msg) {
  h.header()
  |> a.class("navbar bg-base-200 shadow-sm border-b border-base-300")
  |> lp.children([
    h.div()
    |> a.class("max-w-4xl mx-auto w-full flex items-center justify-between")
    |> lp.children([
      h.a()
        |> a.class("btn btn-ghost text-xl")
        |> a.attribute("href", "/")
        |> lp.text_content("FeedReader"),
      nav_links(),
    ]),
  ])
}

fn nav_links() -> Element(msg) {
  h.nav()
  |> lp.children([
    h.ul()
    |> a.class("menu menu-horizontal px-1 gap-1")
    |> lp.children([
      nav_link("/", "Unread"),
      nav_link("/starred", "Starred"),
      nav_link("/history", "History"),
      nav_link("/feeds", "Feeds"),
    ]),
  ])
}

fn nav_link(href: String, label: String) -> Element(msg) {
  h.li()
  |> lp.children([
    h.a()
    |> a.class("")
    |> a.attribute("href", href)
    |> lp.text_content(label),
  ])
}

// ═══════════════════════════════════════════════════════════════
// Entry card (used in full pages AND HTMX fragment responses)
// ═══════════════════════════════════════════════════════════════

pub fn entry_card(entry: Entry) -> Element(msg) {
  let title = option.unwrap(entry.title, "Untitled")
  let content_link = option.unwrap(entry.content_link, "#")
  let date_str = time.humanize_date(entry.published_at)

  // Metadata line: "Feed Name | Date" (matches old Elixir app logic)
  let metadata = case entry.feed_name, date_str {
    Some(feed_name), d if d != "" -> feed_name <> " | " <> d
    Some(feed_name), _ -> feed_name
    None, d if d != "" -> d
    None, _ -> ""
  }

  let star_class = case entry.is_starred {
    True -> "btn-active text-yellow-400 bg-yellow-400/10 border-yellow-400/30"
    False -> ""
  }
  let read_class = case entry.is_read {
    True -> "btn-active text-green-400 bg-green-400/10 border-green-400/30"
    False -> ""
  }
  let star_label = case entry.is_starred {
    True -> "Starred"
    False -> "Star"
  }
  let read_label = case entry.is_read {
    True -> "Mark unread"
    False -> "Mark read"
  }

  h.div()
  |> a.id("entry-" <> entry.id)
  |> a.class(
    "bg-base-200/80 rounded-lg border border-base-300/50 p-4 backdrop-blur-sm",
  )
  |> lp.children([
    // Title link
    h.h2()
      |> a.class("text-xl font-semibold hover:text-primary transition-colors")
      |> lp.children([
        h.a()
        |> a.attribute("href", content_link)
        |> a.attribute("target", "_blank")
        |> a.attribute("rel", "noopener noreferrer")
        |> lp.text_content(title),
      ]),
    // Metadata: "Feed Name | Date" (conditional)
    case metadata {
      "" -> element.none()
      _ ->
        h.div()
        |> a.class("text-sm text-base-content/60 mt-2")
        |> lp.text_content(metadata)
    },
    // Comments link (conditional)
    case entry.comments_link {
      None -> element.none()
      Some(url) ->
        h.div()
        |> a.class("mt-2")
        |> lp.children([
          h.a()
          |> a.class(
            "text-sm text-primary/70 hover:text-primary transition-colors",
          )
          |> a.attribute("href", url)
          |> a.attribute("target", "_blank")
          |> a.attribute("rel", "noopener noreferrer")
          |> lp.text_content("Comments"),
        ])
    },
    // Action buttons (HTMX — no page refresh)
    h.div()
      |> a.class("flex justify-end gap-2 mt-4")
      |> lp.children([
        // Star toggle
        h.button()
          |> a.id("star-btn-" <> entry.id)
          |> a.class("btn btn-sm transition-all duration-200 " <> star_class)
          |> hx_attr(hx.post(url: "/entry/" <> entry.id <> "/toggle-star"))
          |> hx_attr(hx.target(hx.Closest("#entry-" <> entry.id)))
          |> hx_attr(hx.swap(hx.OuterHTML))
          |> lp.children([
            star_icon(),
            element.text(star_label),
          ]),
        // Read toggle
        h.button()
          |> a.id("read-btn-" <> entry.id)
          |> a.class("btn btn-sm transition-all duration-200 " <> read_class)
          |> hx_attr(hx.post(url: "/entry/" <> entry.id <> "/toggle-read"))
          |> hx_attr(hx.target(hx.Closest("#entry-" <> entry.id)))
          |> hx_attr(hx.swap(hx.OuterHTML))
          |> lp.children([
            check_circle_icon(),
            element.text(read_label),
          ]),
      ]),
  ])
}

// ═══════════════════════════════════════════════════════════════
// Inline SVG icons (Heroicons outline, MIT licensed)
// ═══════════════════════════════════════════════════════════════

fn star_icon() -> Element(msg) {
  element.namespaced(
    "http://www.w3.org/2000/svg",
    "svg",
    [
      attr.class("w-4 h-4 inline"),
      attr.attribute("fill", "none"),
      attr.attribute("viewBox", "0 0 24 24"),
      attr.attribute("stroke-width", "1.5"),
      attr.attribute("stroke", "currentColor"),
    ],
    [
      element.namespaced(
        "http://www.w3.org/2000/svg",
        "path",
        [
          attr.attribute("stroke-linecap", "round"),
          attr.attribute("stroke-linejoin", "round"),
          attr.attribute(
            "d",
            "M11.48 3.499a.562.562 0 0 1 1.04 0l2.125 5.111a.563.563 0 0 0 .475.345l5.518.442c.499.04.701.663.321.988l-4.204 3.602a.563.563 0 0 0-.182.557l1.285 5.385a.562.562 0 0 1-.84.61l-4.725-2.885a.562.562 0 0 0-.586 0L6.982 20.54a.562.562 0 0 1-.84-.61l1.285-5.386a.562.562 0 0 0-.182-.557l-4.204-3.602a.562.562 0 0 1 .321-.988l5.518-.442a.563.563 0 0 0 .475-.345L11.48 3.5Z",
          ),
        ],
        [],
      ),
    ],
  )
}

fn check_circle_icon() -> Element(msg) {
  element.namespaced(
    "http://www.w3.org/2000/svg",
    "svg",
    [
      attr.class("w-4 h-4 inline"),
      attr.attribute("fill", "none"),
      attr.attribute("viewBox", "0 0 24 24"),
      attr.attribute("stroke-width", "1.5"),
      attr.attribute("stroke", "currentColor"),
    ],
    [
      element.namespaced(
        "http://www.w3.org/2000/svg",
        "path",
        [
          attr.attribute("stroke-linecap", "round"),
          attr.attribute("stroke-linejoin", "round"),
          attr.attribute(
            "d",
            "M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z",
          ),
        ],
        [],
      ),
    ],
  )
}

// ═══════════════════════════════════════════════════════════════
// Feed card
// ═══════════════════════════════════════════════════════════════

pub fn feed_card(feed: Feed) -> Element(msg) {
  let name = option.unwrap(feed.name, "Unnamed Feed")
  let last_fetched = time.humanize_date(feed.last_fetched_at)

  h.div()
  |> a.class("card bg-base-100 shadow border border-base-200")
  |> lp.children([
    h.div()
    |> a.class("card-body p-4")
    |> lp.children([
      h.div()
      |> a.class("flex justify-between items-start")
      |> lp.children([
        h.div()
          |> lp.children([
            h.h3()
              |> a.class("font-bold text-lg")
              |> lp.text_content(name),
            h.p()
              |> a.class("text-sm text-gray-500")
              |> lp.text_content(feed.feed_url),
            h.div()
              |> a.class("text-xs text-gray-400 mt-1")
              |> lp.text_content("Category: " <> feed.category),
            case last_fetched {
              "" ->
                h.div()
                |> a.class("text-xs text-gray-400 mt-1")
                |> lp.text_content("Last parsed: never")
              _ ->
                h.div()
                |> a.class("text-xs text-gray-400 mt-1")
                |> lp.text_content("Last parsed: " <> last_fetched)
            },
            case feed.fetch_error {
              None -> element.none()
              Some(err) ->
                h.div()
                |> a.class("text-xs text-error mt-1")
                |> lp.text_content("Error: " <> err)
            },
          ]),
        // Delete button (HTMX)
        h.button()
          |> a.class("btn btn-sm btn-ghost text-error")
          |> hx_attr(hx.delete(url: "/feeds/" <> feed.id))
          |> hx_attr(hx.target(hx.Closest(".card")))
          |> hx_attr(hx.swap(hx.OuterHTML))
          |> lp.text_content("Delete"),
      ]),
    ]),
  ])
}

// ═══════════════════════════════════════════════════════════════
// Flash message
// ═══════════════════════════════════════════════════════════════

pub fn flash(kind: FlashKind, msg: String) -> Element(msg) {
  let class = case kind {
    Info -> "alert alert-info"
    Error -> "alert alert-error"
  }
  h.div()
  |> a.class(class <> " shadow-lg transition-all duration-300 mb-4")
  |> lp.text_content(msg)
}

pub type FlashKind {
  Info
  Error
}
