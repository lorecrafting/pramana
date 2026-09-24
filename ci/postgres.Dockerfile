# Cached CI fixture only. The application test suite still creates and migrates its
# own disposable databases; this image merely avoids compiling pg_bigm on every run.
#
# Keep the base aligned with .github/workflows/ci.yml's former service image. pg_bigm is
# pinned to the exact commit behind tag v1.2-20250903 rather than downloaded from a moving
# tag during each test run.
ARG PGVECTOR_IMAGE=pgvector/pgvector:pg18@sha256:2ba9ca5f2e7daa0f0e7723cba1ee9167bab54efd3640516a44ac1a928dd67e7a

FROM ${PGVECTOR_IMAGE} AS builder
ARG PG_BIGM_COMMIT=735dceba0ecdd8ac1aaaaa207226a7102b6bbd71

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
      build-essential postgresql-server-dev-18 wget ca-certificates && \
    wget -q -O /tmp/pg_bigm.tar.gz \
      "https://github.com/pgbigm/pg_bigm/archive/${PG_BIGM_COMMIT}.tar.gz" && \
    mkdir /tmp/pg_bigm && \
    tar zxf /tmp/pg_bigm.tar.gz --strip-components=1 -C /tmp/pg_bigm && \
    make -C /tmp/pg_bigm USE_PGXS=1 with_llvm=no && \
    make -C /tmp/pg_bigm USE_PGXS=1 with_llvm=no install

FROM ${PGVECTOR_IMAGE}
COPY --from=builder /usr/lib/postgresql/18/lib/pg_bigm.so /usr/lib/postgresql/18/lib/pg_bigm.so
COPY --from=builder /usr/share/postgresql/18/extension/pg_bigm* /usr/share/postgresql/18/extension/
