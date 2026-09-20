#!/usr/bin/env bash
set -euo pipefail

mode=${1:-}
state_dir=${2:-}
artifact_dir=${3:-}
script_path=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")

as_root() {
  if [[ $(id -u) -eq 0 ]]; then
    "$@"
  else
    sudo -n "$@"
  fi
}

record() {
  local message=$1
  if [[ -n ${artifact_dir:-} ]]; then
    mkdir -p "$artifact_dir"
    printf '%s\n' "$message" >>"$artifact_dir/host.log"
  fi
}

require_state_path() {
  [[ -n ${RUNNER_TEMP:-} ]] || { record "missing RUNNER_TEMP"; return 1; }
  [[ -n $state_dir ]] || { record "missing state directory"; return 1; }

  local parent base
  parent=$(cd "$(dirname "$state_dir")" && pwd -P)
  base=$(basename "$state_dir")
  [[ $parent == "$(cd "$RUNNER_TEMP" && pwd -P)" ]] || {
    record "state parent is outside RUNNER_TEMP"
    return 1
  }
  [[ $base =~ ^fr19a-sync-eio-[A-Za-z0-9._-]+$ ]] || {
    record "invalid state basename"
    return 1
  }
  [[ ! -L $state_dir ]] || { record "state directory is a symlink"; return 1; }
}

read_state() {
  require_state_path
  [[ -d $state_dir ]] || { record "state directory does not exist"; return 1; }

  image=$(<"$state_dir/image")
  mount_path=$(<"$state_dir/mount")
  map_name=$(<"$state_dir/map")
  loop_device=$(<"$state_dir/loop")
  sectors=$(<"$state_dir/sectors")
  linear_table=$(<"$state_dir/linear-table")

  [[ $image == "$state_dir/image.raw" && ! -L $image ]] || return 1
  [[ $mount_path == "$state_dir/mountpoint" && ! -L $mount_path ]] || return 1
  [[ $map_name =~ ^fr19a_sync_eio_[0-9]+_[0-9]+_[0-9]+$ ]] || return 1
  [[ $loop_device =~ ^/dev/loop[0-9]+$ ]] || return 1
  [[ $sectors =~ ^[1-9][0-9]*$ ]] || return 1

  [[ $linear_table =~ ^0\ $sectors\ linear\ ([0-9]+:[0-9]+|/dev/loop[0-9]+)\ 0$ ]] || return 1
  error_table="0 $sectors error"
}

mapper_exists() {
  as_root dmsetup info "$map_name" >/dev/null 2>&1
}

mapper_suspended() {
  as_root dmsetup info "$map_name" | grep -Eq '^State:[[:space:]]+SUSPENDED'
}

record_mapper() {
  local phase=$1
  {
    printf 'phase=%s\n' "$phase"
    as_root dmsetup table "$map_name"
    as_root dmsetup status "$map_name"
    as_root findmnt -rn -M "$mount_path" -o SOURCE,TARGET,FSTYPE,OPTIONS || true
  } >>"$artifact_dir/mapper-transitions.txt"
}

loop_matches() {
  local output
  output=$(as_root losetup "$loop_device" 2>/dev/null || true)
  [[ $output == *"($image)"* ]]
}

restore_linear() {
  read_state
  mapper_exists || return 0
  loop_matches || { record "refusing restore: loop identity mismatch"; return 1; }

  if ! mapper_suspended; then
    as_root dmsetup suspend --noflush --nolockfs "$map_name"
  fi
  printf '%s\n' "$linear_table" | as_root dmsetup load "$map_name"
  as_root dmsetup resume "$map_name"
  record "restored exact linear table: $linear_table"
  record_mapper restored
}

cleanup_state() {
  require_state_path
  mkdir -p "$artifact_dir"
  : >"$artifact_dir/cleanup.txt"

  if [[ -f $state_dir/map && -f $state_dir/loop && -f $state_dir/sectors &&
        -f $state_dir/image && -f $state_dir/mount && -f $state_dir/linear-table ]]; then
    read_state

    if mapper_exists; then
      restore_linear || true
    fi
  fi

  if [[ -f $state_dir/mount ]]; then
    mount_path=$(<"$state_dir/mount")
    [[ $mount_path == "$state_dir/mountpoint" && ! -L $mount_path ]] || {
      record "refusing cleanup: invalid mount identity"
      return 1
    }
    if as_root findmnt -rn -M "$mount_path" >/dev/null 2>&1; then
      as_root umount "$mount_path"
      printf 'unmounted=%s\n' "$mount_path" >>"$artifact_dir/cleanup.txt"
    fi
  fi

  if [[ -f $state_dir/map ]]; then
    map_name=$(<"$state_dir/map")
    [[ $map_name =~ ^fr19a_sync_eio_[0-9]+_[0-9]+_[0-9]+$ ]] || {
      record "refusing cleanup: invalid mapper identity"
      return 1
    }
    if mapper_exists; then
      as_root dmsetup remove --retry "$map_name"
      printf 'removed_mapper=%s\n' "$map_name" >>"$artifact_dir/cleanup.txt"
    fi
  fi

  if [[ -f $state_dir/loop && -f $state_dir/image ]]; then
    loop_device=$(<"$state_dir/loop")
    image=$(<"$state_dir/image")
    [[ $loop_device =~ ^/dev/loop[0-9]+$ && $image == "$state_dir/image.raw" && ! -L $image ]] || {
      record "refusing cleanup: invalid loop identity"
      return 1
    }
    if loop_matches; then
      as_root losetup -d "$loop_device"
      printf 'detached_loop=%s\n' "$loop_device" >>"$artifact_dir/cleanup.txt"
    fi
  fi

  assert_clean
}

assert_clean() {
  require_state_path
  local failed=0

  if [[ -f $state_dir/mount ]]; then
    mount_path=$(<"$state_dir/mount")
    if as_root findmnt -rn -M "$mount_path" >/dev/null 2>&1; then
      printf 'remaining_mount=%s\n' "$mount_path" >>"$artifact_dir/cleanup.txt"
      failed=1
    fi
  fi

  if [[ -f $state_dir/map ]]; then
    map_name=$(<"$state_dir/map")
    if [[ $map_name =~ ^fr19a_sync_eio_[0-9]+_[0-9]+_[0-9]+$ ]] && mapper_exists; then
      printf 'remaining_mapper=%s\n' "$map_name" >>"$artifact_dir/cleanup.txt"
      failed=1
    fi
  fi

  if [[ -f $state_dir/loop ]]; then
    loop_device=$(<"$state_dir/loop")
    if [[ $loop_device =~ ^/dev/loop[0-9]+$ ]] && as_root losetup "$loop_device" >/dev/null 2>&1; then
      printf 'remaining_loop=%s\n' "$loop_device" >>"$artifact_dir/cleanup.txt"
      failed=1
    fi
  fi

  if [[ $failed -eq 0 ]]; then
    printf 'exact_resources_remaining=false\n' >>"$artifact_dir/cleanup.txt"
  fi

  return "$failed"
}

setup_state() {
  require_state_path
  mkdir -p "$state_dir" "$artifact_dir"
  [[ ! -e $state_dir/image.raw ]] || { record "image already exists"; return 1; }

  local run_id attempt unique image_size
  run_id=${GITHUB_RUN_ID:-0}
  attempt=${GITHUB_RUN_ATTEMPT:-0}
  unique=$$
  image_size=134217728
  map_name="fr19a_sync_eio_${run_id}_${attempt}_${unique}"
  image="$state_dir/image.raw"
  mount_path="$state_dir/mountpoint"
  mkdir -p "$mount_path"
  truncate -s "$image_size" "$image"

  printf '%s\n' "$image" >"$state_dir/image"
  printf '%s\n' "$mount_path" >"$state_dir/mount"
  printf '%s\n' "$map_name" >"$state_dir/map"

  loop_device=$(as_root losetup --find --show --sizelimit "$image_size" "$image")
  [[ $loop_device =~ ^/dev/loop[0-9]+$ ]] || return 1
  printf '%s\n' "$loop_device" >"$state_dir/loop"

  sectors=$(as_root blockdev --getsz "$loop_device")
  [[ $sectors =~ ^[1-9][0-9]*$ ]] || return 1
  printf '%s\n' "$sectors" >"$state_dir/sectors"

  linear_table="0 $sectors linear $loop_device 0"
  printf '%s\n' "$linear_table" | as_root dmsetup create "$map_name"
  linear_table=$(as_root dmsetup table "$map_name")
  [[ $linear_table =~ ^0\ $sectors\ linear\ ([0-9]+:[0-9]+|/dev/loop[0-9]+)\ 0$ ]] || return 1
  printf '%s\n' "$linear_table" >"$state_dir/linear-table"
  as_root mkfs.ext4 -q -F "/dev/mapper/$map_name"
  as_root mount -o nodev,nosuid,noexec "/dev/mapper/$map_name" "$mount_path"
  as_root chown "$(id -u):$(id -g)" "$mount_path"

  {
    printf 'image=%s\nloop=%s\nmap=%s\nsectors=%s\nmount=%s\n' \
      "$image" "$loop_device" "$map_name" "$sectors" "$mount_path"
    as_root dmsetup table "$map_name"
    as_root dmsetup status "$map_name"
    as_root findmnt -rn -M "$mount_path" -o SOURCE,TARGET,FSTYPE,OPTIONS
  } >"$artifact_dir/setup.txt"
}

capability() {
  require_state_path
  mkdir -p "$artifact_dir"
  : >"$artifact_dir/capability.txt"
  local supported=true elixir_path erl_path elixir_dir erl_dir runtime_path

  for command in sudo losetup dmsetup blockdev mkfs.ext4 mount umount findmnt strace \
    elixir erl timeout; do
    if command -v "$command" >/dev/null 2>&1; then
      printf '%s=%s\n' "$command" "$(command -v "$command")" >>"$artifact_dir/capability.txt"
    else
      printf '%s=missing\n' "$command" >>"$artifact_dir/capability.txt"
      supported=false
    fi
  done

  if sudo -n true 2>/dev/null; then
    printf 'sudo_noninteractive=true\n' >>"$artifact_dir/capability.txt"
  else
    printf 'sudo_noninteractive=false\n' >>"$artifact_dir/capability.txt"
    supported=false
  fi

  if [[ $supported == true ]]; then
    sudo -n modprobe loop 2>>"$artifact_dir/capability.txt" || true
    sudo -n modprobe dm_mod 2>>"$artifact_dir/capability.txt" || true

    if [[ -c /dev/mapper/control ]]; then
      printf 'mapper_control=character-device\n' >>"$artifact_dir/capability.txt"
    else
      printf 'mapper_control=unavailable\n' >>"$artifact_dir/capability.txt"
      supported=false
    fi

    if sudo -n dmsetup targets >"$artifact_dir/dm-targets.txt" 2>&1 &&
      grep -Eq '^error[[:space:]]' "$artifact_dir/dm-targets.txt"; then
      printf 'dm_error_target=true\n' >>"$artifact_dir/capability.txt"
    else
      printf 'dm_error_target=false\n' >>"$artifact_dir/capability.txt"
      supported=false
    fi
  fi

  if [[ $supported != true ]]; then
    printf 'supported=false\n' >>"$artifact_dir/capability.txt"
    return 78
  fi

  elixir_path=$(command -v elixir)
  erl_path=$(command -v erl)
  [[ $elixir_path == /* && -x $elixir_path && $erl_path == /* && -x $erl_path ]] || {
    printf 'beam_runtime_path=invalid\nsupported=false\n' >>"$artifact_dir/capability.txt"
    return 78
  }
  elixir_dir=$(cd "$(dirname "$elixir_path")" && pwd -P)
  erl_dir=$(cd "$(dirname "$erl_path")" && pwd -P)
  [[ $elixir_dir != *:* && $erl_dir != *:* && $elixir_dir != *$'\n'* && $erl_dir != *$'\n'* ]] || {
    printf 'beam_runtime_path=invalid\nsupported=false\n' >>"$artifact_dir/capability.txt"
    return 78
  }
  runtime_path="$elixir_dir:$erl_dir:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  printf 'beam_runtime_path=%s\n' "$runtime_path" >>"$artifact_dir/capability.txt"

  trap 'cleanup_state || true' EXIT
  setup_state
  local raw_file raw_trace
  raw_file="$state_dir/mountpoint/raw-sync.bin"
  raw_trace="$artifact_dir/raw-strace"

  as_root /usr/bin/env \
    PATH="$runtime_path" \
    RUNNER_TEMP="$RUNNER_TEMP" \
    GITHUB_RUN_ID="${GITHUB_RUN_ID:-0}" \
    GITHUB_RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-0}" \
    timeout 45s strace -ff -yy \
    -e trace=fsync,fdatasync,pwrite64,write,openat,close \
    -o "$raw_trace" env FR19A_ARTIFACT_DIR="$artifact_dir" \
    "$elixir_path" "$(dirname "$script_path")/fr19a_raw_sync_eio.exs" \
    "$raw_file" "$script_path" "$state_dir" "$artifact_dir" \
    >"$artifact_dir/raw-probe.txt" 2>&1

  if grep -Fh "$raw_file" "$raw_trace"* | grep -Eq '(fsync|fdatasync)\(.*\) = -1 EIO'; then
    grep -Fh "$raw_file" "$raw_trace"* | grep -E '(fsync|fdatasync)\(.*\) = -1 EIO' \
      >"$artifact_dir/raw-sync-eio.txt"
    printf 'raw_sync_eio=true\nsupported=true\n' >>"$artifact_dir/capability.txt"
  else
    printf 'raw_sync_eio=false\nsupported=false\n' >>"$artifact_dir/capability.txt"
    return 78
  fi
}

case "$mode" in
  capability)
    capability
    ;;
  setup)
    setup_state
    ;;
  suspend)
    read_state
    loop_matches || { record "refusing suspend: loop identity mismatch"; exit 1; }
    mapper_exists || { record "refusing suspend: mapper missing"; exit 1; }
    [[ $(as_root dmsetup table "$map_name") == "$linear_table" ]] || {
      record "refusing suspend: unexpected mapper table"
      exit 1
    }
    as_root dmsetup suspend "$map_name"
    record "suspended exact mapper $map_name"
    record_mapper suspended
    ;;
  error-resume)
    read_state
    loop_matches || { record "refusing error load: loop identity mismatch"; exit 1; }
    mapper_exists || { record "refusing error load: mapper missing"; exit 1; }
    printf '%s\n' "$error_table" | as_root dmsetup load "$map_name"
    if ! as_root dmsetup resume "$map_name"; then
      record "error-table resume failed; restoring exact linear table"
      restore_linear
      exit 1
    fi
    [[ $(as_root dmsetup table "$map_name") == "$error_table" ]]
    record "loaded exact error table: $error_table"
    record_mapper error
    ;;
  restore)
    restore_linear
    ;;
  cleanup)
    cleanup_state
    ;;
  assert-clean)
    assert_clean
    ;;
  *)
    printf 'usage: %s capability|setup|suspend|error-resume|restore|cleanup|assert-clean STATE ARTIFACTS\n' \
      "$0" >&2
    exit 64
    ;;
esac
