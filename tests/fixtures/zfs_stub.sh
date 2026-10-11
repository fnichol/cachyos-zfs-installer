#!/usr/bin/env bash
# Test double for `zfs`, backed by fixture files in `$ZFS_FIXTURES`:
#
# * `filesystems`: `<name>\t<origin>` lines, in creation order
# * `snapshots`: `<name>\t<clones>` lines
# * `destroy_fail`: dataset names whose `destroy` fails (optional)
#
# Every `destroy` invocation is appended to `calls.log`. Fixture state is never
# modified, so each test describes the state its code under test will observe.
set -euo pipefail

fixtures="${ZFS_FIXTURES:?ZFS_FIXTURES must be set}"

# Supports: zfs list [-r] [-H] [-p] [-d N] [-s prop] [-t type] [-o fields] <ds>
list() {
  local type=filesystem fields=name depth="" parent="" file name value dataset

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t)
        type="$2"
        shift 2
        ;;
      -o)
        fields="$2"
        shift 2
        ;;
      -d)
        depth="$2"
        shift 2
        ;;
      -s) shift 2 ;;
      -r | -H | -p) shift ;;
      *)
        parent="$1"
        shift
        ;;
    esac
  done

  file="$fixtures/${type}s"
  [[ -f "$file" ]] || return 0

  while IFS=$'\t' read -r name value; do
    dataset="${name%@*}"
    if [[ -n "$depth" ]]; then
      [[ "$dataset" == "$parent" ]] || continue
    else
      [[ "$dataset" == "$parent" || "$dataset" == "$parent"/* ]] || continue
    fi

    case "$fields" in
      name) echo "$name" ;;
      clones) echo "$value" ;;
      name,clones) printf '%s\t%s\n' "$name" "$value" ;;
      *)
        echo "zfs stub: unsupported fields: $fields" >&2
        return 2
        ;;
    esac
  done <"$file"
}

# Supports: zfs get -H -o value <origin|clones> <dataset>
get() {
  local property="$4" dataset="$5" file

  case "$property" in
    origin) file="$fixtures/filesystems" ;;
    clones) file="$fixtures/snapshots" ;;
    *)
      echo "zfs stub: unsupported property: $property" >&2
      return 2
      ;;
  esac

  if [[ ! -f "$file" ]] \
    || ! awk -F'\t' -v ds="$dataset" \
      '$1 == ds { print $2; found = 1 } END { exit !found }' "$file"; then
    echo "cannot open '$dataset': dataset does not exist" >&2
    return 1
  fi
}

# Supports: zfs destroy [-r] <dataset>
destroy() {
  local target="${!#}"

  echo "destroy $*" >>"$fixtures/calls.log"

  if [[ -f "$fixtures/destroy_fail" ]] \
    && grep -qxF "$target" "$fixtures/destroy_fail"; then
    echo "cannot destroy '$target': dataset is busy" >&2
    return 1
  fi
}

cmd="$1"
shift
case "$cmd" in
  list) list "$@" ;;
  get) get "$@" ;;
  destroy) destroy "$@" ;;
  *)
    echo "zfs stub: unsupported command: $cmd" >&2
    exit 2
    ;;
esac
