#!/bin/bash
# Setup ZFS datasets for user home directories with delegation
#
# Handles the dataset shadowing issue by preserving existing home contents
set -euo pipefail

main() {
  # Redirect standard error to standard output since calamares doesn't capture
  # stderr
  exec 2>&1

  if [[ -n "${DEBUG:-}" ]]; then set -x; fi
  if [[ -n "${TRACE:-}" ]]; then set -xv; fi

  local root="$1"
  local username="$2"
  local pool_name="${3:-zroot}"

  local owns
  owns="$(grep -E "^$username:" "$root/etc/passwd" | awk -F: '{print $3 FS $4}')"

  local home_dir
  home_dir="$(grep -E "^$username:" "$root/etc/passwd" | awk -F: '{print $6}')"

  local home_dir_tmp_mount="$home_dir.tmp"

  local dataset="$pool_name/data/home/$username"

  # Create ZFS dataset and assign temporary mount point
  zfs create -o "mountpoint=$home_dir_tmp_mount" "$dataset" || return 1

  # Update permissions and ownership
  chown -R "$owns" "$root/$home_dir_tmp_mount"
  chmod 0750 "$root/$home_dir_tmp_mount"

  # Copy existing home directory content into dataset
  (
    cd "$root/$home_dir"
    tar cpf - . | tar xpf - -C "$root/$home_dir_tmp_mount"
  ) || return 1

  # Empty out and re-create home directory mount point
  rm -rf "${root:?}/$home_dir"
  mkdir -pv "$root/$home_dir"
  chown -R "$owns" "$root/$home_dir"
  chmod 0750 "$root/$home_dir"

  # Update mount point for dataset
  zfs set "mountpoint=$home_dir" "$dataset" || return 1

  # Delegate ZFS permissions (power user level)
  zfs allow -u "$username" \
    compression,mountpoint,create,mount,snapshot,destroy,send,receive,hold,release \
    "$dataset" || return 1

  # Finally, clean up
  rmdir "$root/$home_dir_tmp_mount"

  echo "✓ ZFS user home for $username setup complete"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@" || exit 99
fi
