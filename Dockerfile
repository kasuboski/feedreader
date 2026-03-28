ARG ELIXIR_VERSION=1.18.3
ARG OTP_VERSION=27.3
ARG ALPINE_VERSION=3.21.3
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-${ALPINE_VERSION}"
ARG RUNNER_IMAGE="alpine:${ALPINE_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

ENV MIX_ENV="prod"

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

RUN mix assets.deploy

RUN mix compile

COPY config/runtime.exs config/

RUN mix release

FROM ${RUNNER_IMAGE} AS runner

RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app

RUN addgroup -g 1000 -S app && \
    adduser -u 1000 -S app -G app

RUN chown app:app /app

USER app

COPY --from=builder --chown=app:app /app/_build/${MIX_ENV}/rel/feedreader ./

ENV MIX_ENV="prod"
ENV PHX_SERVER="true"

EXPOSE 4000

CMD ["/app/bin/server"]
