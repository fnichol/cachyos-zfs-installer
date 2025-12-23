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
  echo "Creating user ZFS dataset: $dataset"
  zfs create -o "mountpoint=$home_dir_tmp_mount" "$dataset" || return 1

  # Update permissions and ownership
  chown -R "$owns" "$root/$home_dir_tmp_mount"
  chmod 0750 "$root/$home_dir_tmp_mount"

  # Copy existing home directory content into dataset
  echo "Copying user's existing home directory content to dataset"
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

  local user_uid user_gid user_comment
  user_uid="$(grep -E "^$username:" "$root/etc/passwd" | awk -F: '{print $3}')"
  user_gid="$(grep -E "^$username:" "$root/etc/passwd" | awk -F: '{print $4}')"
  user_comment="$(
    grep -E "^$username:" "$root/etc/passwd" | awk -F: '{print $5}'
  )"

  # Create a temporary user on the live ISO system so that a "local" user is
  # present when delegating ZFS dataset permissions
  echo "Creating temporary local user for ZFS permissions delegation: $username"
  useradd \
    --non-unique \
    --no-create-home \
    --uid "$user_uid" \
    --gid "$user_gid" \
    --comment "$user_comment" \
    --shell /bin/bash \
    "$username"

  # Delegate ZFS permissions (power user level)
  echo "Delegating ZFS permissions of $dataset to: $username"
  zfs allow -u "$username" \
    compression,mountpoint,create,mount,snapshot,destroy,send,receive,hold,release \
    "$dataset" || return 1

  # Delete the temporary user
  echo "Deleting temporary user: $username"
  userdel \
    --force \
    "$username" 2>/dev/null

  # Finally, clean up
  rmdir "$root/$home_dir_tmp_mount"

  echo "✓ ZFS user home for $username setup complete"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@" || exit 99
fi
