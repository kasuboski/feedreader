//// HTMX partial response helpers.
////
//// These return HTML fragments (not full documents) for HTMX swap responses.
//// Toggle read/star returns the updated entry card; load-more returns the
//// next batch of cards; delete returns empty content (removes the card).

import feedreader/db.{type Entry, type Feed}
import feedreader/web/html as view
import gleam/list
import lustre/element

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
