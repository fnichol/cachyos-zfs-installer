#!/bin/bash
# Configure ZFS native encryption for ZFSBootMenu compatibility
# This script sets up encryption keyfiles and kernel parameters needed for
# encrypted ZFS root to boot successfully with ZFSBootMenu
set -euo pipefail

main() {
  # Redirect standard error to standard output since calamares doesn't capture
  # stderr
  exec 2>&1

  if [[ -n "${DEBUG:-}" ]]; then set -x; fi
  if [[ -n "${TRACE:-}" ]]; then set -xv; fi

  # Configuration
  local root="$1"
  local pool_name="${2:-zroot}"
  local boot_env="${3:-${pool_name}/ROOT/default}"
  local keyfile_dir="/etc/zfs/keys"
  local keyfile_path="$keyfile_dir/$pool_name.key"
  local mkinitcpio_conf="$root/etc/mkinitcpio.conf"

  # Find the encryption root for the boot environment
  local encryption_root
  encryption_root=$(find_encryption_root "$boot_env")

  if [[ -z "$encryption_root" ]]; then
    echo "✓ Boot environment is not encrypted, skipping encryption setup"
    return 0
  fi

  echo "Found encryption root: $encryption_root"

  # Setup encryption keyfile and configuration
  create_keyfile_from_passphrase \
    "$root" \
    "$pool_name" \
    "$keyfile_dir" \
    "$keyfile_path" \
    "$encryption_root"
  set_keylocation "$pool_name" "$encryption_root" "$keyfile_path"
  add_keyfile_to_initramfs "$mkinitcpio_conf" "$keyfile_path"

  echo "✓ ZFS encryption configuration complete"
}

find_encryption_root() {
  local dataset="$1"

  # Check if dataset is encrypted
  local encryption
  encryption="$(zfs get -H -o value encryption "$dataset" 2>/dev/null)" \
    || return 0

  if [[ "$encryption" == "off" ]]; then
    return 0
  fi

  # Get the encryption root
  local encroot
  encroot="$(zfs get -H -o value encryptionroot "$dataset" 2>/dev/null)" \
    || return 0

  if [[ "$encroot" != "-" ]]; then
    echo "$encroot"
  fi
}

create_keyfile_from_passphrase() {
  local root="$1"
  local pool_name="$2"
  local keyfile_dir="$3"
  local keyfile_path="$4"
  local encryption_root="$5"

  local dataset="$pool_name/keystore"

  mkdir -pv "$root/$keyfile_dir"

  echo "Creating keystore dataset '$dataset' at: $keyfile_dir"
  zfs create -o "mountpoint=$keyfile_dir" "$dataset" || return 1

  # Ensure directory exists and has correct permissions
  chown -R "root:root" "$root/$keyfile_dir"
  chmod 700 "$root/$keyfile_dir"

  # The passphrase should be in a temporary file created by the
  # zfs_keyfile_passphrase Python module
  local temp_passphrase_file="/tmp/.zfs_passphrase"

  if [[ ! -f "$temp_passphrase_file" ]]; then
    echo "ERROR: ZFS passphrase file not found at ${temp_passphrase_file}" >&2
    echo "The zfs_keyfile_passphrase module may not have run" >&2
    return 1
  fi

  echo "Creating keyfile from captured passphrase..."

  # Copy the passphrase to the final keyfile location
  cp -v "$temp_passphrase_file" "$root/$keyfile_path"
  chmod -v 000 "$root/$keyfile_path"

  # Securely delete the temporary passphrase file
  shred -uvz "$temp_passphrase_file" 2>/dev/null \
    || rm -f "$temp_passphrase_file"

  echo "✓ Created keyfile: $keyfile_path"
}

set_keylocation() {
  local pool_name="$1"
  local encryption_root="$2"
  local keyfile_path="$3"

  zfs set keylocation="file://${keyfile_path}" "$encryption_root"
  zfs set org.zfsbootmenu:keysource="$pool_name/keystore" "$pool_name"

  echo "✓ Set keylocation for $encryption_root"
}

add_keyfile_to_initramfs() {
  local conf_file="$1"
  local keyfile_path="$2"

  # Check if keyfile is already in FILES array
  if grep -q "^FILES=.*${keyfile_path}" "$conf_file"; then
    echo "✓ Keyfile already in FILES array"
    return 0
  fi

  # Add keyfile to FILES array
  if grep -q '^FILES=()' "$conf_file"; then
    # Empty FILES array
    sed -i -e "s|^FILES=()|FILES=(${keyfile_path})|" "$conf_file"

    echo "✓ Added keyfile to empty FILES array"
  elif grep -q '^FILES=(' "$conf_file"; then
    # FILES array has content
    sed -i -E "s|^FILES=\((.*)\)|FILES=(\1 ${keyfile_path})|" "$conf_file"

    echo "✓ Added keyfile to FILES array"
  else
    # No FILES line, append it
    echo "FILES=(${keyfile_path})" >>"$conf_file"

    echo "✓ Created FILES array with keyfile"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@" || exit 99
fi
