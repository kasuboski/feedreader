# FeedReader — Gleam/Erlang feed reader
# Multi-stage Dockerfile: build with rebar3+gleam, ship minimal runtime

FROM ghcr.io/gleam-lang/gleam:v1.16.0-erlang-alpine AS builder

WORKDIR /app

# Install build tools needed for esqlite NIF (C compiler + SQLite dev headers)
RUN apk add --no-cache build-base sqlite-dev

# Copy manifest and fetch deps first (layer caching)
COPY gleam.toml manifest.toml ./
RUN gleam deps download

# Copy source
COPY src/ src/
COPY priv/ priv/

# Build TailwindCSS (glailglind runs the tailwind CLI with config from gleam.toml)
RUN gleam run -m tailwind/install && gleam run -m tailwind/run

# Build
RUN gleam export erlang-shipment

# ─── Runtime stage ──────────────────────────────────────────────
# Must match the OTP version from the builder stage (gleam:v1.16.0-erlang-alpine = OTP 28)
FROM erlang:28-alpine

WORKDIR /app

# Install SQLite runtime library (esqlite NIF depends on libsqlite3)
RUN apk add --no-cache sqlite-libs

COPY --from=builder /app/build/erlang-shipment ./

# Copy priv/ to the CWD so runtime code can find schema.sql and static assets
# (gleam export erlang-shipment nests priv under feedreader/priv/, but our
# code reads from priv/ relative to CWD).
COPY --from=builder /app/priv ./priv

ENV DATABASE_PATH=/data/feedreader.db

VOLUME ["/data"]

EXPOSE 3000

CMD ["./entrypoint.sh", "run"]
