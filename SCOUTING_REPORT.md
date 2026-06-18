# FeedReader → Gleam: Scouting Report & Architecture Recommendation

> Source app: Elixir + Phoenix LiveView + Ash Framework + Oban + SQLite
> Reference project: `../yard` (Gleam + Parrot + sqlight + gleam_otp on the BEAM)

---

## 1. What the current app actually does

A single-user RSS/Atom feed reader with four screens and a background polling engine.

### 1.1 Domain / data (Ash Framework → SQLite)

**`Feed`** — an RSS/Atom subscription
| field | type | notes |
|---|---|---|
| `id` | uuid PK | |
| `name` | string? | display name |
| `site_url` | string? | human site |
| `feed_url` | string **required** | unique identity |
| `category` | string | default `"Uncategorized"` |
| `last_fetched_at` | utc_datetime? | |
| `fetch_error` | string? | last error text |

has_many entries (cascaded delete).

**`Entry`** — a single article parsed from a feed
| field | type | notes |
|---|---|---|
| `id` | uuid PK | |
| `created_at` | utc_datetime | |
| `external_id` | string **required** | RSS `<guid>`/`<id>`, or link fallback |
| `title` | string? | |
| `content_link` | string? | article URL |
| `comments_link` | string? | |
| `published_at` | utc_datetime? | |
| `is_read` | bool | default false |
| `is_starred` | bool | default false |
| `feed_id` | uuid FK → feeds | required |

Unique identity on `(feed_id, external_id)` → upsert on import.

**`User`** / **`Token`** — AshAuthentication magic-link auth. Single `email` field. JWT tokens stored in DB. **Effectively single-user.**

### 1.2 Business actions
- Feed: add, delete (cascade), list, log_fetch_success, log_fetch_error, **import_opml** (parse OPML XML → grouped by category `text` attr, extract `xmlUrl`/`htmlUrl`/`title`).
- Entry reads (keyset pagination, limit 50, sort published_at):
  - `unread` (is_read=false, asc)
  - `starred` (is_starred=true, asc)
  - `history` (desc)
- Entry updates: `toggle_read`, `toggle_starred` (flip boolean), `upsert_from_feed`.

### 1.3 Background processing (Oban)
- **Scheduler** (cron `*/3 * * * *`): list feeds, enqueue a `FetchFeed` job for each feed not fetched in the last 10 min, staggered by 1–5 random minutes.
- **FetchFeed** worker: `Req.get` (30s timeout) → `SweetXml` parse → handle RSS `<item>` **and** Atom `<entry>` → extract guid/title/link(pubDate|published|updated)/comments → **custom RFC822 + ISO8601 date parser** with timezone handling → upsert each entry → PubSub-broadcast genuinely-new entries → log success/error.

### 1.4 Presentation (Phoenix LiveView)
- `EntryLive.Index` — one LiveView, 3 actions (`:unread`/`:starred`/`:history`) via routes `/`, `/starred`, `/history`.
  - Phoenix **Streams** for memory-efficient DOM.
  - "Load More" button pagination (offset-based in practice, despite keyset config).
  - `toggle_star` / `toggle_read` events → stream_insert/stream_delete with optimistic count + removal-from-view logic (e.g. unstarring removes from Starred view).
- `FeedLive.Index` — `/feeds`: add-feed form, **OPML file upload** (`allow_upload`), feed list with last-fetched/error display, delete.
- Humanized relative dates ("just now", "3h ago", "yesterday", fallback `Mon DD, YYYY`).

**Key implication for the rewrite**: the only interactions that genuinely need to avoid a full refresh are the read/unread and star toggles (plus load-more appending, form submits, and deletes). Everything else (navigation between Unread/Starred/History/Feeds) is fine as full page loads. This makes HTMX the natural fit (see §4).

### 1.5 UI / styling
- Tailwind CSS v4 + **DaisyUI** with custom light/dark themes (oklch colors).
- Theme toggle (system/light/dark) via `data-theme` attribute + localStorage.
- Heroicons.
- Layout: navbar + horizontal nav (Unread/Starred/History/Feeds), centered `max-w-4xl`.

### 1.6 Dev / ops
- Dockerized (Dockerfile + docker-compose), GitHub Actions CI builds/pushes image.
- Dev conveniences: Oban Web dashboard, Ash Admin, LiveDashboard, Tidewave, live reload.
- `mark-read.sh` — bulk-mark-read via container RPC (operational script, not a feature).
- Pre-commit: compile, format, credo, sobelow, test.

---

## 2. The mapping: Elixir/Phoenix → Gleam

| Elixir / Phoenix concern | Gleam replacement | confidence |
|---|---|---|
| **Phoenix web framework** | **Wisp** (request/response, routing, sessions, file uploads, testing) | ✅ high |
| **HTTP server (Bandit)** | **Mist** | ✅ high |
| **Phoenix LiveView (real-time SSR)** | **Lustre element API (SSR) + HTMX** for partial swaps | ✅ high |
| **Ash Framework (domain)** | **Plain Gleam modules + custom types** (no ORM needed at this scale) | ✅ high |
| **Ecto / ash_sqlite** | **sqlight** driver | ✅ high |
| **Typed SQL / migrations** | **Parrot** (sqlc-style codegen from schema.sql + queries.sql) — *mandated by AGENTS.md*, proven in `yard` | ✅ high |
| **Oban (background jobs)** | **gleam_otp actors** (scheduler + fetch workers); optional minimal `jobs` table in SQLite for durability | ✅ high |
| **Req (HTTP client)** | **gleam_httpc** | ✅ high |
| **SweetXml (RSS/Atom parse)** | **xmlm** (pure Gleam pull parser) or **xmerl FFI** for messy real-world feeds | ⚠️ medium — see §5 |
| **RFC822 date parsing** | **custom parser** + **birl** for ISO8601/normalization | ✅ high |
| **PubSub (real-time)** | **drop SSE**; optional 30s HTMX poll for an unread badge | ✅ high |
| **AshAuthentication (magic link)** | **Simplified session auth** (cookie + password/token) | ✅ high |
| **Swoosh mailer** | drop (magic link not worth the complexity for single-user) | ✅ |
| **Tailwind v4 + DaisyUI** | **Tailwind v4 + DaisyUI** (unchanged — works with any server) | ✅ high |
| **Heroicons** | inline SVG / heroicon set | ✅ high |
| **Gettext (i18n)** | static strings (not meaningfully used) | ✅ |
| **LiveDashboard / Oban Web / Ash Admin** | optional minimal status route or skip | ✅ |

---

## 3. Web framework decision: **Yes — use Wisp + Mist**

**Recommendation: Wisp on Mist, targeting Erlang/BEAM.**

- **Wisp** is Gleam's de-facto web framework (by Louis Pilfold, Gleam's creator). It gives us routing, request bodies, form parsing, **file uploads**, sessions/cookies, and an excellent testing story (handlers are pure functions of a `Request`). This covers *every* HTTP need of the current app (forms, OPML upload, JSON API).
- **Mist** is the production HTTP server (and supports **SSE / WebSockets** for the real-time new-entry notification).
- **Target Erlang/BEAM** (not JavaScript) — this is critical because the background feed-fetcher is a major feature, and the BEAM's lightweight processes give us trivial concurrency for fetching dozens of feeds in parallel, exactly like the current app relies on.

---

## 4. Frontend decision: **Server-rendered HTML + HTMX (no SPA)**

This is the biggest architectural choice. Three viable paths were evaluated:

| Option | Real-time? | UX control | Effort | Match to LiveView |
|---|---|---|---|---|
| A. Lustre SPA + Wisp JSON API + hydration | via SSE/polling | ★★★★★ (full client animation) | high | diverges |
| **B. Wisp + Lustre SSR + HTMX** ⭐ | optional poll | ★★★★ | **low** | closest |
| C. Lustre Server Components / Sprocket | built-in | ★★★★ | medium | closest (LiveView-style) |

**Recommendation: Path B — server-rendered HTML using Lustre's element API (SSR only), with HTMX for the handful of interactions that must not full-refresh. No SPA, no JSON API, no client Gleam, no hydration, no SSE.**

Why:
1. **The actual requirement is narrow**: server-rendered pages, but read/unread + star toggles must update without a full page refresh. That is HTMX's exact sweet spot.
2. **SSE, SSR, JSON API, and SPA overlap heavily** — adopting all of them would be the most complex option for a feature set that mostly doesn't need it. One mechanism (server emits HTML fragments, HTMX swaps them) replaces all four.
3. **Lustre stays in the stack, but only for its HTML-builder API** (`element.to_document_string` / `element.to_string`). It's the most mature typed HTML generator in Gleam and gives clean server-side rendering. We never start a client runtime.
4. **World-class UI is still achievable**: DaisyUI + Tailwind hover/transition classes handle micro-interactions, and HTMX supports swap transitions. A sprinkle of Alpine.js is available if a tiny bit of client state is ever needed (probably not).
5. **No surface-area drift**: there's no JSON API contract to design and keep in sync with a separate client model. HTMX speaks form-encoded requests and gets HTML back.

Path A (full SPA) is overkill given the requirement; Path C (Server Components) is appealing but younger and less battle-tested. Path B is the closest spiritual successor to the current Phoenix LiveView app at a fraction of the complexity.

**Styling is preserved unchanged**: Tailwind v4 + DaisyUI with the existing light/dark themes.

---

## 5. XML / RSS parsing — the one real risk area

The current parser uses `SweetXml` (xmerl-backed) and handles **both RSS `<item>` and Atom `<entry>`**, messy date formats (RFC822 with named timezones), and malformed feeds. Options:

- **`xmlm`** — pure Gleam pull-based XML parser. Clean, but we'd hand-write the RSS/Atom extraction + the RFC822 date logic (the Elixir app already hand-wrote the latter, so this is ~portable).
- **`xmerl` via Erlang FFI** — the most robust against real-world broken feeds (same engine SweetXml uses). Pragmatic choice if `xmlm` struggles.
- **OPML** uses the same parser (it's XML with `outline` elements).

**Plan**: Start with `xmlm`, port the existing RSS/Atom + RFC822 logic (it's already mostly framework-agnostic string munging), and fall back to an `xmerl` FFI if real-world feeds expose parser weaknesses. *(Note: the one known pure-Gleam RSS reader, billuc's, used nibble and reported 512MB / 3s for basic feeds — we will avoid a from-scratch nibble parser.)*

---

## 6. Proposed Gleam project structure

```
feedreader/                      (single gleam app, target = erlang)
├── gleam.toml
├── schema.sql                   # source of truth DDL (feeds, entries)
├── queries.sql                  # Parrot query source
├── src/
│   ├── feedreader.gleam         # app entry, supervision tree, config
│   ├── feedreader/
│   │   ├── sql.gleam            # ⚙ Parrot-generated (do not edit)
│   │   ├── db.gleam             # typed CRUD over sql.gleam + sqlight (mirrors yard/db.gleam)
│   │   ├── feed.gleam           # Feed type + business logic (add/delete/list/import_opml)
│   │   ├── entry.gleam          # Entry type + reads (unread/starred/history) + toggles
│   │   ├── rss.gleam            # RSS/Atom parse → List(EntryAttrs)
│   │   ├── opml.gleam           # OPML parse → List(FeedAttrs)
│   │   ├── date.gleam           # RFC822 + ISO8601 → birl
│   │   ├── http.gleam           # feed fetcher (gleam_httpc)
│   │   ├── scheduler.gleam      # gleam_otp actor: cron-ish tick → enqueue fetches
│   │   └── fetcher.gleam        # gleam_otp actor(s): fetch+parse+upsert, log success/error
│   └── feedreader/web/
│       ├── server.gleam         # Mist + Wisp bootstrap
│       ├── router.gleam         # routes: page handlers (full HTML) + HTMX fragment handlers + static assets
│       ├── pages.gleam          # full-page render (Unread/Starred/History/Feeds) via Lustre element API
│       ├── fragments.gleam      # HTMX partial responses (single card, feed row, toast, load-more)
│       ├── auth.gleam           # session cookie auth (simplified)
│       └── html/                # Lustre element builders (layout, entry_card, feed_card, nav)
├── priv/
│   ├── static/
│   │   ├── app.css              # Tailwind v4 + DaisyUI themes (ported from assets/css/app.css)
│   │   ├── htmx.min.js          # vendored HTMX
│   │   └── (optional) alpine.min.js
└── test/
```

### Supervision tree (mirrors current `Application`)
```
Application
├── sqlight connection (opened once, held by a db actor / shared)
├── Scheduler actor  ──(every N min)──▶ enqueues Feed(feed_id) msgs
├── Fetcher actor(s) ◀──(processes Feed(feed_id), fetches+parses+upserts)
└── Mist HTTP server (Wisp router: page handlers + HTMX fragments + static assets)
```

### Request flow (HTMX)
- **Full pages**: `GET /` → server renders full HTML document (nav + entry cards) via Lustre `element.to_document_string`.
- **Toggles**: `POST /entry/<id>/toggle-read` (HTMX) → server returns just that card's HTML fragment → HTMX swaps it in place. No full refresh, no JSON.
- **Load more**: `GET /?after=<cursor>` (HTMX) → server returns the next batch of cards + the next "load more" button.
- **Forms / delete / upload**: HTMX POST/DELETE returning the relevant fragment.
- **Optional live badge**: `<span hx-get="/unread-count" hx-trigger="every 30s">` polls a tiny count endpoint. Feeds refresh on a 10-min cycle, so polling is plenty.

---

## 7. Feature parity checklist (what carries over)

- [x] Feed CRUD (add / list / delete with cascade)
- [x] Entry reads: unread / starred / history, paginated
- [x] Toggle read / starred (no full refresh — HTMX swap; preserves the view-removal semantics from LiveView)
- [x] OPML import (file upload + parse + bulk add, grouped by category)
- [x] Background polling (cron scheduler + per-feed fetch workers, staggered)
- [x] RSS **and** Atom parsing, upsert-on-import (dedupe by external_id)
- [x] Date normalization (RFC822 + ISO8601)
- [x] Feed health display (last_fetched_at, fetch_error)
- [x] Real-time new-entry notification → simplified to optional 30s HTMX poll of unread count (no SSE)
- [x] Relative date humanization
- [x] Tailwind v4 + DaisyUI, light/dark themes, theme toggle
- [x] Session auth (simplified from magic-link)
- [x] Docker build + CI

**Intentionally simplified / dropped:**
- Magic-link email auth → simple session/password auth (single-user app; email infra not justified).
- SSE/WebSocket real-time push → optional polling (feeds refresh on a 10-min cycle anyway).
- SPA / client Gleam / JSON API / hydration → server-rendered HTML + HTMX (per actual requirement).
- Gettext i18n → static strings.
- Oban Web / Ash Admin / LiveDashboard dev dashboards → optional minimal `/status` route.

**Opportunities to improve during the rewrite:**
- True keyset/cursor pagination (current code uses offset).
- Parallel feed fetching via BEAM processes (cleaner than Oban queue for this workload).

---

## 8. Recommended dependency set (from packages.gleam.run survey)

### Core stack
| package | role |
|---|---|
| `gleam_stdlib` | stdlib |
| `gleam_erlang` | BEAM process/time interop |
| `gleam_otp` | actors + supervision (scheduler, fetchers) |
| `wisp` | web framework (routing, forms, uploads, sessions) |
| `mist` | HTTP server |
| `lustre` | HTML element API, **SSR-only** (`element.to_document_string` / `to_string_tree`) |
| `lustre_pipes` | pipe-operator builders for Lustre views — required for human + LLM-agent readability; composes with `hx` (targets `lustre < 6.0.0`) |
| ⭐ `hx` | typed HTMX attributes for Lustre + HTMX response headers for Wisp — the server↔client glue |
| `sqlight` | SQLite driver |
| `parrot` | typed SQL codegen (mandated by AGENTS.md, proven in `yard`) |
| `gleam_httpc` | HTTP client for feed fetching |
| `birl` | date/time (ISO8601 + normalization; used in `yard`) |
| `gluid` | UUID v4 (used in `yard`) |
| `envoy` | env vars, zero-dep (used in `yard`/`hermes`) |
| `gleam_json` | JSON (HTMX trigger payloads, any JSON needs) |
| `logging` | Erlang logger config |

### XML / RSS
| package | role |
|---|---|
| **`xmerl` via Erlang FFI** (~40 lines) | **SOLE XML parser** — chosen after spike. Erlang's built-in XML engine (same as Elixir's SweetXml). Handles WordPress namespaces, entities, Unicode. No Gleam package dep. |

> **XML spike result (resolved):** Tested `xmlm` v1.0.1 (pure Gleam) and `xmerl` FFI against real feeds: OPML (77 feeds), Lobsters RSS, Hacker News RSS (non-ASCII titles), xkcd Atom, GitHub Blog Atom (WordPress namespace), fasterthanli.me Atom (heavy Unicode).
>
> **`xmlm` FAILED** on `<site xmlns="com-wordpress:feed-additions:1">` — the WordPress namespace declaration. Error: `unknown namespace prefix ()`. This namespace appears on millions of WordPress blogs (GitHub Blog, countless sites). Hard blocker for a feed reader.
>
> **`xmerl` FFI succeeded on ALL feeds**: parsed GitHub Blog (10 items), preserved Unicode (HN smart quotes, em-dashes, accents), decoded entities (`&#39;`→`'`). The FFI is ~40 lines of Erlang (`xmerl_ffi.erl`) that walks `#xmlElement{}`/`#xmlText{}` records into a simple `{element, Tag, Attrs, Children} | {text, String}` structure, with field-accessor functions for Gleam `@external` calls. Same battle-tested engine as Elixir's SweetXml.
>
> Other packages checked: `parsed_it` (decode-style API but documented Unicode-corruption bug on Erlang XML → rejected), `webls` (feed *generator* not parser → n/a), `htmgrrrl` (HTML SAX, not XML-purpose).

### Forms / parsing
| package | role |
|---|---|
| ⭐ `formal` | type-safe HTML form decoding/validation (add-feed form, OPML upload) |
| `glentities` | HTML entity encoding (safe rendering of feed titles/content) |

### Dev / testing
| package | role |
|---|---|
| `gleeunit` | test runner |
| ⭐ `birdie` | snapshot testing — pairs with Lustre `to_readable_string` for asserting HTMX fragment HTML |
| ⭐ `http_server_mock` | HTTP API mocking — stubs feed fetches in tests (replaces Elixir's `Req.Test`) |
| `mist_reload` | dev hot reload of the mist server |

### Optional / later
| package | role |
|---|---|
| `plume` | security headers (helmet-style) |
| `dot_env` | load the existing `.env` |
| `ghtml` | *optional* HTML-markup → Gleam codegen layer; only if pipe-style Lustre still feels verbose after the spike (v0.1.1, generates Lustre) |
| `automata` | cron/RRULE (already a `yard` dep) — if we want richer scheduling than a simple timer |

> Note on `lustre_pipes` (now a core dep): it's purely syntactic sugar over standard Lustre `Element`/`Attribute` types, so it composes with `hx` and any Lustre-compatible package. If it ever breaks or is abandoned, the fallback is a mechanical refactor back to nested calls or a tiny vendored pipe-wrapper module (~12 lines) — low blast radius.

### Considered and rejected
- **nakai** — server HTML gen; fine alternative to Lustre SSR, but no HTMX companion and less momentum. Lustre wins.
- **rally / lightspeed / sprocket / lustre_server_components** — alternative server-framework/LiveView-style libs; rejected in favor of plain Wisp+Lustre+HTMX.
- **datastar_gleam / datastar_lustre** — Datastar is an HTMX alternative; we standardized on HTMX.
- **wisp_inertia** — Inertia.js (SPA-style rendering); not our pattern.
- **sketch** — CSS-in-Gleam; we use Tailwind.
- **kielet** — gettext; i18n dropped.
- **migrant** — DB migrations; Parrot schema + `IF NOT EXISTS` (as in `yard`) suffices.
- **miniflux_sdk** — we're building a reader, not consuming Miniflux.
- **mork / jot** — Markdown; entries link out, we don't render article bodies.

---

## 9. Open unknowns to resolve before coding

1. **Auth model**: confirm single-user is acceptable (current data model has users/tokens but the app is single-user in practice). If multi-user is wanted later, design `entries`/`feeds` with `user_id` now.
2. **Job durability**: do we need a `jobs` table (retry on crash) or is in-memory actor scheduling enough? Recommend in-memory for v1; feeds are idempotent to re-fetch.
3. **Live badge**: include the optional 30s unread-count poll, or drop live notification entirely?

---

## 9.5 Spike results (both retired)

### XML parser spike
- **`xmlm`** (pure Gleam v1.0.1) — **rejected**: crashes on `<site xmlns="com-wordpress:feed-additions:1">` (WordPress namespace, millions of blogs incl. GitHub Blog). Error: `unknown namespace prefix ()`.
- **`xmerl` FFI** — **chosen**: parses ALL real test feeds (OPML 77 feeds, Lobsters/HN RSS, xkcd/GitHub/ftl Atom), preserves Unicode (HN smart quotes, em-dashes), decodes entities (`&#39;`→`'`). FFI is ~40 lines Erlang (`xmerl_ffi.erl`) exposing `parse/1`, `node_kind/1`, `node_tag/1`, `node_attrs/1`, `node_children/1`, `node_text/1`. Same engine as Elixir's SweetXml. **Must convert binary→charlist for `xmerl_scan:string/2`.**
- Other packages checked & rejected: `parsed_it` (Unicode-corruption bug), `webls` (generator not parser), `htmgrrrl` (HTML not XML).

### Web stack spike
Built minimal server: Wisp + Mist + Lustre (SSR) + lustre_pipes + hx. **All 5 packages compose.** Verified output:
- `GET /` → full HTML doc via `element.to_document_string`; Unicode intact (`·`); HTMX attrs emitted correctly.
- `POST /toggle/:id` → just the card fragment via `element.to_string`; `hx-trigger: showToast` header via `hx_header.trigger`.

**Integration details to remember for the build:**
- `hx.*` functions (`hx.post(url:)`, `hx.target(hx.Closest(".card"))`, `hx.swap(hx.OuterHTML)`) return a Lustre `attribute.Attribute(msg)`, **not** a `lustre_pipes.element.Scaffold(msg)` fn. So they pipe via `a.add(scaffold, attr)`, not bare `hx.post(...)`. A 1-line `hx_attr` adapter makes them pipe bare if preferred.
- `wisp_mist.handler(handler, secret_key_base)` — requires a `secret_key_base: String` arg (the session/cookie signing key).
- `mist.start` (not `start_http`) on a `mist.new(handler) |> mist.port(n)` builder.
- `wisp.handle_head` callback receives the `Request`; `wisp.serve_static` / `wisp.log_request` callbacks receive nothing — mind the `use` arity.
- `lustre_pipes`: childless elements (`<meta>`, `<link>`, `<script>`) must be finalized with `lp.empty()` before going into a `children([...])` list. Text-only elements use `lp.text_content(s)`. Container elements use `lp.children([...])`.
- The `<main>` element is `h.main()` (not `main_`).
- `gleam_http` must be a direct dep if you import `gleam/http` (transitive import is currently a warning, will become an error).

---

## 10. TL;DR

Rewrite as a **single Gleam BEAM application**: **Wisp + Mist** serving **server-rendered HTML** (Lustre element API, SSR-only — endorsed by Gleam's creator for exactly this use case) with **HTMX** (typed via the `hx` package) for the few interactions that must not full-refresh (read/unread + star toggles, load-more, forms, delete). **SQLite + Parrot + sqlight** for storage (mandated, proven in `yard`). **gleam_otp actors** for the cron scheduler + parallel feed fetchers. Tailwind v4 + DaisyUI theming ported verbatim. Simplify auth to sessions. No SPA, no JSON API, no SSE, no hydration — the server emits HTML fragments and HTMX swaps them. The only genuine technical risk is XML/RSS parsing robustness — mitigate with an `xmerl` FFI fallback if the pure-Gleam parser underperforms on real-world feeds.
