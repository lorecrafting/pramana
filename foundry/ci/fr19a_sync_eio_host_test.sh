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

artifact_dir=$(mktemp -d)
trap 'rm -rf "$artifact_dir"' EXIT
expected_loop_name=/dev/loop7
expected_back_file=/runner/_temp/fr19a/image.raw
expected_back_ino=12345
expected_back_maj_min=0:42
expected_loop_maj_min=7:7
queried_loop_name=$expected_loop_name
queried_back_file=$expected_back_file
queried_back_ino=$expected_back_ino
queried_back_maj_min=$expected_back_maj_min
queried_loop_maj_min=$expected_loop_maj_min
queried_offset=0
queried_sizelimit=134217728
validate_loop_identity

queried_back_file=
queried_back_ino=
queried_back_maj_min=
queried_offset=
queried_sizelimit=
if classify_loop_fields; then
  printf 'accepted unbound loop as owned binding\n' >&2
  exit 1
else
  loop_state=$?
  [[ $loop_state -eq 4 ]] || { printf 'unbound exact loop was not classified as unbound\n' >&2; exit 1; }
fi

queried_loop_maj_min=7:8
if classify_loop_fields; then
  printf 'accepted foreign unbound loop identity\n' >&2
  exit 1
else
  loop_state=$?
  [[ $loop_state -eq 3 ]] || { printf 'foreign loop was not classified as foreign\n' >&2; exit 1; }
fi

queried_loop_maj_min=$expected_loop_maj_min
queried_back_file=$expected_back_file
if classify_loop_fields; then
  printf 'accepted partially-null binding\n' >&2
  exit 1
else
  loop_state=$?
  [[ $loop_state -eq 2 ]] || { printf 'partial binding was not classified as unavailable\n' >&2; exit 1; }
fi

queried_back_ino=$expected_back_ino
queried_back_maj_min=$expected_back_maj_min
queried_offset=0
queried_sizelimit=134217728
classify_loop_fields

queried_back_ino=99999
if validate_loop_identity; then
  printf 'accepted mismatched backing inode\n' >&2
  exit 1
else
  identity_status=$?
  [[ $identity_status -eq 3 ]] || { printf 'identity mismatch was not classified as mismatch\n' >&2; exit 1; }
fi

query_loop_identity() { return 1; }
if verify_loop_identity regression-query-absent; then
  printf 'accepted absent loop as owned\n' >&2
  exit 1
else
  query_status=$?
  [[ $query_status -eq 1 ]] || { printf 'zero-row query was not classified as absent\n' >&2; exit 1; }
fi

query_loop_identity() { return 2; }
if verify_loop_identity regression-query-error; then
  printf 'accepted unavailable loop query\n' >&2
  exit 1
else
  query_status=$?
  [[ $query_status -eq 2 ]] || { printf 'query error was not classified as unavailable\n' >&2; exit 1; }
fi

printf 'semantic error-table and loop-identity validation: pass\n'
