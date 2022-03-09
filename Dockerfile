FROM rust:slim-buster as build
RUN apt-get update && apt-get install -y libssl-dev pkg-config

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
COPY --from=build --chown=1000:0 /feedreader/target/release/feedreader feedreader

EXPOSE 3030

CMD [ "./feedreader" ]