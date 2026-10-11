#!/usr/bin/env bash
# Shared functions for ZFS boot environment pacman hooks

# Loads configuration from file and sets default values.
#
# * `@param [String]` path to configuration file (default:
#   `/etc/pacman-zfs-hooks.conf`)
# * `@return 0` if successful
#
# # Environment Variables
#
# * `RETENTION_COUNT` number of boot environments to retain (default: `24`)
# * `ZFS_ROOT_POOL` ZFS root pool path (default: `zroot/ROOT`)
load_config() {
  local config_file="${1:-/etc/pacman-zfs-hooks.conf}"

  if [[ -f "$config_file" ]]; then
    # shellcheck source=/dev/null
    . "$config_file"
  fi

  # Set defaults if not configured
  RETENTION_COUNT="${RETENTION_COUNT:-24}"
  ZFS_ROOT_POOL="${ZFS_ROOT_POOL:-zroot/ROOT}"
}

# Detects the current boot environment from the root mountpoint.
#
# * `@stdout` boot environment name
# * `@return 0` if successful
get_current_be() {
  zfs list -H -o name,mounted,mountpoint 2>/dev/null \
    | awk '$2=="yes" && $3=="/" {print $1}' \
    | sed 's|.*/||'
}

# Prints an error message to standard error and exits with a non-zero exit
# code.
#
# * `@param [String]` error message
# * `@stderr` error text and abort message
#
# # Notes
#
# This function calls `exit` and will **not** return.
abort_transaction() {
  echo "ERROR: $1" >&2
  echo "Aborting package transaction for safety" >&2
  exit 1
}

# Determines whether a package contains files in the `/boot` directory.
#
# * `@param [String]` package name
# * `@return 0` if package contains files in `/boot`
# * `@return 1` if package does not contain files in `/boot`
is_boot_critical_package() {
  local pkg="$1"

  pacman -Ql "$pkg" 2>/dev/null | grep -q "^$pkg /boot/"
}

# Sorts package names alphabetically and formats them as a comma-separated
# list.
#
# * `@param [Array]` package names
# * `@stdout` sorted, comma-separated package names
# * `@return 0` if successful
format_package_list() {
  local -a packages=("$@")

  printf '%s\n' "${packages[@]}" | sort | paste -sd ', '
}

# Sorts kernel package names with versions and formats them as a
# comma-separated list.
#
# * `@param [Array]` kernel package names
# * `@stdout` sorted, comma-separated kernel packages with versions
# * `@return 0` if successful
format_kernel_packages() {
  local -a packages=("$@")
  local -a kernel_info=()

  for pkg in "${packages[@]}"; do
    if [[ -n "$pkg" ]]; then
      local version
      version=$(pacman -Q "$pkg" 2>/dev/null | awk '{print $2}')

      if [[ -n "$version" ]]; then
        kernel_info+=("$pkg $version")
      fi
    fi
  done

  printf '%s\n' "${kernel_info[@]}" | sort | paste -sd ', '
}

# Prints the running kernel version.
#
# * `@stdout` kernel version string
# * `@return 0` if successful
get_running_kernel() {
  uname -r
}

# Generates a UTC timestamp in the format `YYYYMMDD-HHMMSS`.
#
# * `@stdout` UTC timestamp string
# * `@return 0` if successful
generate_timestamp() {
  date -u +%Y%m%d-%H%M%S
}

# Determines whether a snapshot was created by the pre-transaction hook.
#
# * `@param [String]` full snapshot name
# * `@return 0` if the snapshot name matches `@be-YYYYMMDD-HHMMSS-pre-<type>`
# * `@return 1` otherwise
is_boot_env_snapshot() {
  [[ "$1" =~ @be-[0-9]{8}-[0-9]{6}-pre-[a-z]+$ ]]
}

# Determines whether a boot environment can be safely destroyed.
#
# A boot environment is not prunable when it is the running boot environment
# or when any of its snapshots has dependent clones (destroying it would
# require destroying other boot environments).
#
# * `@param [String]` full boot environment dataset name
# * `@param [String]` current boot environment name
# * `@stdout` reason when the boot environment is not prunable
# * `@return 0` if prunable
# * `@return 1` if not prunable
is_boot_env_prunable() {
  local boot_env="$1"
  local current_be="$2"

  if [[ "${boot_env##*/}" == "$current_be" ]]; then
    echo "currently booted"
    return 1
  fi

  if zfs list -H -t snapshot -o clones -d 1 "$boot_env" 2>/dev/null \
    | awk '$0 != "" && $0 != "-" { found = 1 } END { exit !found }'; then
    echo "has dependent clones"
    return 1
  fi

  return 0
}

# Selects the oldest boot environments exceeding the retention count.
#
# Boot environments which are not prunable are skipped in favor of the next
# oldest, but still count toward `$RETENTION_COUNT`.
#
# * `@param [String]` current boot environment name
# * `@stdout` boot environment dataset names to destroy, oldest first
# * `@stderr` skipped boot environments and shortfall warning
# * `@return 0` if successful
select_boot_envs_to_prune() {
  local current_be="$1"
  local -a boot_envs=()
  local boot_env reason to_delete selected=0

  mapfile -t boot_envs < <(
    zfs list \
      -r \
      -H \
      -o name \
      -s creation \
      -t filesystem \
      "$ZFS_ROOT_POOL" \
      2>/dev/null \
      | grep "/be-" \
      || true
  )

  to_delete=$((${#boot_envs[@]} - RETENTION_COUNT))
  if [[ "$to_delete" -le 0 ]]; then
    return 0
  fi

  for boot_env in "${boot_envs[@]}"; do
    if [[ "$selected" -ge "$to_delete" ]]; then
      break
    fi

    if reason=$(is_boot_env_prunable "$boot_env" "$current_be"); then
      echo "$boot_env"
      ((++selected))
    else
      echo "Skipping ${boot_env##*/}: $reason" >&2
    fi
  done

  if [[ "$selected" -lt "$to_delete" ]]; then
    echo "WARNING: only $selected of $to_delete boot environment(s)" \
      "eligible for removal" >&2
  fi
}

# Destroys a boot environment and its origin snapshot.
#
# The origin snapshot belongs to the parent dataset, so it is not removed by
# `zfs destroy -r`. It is destroyed only when it was created by the
# pre-transaction hook and no other clones depend on it.
#
# * `@param [String]` full boot environment dataset name
# * `@stdout` progress messages
# * `@stderr` warnings on failure
# * `@return 0` if the boot environment was destroyed
# * `@return 1` if the boot environment could not be destroyed
destroy_boot_env() {
  local boot_env="$1"
  local origin clones

  # Read the origin before destroying, as it reflects any promotions
  origin="$(
    zfs get \
      -H \
      -o value \
      origin \
      "$boot_env" \
      2>/dev/null
  )" || origin="-"

  if ! zfs destroy -r "$boot_env"; then
    echo "WARNING: Failed to destroy boot environment: $boot_env" >&2
    return 1
  fi
  echo "Removed boot environment: $boot_env"

  if [[ "$origin" == "-" ]] || ! is_boot_env_snapshot "$origin"; then
    return 0
  fi

  clones=$(zfs get -H -o value clones "$origin" 2>/dev/null) || return 0
  if [[ -n "$clones" && "$clones" != "-" ]]; then
    echo "Keeping snapshot $origin: still has clones"
    return 0
  fi

  if zfs destroy "$origin"; then
    echo "Removed snapshot: $origin"
  else
    echo "WARNING: Failed to destroy snapshot: $origin" >&2
  fi
}

# Destroys pre-transaction hook snapshots which no longer have any clones.
#
# This reclaims snapshots leaked by earlier versions of the post-transaction
# hook and any left behind when a boot environment was removed by other means.
#
# * `@stdout` progress messages
# * `@stderr` warnings on failure
# * `@return 0` if successful
sweep_orphaned_snapshots() {
  local snapshot clones removed=0

  while IFS=$'\t' read -r snapshot clones; do
    if ! is_boot_env_snapshot "$snapshot"; then
      continue
    fi
    if [[ -n "$clones" && "$clones" != "-" ]]; then
      continue
    fi

    if zfs destroy "$snapshot"; then
      echo "Removed orphaned snapshot: $snapshot"
      ((++removed))
    else
      echo "WARNING: Failed to destroy snapshot: $snapshot" >&2
    fi
  done < <(
    zfs list \
      -H \
      -t snapshot \
      -o name,clones \
      -r \
      "$ZFS_ROOT_POOL" \
      2>/dev/null \
      || true
  )

  if [[ "$removed" -gt 0 ]]; then
    echo "Removed $removed orphaned snapshot(s)"
  fi
}
