FROM rust:slim-buster as build
RUN apt-get update && apt-get install -y libssl-dev pkg-config

RUN USER=root cargo new --bin feedreader
WORKDIR /feedreader

COPY Cargo.* ./

RUN cargo build --release && rm src/*.rs && rm target/release/deps/feedreader*

COPY . .
RUN cargo build --release

FROM debian:buster-slim
WORKDIR /feedreader
COPY --from=build /feedreader/target/release/feedreader feedreader

CMD [ "./feedreader" ]