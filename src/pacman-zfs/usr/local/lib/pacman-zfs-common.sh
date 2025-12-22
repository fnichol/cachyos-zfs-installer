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
