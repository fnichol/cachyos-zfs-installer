#!/bin/bash
# Create baseline boot environment after fresh install
set -euo pipefail

main() {
  # Redirect standard error to standard output since calamares doesn't capture
  # stderr
  exec 2>&1

  if [[ -n "${DEBUG:-}" ]]; then set -x; fi
  if [[ -n "${TRACE:-}" ]]; then set -xv; fi

  install --verbose --mode=644 \
    /tmp/pacman-zfs/etc/pacman-zfs-hooks.conf \
    /etc/

  install --verbose --mode=644 \
    /tmp/pacman-zfs/etc/pacman.d/hooks/zfs-post-cleanup.hook \
    /etc/pacman.d/hooks/
  install --verbose --mode=644 \
    /tmp/pacman-zfs/etc/pacman.d/hooks/zfs-pre-upgrade.hook \
    /etc/pacman.d/hooks/

  install --verbose --mode=755 \
    /tmp/pacman-zfs/usr/local/bin/pacman-zfs-post \
    /usr/local/bin/
  install --verbose --mode=755 \
    /tmp/pacman-zfs/usr/local/bin/pacman-zfs-pre \
    /usr/local/bin/

  install --verbose --mode=755 \
    /tmp/pacman-zfs/usr/local/lib/pacman-zfs-common.sh \
    /usr/local/lib/

  echo "✓ Installed pacman-zfs"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@" || exit 99
fi
