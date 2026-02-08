# =============================================================================
# Stage 1: Build the Rust bughouse engine
# =============================================================================
FROM rust:1.85-slim-bookworm AS rust-builder

RUN apt-get update -y && apt-get install -y git pkg-config && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN git clone --depth 1 https://github.com/vcsawant/bughouse-engine.git

WORKDIR /build/bughouse-engine
RUN cargo build --release

# =============================================================================
# Stage 2: Build the Elixir/Phoenix release
# =============================================================================
FROM hexpm/elixir:1.18.3-erlang-26.2.5.8-debian-bookworm-20260202-slim AS elixir-builder

RUN apt-get update -y && \
    apt-get install -y build-essential git curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build environment
ENV MIX_ENV="prod"

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config files
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Copy application source
COPY priv priv
COPY lib lib
COPY assets assets

# Compile first — generates phoenix-colocated hooks needed by esbuild
RUN mix compile

# Build assets (tailwind + esbuild bundle colocated hooks from _build)
RUN mix assets.deploy

# Copy runtime config
COPY config/runtime.exs config/

# Build the release
COPY rel rel
RUN mix release

# =============================================================================
# Stage 3: Production runner
# =============================================================================
FROM debian:bookworm-20260202-slim AS runner

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR /app

# Create a non-root user
RUN useradd --create-home app

# Create directories for engine logs
RUN mkdir -p /var/log/bughouse/engine && \
    chown -R app:app /var/log/bughouse

# Copy the Elixir release from builder
COPY --from=elixir-builder --chown=app:app /app/_build/prod/rel/bughouse ./

# Copy the Rust engine binary from builder
COPY --from=rust-builder --chown=app:app /build/bughouse-engine/target/release/bughouse_engine /app/bin/bughouse_engine

USER app

CMD ["/app/bin/server"]
