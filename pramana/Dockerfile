# Pramāṇa — build from the repository root with: docker build -f pramana/Dockerfile pramana
#
# Two stages: a builder with the full Elixir/Rust toolchain, and a runtime image holding a
# release and nothing else. Omitting Mix removes CLI tasks, not database write
# authority; the deployment still needs an appropriately restricted database role.
#
# The corpus is NOT in this image and never will be. We publish the pipeline, not the
# corpus; the database is external and is built by `mix pramana.public.bake`. See
# docs/DEPLOY.md, and note that a node started with PRAMANA_PUBLIC=1 audits the database it
# actually connects to and refuses to serve if it holds anything it may not publish.

ARG ELIXIR_VERSION=1.20.3
ARG OTP_VERSION=29.0.5
ARG DEBIAN_VERSION=bookworm-20250630-slim
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# git for deps fetched from GitHub (heroicons); curl and build-essential for the Rust
# toolchain, which the CJK segmentation NIF needs compiled for the target architecture.
RUN apt-get update -y && \
    apt-get install -y build-essential git curl ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Retains the current stable Rust selection. The BEAM pins are unchanged; a Rust
# pin is a separate dependency-policy decision.
ENV RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo PATH=/opt/cargo/bin:$PATH
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal

WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force
ENV MIX_ENV=prod

# Deps before source, so a code change does not refetch and rebuild the world.
COPY mix.exs mix.lock ./
COPY apps/pramana/mix.exs apps/pramana/
COPY apps/pramana_web/mix.exs apps/pramana_web/
COPY apps/pramana_native/mix.exs apps/pramana_native/
COPY config config
RUN mix deps.get --only prod && mix deps.compile

COPY apps apps
RUN mix compile

# Digested assets, so the release serves them with cache headers and a content hash.
RUN mix assets.deploy

COPY rel rel
RUN mix release

FROM ${RUNNER_IMAGE}

# libstdc++ for the Rust NIF, locales because the corpus is CJK, Tibetan and Pali and a C
# locale mangles all three.
RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8
WORKDIR /app
RUN chown nobody /app

ENV MIX_ENV=prod
COPY --from=builder --chown=nobody:root /app/_build/prod/rel/pramana ./

USER nobody
CMD ["/app/bin/server"]
