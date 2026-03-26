


# Technical Specification: Elixir/Ash Feed Reader

This document serves as the complete technical specification for rebuilding the Rust/Axum feed reader application into a highly concurrent, reactive, and maintainable Elixir application. 

The architecture strictly adheres to the **Ash Framework Mantra ("Model your domain, derive the rest")** and utilizes **Phoenix LiveView** for a real-time, SPA-like experience without custom JavaScript. 

*Note: This project targets modern Phoenix defaults, including Tailwind CSS v4.*

---

## 1. Project Overview & Tech Stack

*   **Language & VM:** Elixir on the Erlang OTP.
*   **Core Architecture:** Ash Framework 3.x.
*   **Database:** SQLite3.
*   **Data Layer:** `ash_sqlite` (built on `ecto_sqlite3`).
*   **Background Processing:** Oban (configured with the `oban_sqlite` engine).
*   **Web Framework:** Phoenix (LiveView).
*   **Styling:** Tailwind CSS v4 + DaisyUI.

---

## 2. Domain and Data Architecture (Ash)

The core logic is encapsulated within a single Ash Domain: `FeedReader.Core`. All database interactions, validations, and business rules occur here. Controllers/LiveViews must *only* interact with this Domain.

### 2.1. Resource: `FeedReader.Core.Feed`

This resource models an RSS/Atom subscription.

*   **Data Layer:** `AshSqlite.DataLayer`
*   **Attributes:**
    *   `id` :uuid (primary key)
    *   `name` :string
    *   `site_url` :string
    *   `feed_url` :string (required)
    *   `category` :string (default: "Uncategorized")
    *   `last_fetched_at` :utc_datetime
    *   `fetch_error` :string
*   **Relationships:**
    *   `has_many :entries, FeedReader.Core.Entry`
*   **Identities:**
    *   `unique_feed_url` (fields: `[:feed_url]`) - Prevents duplicate subscriptions.
*   **Actions:**
    *   *Default CRUD* (read, destroy).
    *   `create :add` (Accepts: `name`, `site_url`, `feed_url`, `category`).
    *   `update :log_fetch_success` (Sets `last_fetched_at` to now(), clears `fetch_error`).
    *   `update :log_fetch_error` (Sets `fetch_error`).

### 2.2. Resource: `FeedReader.Core.Entry`

This resource models individual articles parsed from the feeds.

*   **Data Layer:** `AshSqlite.DataLayer`
*   **Attributes:**
    *   `id` :uuid (primary key)
    *   `external_id` :string (required) - Maps to the RSS `<id>` or `<guid>`.
    *   `title` :string
    *   `content_link` :string
    *   `comments_link` :string
    *   `published_at` :utc_datetime
    *   `is_read` :boolean (default: false)
    *   `is_starred` :boolean (default: false)
*   **Relationships:**
    *   `belongs_to :feed, FeedReader.Core.Feed` (required)
*   **Identities:**
    *   `unique_entry_per_feed` (fields: `[:feed_id, :external_id]`) - Prevents duplicate entries.
*   **Actions (The Business Interface):**
    *   **Reads (with Keyset Pagination):**
        *   `read :unread` (Filter: `is_read == false`, Sort: `published_at: :asc`)
        *   `read :starred` (Filter: `is_starred == true`, Sort: `published_at: :asc`)
        *   `read :history` (Sort: `published_at: :desc`)
        *   *Architectural Note:* Configure these reads with `pagination keyset?: true, default_limit: 50`.
    *   **Updates:**
        *   `update :toggle_read` (Flips `is_read` state).
        *   `update :toggle_starred` (Flips `is_starred` state).
    *   **Creates/Upserts:**
        *   `create :upsert_from_feed` - Must be configured with `upsert?: true` and `upsert_identity: :unique_entry_per_feed`. This ensures background jobs can continuously blast data at the resource without causing SQLite constraint errors.

---

## 3. Background Processing (Oban)

Replace the Rust `IntervalStream` loop with a durable queue to prevent blocking and allow per-feed error handling. Configure Oban to use the SQLite engine.

1.  **`FeedReader.Workers.Scheduler` (Cron Job):**
    *   Scheduled via Oban Cron (e.g., `"* * * * *"` for every minute, or every 3 mins).
    *   Calls `FeedReader.Core.Feed.read!()`.
    *   Iterates over the feeds and enqueues a `FetchFeed` job for each `feed.id`.
2.  **`FeedReader.Workers.FetchFeed` (Worker Job):**
    *   Takes `%{"feed_id" => id}` as arguments.
    *   Fetches the feed using an HTTP client (e.g., `Req`).
    *   Parses the XML.
    *   Iterates over parsed items and passes them to `FeedReader.Core.Entry.upsert_from_feed!`.
    *   Calls `Feed.log_fetch_success!` or `Feed.log_fetch_error!` based on the outcome.

---

## 4. Presentation Layer (Phoenix LiveView)

We replace server-rendered Askama templates + HTMX with stateful Phoenix LiveView components.

### 4.1. Routing
Map standard Phoenix routes to a unified LiveView that handles the different reading states via the `live_action` parameter.
```elixir
live "/", EntryLive.Index, :unread
live "/starred", EntryLive.Index, :starred
live "/history", EntryLive.Index, :history
live "/feeds", FeedLive.Index, :index
```

### 4.2. `EntryLive.Index` Architecture

1.  **Mounting & Streams:**
    *   On `mount`, detect the `live_action` (`:unread`, `:starred`, `:history`).
    *   Call the corresponding Ash Action (e.g., `Core.Entry.unread!()`).
    *   Extract the results and assign them to a **Phoenix Stream** (`stream(socket, :entries, page.results)`). This prevents holding the entire DOM/feed list in server memory.
2.  **Infinite Scroll (Pagination):**
    *   Apply `phx-viewport-bottom="load_more"` to the main stream container.
    *   When triggered, call the Ash read action again passing `page: [after: socket.assigns.cursor]`.
    *   Append the new results to the stream.
3.  **Toggling State:**
    *   Buttons for "Star" or "Mark Read" trigger `phx-click="toggle_star"` with `phx-value-id={entry.id}`.
    *   The LiveView calls `Core.Entry.toggle_starred!(id)`.
    *   The LiveView explicitly updates the stream item with the returned data: `stream_insert(socket, :entries, updated_entry)`. This replaces HTMX swapping natively.

---

## 5. UI/UX Design (Tailwind v4 + DaisyUI)

The UI will be built using standard HTML markup heavily styled by Tailwind utility classes and DaisyUI components.

### 5.1. Tailwind v4 Configuration
Because modern Phoenix starters use Tailwind v4, **there is no `tailwind.config.js`**. All configuration is done via CSS in `assets/css/app.css`.

To integrate DaisyUI and dark mode:
*   Import DaisyUI directly in your `app.css` via the Tailwind plugin directive: `@plugin "daisyui";`.
*   DaisyUI handles dark mode out-of-the-box based on the user's OS `prefers-color-scheme`. 
*   Theme customizations can be defined within the CSS file using `@theme` and DaisyUI's specific CSS variables.

### 5.2. Layout Structure
*   **App Shell (`components/layouts/app.html.heex`):**
    *   **Header/Navbar:** DaisyUI `<div class="navbar bg-base-100 shadow-sm">`. 
    *   **Sidebar (Desktop) / Drawer (Mobile):** Contains the navigation links (`Unread`, `Starred`, `History`, `Feeds`).
    *   **Main Content:** A centered, max-width container (`max-w-4xl mx-auto p-4`).
*   **Entry Card (`EntryLive.Index` list items):**
    *   Use DaisyUI Cards: `<div class="card bg-base-100 shadow-xl mb-4 border border-base-200">`.
    *   Header: Article Title (`text-xl font-bold hover:text-primary transition-colors`).
    *   Actions (Footer): DaisyUI Buttons (`<button class="btn btn-sm btn-ghost">Star</button>`).

---

## 6. Real-Time PubSub (The "Ash Advantage")

Since Oban is updating the database in the background, the UI should reflect this without the user refreshing.

1.  **Configure Ash Notifier:** On the `Entry` resource, configure the `:pub_sub` notifier to broadcast a message (e.g., `entry:created`) whenever `:upsert_from_feed` results in a new record.
2.  **LiveView Subscription:** In the `mount` of `EntryLive.Index`, use `Phoenix.PubSub.subscribe`.
3.  **Handle Info:** When the LiveView receives the PubSub message, show a DaisyUI Toast (`<div class="toast">...</div>`) notifying the user of new articles.

---

## 7. Testing Strategy

To ensure high maintainability and independent iteration, the testing architecture strictly separates the **Ash Resource layer** (business logic/data) from the **Phoenix View layer** (presentation). Standard `Ecto.Adapters.SQL.Sandbox` will be used to ensure test databases are isolated and fast.

### 7.1. Testing the Ash Domain (Data & Business Logic)
These tests live in `test/feed_reader/core/` and never interact with Phoenix, HTML, or LiveView.

*   **Action Unit Tests:**
    *   Test `Core.Feed.add!` to ensure duplicate `feed_url`s are rejected (validating Ash identities).
    *   Test `Core.Entry.toggle_starred!` to ensure the boolean flips and the `updated_at` timestamp changes.
    *   Test `Core.Entry.upsert_from_feed!` by feeding it the exact same payload twice, asserting that the total count of entries in the database does not increase (validating SQLite constraints and upsert behavior).
*   **Background Worker Tests:**
    *   Use `Req.Test` to stub the HTTP requests to fake RSS XML payloads.
    *   Use `Oban.Testing` to execute the `FetchFeed` worker inline, asserting that calling the worker results in the correct number of `Entry` records being created via the Ash Domain.

### 7.2. Testing the Phoenix Layer (Presentation & LiveView)
These tests live in `test/feed_reader_web/live/` and focus entirely on rendering, user events, and DOM updates. They trust that the Ash Domain actions work correctly.

*   **Setup:** Use Ash actions in the test `setup` block to seed the sandbox database (e.g., create 3 unread entries).
*   **Mount & Render:** 
    *   Use `Phoenix.LiveViewTest.live/2` to mount `/`.
    *   Assert that the HTML contains the titles of the 3 seeded unread entries.
*   **Event Interactions (The "HTMX" replacement):**
    *   Locate the "Star" button on the first entry.
    *   Trigger the event: `view |> element("#star-btn-#{entry.id}") |> render_click()`.
    *   *Assertion:* Assert the LiveView DOM updates correctly (e.g., the button text changes from "Star" to "Unstar" or the icon changes). We *do not* need to query the database here to check if it was starred; we only test that the LiveView processed the event and updated the stream UI.
*   **Pagination:** 
    *   Trigger the `phx-viewport-bottom` event.
    *   Assert that the LiveView appends the next batch of items to the DOM.

---

## 8. Implementation Phasing for Developer

*   **Phase 1: Foundation.** Initialize Phoenix, install Ash, `ash_sqlite`, configure Ecto SQLite repos, install Tailwind v4/DaisyUI via `app.css`.
*   **Phase 2: Modeling & Core Tests.** Write the Ash Domain and Resources (`Feed`, `Entry`). Write the Ash tests (Section 7.1) to validate identities, pagination, and actions.
*   **Phase 3: Background.** Install Oban (`oban_sqlite`). Write the HTTP fetching logic, mock it with `Req.Test`, and verify the pipeline from XML parsing to `upsert_from_feed!`.
*   **Phase 4: Presentation & View Tests.** Build the LiveViews and their corresponding `Phoenix.LiveViewTest`s. Implement Streams for memory efficiency. Map out the UI using DaisyUI classes.
*   **Phase 5: Refinement.** Implement Keyset pagination via infinite scroll. Add the PubSub real-time toast notifications. Implement the OPML import file upload in `FeedLive.Index`.