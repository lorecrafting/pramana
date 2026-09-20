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
  expected_loop_name=$(<"$state_dir/loop-name")
  expected_back_file=$(<"$state_dir/back-file")
  expected_back_ino=$(<"$state_dir/back-ino")
  expected_back_maj_min=$(<"$state_dir/back-maj-min")
  expected_loop_maj_min=$(<"$state_dir/loop-maj-min")

  [[ $image == "$state_dir/image.raw" && ! -L $image ]] || return 1
  [[ $mount_path == "$state_dir/mountpoint" && ! -L $mount_path ]] || return 1
  [[ $map_name =~ ^fr19a_sync_eio_[0-9]+_[0-9]+_[0-9]+$ ]] || return 1
  [[ $loop_device =~ ^/dev/loop[0-9]+$ ]] || return 1
  [[ $sectors =~ ^[1-9][0-9]*$ ]] || return 1

  [[ $linear_table =~ ^0\ $sectors\ linear\ ([0-9]+:[0-9]+|/dev/loop[0-9]+)\ 0$ ]] || return 1
  [[ $expected_loop_name == "$loop_device" ]] || return 1
  [[ $expected_back_file == "$image" && $expected_back_ino =~ ^[1-9][0-9]*$ ]] || return 1
  [[ $expected_back_maj_min =~ ^[0-9]+:[0-9]+$ ]] || return 1
  [[ $expected_loop_maj_min =~ ^[0-9]+:[0-9]+$ ]] || return 1
  [[ $linear_table == "0 $sectors linear $expected_loop_maj_min 0" ]] || return 1
  error_table="0 $sectors error"
}

query_mapper() {
  local phase=$1
  local stdout_file="$artifact_dir/mapper-query-$phase.stdout"
  local stderr_file="$artifact_dir/mapper-query-$phase.stderr"
  local status

  if as_root dmsetup info "$map_name" >"$stdout_file" 2>"$stderr_file"; then
    status=0
  else
    status=$?
  fi
  printf 'phase=%s status=%s map=%s\n' "$phase" "$status" "$map_name" \
    >>"$artifact_dir/mapper-query-status.txt"

  if [[ $status -eq 0 ]]; then
    return 0
  fi
  if grep -Eqi 'does not exist|not found|no such device' "$stdout_file" "$stderr_file"; then
    return 1
  fi
  return 2
}

mapper_suspended() {
  as_root dmsetup info "$map_name" | grep -Eq '^State:[[:space:]]+SUSPENDED'
}

validate_error_table() {
  local table=$1
  local expected_sectors=$2

  printf '%s\n' "$table" | awk -v expected_sectors="$expected_sectors" '
    NF == 0 { next }
    {
      rows += 1
      if (NF != 3 || $1 != "0" || $2 != expected_sectors || $3 != "error") {
        valid = 0
      } else if (rows == 1) {
        valid = 1
      }
    }
    END { exit !(rows == 1 && valid == 1) }
  '
}

record_phase() {
  local phase=$1
  local status=$2
  printf 'epoch_ns=%s phase=%s status=%s\n' "$(date +%s%N)" "$phase" "$status" \
    >>"$artifact_dir/error-table-phase.txt"
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

classify_loop_fields() {
  [[ -n $queried_loop_name && -n $queried_loop_maj_min ]] || return 2
  if [[ -z $queried_back_file && -z $queried_back_ino && -z $queried_back_maj_min &&
        -z $queried_offset && -z $queried_sizelimit ]]; then
    [[ $queried_loop_name == "$expected_loop_name" ]] || return 3
    [[ -z ${expected_loop_maj_min:-} || $queried_loop_maj_min == "$expected_loop_maj_min" ]] || return 3
    return 4
  fi
  [[ -n $queried_back_file && -n $queried_back_ino && -n $queried_back_maj_min &&
    -n $queried_offset && -n $queried_sizelimit ]] || return 2
}

query_loop_identity() {
  local phase=$1
  local stdout_file="$artifact_dir/loop-query-$phase.json"
  local stderr_file="$artifact_dir/loop-query-$phase.stderr"
  local status

  if as_root losetup --json --list \
    --output NAME,BACK-FILE,BACK-INO,BACK-MAJ:MIN,MAJ:MIN,OFFSET,SIZELIMIT \
    "$loop_device" >"$stdout_file" 2>"$stderr_file"; then
    status=0
  else
    status=$?
  fi
  printf 'phase=%s status=%s expected_loop=%s expected_back_file=%s\n' \
    "$phase" "$status" "$loop_device" "$image" >>"$artifact_dir/loop-query-status.txt"
  [[ $status -eq 0 ]] || return 2
  local count
  count=$(jq -er '.loopdevices | length' "$stdout_file") || return 2
  [[ $count -ne 0 ]] || return 1
  [[ $count -eq 1 ]] || return 2

  queried_loop_name=$(jq -r '.loopdevices[0].name // empty' "$stdout_file")
  queried_back_file=$(jq -r '.loopdevices[0]["back-file"] // empty' "$stdout_file")
  queried_back_ino=$(jq -r '.loopdevices[0]["back-ino"] // empty' "$stdout_file")
  queried_back_maj_min=$(jq -r '.loopdevices[0]["back-maj:min"] // empty' "$stdout_file")
  queried_loop_maj_min=$(jq -r '.loopdevices[0]["maj:min"] // empty' "$stdout_file")
  queried_offset=$(jq -r '.loopdevices[0].offset // empty' "$stdout_file")
  queried_sizelimit=$(jq -r '.loopdevices[0].sizelimit // empty' "$stdout_file")

  classify_loop_fields || return $?
  queried_back_file=$(realpath -e "$queried_back_file") || return 2
  return 0
}

validate_loop_identity() {
  [[ $queried_loop_name == "$expected_loop_name" ]] || return 3
  [[ $queried_back_file == "$expected_back_file" ]] || return 3
  [[ $queried_back_ino == "$expected_back_ino" ]] || return 3
  [[ $queried_back_maj_min == "$expected_back_maj_min" ]] || return 3
  [[ $queried_loop_maj_min == "$expected_loop_maj_min" ]] || return 3
  [[ $queried_offset == 0 && $queried_sizelimit == 134217728 ]] || return 3
}

verify_loop_identity() {
  local phase=$1
  local query_status
  if query_loop_identity "$phase"; then
    query_status=0
  else
    query_status=$?
    return "$query_status"
  fi

  {
    printf 'expected_loop=%s\nexpected_back_file=%s\nexpected_back_ino=%s\n' \
      "$expected_loop_name" "$expected_back_file" "$expected_back_ino"
    printf 'expected_back_maj_min=%s\nexpected_loop_maj_min=%s\n' \
      "$expected_back_maj_min" "$expected_loop_maj_min"
    printf 'queried_loop=%s\nqueried_back_file=%s\nqueried_back_ino=%s\n' \
      "$queried_loop_name" "$queried_back_file" "$queried_back_ino"
    printf 'queried_back_maj_min=%s\nqueried_loop_maj_min=%s\n' \
      "$queried_back_maj_min" "$queried_loop_maj_min"
    printf 'queried_offset=%s\nqueried_sizelimit=%s\n' "$queried_offset" "$queried_sizelimit"
  } >>"$artifact_dir/loop-query-status.txt"

  validate_loop_identity
}

restore_linear() {
  read_state
  if query_mapper restore-check; then
    mapper_state=0
  else
    mapper_state=$?
    [[ $mapper_state -eq 1 ]] && return 0
    record "refusing restore: mapper identity unavailable"
    return 1
  fi
  if verify_loop_identity restore; then
    loop_state=0
  else
    loop_state=$?
    if [[ $loop_state -eq 2 ]]; then
      record "refusing restore: loop identity unavailable"
    elif [[ $loop_state -eq 1 ]]; then
      record "refusing restore: recorded loop is absent"
    else
      record "refusing restore: loop identity mismatch"
    fi
    return 1
  fi

  current_table=$(as_root dmsetup table "$map_name") || return 1
  if [[ $current_table == "$linear_table" ]] && ! mapper_suspended; then
    record "exact linear table is already active: $linear_table"
    record_mapper restored
    return 0
  fi

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
  touch "$artifact_dir/cleanup.txt"
  printf 'cleanup_attempt_epoch=%s\n' "$(date +%s)" >>"$artifact_dir/cleanup.txt"

  if [[ -f $state_dir/map && -f $state_dir/loop && -f $state_dir/sectors &&
        -f $state_dir/image && -f $state_dir/mount && -f $state_dir/linear-table ]]; then
    read_state

    if query_mapper cleanup-restore-check; then
      restore_linear
    else
      mapper_state=$?
      [[ $mapper_state -eq 1 ]] || {
        record "refusing cleanup: mapper identity unavailable"
        return 1
      }
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
    if query_mapper cleanup-remove-check; then
      as_root dmsetup remove --retry "$map_name"
      printf 'removed_mapper=%s\n' "$map_name" >>"$artifact_dir/cleanup.txt"
    else
      mapper_state=$?
      [[ $mapper_state -eq 1 ]] || return 1
    fi
  fi

  if [[ -f $state_dir/loop && -f $state_dir/image ]]; then
    loop_device=$(<"$state_dir/loop")
    image=$(<"$state_dir/image")
    [[ $loop_device =~ ^/dev/loop[0-9]+$ && $image == "$state_dir/image.raw" && ! -L $image ]] || {
      record "refusing cleanup: invalid loop identity"
      return 1
    }
    read_state
    if verify_loop_identity cleanup-detach; then
      as_root losetup -d "$loop_device"
      printf 'detached_loop=%s\n' "$loop_device" >>"$artifact_dir/cleanup.txt"
    else
      loop_state=$?
      [[ $loop_state -eq 1 || $loop_state -eq 4 ]] || {
        record "refusing cleanup: loop identity unavailable or mismatched ($loop_state)"
        return 1
      }
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
    if [[ $map_name =~ ^fr19a_sync_eio_[0-9]+_[0-9]+_[0-9]+$ ]]; then
      if query_mapper assert-clean; then
        printf 'remaining_mapper=%s\n' "$map_name" >>"$artifact_dir/cleanup.txt"
        failed=1
      else
        mapper_state=$?
        if [[ $mapper_state -ne 1 ]]; then
          printf 'mapper_identity=unavailable\n' >>"$artifact_dir/cleanup.txt"
          failed=1
        fi
      fi
    fi
  fi

  if [[ -f $state_dir/loop ]]; then
    loop_device=$(<"$state_dir/loop")
    if [[ $loop_device =~ ^/dev/loop[0-9]+$ ]]; then
      read_state
      if verify_loop_identity assert-clean; then
        printf 'remaining_loop=%s\n' "$loop_device" >>"$artifact_dir/cleanup.txt"
        failed=1
      else
        loop_state=$?
        if [[ $loop_state -ne 1 && $loop_state -ne 4 ]]; then
          printf 'loop_identity=unavailable_or_mismatched:%s\n' "$loop_state" \
            >>"$artifact_dir/cleanup.txt"
          failed=1
        fi
      fi
    fi
  fi

  if [[ $failed -eq 0 ]]; then
    printf 'exact_resources_remaining=false\n' >>"$artifact_dir/cleanup.txt"
  fi

  return "$failed"
}

recover_remount() {
  read_state
  verify_loop_identity recover-pre-unmount || {
    status=$?
    record "refusing recovery remount: loop identity status $status"
    return 1
  }
  query_mapper recover-pre-unmount || {
    status=$?
    record "refusing recovery remount: mapper identity status $status"
    return 1
  }
  [[ $(as_root dmsetup table "$map_name") == "$linear_table" ]] || {
    record "refusing recovery remount: mapper does not reference recorded loop identity"
    return 1
  }

  local mounted
  mounted=$(as_root findmnt -rn -M "$mount_path" -o SOURCE,TARGET,FSTYPE,OPTIONS) || {
    record "refusing recovery remount: exact mount is unavailable"
    return 1
  }
  [[ $mounted == "/dev/mapper/$map_name $mount_path ext4 "* ]] || {
    record "refusing recovery remount: exact mount identity mismatch"
    return 1
  }
  printf 'before_unmount=%s\n' "$mounted" >>"$artifact_dir/recovery-remount.txt"

  as_root umount "$mount_path"
  if as_root findmnt -rn -M "$mount_path" >"$artifact_dir/recovery-findmnt-after-unmount.txt" 2>&1; then
    record "ordinary unmount did not remove exact mount"
    return 1
  fi
  printf 'ordinary_unmount=pass\n' >>"$artifact_dir/recovery-remount.txt"

  verify_loop_identity recover-pre-mount || return 1
  query_mapper recover-pre-mount || return 1
  [[ $(as_root dmsetup table "$map_name") == "$linear_table" ]] || return 1
  as_root mount -o nodev,nosuid,noexec "/dev/mapper/$map_name" "$mount_path"

  mounted=$(as_root findmnt -rn -M "$mount_path" -o SOURCE,TARGET,FSTYPE,OPTIONS) || return 1
  [[ $mounted == "/dev/mapper/$map_name $mount_path ext4 "* ]] || return 1
  options=${mounted#* ext4 }
  [[ ,$options, == *,rw,* && ,$options, == *,nodev,* && ,$options, == *,nosuid,* &&
    ,$options, == *,noexec,* && ,$options, != *,emergency_ro,* ]] || {
    record "ordinary remount did not produce expected writable recovered filesystem"
    return 1
  }
  printf 'after_remount=%s\nordinary_remount_recovery=pass\n' "$mounted" \
    >>"$artifact_dir/recovery-remount.txt"
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
  image=$(realpath -e "$image")

  printf '%s\n' "$image" >"$state_dir/image"
  printf '%s\n' "$mount_path" >"$state_dir/mount"
  printf '%s\n' "$map_name" >"$state_dir/map"

  loop_device=$(as_root losetup --find --show --sizelimit "$image_size" "$image")
  [[ $loop_device =~ ^/dev/loop[0-9]+$ ]] || return 1
  printf '%s\n' "$loop_device" >"$state_dir/loop"

  if query_loop_identity setup; then
    :
  else
    record "setup loop identity query failed: $?"
    return 1
  fi
  expected_loop_name=$loop_device
  expected_back_file=$image
  expected_back_ino=$(stat -c %i "$image")
  expected_back_maj_min=$(findmnt -rn -T "$image" -o MAJ:MIN)
  expected_loop_maj_min=$queried_loop_maj_min
  validate_loop_identity || { record "setup loop identity mismatch"; return 1; }
  printf '%s\n' "$expected_loop_name" >"$state_dir/loop-name"
  printf '%s\n' "$expected_back_file" >"$state_dir/back-file"
  printf '%s\n' "$expected_back_ino" >"$state_dir/back-ino"
  printf '%s\n' "$expected_back_maj_min" >"$state_dir/back-maj-min"
  printf '%s\n' "$expected_loop_maj_min" >"$state_dir/loop-maj-min"

  sectors=$(as_root blockdev --getsz "$loop_device")
  [[ $sectors =~ ^[1-9][0-9]*$ ]] || return 1
  printf '%s\n' "$sectors" >"$state_dir/sectors"

  linear_table="0 $sectors linear $expected_loop_maj_min 0"
  printf '%s\n' "$linear_table" | as_root dmsetup create "$map_name"
  linear_table=$(as_root dmsetup table "$map_name")
  [[ $linear_table == "0 $sectors linear $expected_loop_maj_min 0" ]] || return 1
  printf '%s\n' "$linear_table" >"$state_dir/linear-table"
  as_root mkfs.ext4 -q -F "/dev/mapper/$map_name"
  as_root mount -o nodev,nosuid,noexec "/dev/mapper/$map_name" "$mount_path"
  as_root chown "$(id -u):$(id -g)" "$mount_path"

  {
    printf 'image=%s\nloop=%s\nloop_maj_min=%s\nback_inode=%s\nback_dev=%s\nmap=%s\nsectors=%s\nmount=%s\n' \
      "$image" "$loop_device" "$expected_loop_maj_min" "$expected_back_ino" \
      "$expected_back_maj_min" "$map_name" "$sectors" "$mount_path"
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

  {
    uname -srvmo || true
    strace --version | head -n 1 || true
  } >"$artifact_dir/host-versions.txt" 2>&1

  if bash "$(dirname "$script_path")/fr19a_sync_eio_host_test.sh"; then
    printf 'semantic_error_table_regression=pass\n' >"$artifact_dir/host-self-test.txt"
  else
    printf 'semantic_error_table_regression=fail\n' >"$artifact_dir/host-self-test.txt"
    return 1
  fi

  for command in sudo losetup dmsetup blockdev mkfs.ext4 mount umount findmnt strace awk \
    elixir erl timeout jq realpath stat; do
    if command -v "$command" >/dev/null 2>&1; then
      printf '%s=%s\n' "$command" "$(command -v "$command")" >>"$artifact_dir/capability.txt"
    else
      printf '%s=missing\n' "$command" >>"$artifact_dir/capability.txt"
      supported=false
    fi
  done

  if sudo -n true 2>/dev/null; then
    printf 'sudo_noninteractive=true\n' >>"$artifact_dir/capability.txt"
    sudo -n dmsetup version >>"$artifact_dir/host-versions.txt" 2>&1 || true
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
    timeout 45s strace -ff -yy -ttt \
    -e trace=fsync,fdatasync,pwrite64,write,openat,close \
    -o "$raw_trace" env FR19A_ARTIFACT_DIR="$artifact_dir" \
    "$elixir_path" "$(dirname "$script_path")/fr19a_raw_sync_eio.exs" \
    "$raw_file" "$script_path" "$state_dir" "$artifact_dir" \
    >"$artifact_dir/raw-probe.txt" 2>&1

  raw_sync_line=$(grep -Fh "$raw_file" "$raw_trace"* | \
    grep -E '(fsync|fdatasync)\(.*\) = -1 (EIO|EROFS)' | tail -n 1 || true)
  raw_errno=$(printf '%s\n' "$raw_sync_line" | sed -nE 's/.* = -1 (EIO|EROFS).*/\1/p')

  if [[ -z $raw_sync_line ]] || \
    ! grep -Eq 'phase=semantic-assert status=0$' "$artifact_dir/error-table-phase.txt"; then
    printf 'raw_sync_failure=missing\nsupported=false\n' >>"$artifact_dir/capability.txt"
    return 78
  fi

  if [[ $raw_errno == EROFS ]] && \
    ! grep -Eq 'emergency_ro' "$artifact_dir/mapper-transitions.txt"; then
    printf 'raw_sync_failure=erofs_without_emergency_ro\nsupported=false\n' \
      >>"$artifact_dir/capability.txt"
    return 78
  fi

  {
    printf 'schema=pramana-foundry-fr19a-raw-sync-fault/v1\n'
    printf 'errno=%s\n' "$raw_errno"
    printf 'controlled_error_table=true\n'
    if [[ $raw_errno == EROFS ]]; then
      printf 'ext4_emergency_ro=true\n'
    else
      printf 'ext4_emergency_ro=not_required\n'
    fi
    printf 'result=pass\n%s\n' "$raw_sync_line"
  } >"$artifact_dir/raw-sync-proof.txt"
  printf 'raw_sync_failure=%s\nsupported=true\n' "${raw_errno,,}" \
    >>"$artifact_dir/capability.txt"
}

if [[ ${FR19A_SYNC_EIO_SOURCE_ONLY:-0} == 1 ]]; then
  return 0
fi

case "$mode" in
  capability)
    capability
    ;;
  setup)
    setup_state
    ;;
  suspend)
    read_state
    verify_loop_identity suspend || { status=$?; record "refusing suspend: loop identity status $status"; exit 1; }
    query_mapper suspend || { status=$?; record "refusing suspend: mapper identity status $status"; exit 1; }
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
    verify_loop_identity error-resume || { status=$?; record "refusing error load: loop identity status $status"; exit 1; }
    query_mapper error-resume || { status=$?; record "refusing error load: mapper identity status $status"; exit 1; }
    [[ $(as_root dmsetup table "$map_name") == "$linear_table" ]] || {
      record "refusing error load: mapper does not reference recorded loop identity"
      exit 1
    }
    : >"$artifact_dir/error-table-phase.txt"
    if printf '%s\n' "$error_table" | as_root dmsetup load "$map_name"; then
      record_phase load 0
    else
      load_status=$?
      record_phase load "$load_status"
      restore_linear
      exit "$load_status"
    fi
    if as_root dmsetup resume "$map_name"; then
      resume_status=0
    else
      resume_status=$?
      record_phase resume "$resume_status"
      record "error-table resume failed; restoring exact linear table"
      restore_linear
      exit "$resume_status"
    fi
    record_phase resume "$resume_status"
    if observed_error_table=$(as_root dmsetup table "$map_name"); then
      table_status=0
    else
      table_status=$?
    fi
    record_phase table-read "$table_status"
    {
      printf 'observed_table_begin\n%s\nobserved_table_end\n' "$observed_error_table"
    } >>"$artifact_dir/error-table-phase.txt"
    if [[ $table_status -ne 0 ]] || ! validate_error_table "$observed_error_table" "$sectors"; then
      record_phase semantic-assert 1
      restore_linear
      exit 1
    fi
    record_phase semantic-assert 0
    record "loaded exact error table: $error_table"
    record_mapper error
    ;;
  restore)
    restore_linear
    ;;
  recover-remount)
    recover_remount
    ;;
  cleanup)
    cleanup_state
    ;;
  assert-clean)
    assert_clean
    ;;
  *)
    printf 'usage: %s capability|setup|suspend|error-resume|restore|recover-remount|cleanup|assert-clean STATE ARTIFACTS\n' \
      "$0" >&2
    exit 64
    ;;
esac
