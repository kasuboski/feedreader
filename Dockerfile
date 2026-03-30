ARG BUILDER_IMAGE="hexpm/elixir:1.18-erlang-27.0-ubuntu-noble-20260217"
ARG RUNNER_IMAGE="ubuntu:noble-20260217"
ARG MIX_ENV=prod

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

ARG MIX_ENV
ENV MIX_ENV=${MIX_ENV}

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

RUN apt-get update -y && apt-get install -y libstdc++-12-dev openssl ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN groupadd -g 1001 app && \
    useradd -u 1001 -g app -m app

RUN chown app:app /app

USER app

ARG MIX_ENV
COPY --from=builder --chown=app:app /app/_build/${MIX_ENV}/rel/feedreader ./

ENV MIX_ENV=${MIX_ENV}
ENV PHX_SERVER="true"
ENV DATABASE_PATH="/app/data/feedreader.db"
ENV SECRET_KEY_BASE=""
ENV LIVE_VIEW_SIGNING_SALT=""
ENV TOKEN_SIGNING_SECRET=""
ENV PHX_HOST="localhost"
ENV POOL_SIZE="10"
ENV PORT="4000"

EXPOSE 4000

CMD ["/app/bin/feedreader", "start"]
