//// HTMX partial response helpers.
////
//// These return HTML fragments (not full documents) for HTMX swap responses.
//// Toggle read/star returns the updated entry card; load-more returns the
//// next batch of cards; delete returns empty content (removes the card).
//// Empty-state fragments are injected when the last entry on a filtered page
//// is removed (e.g. marking the last unread entry as read).

import feedreader/db.{type Entry, type Feed}
import feedreader/web/html as view
import gleam/list
import lustre/element
import lustre_pipes/attribute as a
import lustre_pipes/element as lp
import lustre_pipes/element/html as h

/// Return a single entry card fragment (post-toggle response).
pub fn entry_card_fragment(entry: Entry) -> String {
  view.entry_card(entry) |> element.to_string
}

/// Return a batch of entry cards for load-more (HTMX beforeend swap).
pub fn entry_list_fragment(entries: List(Entry)) -> String {
  entries
  |> list.map(view.entry_card)
  |> element.fragment
  |> element.to_string
}

/// Return a single feed card fragment (after add/delete).
pub fn feed_card_fragment(feed: Feed) -> String {
  view.feed_card(feed) |> element.to_string
}

/// Return the unread empty-state fragment (injected when last unread entry
/// is marked read via HTMX).
pub fn unread_empty_state() -> String {
  h.div()
  |> a.id("empty-state")
  |> a.class("text-center py-8 text-base-content/60")
  |> lp.children([
    h.p() |> lp.text_content("Nothing left to read"),
    h.p() |> a.class("mt-2") |> lp.text_content("Touch grass 🌿"),
  ])
  |> element.to_string
}

/// Return the starred empty-state fragment (injected when last starred entry
/// is un-starred via HTMX).
pub fn starred_empty_state() -> String {
  h.div()
  |> a.id("empty-state")
  |> a.class("text-center py-8 text-base-content/60")
  |> lp.children([
    h.p() |> lp.text_content("Nothing starred yet"),
    h.p()
      |> a.class("mt-2")
      |> lp.text_content("Star entries to save them for later"),
  ])
  |> element.to_string
}
