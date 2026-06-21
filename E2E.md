# E2E Behavioral Tests (BDD)

Behavior-Driven Development scenarios for the feed reader, covering the full
user-facing surface. Written in Gherkin (`Feature` / `Scenario` / `Given` / `When`
/ `Then`). These describe *what the app does from the outside*, independent of
implementation — they should hold whether the backend is the old Elixir app or
the new Gleam rewrite.

**How to use this file**: each Scenario maps to one E2E test. Group into suites
by Feature. Scenarios assume a running, **unauthenticated** server (auth is
handled outside the app, e.g. by a reverse proxy in front of it — the app
itself enforces no access control, matching the current Elixir deployment).
Background-fetch scenarios use injected/mocked feeds and a controllable clock
(no real network, no `process.sleep`).

**Scope notes**:
- "The app" = the running server (Mist) + browser client (HTMX). E2E exercises
  the HTTP boundary and rendered HTML, not internal functions.
- UI assertions target rendered HTML strings (titles, classes, hx-attributes).
- "Entry" = a feed article; "Feed" = an RSS/Atom subscription.
- **No authentication**: the app does not enforce auth (handled externally).
  All routes are open.

## Feature: Feed Management — Adding Feeds

```gherkin
Background:
  Given the database is empty

Scenario: Add a feed with only a URL
  When I submit the add-feed form with feed_url "https://example.com/rss"
  Then a new Feed is persisted with that feed_url
  And the response confirms "Feed added"
  And the feed appears in the feeds list with category "Uncategorized"

Scenario: Add a feed with full metadata
  When I submit the add-feed form with:
    | feed_url | https://example.com/rss |
    | name     | Example Blog           |
    | site_url | https://example.com    |
    | category | Tech                   |
  Then the Feed is persisted with all four fields
  And it appears under category "Tech" in the feeds list

Scenario: Adding a duplicate feed URL is rejected
  Given a feed exists with feed_url "https://example.com/rss"
  When I submit the add-feed form with feed_url "https://example.com/rss"
  Then no second feed is created
  And the response indicates the feed already exists (or is silently ignored)
  And the feeds list still contains exactly one entry for that URL

Scenario: Add feed rejects a blank URL
  When I submit the add-feed form with an empty feed_url
  Then the form validation fails
  And no feed is persisted

Scenario: Add feed with a name but no explicit category defaults to Uncategorized
  When I submit the add-feed form with name "X" and no category
  Then the persisted feed has category "Uncategorized"
```

---

## Feature: Feed Management — Listing & Deleting

```gherkin
Background:
  Given several feeds exist across categories "Tech", "News", "Uncategorized"

Scenario: Feeds page lists all feeds
  When I request "/feeds"
  Then the response contains one card per feed
  And each card shows the feed name, feed_url, and category
  And each card has a "Delete" button

Scenario: Feeds page shows fetch health
  Given a feed was last fetched successfully 2 minutes ago
  And another feed's last fetch errored with "HTTP status: 503"
  When I request "/feeds"
  Then the first card shows "Last parsed: 2m ago"
  And the second card shows the error text in an error-styled element

Scenario: Feeds page empty state
  Given the database has no feeds
  When I request "/feeds"
  Then the response shows an empty-state message like "No feeds yet"

Scenario: Delete a feed removes it and cascades to entries
  Given a feed exists with 5 entries
  When I click "Delete" on that feed's card (HTMX DELETE)
  Then the feed card is removed from the DOM via HTMX swap
  And the feed no longer exists in the database
  And none of its 5 entries remain in the database

Scenario: Delete requires confirmation for feeds with entries
  # Optional UX — document the chosen behavior
  Given a feed exists with entries
  When I click "Delete"
  Then I am prompted to confirm (or the delete proceeds immediately — pick one)
```

---

## Feature: OPML Import

```gherkin
Background:
  Given the database is empty

Scenario: Import a well-formed OPML file
  Given an OPML file with 77 feeds across 3 categories (All, Austin, Tech)
  When I upload it via the OPML import form
  Then all 77 feeds are persisted
  And each feed is categorized per its parent outline's "text" attribute
  And the response reports "Imported 77 feeds"

Scenario: OPML import preserves Unicode in titles
  Given an OPML file containing outlines titled "Ariadne's Space" and "Christine Dodrill's Blog"
  When I import it
  Then the persisted feed titles contain the curly apostrophe (U+2019) intact
  And the feeds list renders those titles without mojibake

Scenario: OPML import is idempotent on duplicate feeds
  Given 3 feeds from "All" category already exist
  When I import an OPML file containing those same 3 feeds plus 10 new ones
  Then only the 10 new feeds are added
  And the 3 existing feeds are unchanged
  And the response reports "Imported 10 feeds"

Scenario: OPML with nested categories groups correctly
  Given an OPML file with nested outline elements
  When I import it
  Then leaf outlines (with xmlUrl) become feeds
  And parent outlines (without xmlUrl) define categories
  And feeds with no parent category default to "Uncategorized"

Scenario: OPML import with malformed XML reports an error
  Given an OPML file that is not valid XML
  When I import it
  Then the response reports an import error
  And no feeds are persisted
  And the existing database state is unchanged

Scenario: OPML import without a file shows an error
  When I submit the OPML form with no file selected
  Then the response reports "No file uploaded"
  And no feeds are persisted

Scenario: OPML outline with title uses title; falling back to text
  Given an outline with title="Real Title" and text="Fallback"
  When I import it
  Then the feed name is "Real Title"
  # And an outline with empty title but text="X" → name "X"
```

---

## Feature: Viewing Entries — Unread

```gherkin
Background:
  Given feeds exist with entries in various states

Scenario: Unread page shows only unread entries
  Given 3 unread entries and 2 read entries exist
  When I request "/" (the unread view)
  Then the response contains the 3 unread entries' titles
  And does not contain the 2 read entries' titles
  And the page heading says "Unread"

Scenario: Unread entries are sorted oldest-first
  Given unread entries with published_at times T1 < T2 < T3
  When I request "/"
  Then the entries appear in order T1, T2, T3 (ascending by published_at)

Scenario: Unread page empty state
  Given no unread entries exist
  When I request "/"
  Then the response shows an empty-state message (e.g. "Nothing left to read")

Scenario: Entry card shows feed name and relative date
  Given an unread entry titled "X" from feed "Blog" published 3 hours ago
  When I request "/"
  Then the card shows "Blog" and "3h ago"
  And the title links to the entry's content_link in a new tab

Scenario: Entry card shows comments link when present
  Given an entry with a comments_link
  When I request "/"
  Then the card contains a "Comments" link to that URL

Scenario: Entry card hides comments link when absent
  Given an entry with no comments_link
  When I request "/"
  Then the card does not contain a "Comments" link
```

---

## Feature: Viewing Entries — Starred & History

```gherkin
Scenario: Starred page shows only starred entries, oldest-first
  Given 2 starred and 3 unstarred entries
  When I request "/starred"
  Then only the 2 starred entries appear, ascending by published_at
  And the heading says "Starred"

Scenario: History page shows all entries, newest-first
  Given entries across many dates
  When I request "/history"
  Then all entries appear, descending by published_at
  And the heading says "History"
  And both read and unread entries are included

Scenario: Navigation highlights the current section
  When I request "/starred"
  Then the "Starred" nav link has the active class
  And the other nav links do not
```

---

## Feature: Entry Interactions — Toggle Read (HTMX)

```gherkin
Background:
  Given I am on the unread page
  And an unread entry "E1" is visible

Scenario: Mark an entry read via HTMX without full page refresh
  When I click "Mark read" on "E1"
  Then the server receives POST /entry/<id>/toggle-read
  And the response is an HTML fragment (not a full document)
  And the entry's card is swapped in place (no full page reload)
  And the button now reads "Mark unread"
  And the entry is_read flag is now true in the database

Scenario: Marking read removes the entry from the Unread view
  When I click "Mark read" on "E1" while on "/"
  Then "E1" is removed from the visible list
  And the unread count decreases by one
  # This mirrors the Elixir stream_delete behavior

Scenario: Toggling read back to unread restores it
  Given "E1" is currently read and visible on /history
  When I click "Mark unread" on "E1"
  Then the button now reads "Mark read"
  And is_read is false in the database
  And visiting "/" shows "E1" again

Scenario: Toggle read is reflected across views
  Given "E1" is unread
  When I mark it read on "/"
  And I navigate to "/history"
  Then "E1" appears in history (because history shows all entries)
```

---

## Feature: Entry Interactions — Toggle Star (HTMX)

```gherkin
Background:
  Given an unstarred entry "E1" is visible

Scenario: Star an entry via HTMX
  When I click "Star" on "E1"
  Then POST /entry/<id>/toggle-star is sent
  And the card swaps in place with the button now reading "Starred"
  And is_starred is true in the database
  And the button has the starred styling (e.g. yellow highlight class)

Scenario: Unstarring removes the entry from the Starred view
  Given I am on "/starred" and "E1" (starred) is visible
  When I click "Starred" to unstar "E1"
  Then "E1" is removed from the visible list
  And the starred count decreases by one
  And is_starred is false in the database

Scenario: Starring persists across navigation
  When I star "E1" on "/"
  And I navigate to "/starred"
  Then "E1" appears in the starred list

Scenario: Toggle star updates the count optimistically
  Given the starred view shows 3 entries
  When I unstar one
  Then the displayed count updates to 2 without a full refresh
```

---

## Feature: Pagination — Load More

```gherkin
Background:
  Given more than one page of unread entries exist (page size N)

Scenario: Load more appends the next page
  When I am on "/" and the first N entries are visible
  And I click "Load more"
  Then GET /?after=<offset> is sent
  And the next N entries are appended to the list (HTMX beforeend swap)
  And the "Load more" button updates to fetch the following page

Scenario: Load more is hidden when no more entries
  Given exactly N unread entries exist
  When I request "/"
  Then no "Load more" button is rendered

Scenario: Load more on the last page
  Given 2.5 pages of entries exist
  When I load more twice
  Then the second load returns the remaining partial page
  And the "Load more" button disappears after the final load

Scenario: Load more preserves sort order
  When entries are sorted ascending and I load more
  Then the appended entries continue the ascending sequence seamlessly
```

---

## Feature: Background Feed Fetching

```gherkin
Background:
  Given the scheduler and fetcher actors are running
  And HTTP fetches are mocked (no real network)

Scenario: Scheduler enqueues due feeds on tick
  Given 3 feeds exist, none ever fetched
  When the scheduler ticks
  Then a Fetch message is enqueued for each of the 3 feeds

Scenario: Recently-fetched feeds are skipped on tick
  Given feed A was fetched 2 minutes ago and feed B was fetched 15 minutes ago
  When the scheduler ticks
  Then only feed B is enqueued (10-minute throttle)
  And feed A is skipped

Scenario: Never-fetched feed is enqueued on first tick
  Given a feed with last_fetched_at = NULL
  When the scheduler ticks
  Then that feed is enqueued

Scenario: Fetcher fetches, parses, and upserts entries
  Given feed F exists with feed_url pointing to a mocked RSS response containing 5 items
  When the fetcher processes F
  Then 5 entries are upserted into the database
  And each entry has external_id, title, content_link, published_at populated
  And feed F's last_fetched_at is updated to ~now
  And feed F's fetch_error is cleared

Scenario: Re-fetching a feed does not duplicate entries
  Given feed F was already fetched and has 5 entries
  When the fetcher processes F again with the same RSS content
  Then the entries table still has exactly 5 entries for F
  # Dedup via UNIQUE(feed_id, external_id) upsert

Scenario: Re-fetching updates changed entries
  Given feed F has an entry with title "Old Title"
  When the fetcher processes F and the RSS now has title "New Title" for the same guid
  Then the entry's title is updated to "New Title"

Scenario: Fetch failure is logged on the feed
  Given feed F's URL returns HTTP 503
  When the fetcher processes F
  Then feed F's fetch_error is set to an error message containing "503"
  And feed F's last_fetched_at is updated
  And no new entries are inserted

Scenario: Fetch timeout is logged as an error
  Given feed F's URL times out (mocked)
  When the fetcher processes F
  Then feed F's fetch_error is set to a timeout error message

Scenario: Fetcher handles malformed RSS gracefully
  Given feed F's URL returns "<not><valid>rss"
  When the fetcher processes F
  Then feed F's fetch_error is set to a parse-error message
  And no partial entries are inserted

Scenario: Fetcher handles WordPress-namespaced feeds
  Given feed F's RSS contains <site xmlns="com-wordpress:feed-additions:1">
  When the fetcher processes F
  Then the feed parses successfully (no crash)
  And entries are extracted normally

Scenario: Scheduler staggers fetches to avoid thundering herd
  Given 10 feeds become due simultaneously
  When the scheduler ticks
  Then fetches are scheduled with staggered delays (1–5 minute spread)
  # Assert via injected clock: not all 10 fire at t=0

Scenario: New entry triggers a notification event
  Given the fetcher emits EntryUpserted events to subscribers
  And a test subscriber is registered
  When the fetcher inserts a genuinely new entry
  Then the subscriber receives an EntryUpserted event for that entry
  # Updated (re-fetched) entries do NOT emit the event
```

---

## Feature: RSS/Atom Parsing (via fetcher, behavioral)

```gherkin
Scenario: Parse a standard RSS 2.0 feed
  Given a mocked RSS response with <item> elements
  When the fetcher processes it
  Then each <item> becomes an entry with title, link, guid, pubDate

Scenario: Parse an Atom feed
  Given a mocked Atom response with <entry> elements
  When the fetcher processes it
  Then each <entry> becomes an entry with title, link (from <link rel=alternate href>), id, updated/published

Scenario: Atom entry with multiple links selects the alternate
  Given an Atom <entry> with <link rel=self>, <link rel=alternate>, and <link rel=enclosure>
  When parsed
  Then the entry's content_link is the alternate link's href

Scenario: Atom entry with no rel attribute defaults to alternate
  Given an Atom <entry> with a bare <link href="..."> (no rel)
  When parsed
  Then content_link is that href

Scenario: RSS item without guid falls back to link as external_id
  Given an RSS <item> with a <link> but no <guid>
  When parsed
  Then the entry's external_id equals the link

Scenario: Date parsing handles RFC822 format
  Given an item with <pubDate>Thu, 12 Jun 2025 14:30:00 EST</pubDate>
  When parsed
  Then published_at is normalized to UTC correctly

Scenario: Date parsing handles ISO8601 format
  Given an entry with <published>2025-06-12T19:30:00Z</published>
  When parsed
  Then published_at is normalized correctly

Scenario: Date parsing handles named timezone abbreviations
  Given pubDates with EST, PST, GMT, UTC
  When parsed
  Then each is converted to the correct UTC offset

Scenario: Unicode in titles is preserved
  Given items with titles containing curly quotes (’), em-dashes (—), and CJK characters
  When parsed and stored
  Then the persisted titles match byte-for-byte (no corruption)

Scenario: Numeric character references are decoded
  Given a title containing "GitHub&#8217;s Blog"
  When parsed
  Then the stored title is "GitHub's Blog" (U+2019)
```

---

## Feature: Theming (dark mode only)

> The rewrite ships **dark mode only** — no light theme, no theme switcher, no
> client-side theme JS. This is simpler than the current Elixir app (which
> defines both themes but has no working toggle UI). These scenarios pin the
> expected behavior.

```gherkin
Scenario: Dark theme is always applied
  Given any visitor on any page
  When the page loads
  Then the <html> element has data-theme="dark"
  And the DaisyUI dark theme colors are rendered (oklch dark palette)
  And there is no light-theme CSS loaded
  And there is no theme-switch UI element anywhere in the DOM

Scenario: No theme JS is shipped
  Given any page
  When inspecting the bundled JS
  Then there is no localStorage handling for "phx:theme"
  And there is no setTheme / data-theme mutation script
  # Dark mode is pure CSS — zero client-side theme logic.

Scenario: Page renders correctly with no OS preference
  Given a browser with prefers-color-scheme unset (or set to light)
  When any page loads
  Then the page still renders in dark mode
  # Dark mode is hardcoded, not OS-conditional.
```

---

## Feature: Static Assets & Navigation

```gherkin
Scenario: CSS is served and applied
  When I request the stylesheet URL
  Then the response is a CSS file with Tailwind + DaisyUI content
  And the page renders with DaisyUI component styling visible

Scenario: HTMX library is loaded
  When any page loads
  Then htmx.min.js is loaded (no console errors)
  And HTMX attributes on buttons are functional

Scenario: Client-side error reconnect indicator
  Given the server becomes unreachable mid-session
  When HTMX detects disconnection
  Then a reconnect indicator toast appears
  And it disappears when the connection restores

Scenario: Brand and navigation are present on every page
  When I request any page
  Then the navbar shows "FeedReader" brand
  And nav links to Unread, Starred, History, Feeds are present
```

---

## Feature: Resilience & Edge Cases

```gherkin
Scenario: Server starts with an empty database
  Given no database file exists
  When the server starts
  Then the schema is initialized (tables created)
  And "/" renders the empty state without error

Scenario: Server restarts and preserves data
  Given feeds and entries exist
  When the server is restarted
  Then all feeds and entries are still present and viewable

Scenario: Concurrent toggle requests on the same entry
  When two toggle-read requests for "E1" fire near-simultaneously
  Then the final is_read state is consistent (no corruption)
  # Either both-succeed-serially or one-wins; document which

Scenario: Request to a non-existent entry returns not-found
  When I POST /entry/does-not-exist/toggle-read
  Then the response is 404 (or a graceful error fragment)

Scenario: Request to a non-existent route returns 404
  When I request "/nonexistent"
  Then the response is 404

Scenario: Fetcher does not crash the server on a bad feed
  Given a feed URL returns garbage bytes
  When the scheduler ticks and the fetcher processes it
  Then the error is logged on the feed
  And the server remains running and responsive
  And other feeds continue to be fetched normally

Scenario: Very large feed is handled without exhaustion
  Given a mocked feed with 1000 items
  When the fetcher processes it
  Then all 1000 entries are upserted
  And memory usage remains bounded (no OOM)

Scenario: Feed with entries lacking published_at
  Given items with no parseable date
  When processed
  Then entries are stored with published_at = NULL
  And sorting places them consistently (e.g. treated as oldest or newest — document)
```

---

## Feature: Operational Scripts (mark-read)

```gherkin
Scenario: Bulk mark-read keeps recent entries unread
  Given entries spanning the last 24 hours
  When the bulk mark-read operation runs (cutoff = 6 hours ago)
  Then entries older than 6 hours are marked read
  And entries newer than 6 hours remain unread
  # If this becomes an in-app admin route rather than a shell script,
  # adapt the trigger but preserve the behavior.
```

---

## Coverage matrix

| Feature area | Scenarios | Key risks covered |
|---|---:|---|
| Feed add/list/delete | 9 | duplicate rejection, cascade delete, health display |
| OPML import | 7 | Unicode, idempotency, malformed XML, nesting |
| Entry viewing | 10 | sort order, empty states, conditional comments link |
| Toggle read/star | 8 | HTMX no-refresh, view-removal semantics, cross-view consistency |
| Pagination | 4 | append, hide-on-empty, last partial page, sort continuity |
| Background fetching | 11 | throttle, dedup, update-on-change, error logging, WordPress ns, stagger, events |
| RSS/Atom parsing | 10 | RSS+Atom, link selection, guid fallback, dates, Unicode, entities |
| Theming | 3 | dark-only, no theme JS, ignores OS preference |
| Assets & nav | 4 | CSS/HTMX served, reconnect indicator |
| Resilience | 8 | empty DB, restart, concurrency, 404s, bad feeds, large feeds, NULL dates |
| Operational | 1 | bulk mark-read cutoff |
| **Total** | **76** | |

---

## Implementation notes for the Gleam rewrite

- **No auth layer to test**: the app is intentionally open; auth is the deployer's responsibility (reverse proxy, network boundary, etc.). Do not add login/logout scenarios or session-cookie assertions.

- **HTTP-level E2E**: use `wisp.testing` request builders to assert status codes and `string.contains` on response bodies. Most scenarios above are HTTP-assertable without a real browser.
- **HTMX behavior** (toggle swaps, load-more appends): assert the response is a fragment (not a full document) and that hx-attributes are present on the returned markup. Full browser-level swap testing is optional; the contract is "server returns the right fragment + headers."
- **Background fetching**: never use real network or `process.sleep`. Mock HTTP via `http_server_mock`; control the scheduler clock or extract the pure `feeds_due(feeds, now)` decision function and test it directly.
- **Actor events**: use `send_and_confirm` (gleam-testing skill Pattern 1) — register a test subscriber, trigger the fetch, `process.receive` on the subscriber subject, assert the event.
- **Unicode assertions**: compare against literal codepoints (`"’"` not `"'"`) to catch encoding regressions (this is exactly the class of bug that killed `parsed_it`/`xmlm` in the spike).
- **Birdie snapshots**: use for rendered HTML fragments (entry cards, pages) to catch unintended markup changes; accept first run deliberately.
