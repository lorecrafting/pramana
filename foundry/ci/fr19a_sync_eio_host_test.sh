#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
FR19A_SYNC_EIO_SOURCE_ONLY=1 source "$script_dir/fr19a_sync_eio_host.sh"

validate_error_table '0 262144 error ' 262144
validate_error_table $'\t0\t262144\terror\t' 262144

if validate_error_table $'0 262144 error\n0 262144 error' 262144; then
  printf 'accepted extra table row\n' >&2
  exit 1
fi

if validate_error_table '0 131072 error ' 262144; then
  printf 'accepted wrong extent\n' >&2
  exit 1
fi

if validate_error_table '0 262144 linear 7:0 0' 262144; then
  printf 'accepted wrong target\n' >&2
  exit 1
fi

if validate_error_table '0 262144 error unexpected' 262144; then
  printf 'accepted error target parameters\n' >&2
  exit 1
fi

printf 'semantic error-table validation: pass\n'
