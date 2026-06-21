# Status

## Current Goal
Rewrite the Elixir/Phoenix feed reader as a Gleam application. **Complete — feature parity achieved and validated.** The Gleam project is now in this repo root (replacing the Elixir implementation). 2963 LOC across 17 source files, 80 unit tests, 76 E2E scenarios validated against a live server, `mise run pre-commit` green. UI fully styled with Tailwind + DaisyUI dark theme. Visual parity with old Elixir app confirmed via screenshots — feed names in metadata, Heroicons SVG buttons, card layout all match.

**Validation receipt**: [`receipt.html`](./receipt.html) — open in browser for full walkthrough + test results.

The original Elixir implementation has been removed. The `../feedreader_gleam/` directory is preserved as a reference copy.

## Documents
- [`SCOUTING_REPORT.md`](./SCOUTING_REPORT.md) — architecture, feature map, package survey, spike results
- [`PLAN.md`](./PLAN.md) — condensed 7-phase implementation build order
- [`E2E.md`](./E2E.md) — 76 BDD scenarios across 11 feature areas
- [`STATUS.md`](./STATUS.md) — this file
- [`receipt.html`](./receipt.html) — standalone validation receipt (open in browser)
- [`../feedreader_gleam/`](../feedreader_gleam/) — reference copy of the Gleam project (pre-merge)

## Steps & Progress
- [x] **Phase 0**: Scouting & architecture
- [x] **PLAN.md** + **E2E.md** written
- [x] **Phase 1**: Scaffold + SQLite schema + Parrot codegen + db.gleam — 17 tests
- [x] **Phase 2**: Domain & parsers (xml/xmerl FFI, rss, date, opml) — 33 tests
- [x] **Phase 3**: Background workers (http, fetcher, scheduler) — 15 tests
- [x] **Phase 4**: Web layer (html, pages, fragments, router, server) — 15 tests
- [x] **Phase 5**: Theming & assets — Tailwind v4 + DaisyUI dark-only, compiled via glailglind (no Node.js), HTMX vendored
- [x] **Phase 6**: App wiring (scheduler+fetcher actors wired), Docker, CI, mark-read.sh
- [x] **Runtime smoke test passed**: server starts, pages render, feeds add, dark theme, nav, 404
- [x] **E2E validation**: 76/76 BDD scenarios validated against live server
- [x] **Receipt generated**: `receipt.html` — standalone HTML artifact with all results + project walkthrough
- [x] **Elixir implementation removed; Gleam project moved to repo root**
- [x] **CSS fix**: Fixed `@source` paths in `priv/static/css/app.css` — Tailwind utilities and DaisyUI components now compile correctly
- [x] **Visual comparison with old Elixir app**: Identified two styling gaps to fix
- [x] **Styling parity fix**: Code complete (feed name + icons), tests pass, screenshots visually confirmed — matches old app's metadata line + button icons
- [x] **Crash resilience fix**: gleam_httpc FFI crashes on unknown errors (socket_closed_remotely) and takes down the whole app via linked actors. Fixed with HTTP worker isolation + supervision tree + 2 tests
- [x] **Mark-read disappears from unread page**: Toggle handlers now context-aware via Referer header. Marking as read on unread page returns empty fragment (card removed). Un-starring on starred page returns empty fragment.
- [x] **Load More fix**: Fixed HTMX pagination — server returns entry fragments (not full page) for HTMX requests, OOB swap updates/removes Load More button, corrected `hx-target` from `closest #entries` to `#entries` (button is a sibling, not descendant)
- [x] **Full feature audit**: All 21 features verified (unread/starred/history/feeds pages, add feed, delete feed, OPML import, toggle read/star with context-aware removal, load more, empty states, 404, CSS/JS assets)
- [x] **Button color fix**: Changed starred/read button active states from DaisyUI semantic colors (`text-warning`/`text-success`) to raw Tailwind palette matching old app (`text-yellow-400`/`text-green-400` with matching bg/border opacity)
- [x] **Full color audit**: Compared all color classes between old Elixir templates and new Gleam views. Fixed feed card detail text (`text-gray-400`/`text-gray-500` replacing `text-base-content/40`/`text-base-content/60`) and empty feeds state (`text-gray-500`). All entry card, nav, form, and button colors now match old app exactly.
- [x] **Favicon**: Added inline SVG star favicon (yellow `#FEC700` Heroicon star) to `<head>`, matching old Elixir app.
- [x] **Font/hover/structural parity**: Removed all self-added CSS classes not present in old app — header `sticky top-0 z-50 backdrop-blur-md`, nav links `btn btn-ghost btn-sm hover:bg-base-300 hover:text-primary transition-all`, logo `hover:bg-base-300 transition-colors`, entry card `card transition-all hover:border-primary/30 hover:shadow-lg`, feed card `transition-all hover:shadow-lg hover:border-primary/30`, form buttons `hover:scale-105 transition-transform`, input `focus:border-primary transition-colors`, delete button `hover:bg-error/10 transition-all`. Added `min-h-screen bg-base-100` wrapper div matching old app layout. Nav links are now plain `<a>` inside DaisyUI `menu-horizontal` (DaisyUI handles hover/active styling).
- [x] **Dockerfile + CI fix**: Dockerfile runtime stage now explicitly copies `priv/` to CWD (erlang-shipment nests it under `feedreader/priv/`). Fixed CMD to `./entrypoint.sh run` (removed unnecessary `-m feedreader` args that entrypoint.sh already handles). CI verified correct for Gleam project.
- [x] **Docker build + run verified**: Fixed 3 Docker issues: (1) missing C compiler for esqlite NIF — added `build-base sqlite-dev` to builder; (2) OTP version mismatch — Gleam image uses OTP 28, runtime was OTP 26, beam files incompatible; (3) bind address — mist defaults to `127.0.0.1` (localhost only), Docker needs `0.0.0.0`. CI updated to OTP 28.

## Architecture Decisions (locked)
- **Backend**: Wisp + Mist, Erlang/BEAM
- **Frontend**: Lustre SSR + lustre_pipes + HTMX (typed via hx)
- **Storage**: SQLite + Parrot + sqlight
- **Background**: gleam_otp actors (scheduler 3-min tick + fetcher pool)
- **Styling**: Tailwind v4 + DaisyUI dark-only, compiled via **glailglind** (Tailwind CLI binary, no Node.js)
- **Auth**: none (external)
- **XML**: xmerl via Erlang FFI

## Resolved Dependency Versions
| Package | Version |
|---|---|
| gleam_stdlib | 1.0.3 |
| gleam_erlang | 1.3.0 |
| gleam_otp | 1.2.0 |
| wisp | 2.2.2 |
| mist | 6.0.3 |
| lustre | 5.7.0 |
| lustre_pipes | 0.3.0 |
| hx | 3.0.0 |
| sqlight | 1.1.0 |
| parrot | 1.2.12 |
| birl | 1.9.0 |
| glailglind | 2.3.0 (dev) |
| glinter | 2.x (dev) |

## Unknowns
- (all resolved)

## DB Migration
The old Elixir/Ash schema and the new Gleam schema are **identical** — same tables, same columns, same types (SQLite `INTEGER` for booleans, `TEXT` for everything else). Data can be transferred directly via `ATTACH DATABASE` + `INSERT OR IGNORE`. No transformation needed. One caveat: old `feeds.category` could be NULL (no `NOT NULL` constraint), new schema has `DEFAULT 'Uncategorized'`. Use `COALESCE(category, 'Uncategorized')` if transferring from old DB.

**The app can load directly from the old DB file with no migration needed.** Just set `DATABASE_PATH=/path/to/old_feedreader_dev.db`. The `db.migrate()` function uses `CREATE TABLE IF NOT EXISTS` (no-op if tables exist). Old DB will have extra tables (`users`, `tokens`, `oban_jobs`, `schema_migrations`) from Ash/Oban — those are harmless, the app only queries `feeds` and `entries`. One non-issue: the old `entries` table lacks `ON DELETE CASCADE` on the FK (SQLite can't add it after creation), but the delete handler doesn't rely on cascade.

## Discovered Issues
- Parrot: no `ParamNullable` — nullable stored as `""`, converted via helpers
- Parrot: each `:many` query generates its own type — needed separate converters
- gleam_otp: `actor.new(state)` + `on_message` + `start` for simple; `new_with_initialiser` + `returning` + `initialised` for init-based
- birl: `birl.subtract(time, duration.minutes(n))` via `birl/duration`
- FFI files: must be in `src/` root, module name matches filename
- sqlight: exec queries use `decode.success(Nil)` as decoder
- rebar3: must `eval "$(mise activate bash)"` before gleam commands
- lustre_pipes: conditional children use `element.none()`; childless elements use `lp.empty()`
- wisp v2: `handle_head` takes `fn(Request)` (use `use req <-`); `require_form` takes `fn(FormData)`; `get_query` returns `List(#(String, String))`
- Erlang `integer_to_list/1` returns charlist — use `gleam/int.to_string`
- glailglind: Tailwind CLI binary via `gleam run -m tailwind/install`; configure in `gleam.toml` `[tools.tailwind]` with args
- Port 3000 must be free before starting server (old processes hold it)
- **Schema single source of truth**: `src/feedreader/sql/schema.sql` is the canonical file. `db.migrate()` reads from `priv/schema.sql` at runtime (Gleam includes `priv/` in releases). `mise run gen` copies schema.sql to `priv/` after Parrot codegen — one file to edit, both codegen and runtime stay in sync.
- **Tailwind CSS `@source` paths must use `**/*.gleam` globs**: After moving the project to the repo root, the `@source` paths in `priv/static/css/app.css` broke because they resolved relative to the CSS file location. The correct path from `priv/static/css/` to `src/` is `../../../src/`. The fix: `@source "../../../src/feedreader/web/**/*.gleam";` and `@source "../../../src/**/*.gleam";`. Without this, Tailwind v4 compiles zero utility classes and zero DaisyUI components (16KB vs 51KB output).
- **Styling parity with old Elixir app**: Two gaps identified from screenshot comparison, **both now fixed in code**:
  1. **Feed name in metadata line** — OLD: `Hacker News | Apr 12, 2026`. NEW: just `Apr 12, 2026`. **FIXED**: SQL queries updated with `JOIN feeds f ON f.id = e.feed_id`, Parrot regenerated (types now include `feed_name`/`feed_site_url`/`feed_feed_url`), `Entry` type extended with `feed_name: Option(String)`, all 4 `row_to_entry_*` converters updated to call `compute_feed_name()` (mirrors old app's `feed_display_name/1`: name → site_url root domain → feed_url root domain via `root_domain()` helper), `html.gleam` `entry_card` now renders `metadata` as `"Feed Name | Date"` matching old app's conditional logic.
  2. **Button icons** — OLD: `<.icon name="hero-star"/>` + `<.icon name="hero-check-circle"/>`. NEW: plain text. **FIXED**: Added `star_icon()` and `check_circle_icon()` functions in `html.gleam` using `element.namespaced()` with inline Heroicons SVG paths. Buttons now render `lp.children([icon, element.text(label)])`.

- **gleam_stdlib 1.0 has no `list.at/2`**: Use `list.reverse` + pattern match `[tld, second, ..]` instead.
- **gleam_httpc FFI crashes on unknown error shapes**: `gleam_httpc_ffi:normalise_error/1` only maps `failed_connect` and `timeout`; everything else (e.g. `socket_closed_remotely`) calls `erlang:error({unexpected_httpc_error, ...})` which throws an uncatchable exception in the calling process. **FIX**: `http.fetch` now runs the HTTP request in an isolated, unlinked, monitored process via `process.spawn_unlinked` + `process.monitor`. If the worker crashes, we catch the `MonitorDown` and return `Error(...)`.
- **No supervision tree = actor crash kills everything**: `server.gleam` started actors with `actor.start` (which uses `spawn_link`), linking them directly to the main process. When the fetcher crashed, the EXIT signal propagated to main, taking down the whole app. **FIX**: Added `gleam/otp/static_supervisor` with `OneForOne` strategy and restart tolerance (10/60s). Scheduler now runs under the supervisor.
- **gleam_erlang `process.select` vs `select_map`**: `process.select(selector, for: subject)` is for same-typed messages; use `process.select_map(selector, subject, mapping_fn)` to transform message types for the selector.
- **xmerl `expected_element_start_tag` / `unexpected_end` errors are benign stderr noise**: xmerl_scan writes to the Erlang error logger during parsing of malformed feeds, but returns `{error, ...}` which our FFI catches and converts to `ParseError`. No crash, no data loss.
- **Erlang FFI tuple shapes must match Gleam external type**: `{ok, A, B}` (3-tuple) does NOT match `Result(#(a, b), c)` (Result wrapping 2-tuple). Return `{ok, {A, B}}` instead.
- **Gleam guards cannot call functions**: `case x { _ if string.ends_with(x, "/") -> }` is illegal. Compute the boolean first, then match on it: `let is_x = string.ends_with(x, "/"); case is_x { True -> ... }`.
- **Context-aware HTMX removal via Referer header**: Toggle endpoints (`/entry/:id/toggle-read`, `/entry/:id/toggle-star`) check the `Referer` header to determine the current page view. On filtered pages (unread/starred), entries that no longer match return an empty fragment response, causing HTMX to remove the card from the DOM. Mirrors the old Elixir app's `stream_delete` behavior.
- **`request.get_header` returns `Result(String, Nil)`, not `Option(String)`**: Use `result.unwrap(request.get_header(req, "referer"), "")` to extract headers from a `wisp.Request`.
- **HTMX `closest` selector traverses ancestors, not siblings**: `hx-target="closest #entries"` fails if the button is a sibling of `#entries`, not a child. Use `hx-target="#entries"` (plain CSS selector) instead.
- **HTMX load-more requires fragment response, not full page**: When `?after=N` is requested via HTMX (`HX-Request: true` header), the server must return only entry card fragments + an OOB-updated Load More button. Returning a full `<!doctype html>` document breaks the `beforeend` swap. Use `hx-swap-oob="true"` on the `#load-more-container` to replace the old button.
- **hx v3.0 selector API**: `hx.target()` takes `hx.Selector("#id")`, not `hx.Closest("#id")` or `hx.Element("#id")`.
- **DaisyUI semantic colors vs raw Tailwind palette**: DaisyUI `text-warning`/`text-success` map to muted theme palette tones that look nothing like the old app's vivid `text-yellow-400`/`text-green-400`. When matching an existing app's look, use raw Tailwind palette classes directly, not DaisyUI semantic aliases.
- **erlang-shipment nests priv/ under application dir**: `gleam export erlang-shipment` puts priv files at `feedreader/priv/`, not `priv/`. Runtime code reading relative paths like `priv/schema.sql` needs `priv/` at CWD. Fix: Dockerfile runtime stage explicitly copies `COPY --from=builder /app/priv ./priv`.
- **entrypoint.sh already handles module invocation**: The generated `entrypoint.sh run` already calls `-eval "feedreader@@main:run(feedreader)". Passing extra `-m feedreader` args via CMD is redundant and could cause issues.
- **Docker OTP version must match builder**: `ghcr.io/gleam-lang/gleam:v1.16.0-erlang-alpine` ships with OTP 28. Runtime image must also be OTP 28 (was 26) — beam bytecode is not forward-compatible.
- **Docker needs C compiler for esqlite NIF**: The Alpine builder image doesn't include `cc`. Add `apk add --no-cache build-base sqlite-dev` before `gleam export erlang-shipment`. Runtime stage needs `sqlite-libs` for the shared library.
- **mist defaults to localhost binding**: `mist.start` binds to `127.0.0.1` by default. Docker containers need `mist.bind("0.0.0.0")` to accept forwarded traffic.
