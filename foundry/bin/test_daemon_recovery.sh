#!/usr/bin/env bash
# Isolated FR-04 ownership/recovery fixture wrapper. No daemon or Herdr is started.

set -euo pipefail

cd "$(dirname "$0")/.."

ELIXIR_BIN="/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin"
ERLANG_BIN="/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin"
FIXTURE_PARENT="$(mktemp -d /tmp/pramana-fr04-recovery.XXXXXX)"

cleanup() {
  rm -rf -- "$FIXTURE_PARENT"
}
trap cleanup EXIT

export PATH="$ELIXIR_BIN:$ERLANG_BIN:/usr/bin:/bin"
export TMPDIR="$FIXTURE_PARENT/tmp"
export MIX_ENV=test
mkdir -p "$TMPDIR"
unset HERDR_ENV COORDINATOR_TICK PRAMANA_RUNTIME_ROOT PRAMANA_RUNTIME_ROOT_FRESH

mix test test/pramana_foundry/daemon_recovery_test.exs --seed 40423
