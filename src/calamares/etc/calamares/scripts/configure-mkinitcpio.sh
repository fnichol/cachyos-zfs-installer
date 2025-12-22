#!/bin/bash
# Configure mkinitcpio.conf for ZFS with network boot support
set -euo pipefail

main() {
  # Redirect standard error to standard output since calamares doesn't capture
  # stderr
  exec 2>&1

  if [[ -n "${DEBUG:-}" ]]; then set -x; fi
  if [[ -n "${TRACE:-}" ]]; then set -xv; fi

  local config_file="/etc/mkinitcpio.conf"
  local extra_hooks=""

  # Apply modifications
  install_packages
  add_zfs_module "$config_file"
  modify_hooks "$config_file" "$extra_hooks"
  set_compression "$config_file"
  generate_initramfs

  echo "Configuration complete!"
}

install_packages() {
  local add_pkgs=()

  for pkg in "${add_pkgs[@]}"; do
    if ! pacman -Q "$pkg" >/dev/null 2>&1; then
      pacman -S --noconfirm "$pkg"

      echo "✓ Installed package: $pkg"
    fi
  done
}

add_zfs_module() {
  local conf_file="$1"

  # Check if 'zfs' is already in MODULES array
  if grep -q '^MODULES=.*zfs' "$conf_file"; then
    echo "✓ 'zfs' already in MODULES array"
    return 0
  fi

  # Add zfs to MODULES array
  # If MODULES=() is empty, replace with MODULES=(zfs)
  if grep -q '^MODULES=()' "$conf_file"; then
    sed -i -e 's/^MODULES=()/MODULES=(zfs)/' "$conf_file"
    echo "✓ Added 'zfs' to empty MODULES array"
  # If MODULES has content, append zfs
  elif grep -q '^MODULES=(' "$conf_file"; then
    sed -i -E 's/^MODULES=\((.*)\)/MODULES=(\1 zfs)/' "$conf_file"
    echo "✓ Added 'zfs' to MODULES array"
  fi
}

modify_hooks() {
  local conf_file="$1"
  local extra_hooks="$2"

  # Check if 'zfs' exists in HOOKS array
  if ! grep -q '^HOOKS=.*zfs' "$conf_file"; then
    echo "ERROR: 'zfs' not found in HOOKS array, aborting" >&2
    exit 1
  fi

  if ! grep -q "^HOOKS=.*$extra_hooks" "$conf_file"; then
    sed -i \
      -E 's/^(HOOKS=\(.*[[:space:]])zfs/\1'"$extra_hooks"' zfs/' \
      "$conf_file"

    echo "✓ Inserted '$extra_hooks' before 'zfs' in HOOKS array"
  fi

}

set_compression() {
  local conf_file="$1"

  if grep -q '^#COMPRESSION="zstd"' "$conf_file"; then
    sed -i -e 's|^#\(COMPRESSION="zstd"\)|\1|' "$conf_file"

    echo "✓ Set zstd initramfs compression"
  fi
}

generate_initramfs() {
  if mkinitcpio -P; then
    echo "✓ Initramfs generated successfully"
  else
    echo "ERROR: Failed to generate initramfs" >&2
    exit 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@" || exit 99
fi
