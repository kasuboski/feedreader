# syntax=docker/dockerfile:1.4
FROM rust:slim-buster as build
RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
  apt-get update && apt-get --no-install-recommends install -y libssl-dev pkg-config

RUN USER=root cargo new --bin feedreader
WORKDIR /feedreader

COPY Cargo.* ./

RUN cargo build --release && rm src/*.rs && rm target/release/deps/feedreader*

COPY . .
RUN cargo build --release

FROM debian:buster-slim

ENV USER=app
ENV UID=1000

RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid "${UID}" \
    "${USER}"

WORKDIR /feedreader
COPY --link --from=build --chown=1000:0 /feedreader/target/release/feedreader feedreader

EXPOSE 3030

CMD [ "./feedreader" ]
