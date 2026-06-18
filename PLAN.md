# Implementation Plan: FeedReader → Gleam

> **Architecture & rationale**: see [`SCOUTING_REPORT.md`](./SCOUTING_REPORT.md). This plan is the build order.
> **Testing**: follow [`.pi/skills/gleam-testing/SKILL.md`](.pi/skills/gleam-testing/SKILL.md) — `assert` not bare booleans, `let assert` for Result/Option, **never `process.sleep`** in actor tests (use `send_and_confirm`).
> **Standing rule**: `mise run pre-commit` must pass before committing any step. Each module ships with its test.

---

## Stack (locked, from spikes)

Wisp + Mist · Lustre SSR + `lustre_pipes` + `hx` · SQLite + Parrot + sqlight · gleam_otp actors · xmerl Erlang FFI (XML) · Tailwind v4 + DaisyUI · target = Erlang/BEAM.

| dep | role |
|---|---|
| `wisp`, `mist`, `gleam_http` | web framework, server, http types |
| `lustre`, `lustre_pipes`, `hx` | SSR HTML (pipe-style), HTMX attrs + headers |
| `sqlight`, `parrot` | SQLite driver, typed SQL codegen |
| `gleam_otp`, `gleam_erlang` | actors/supervision, BEAM interop |
| `gleam_httpc` | feed fetching |
| `birl`, `gluid`, `envoy` | dates, UUIDv4, env vars |
| `formal`, `glentities` | form parsing, HTML entity encoding |
| `gleeunit`, `birdie`, `http_server_mock` | tests, snapshots, HTTP mocking |
| (FFI) `xmerl_ffi.erl` | XML parsing (no Gleam package) |

---

## Build order

### Phase 1 — Scaffold & DB foundation

**1.1 Project init**
- `gleam new feedreader --template=erlang`
- `gleam.toml`: deps above. `target = "erlang"`.
- Add `mise.toml` (gleam/erlang/rebar3 tools; mirror `../yard/mise.toml` task shape: `format`, `check`, `test`, `pre-commit`).
- `.gitignore`: `build/`, `*.db`, `*.db-wal`, `*.db-shm`, `priv/static/*.js`, `priv/static/*.css` (generated).
- Move `SCOUTING_REPORT.md`, `PLAN.md`, `STATUS.md`, `AGENTS.md`, `SPEC.md` into the new project root; keep `feeds.opml` as a test fixture.

**1.2 SQLite schema + Parrot codegen** (mirror `../yard/yard/src/yard/sql/schema.sql`)
- Write `schema.sql` (source of truth, `CREATE TABLE IF NOT EXISTS …`): `feeds`, `entries` (port from `priv/resource_snapshots/repo/*/` JSON — see SCOUTING_REPORT §1.1).
  - `feeds(id TEXT PK, name TEXT, site_url TEXT, feed_url TEXT NOT NULL UNIQUE, category TEXT DEFAULT 'Uncategorized', last_fetched_at TEXT, fetch_error TEXT)`
  - `entries(id TEXT PK, created_at TEXT NOT NULL, external_id TEXT NOT NULL, title TEXT, content_link TEXT, comments_link TEXT, published_at TEXT, is_read INTEGER NOT NULL DEFAULT 0, is_starred INTEGER NOT NULL DEFAULT 0, feed_id TEXT NOT NULL REFERENCES feeds(id) ON DELETE CASCADE, UNIQUE(feed_id, external_id))`
- Write `queries.sql` with Parrot queries: `list_feeds`, `get_feed`, `insert_feed`, `delete_feed`, `log_fetch_success`, `log_fetch_error`, `list_entries` (paginated variants: unread/starred/history), `get_entry`, `upsert_entry`, `toggle_read`, `toggle_starred`, `unread_count`.
- `mise run gen` task: `sqlite3 /tmp/gen.db < schema.sql && gleam run -m parrot -- --sqlite /tmp/gen.db && rm /tmp/gen.db` → produces `src/feedreader/sql.gleam` (do not edit).
- **Test**: open `:memory:` db, run schema, assert tables exist (`PRAGMA table_info`), insert/select roundtrip.

**1.3 `db.gleam`** — typed CRUD wrappers (port pattern from `../yard/yard/src/yard/db.gleam`)
- `Feed`/`Entry` custom types. `param_to_value` / `params_to_values` helpers. `open(path)`, `migrate(conn)`, `new_id()`, `now_ts()` (birl).
- One public fn per query from `sql.gleam`, mapping `Result(_, sqlight.Error)` → `Result(_, Nil)` for ergonomics.
- **Tests**: `with_db` helper (open `:memory:`, migrate, pass conn). Test insert + list + get + delete + upsert idempotency. Use `let assert Ok(...)` for unwraps; `assert` for value checks.

### Phase 2 — Domain & parsing

**2.1 `feed.gleam`** — feed business logic
- `add(conn, attrs)` (insert, ignore-on-duplicate-feed_url), `list`, `get(id)`, `delete` (cascade), `log_fetch_success/error`.
- **Tests**: add rejects duplicate `feed_url`; delete cascades to entries (`PRAGMA foreign_keys=ON`).

**2.2 `entry.gleam`** — entry reads/toggles
- `list_unread/starred/history(conn, limit, offset)` returning `List(Entry)`.
- `get(id)`, `toggle_read(conn, id)`, `toggle_starred(conn, id)` (flip + update), `upsert(conn, attrs)`.
- **Tests**: upsert same `(feed_id, external_id)` twice → count unchanged (dedupe). Toggle flips boolean. Unread excludes read entries.

**2.3 `xmerl_ffi.erl`** (port verbatim from XML spike) + `xml.gleam`
- FFI exposes `parse/1`, `node_kind/1`, `node_tag/1`, `node_attrs/1`, `node_children/1`, `node_text/1`. **Must `binary_to_list` before `xmerl_scan:string`.**
- `xml.gleam`: `XmlNode` type (`Element`/`Text`), `parse(source)` → `Result(XmlNode, ParseError)`, tree helpers (`elements_by_tag`, `children_by_tag`, `text_of`, `child_text`, `attr`).
- **Tests** (birdie snapshots of parsed trees + assertions): parse OPML fixture → 77 feeds; parse `fixtures/xkcd_atom.xml`, `fixtures/lobsters_rss.xml`, `fixtures/github_atom.xml` (the xmlm-failure case) → entries extracted; Unicode preserved (assert titles contain `’`/`—`).

**2.4 `rss.gleam`** — RSS/Atom → `List(EntryAttrs)`
- Port from Elixir `FetchFeed.parse_feed`. Handle `<item>` (RSS) + `<entry>` (Atom). Extract title/link/guid|id/comments/pubDate|published|updated.
- **Tests**: synthetic feeds covering RSS, Atom, missing fields, Atom `<link rel=alternate>`, multiple `<link>`s, CDATA. Real fixtures as integration tests.

**2.5 `date.gleam`** — date parsing
- Port Elixir `parse_rfc822` + ISO8601. Use `birl` for normalization. Handle named TZ abbrevs (EST/PST/…).
- **Tests**: table of RFC822 + ISO8601 inputs → expected birl values. Edge cases: `nil` input, `""`, no-TZ, `Z`, `+0800`, `EST`.

**2.6 `opml.gleam`** — OPML import
- Port `FeedReader.Core.import_opml`. Walk nested `<outline>`, group by parent `text` attr, extract `xmlUrl`/`htmlUrl`/`title`. Returns `{success, error}` counts.
- **Tests**: parse `fixtures/feeds.opml` → 77 feeds across 3 categories; duplicate import is idempotent (feeds already exist → ignored).

### Phase 3 — Background workers

**3.1 `http.gleam`** — feed fetcher
- `fetch(url)` via `gleam_httpc` (30s timeout). Return `Result(String, FetchError)` (body on 200, error otherwise).
- **Tests**: `http_server_mock` stub returning a canned RSS body; stub returning 404; stub timing out.

**3.2 `fetcher.gleam`** — gleam_otp actor
- Takes `{db_conn, feed_id}`, fetches → parses (rss.gleam) → upserts each entry → logs success/error.
- **Actor message type**: `Fetch(feed_id)`, `Subscribe(Subject(Event))`, `Stop`.
- Emits `EntryUpserted(entry)` events to subscribers (for future real-time / unread-count).
- **Tests** (skill Pattern 1 `send_and_confirm`): start actor with `:memory:` db + seeded feed; `Subscribe(test_subj)`; `Fetch(feed_id)`; `process.receive` on test subj → assert entry persisted + `last_fetched_at` set. No `process.sleep`. Dead-subscriber resilience test.

**3.3 `scheduler.gleam`** — gleam_otp actor (cron tick)
- Every N minutes: list feeds, enqueue `Fetch(feed_id)` for each due (last fetched > 10min ago or nil). Stagger 1–5min via `process.send_after`.
- **Tests** (Pattern 1 + listener): inject a fake "now" / controllable clock OR test the pure decision function `feeds_due(feeds, now)` separately from the actor loop. Actor test: `Tick` → assert fetcher received N `Fetch` messages (use a test fetcher Subject that records).

### Phase 4 — Web layer

**4.1 `web/server.gleam`** — Mist + Wisp bootstrap
- `wisp_mist.handler(handle_request, secret_key_base)` where `secret_key_base` from env. `mist.new |> mist.port(3000) |> mist.start`. Hold db_conn in app state.
- **No test** (integration-tested via handlers).

**4.2 `web/router.gleam`** — route table
- Routes (full pages = HTML doc; fragments = HTML fragment):
  - `GET /` → unread page · `GET /starred` · `GET /history` · `GET /feeds`
  - `POST /entry/:id/toggle-read` · `POST /entry/:id/toggle-star` (fragments)
  - `GET /?after=<offset>` → load-more fragment
  - `POST /feeds` (add) · `POST /feeds/import` (OPML multipart) · `DELETE /feeds/:id` (fragments)
  - `GET /static/*` (css/js/htmx.min.js)
  - `GET /unread-count` (optional poll fragment)
- **Tests**: handler-level — build `wisp.Request` via `wisp.testing` helpers, assert response status + `string.contains(body, "...")`.

**4.3 `web/html.gleam`** — shared Lustre element builders (pipe-style)
- `layout(title, current_path, inner)`, `nav(current_path)`, `entry_card(entry)`, `feed_card(feed)`, `flash(kind, msg)`, `hx_attr` helper (1-line adapter so `|> hx_attr(hx.post(url: …))` pipes bare).
- **Tests** (birdie snapshots): render `entry_card(sample)` → snapshot the HTML. Toggle re-renders with flipped classes.

**4.4 `web/pages.gleam`** — full-page render
- `unread_page(entries, offset, has_more)`, `starred_page`, `history_page`, `feeds_page(feeds, flash)`. Each returns `element.Element(msg)`; router calls `element.to_document_string`.
- Port Elixir `EntryLive`/`FeedLive` markup via lustre_pipes. Preserve DaisyUI classes from `assets/css/app.css`.
- Relative-date helper (`humanize_date`) ported from `time_helpers.ex`.
- **Tests**: birdie snapshot each page with fixture data.

**4.5 `web/fragments.gleam`** — HTMX partial responses
- `entry_card_fragment(entry)` (post-toggle), `load_more_fragment(entries, next_offset)`, `feed_row_fragment(feed)`, `toast_fragment(msg)`.
- Return via `wisp.html_body(element.to_string(...))`. Use `hx_header.trigger`/`hx_header.redirect` where needed (e.g. after OPML import → redirect to /feeds with flash).
- **Tests**: birdie snapshots; assert response headers (`hx-trigger`) via `wisp.testing`.

### Phase 5 — Theming & assets

**5.1 Port CSS** — copy `assets/css/app.css` (Tailwind v4 + DaisyUI light/dark themes, oklch colors) verbatim → `priv/static/css/app.css`. Copy `assets/vendor/daisyui*.js`, `heroicons.js` → `priv/static/vendor/`.
**5.2 Vendor HTMX** → `priv/static/js/htmx.min.js` (v2.0.4). Theme-toggle JS from `root.html.heex` → small inline `<script>` in `layout`.
**5.3 Build pipeline**: add a `mise` task `assets:build` running Tailwind CLI (or `glailglind`) → `priv/static/css/app.css`. Run in `pre-commit` + CI.

### Phase 6 — Auth (simplified)

**6.1 `web/auth.gleam`** — session cookie auth
- Single hardcoded admin password from env (`FEEDREADER_PASSWORD`). `POST /login` validates → sets signed session cookie via `wisp.set_cookie` (using `secret_key_base`). `require_auth(req, handler)` middleware: redirect to `/login` if no valid session.
- Drop magic-link / Swoosh / AshAuthentication entirely.
- **Tests**: login with correct password → 302 + cookie set; wrong password → 401; `require_auth` redirects unauthenticated.

### Phase 7 — App wiring & ops

**7.1 `feedreader.gleam`** — supervision tree (mirror Elixir `Application`)
- `supervisor.new(strategy: OneForOne)` with children: db connection actor, scheduler actor, fetcher pool actor(s), mist HTTP server. Read config from env via `envoy`.
**7.2 Docker** — `Dockerfile` (multi-stage: build with rebar3/gleam, copy beam artifacts + priv/static). `docker-compose.yaml` (volume for `*.db`).
**7.3 CI** — `.github/workflows/ci.yml`: `gleam format --check`, `gleam check`, `gleam test`, asset build. Replace the old `docker.yml`.
**7.4 `mark-read.sh`** — port to call the Gleam app (or drop if the bulk-mark-read is better as an in-app admin route).

---

## Testing strategy summary

| Layer | Tool | Pattern |
|---|---|---|
| DB (`db.gleam`, `feed.gleam`, `entry.gleam`) | gleeunit + `:memory:` sqlite | `with_db` helper; `let assert Ok(...)`; `assert` on values |
| Parsers (`xml`, `rss`, `opml`, `date`) | gleeunit + birdie snapshots | snapshot parsed trees; assert on extracted fields; real fixtures in `test/fixtures/` |
| HTTP fetch | `http_server_mock` | stubbed responses (200/404/timeout) |
| Actors (`fetcher`, `scheduler`) | gleeunit + `process.receive` | **send_and_confirm** (skill Pattern 1); test listener for side effects (Pattern 2); no `process.sleep` |
| Web handlers | `wisp.testing` request builders | assert status + `string.contains(body)`; birdie snapshot rendered HTML |
| Snapshots | `birdie` | accept first run with `gleam test -- -b` then review |

**Rule**: every module in `src/` has a matching `test/<module>_test.gleam`. Tests run in `mise run pre-commit` (fast `:memory:` db, mocked HTTP — no network).

---

## Definition of done

- [ ] `mise run pre-commit` green (format + check + test)
- [ ] `gleam run` starts server on :3000; browser loads `/` showing unread entries
- [ ] Add a feed via `/feeds` → scheduler fetches within 10min → entries appear
- [ ] Toggle read/star updates in place (HTMX swap, no full refresh)
- [ ] OPML import (`fixtures/feeds.opml`) → 77 feeds imported, categorized
- [ ] Dark/light/system theme toggle works
- [ ] Docker image builds + runs
- [ ] CI green on push
