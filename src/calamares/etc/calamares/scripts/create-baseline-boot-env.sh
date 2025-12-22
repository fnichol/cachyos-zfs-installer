#!/bin/bash
# Create baseline boot environment after fresh install
set -euo pipefail

main() {
  # Redirect standard error to standard output since calamares doesn't capture
  # stderr
  exec 2>&1

  if [[ -n "${DEBUG:-}" ]]; then set -x; fi
  if [[ -n "${TRACE:-}" ]]; then set -xv; fi

  local pool_name="${1:-zroot}"
  local default_boot_env="${pool_name}/ROOT/default"
  local baseline_boot_env="${pool_name}/ROOT/baseline"

  # Verify base BE exists
  if ! zfs list "$default_boot_env" >/dev/null 2>&1; then
    echo "ERROR: Base boot environment '$default_boot_env' does not exist" >&2
    exit 1
  fi

  zfs snapshot "${default_boot_env}@baseline"

  zfs clone "${default_boot_env}@baseline" "$baseline_boot_env"

  zfs set \
    canmount=noauto \
    "$baseline_boot_env"
  zfs set \
    org.zfsbootmenu:active=off \
    "$baseline_boot_env"
  zfs set \
    org.zfsbootmenu:description="Factory baseline install" \
    "$baseline_boot_env"
  zfs set org.zfsbootmenu:commandline="rw zfs=$baseline_boot_env" \
    "$baseline_boot_env"

  echo "✓ Created baseline boot environment: $baseline_boot_env"

  info "Boot environments:"
  zfs list -r "${pool_name}/ROOT"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@" || exit 99
fi
