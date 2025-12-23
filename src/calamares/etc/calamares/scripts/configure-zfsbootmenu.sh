#!/bin/bash
# Generate ZFSBootMenu unified EFI images
set -euo pipefail

main() {
  # Redirect standard error to standard output since calamares doesn't capture
  # stderr
  exec 2>&1

  if [[ -n "${DEBUG:-}" ]]; then set -x; fi
  if [[ -n "${TRACE:-}" ]]; then set -xv; fi

  # Configuration
  local pool_name="${1:-zroot}"
  local boot_env="${2:-${pool_name}/ROOT/default}"

  install_packages
  set_boot_parameters "$pool_name" "$boot_env"
  customize_config
  generate_zfsbootmenu
  create_efi_boot_entry
}

install_packages() {
  local add_pkgs=(
    zfs-meta
    zfsbootmenu
  )

  for pkg in "${add_pkgs[@]}"; do
    if ! pacman -Q "$pkg" >/dev/null 2>&1; then
      pacman -S --noconfirm "$pkg"

      echo "✓ Installed package: $pkg"
    fi
  done
}

set_boot_parameters() {
  local pool_name="$1"
  local boot_env="$2"

  local boot_root_dataset
  boot_root_dataset="$(dirname "$boot_env")"

  # Set kernel command line parameters for ZFSBootMenu
  # - `rw`: Tell zfs hook to import pool read-write (not readonly)
  local cmdline="rw"
  zfs set "org.zfsbootmenu:commandline=$cmdline" "$boot_root_dataset"

  # Expand parent dataset commandline values
  zfs set "org.zfsbootmenu:commandline=%{parent}" "$boot_env"

  zfs set "org.zfsbootmenu:rootprefix=zfs=" "$boot_root_dataset"

  zpool set "bootfs=$boot_env" "$pool_name"

  echo "✓ Set kernel rootprefix"
}

customize_config() {
  install -v -m 644 -D \
    /etc/calamares/scripts/zfsbootmenu_config.yaml \
    /etc/zfsbootmenu/config.yaml

  rm -fv /etc/calamares/scripts/zfsbootmenu_config.yaml

  echo "✓ Installed custom ZFSBootMenu configuration"
}

generate_zfsbootmenu() {
  if generate-zbm; then
    echo "✓ ZFSBootMenu images generated successfully"
  else
    echo "ERROR: Failed to generate ZFSBootMenu images" >&2
    exit 1
  fi
}

create_efi_boot_entry() {
  # Find the ESP device
  local esp_dev
  esp_dev=$(findmnt -n -o SOURCE /boot/efi)

  # Extract disk and partition number
  local disk="${esp_dev%p[0-9]*}"
  local part="${esp_dev##*p}"

  echo "ESP device: $esp_dev (disk: $disk, partition: $part)"

  # Create boot entry
  if efibootmgr --create \
    --disk "$disk" \
    --part "$part" \
    --label "ZFSBootMenu" \
    --loader '\EFI\ZFSBootMenu\vmlinuz-linux-cachyos.EFI'; then

    echo "✓ EFI boot entry created"
  else
    echo "ERROR: Failed to create EFI boot entry" >&2
    exit 1
  fi

  # Set boot order (ZFSBootMenu first)
  local new_entry
  new_entry=$(efibootmgr | grep "ZFSBootMenu" | head -1 | cut -c5-8)

  if [[ -n "$new_entry" ]]; then
    efibootmgr --bootorder "$new_entry"

    echo "✓ Set boot order (ZFSBootMenu first: $new_entry)"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@" || exit 99
fi
