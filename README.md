# feedreader

A Gleam/Erlang RSS and Atom feed reader. Tracks feeds, fetches entries on a
schedule, and serves a server-rendered HTML UI with HTMX for partial updates.

## Features

- Subscribe to RSS/Atom feeds (manual add or OPML import)
- Unread, starred, and history views
- Background scheduler fetches new entries every 3 minutes
- SQLite storage via [sqlight](https://hexdocs.pm/sqlight/) + [Parrot](https://hexdocs.pm/parrot/) codegen
- Server-rendered HTML with [Lustre](https://hexdocs.pm/lustre/) + [lustre_pipes](https://hexdocs.pm/lustre_pipes/) + [HTMX](https://htmx.org/)
- No authentication (handle at the reverse proxy / network layer)

## Quick start

```sh
mise install          # install gleam, erlang, rebar3
gleam deps download
gleam run             # serves on http://localhost:3000
```

The database defaults to `feedreader.db` in the working directory. Override
with the `DATABASE_PATH` environment variable.

## Development

```sh
gleam check           # type check
gleam test            # run the test suite
gleam format          # format code
mise run pre-commit   # format + check + lint + test
mise run gen          # regenerate Parrot SQL codegen from schema + queries
mise run assets       # install + build TailwindCSS
```

## Deploy with Docker

The CI builds a multi-arch image (amd64 + arm64) and pushes it to GHCR on every
push to `main` and on version tags (`v1.0.0`).

```sh
docker pull ghcr.io/kasuboski/feedreader:main
docker run -d \
  -p 3000:3000 \
  -v feedreader-data:/data \
  -e DATABASE_PATH=/data/feedreader.db \
  ghcr.io/kasuboski/feedreader:main
```

Or with docker-compose (see `docker-compose.yaml`):

```sh
docker compose up -d
```

The SQLite database persists in a Docker volume mounted at `/data`. To migrate
from the old Elixir/Phoenix deployment, copy the existing `feedreader.db` into
the volume — the schema is compatible.

## Architecture

| Layer | Technology |
|---|---|
| Language | Gleam → Erlang/BEAM |
| Web server | [Wisp](https://hexdocs.pm/wisp/) + [Mist](https://hexdocs.pm/mist/) |
| HTML rendering | [Lustre](https://hexdocs.pm/lustre/) SSR + [lustre_pipes](https://hexdocs.pm/lustre_pipes/) |
| Interactivity | [HTMX](https://htmx.org/) via [hx](https://hexdocs.pm/hx/) |
| Database | SQLite via [sqlight](https://hexdocs.pm/sqlight/) + [Parrot](https://hexdocs.pm/parrot/) |
| Background workers | Gleam/OTP actors (scheduler + fetcher) under a supervisor |

See `SCOUTING_REPORT.md` for the full Elixir → Gleam migration analysis.
