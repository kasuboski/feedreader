# FeedReader — Gleam/Erlang feed reader
# Multi-stage Dockerfile: build with gleam+rebar3, ship minimal runtime.
# Uses Debian (not Alpine) because the Tailwind v4 standalone CLI is
# glibc-linked and doesn't work reliably under musl.

FROM ghcr.io/gleam-lang/gleam:v1.16.0-erlang AS builder

WORKDIR /app

# Install build tools needed for esqlite NIF (C compiler + SQLite dev headers)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential sqlite3 libsqlite3-dev \
  && rm -rf /var/lib/apt/lists/*

# Copy manifest and fetch deps first (layer caching)
COPY gleam.toml manifest.toml ./
RUN gleam deps download

# Copy source
COPY src/ src/
COPY priv/ priv/

# Build TailwindCSS (glailglind runs the tailwind CLI with config from gleam.toml)
RUN gleam run -m tailwind/install && gleam run -m tailwind/run

# Build Erlang shipment
RUN gleam export erlang-shipment

# ─── Runtime stage ──────────────────────────────────────────────
# Must match the OTP version from the builder stage (gleam:v1.16.0-erlang = OTP 28)
FROM erlang:28-slim

WORKDIR /app

# Install runtime deps:
# - libsqlite3-0: esqlite NIF depends on libsqlite3
# - ca-certificates: httpc needs CA certs to verify HTTPS feeds
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsqlite3-0 ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/build/erlang-shipment ./

# Copy priv/ to the CWD so runtime code can find schema.sql and static assets
# (gleam export erlang-shipment nests priv under feedreader/priv/, but our
# code reads from priv/ relative to CWD).
COPY --from=builder /app/priv ./priv

ENV DATABASE_PATH=/data/feedreader.db

VOLUME ["/data"]

EXPOSE 3000

CMD ["./entrypoint.sh", "run"]
