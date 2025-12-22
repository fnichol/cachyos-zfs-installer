# CachyOS ZFS Installer

|         |                                           |
| ------: | ----------------------------------------- |
|      CI | [![CI Status][badge-ci-overall]][ci]      |
| License | [![Crate license][badge-license]][github] |

An installer that configures [CachyOS][cachyos] with an optionally encrypted ZFS
root filesystem, [ZFSBootMenu][zfsbootmenu] bootloader, and automatic boot
environments.

**Table of Contents**

<!-- toc -->

- [Motivation](#motivation)
- [Features](#features)
- [Architecture](#architecture)
  - [Components](#components)
  - [Boot Flow](#boot-flow)
- [ZFS Dataset Layout](#zfs-dataset-layout)
  - [Pool Configuration](#pool-configuration)
  - [Dataset Hierarchy](#dataset-hierarchy)
  - [Dataset Properties](#dataset-properties)
- [Approach](#approach)
- [Usage](#usage)
  - [Quick Start](#quick-start)
  - [Installation Process](#installation-process)
  - [Post-Installation](#post-installation)
- [Boot Environments](#boot-environments)
- [User Home Directories](#user-home-directories)
- [Prior Art and References](#prior-art-and-references)
- [Code of Conduct](#code-of-conduct)
- [Issues](#issues)
- [Contributing](#contributing)
- [Authors](#authors)
- [License](#license)

<!-- tocstop -->

## Motivation

Linux distributions rarely ship with ZFS root filesystem support because ZFS
license terms conflict with kernel distribution policies. Users who want ZFS
must configure the system themselves, navigating complex interactions between
bootloaders, initramfs hooks, encryption keyfiles, and boot environment
management.

This installer solves four specific problems:

**1. Bootloader Configuration**

systemd-boot expects kernel and initramfs files on a FAT32 ESP partition. ZFS
cannot live on FAT32, and storing kernels outside ZFS defeats the purpose of
boot environments. ZFSBootMenu solves this by creating unified EFI images that
contain everything needed to discover and boot ZFS pools, leaving only one small
file on the ESP per kernel version.

**2. Encryption Key Management**

ZFSBootMenu uses kexec to boot into selected environments. The kexec boundary
loses all encryption keys loaded in memory, causing the system initramfs to
prompt for passphrases again. This installer creates encryption keyfiles during
installation and embeds them in the initramfs, enabling automatic unlock after
ZFSBootMenu passes control to the system kernel.

**3. Boot Environment Automation**

Boot environments provide system snapshots before risky changes, but manual
snapshot creation fails when users forget. This installer configures pacman
hooks that automatically create boot environments before any package operation
touches the kernel, ZFS, or bootloader packages.

**4. Filesystem Modernization**

Traditional Linux filesystems lack features that professional users expect:
atomic snapshots, transparent compression, dataset delegation, and data
integrity verification. ZFS provides these features, and this installer makes
them accessible without requiring deep ZFS expertise.

## Features

- **Optionlly encrypted ZFS root** with automatic keyfile-based unlock
- **ZFSBootMenu bootloader** with unified EFI images
- **Automatic boot environments** via pacman hooks before system updates
- **Baseline factory snapshot** for recovery scenarios
- **Delegated user home directories** enabling users to manage their own ZFS
  snapshots
- **Network boot support** with optional remote unlock via Dropbear SSH or
  Tailscale
- **Compression enabled** by default on all datasets
- **Configuration-based approach** requiring no patches to upstream software

## Architecture

### Components

The installer consists of four layers:

**1. Live ISO Configuration (`bin/install`)**

Runs on the CachyOS live ISO before launching the graphical installer. Installs
ZFSBootMenu packages, configures Calamares modules to use ZFS and ZFSBootMenu
instead of ext4 and systemd-boot, and sets up the installation environment.

**2. Calamares Modules and Scripts (`src/calamares/`)**

Custom Calamares configuration that runs during installation:

- **Python module** (`zfs_keyfile_passphrase`) prompts for ZFS encryption
  passphrase with clear explanation, writing it securely to a temporary file
- **Shell scripts** configure mkinitcpio, create encryption keyfiles, generate
  ZFSBootMenu images, set up boot environments, and install pacman hooks
- **Module configuration** files define execution order and integration points

**3. Pacman Hooks (`src/pacman-zfs/`)**

System-level hooks that run before and after package operations:

- **Pre-hook** (`zfs-pre-upgrade.hook`) snapshots the current boot environment
  when kernel or ZFS packages will be updated
- **Post-hook** (`zfs-post-cleanup.hook`) cleans old boot environments based on
  retention policy and regenerates ZFSBootMenu images
- **Common library** (`pacman-zfs-common.sh`) provides shared functionality for
  both hooks

**4. Post-Install Scripts (`src/calamares/etc/calamares/scripts/`)**

Scripts that run in the target system during installation:

- `configure-mkinitcpio.sh` - Adds ZFS module to MODULES array for early loading
- `configure-zfs-encryption.sh` - Creates keyfile from captured passphrase, sets
  dataset keylocation property
- `configure-zfsbootmenu.sh` - Installs packages, sets boot parameters,
  generates unified EFI images
- `create-baseline-boot-env.sh` - Creates factory baseline snapshot for recovery
- `setup-user-home-zfs.sh` - Creates ZFS datasets for user homes with delegated
  permissions

### Boot Flow

1. **UEFI firmware** loads `/boot/efi/EFI/ZFSBootMenu/vmlinuz-linux-cachyos.EFI`
2. **ZFSBootMenu** scans for ZFS pools, prompts for encryption passphrase
3. **User** selects boot environment from menu (default: `zroot/ROOT/default`)
4. **ZFSBootMenu** kexecs into selected environment with kernel parameters from
   `org.zfsbootmenu:commandline` dataset property
5. **System initramfs** boots with ZFS modules loaded early (from MODULES array)
6. **zfs hook** in initramfs reads keyfile from `/etc/zfs/keys/zroot.key`,
   unlocks datasets
7. **Root filesystem** mounts read-write, system boots normally

## ZFS Dataset Layout

The installer creates a structured dataset hierarchy that separates boot
environments from persistent data. This separation ensures that rolling back to
a previous boot environment preserves user data, logs, and container state.

### Pool Configuration

The pool `zroot` is created with these options:

- `ashift=12` - 4KB sector alignment (optimal for modern drives)
- `autotrim=on` - Automatic TRIM for SSDs
- `acltype=posixacl` - POSIX ACL support for Linux permissions
- `atime=off` - Disable access time updates (performance optimization)
- `relatime=off` - Disable relative access time updates
- `xattr=sa` - Store extended attributes in system attributes (performance)
- `normalization=formD` - Unicode normalization for consistent filenames
- `compression=lz4` - Default compression for all datasets (fast, effective)

### Dataset Hierarchy

**Boot Environment Datasets** (included in snapshots, rolled back together):

```
zroot/ROOT                      (mountpoint=none, canmount=off)
├── default                     (mountpoint=/, canmount=noauto) - Active system
└── baseline                    (mountpoint=/, canmount=noauto) - Factory snapshot
```

Additional boot environments appear here automatically via pacman hooks, named
with timestamp prefixes (e.g., `be-2024-12-22-123456`).

**Persistent Data Datasets** (excluded from boot environment snapshots):

```
zroot/data                      (mountpoint=none, canmount=off)
├── home                        (mountpoint=/home)
│   ├── root                    (mountpoint=/root)
│   └── <username>              (mountpoint=/home/<username>) - Created per user
├── opt                         (mountpoint=/opt)
├── srv                         (mountpoint=/srv)
└── var
    ├── lib
    │   ├── containers          (mountpoint=/var/lib/containers) - Podman
    │   ├── docker              (mountpoint=/var/lib/docker) - Docker
    │   ├── libvirt             (mountpoint=/var/lib/libvirt) - VMs
    │   └── lxc                 (mountpoint=/var/lib/lxc) - Containers
    ├── log                     (mountpoint=/var/log)
    ├── spool                   (mountpoint=/var/spool)
    └── tmp                     (mountpoint=/var/tmp)
```

**Encryption Support Datasets** (created when encryption is enabled):

```
zroot/keystore                  (mountpoint=/etc/zfs/keys) - Encryption keyfiles
```

**Virtual Machine Datasets**:

```
zroot/zvols                     (mountpoint=none, canmount=off) - ZVOLs for VMs
```

### Dataset Properties

**Separation of Concerns**

Datasets under `zroot/ROOT/` are included in boot environments. Changes to the
operating system, installed packages, and system configuration live here. When
you roll back to a previous boot environment, these changes revert.

Datasets under `zroot/data/` persist across boot environments. User files,
application data, logs, and container images remain unchanged when you switch
boot environments. This separation prevents data loss during system rollbacks.

**Compression**

All datasets inherit `compression=lz4` by default. LZ4 provides substantial
space savings (typically 20-40% for text and logs, less for media files) with
negligible CPU overhead. Users can change compression on delegated datasets:

```bash
# Use stronger compression (slower writes, better ratio)
zfs set compression=zstd zroot/data/home/$(whoami)

# Disable compression (for pre-compressed data like media files)
zfs set compression=off zroot/data/home/$(whoami)/media
```

**Automatic Snapshot Scope**

The pacman pre-upgrade hook snapshots `zroot/ROOT/default` only, creating a new
boot environment. Persistent data under `zroot/data/` is not snapshotted
automatically. Users manage their own home directory snapshots using delegated
permissions.

## Approach

This installer configures existing tools rather than patching them. The design
follows three principles:

**1. Use Upstream Software**

The installer uses Calamares (CachyOS's chosen installer), ZFSBootMenu (the
standard ZFS bootloader), mkinitcpio (Arch's initramfs generator), and pacman
hooks (Arch's package management system). No forks or patches required.

**2. Configuration Over Code**

Where possible, the installer writes configuration files rather than code:

- `zfsbootmenu/config.yaml` configures bootloader behavior
- `mkinitcpio.conf` configures initramfs generation
- `settings.conf` in Calamares defines module execution order
- `pacman-zfs-hooks.conf` configures boot environment retention policy

**3. Scripts for Integration**

When configuration alone cannot solve a problem, shell scripts provide the
integration layer. For example, the kexec encryption key problem requires a
script to capture passphrases during installation and create keyfiles, but the
script uses standard ZFS commands (`zfs set keylocation=...`) rather than
patching ZFS or ZFSBootMenu.

This approach minimizes maintenance burden. When ZFSBootMenu or Calamares
updates, the installer typically continues working because it relies on stable
interfaces (configuration files, command-line tools) rather than internal
implementation details.

## Usage

### Quick Start

Boot CachyOS live ISO and run:

```sh
curl -sSf https://fnichol.github.io/cachyos-zfs-installer/run.sh | sudo -E bash -s --
```

This command downloads the installer, configures Calamares for ZFS with
ZFSBootMenu, and launches the graphical installer.

### Installation Process

**Step 1: Partition and Install**

The Calamares installer appears after running the quick start command. Follow
the prompts:

1. Select disk and partitioning scheme (ESP mounts at `/boot/efi`)
2. Choose ZFS filesystem (pre-selected)
3. Enable encryption if desired
4. Enter encryption passphrase (first prompt)
5. Re-enter passphrase for keyfile creation (second prompt, with explanation)
6. Configure users, locale, timezone
7. Complete installation

**Step 2: First Boot**

After installation completes, reboot:

1. ZFSBootMenu appears at boot
2. Enter encryption passphrase to unlock pool (third and final time)
3. Select boot environment from menu (default: `default`)
4. System boots to login

Subsequent boots require passphrase entry only once in ZFSBootMenu. The system
initramfs unlocks pools automatically using the keyfile.

### Post-Installation

The system configures itself during installation. No manual configuration
required. The baseline boot environment (`zroot/ROOT/baseline`) provides a
factory-fresh fallback if needed.

To verify installation:

```bash
# Check boot environments
zfs list -r zroot/ROOT

# Check user home delegation
zfs list -r zroot/data/home
zfs allow zroot/data/home/$(whoami)

# Check pacman hooks installed
ls /etc/pacman.d/hooks/zfs-*.hook
```

## Boot Environments

The system creates boot environments automatically before package updates that
affect the kernel, ZFS modules, or bootloader. Each boot environment is a
snapshot of the root filesystem at a point in time.

**List boot environments:**

```bash
zfs list -r zroot/ROOT
```

**Boot from different environment:**

Reboot and select the desired environment from the ZFSBootMenu menu.

**Revert to baseline:**

The baseline environment provides a factory-fresh system state. To boot it:

1. Reboot and select `baseline` from ZFSBootMenu menu, or
2. Set it as default:

```bash
sudo zpool set bootfs=zroot/ROOT/baseline zroot
sudo reboot
```

**Automatic cleanup:**

The post-cleanup hook retains the 24 most recent boot environments by default.
Configure retention in `/etc/pacman-zfs-hooks.conf`:

```bash
# Keep 5 boot environments instead of 24
RETENTION_COUNT=5
```

## User Home Directories

Each user's home directory lives on a ZFS dataset with delegated permissions.
Users can create snapshots, set compression, and manage quotas without root
access.

**Create home directory snapshot:**

```bash
zfs snapshot zroot/data/home/$(whoami)@backup
```

**List snapshots:**

```bash
zfs list -t snapshot -r zroot/data/home/$(whoami)
```

**Restore from snapshot:**

```bash
zfs rollback zroot/data/home/$(whoami)@backup
```

**Access snapshot contents:**

```bash
ls ~/.zfs/snapshot/backup/
```

**Set compression on your dataset:**

```bash
zfs set compression=zstd zroot/data/home/$(whoami)
```

Delegated permissions include: `compression`, `mountpoint`, `create`, `mount`,
`snapshot`, `destroy`, `send`, `receive`, `hold`, `release`. Users cannot change
encryption, quota, or other security-sensitive properties.

## Prior Art and References

This installer builds on work by several communities:

**ZFSBootMenu**

- [ZFSBootMenu Documentation][zfsbootmenu-docs] - Primary reference for
  bootloader configuration
- [Native Encryption Guide][zfsbootmenu-encryption] - Explains keyfile setup for
  kexec compatibility
- [UEFI Booting Guide][zfsbootmenu-uefi] - Unified EFI image configuration

**Arch Linux ZFS**

- [ArchZFS Project][archzfs] - Provides ZFS packages for Arch-based
  distributions
- [Arch Wiki: ZFS][archwiki-zfs] - General ZFS configuration guidance
- [Install Arch Linux on ZFS][archwiki-install] - Manual installation process
  this installer automates

**Boot Environment Management**

- [FreeBSD Boot Environments][freebsd-be] - Original implementation of boot
  environments
- [Solaris/Illumos ZFS Boot Environments][illumos-be] - Enterprise-grade boot
  environment patterns
- [NixOS System Profiles][nixos-profiles] - Similar concept in declarative
  configuration system

**CachyOS**

- [CachyOS Project][cachyos] - Performance-optimized Arch Linux distribution
- [CachyOS Calamares][cachyos-calamares] - Customized installer used as base

**Related Projects**

- [zfsbootmenu-uki][zfsbootmenu-uki] - Alternative unified kernel image approach
- [ZFSBootMenu Dracut Module][dracut-zfsbootmenu] - Dracut-based integration
  (this project uses mkinitcpio)

## Code of Conduct

This project adheres to the Contributor Covenant [code of
conduct][code-of-conduct]. By participating, you are expected to uphold this
code. Please report unacceptable behavior to fnichol@nichol.ca.

## Issues

If you have problems or questions about this project, please contact us through
a [GitHub issue][issues].

## Contributing

You are invited to contribute features, fixes, or updates. We accept pull
requests of any size and process them as quickly as possible.

Before you start coding, discuss your plans through a [GitHub issue][issues],
especially for ambitious contributions. This gives other contributors a chance
to point you in the right direction, give feedback on your design, and help you
discover if someone else is working on the same thing.

## Authors

Created and maintained by [Fletcher Nichol][fnichol] (<fnichol@nichol.ca>).

## License

Licensed under the Mozilla Public License Version 2.0 ([LICENSE.txt][license]).

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in the work by you, as defined in the MPL-2.0 license, shall be
licensed as above, without any additional terms or conditions.

[archzfs]: https://github.com/archzfs/archzfs
[archwiki-install]: https://wiki.archlinux.org/title/Install_Arch_Linux_on_ZFS
[archwiki-zfs]: https://wiki.archlinux.org/title/ZFS
[badge-ci-overall]:
  https://img.shields.io/cirrus/github/fnichol/cachyos-zfs-installer.svg?style=flat-square
[badge-license]: https://img.shields.io/badge/License-MPL%202.0%20-blue.svg
[cachyos]: https://cachyos.org/
[cachyos-calamares]: https://github.com/CachyOS/cachyos-calamares
[ci]: https://cirrus-ci.com/github/fnichol/cachyos-zfs-installer
[code-of-conduct]:
  https://github.com/fnichol/cachyos-zfs-installer/blob/main/CODE_OF_CONDUCT.md
[dracut-zfsbootmenu]: https://github.com/zbm-dev/zfsbootmenu/tree/master/dracut
[fnichol]: https://github.com/fnichol
[freebsd-be]:
  https://docs.freebsd.org/en/books/handbook/cutting-edge/#boot-environments
[github]: https://github.com/fnichol/cachyos-zfs-installer
[illumos-be]: https://illumos.org/man/8/beadm
[issues]: https://github.com/fnichol/cachyos-zfs-installer/issues
[license]:
  https://github.com/fnichol/cachyos-zfs-installer/blob/main/LICENSE.txt
[nixos-profiles]: https://nixos.org/manual/nixos/stable/#sec-rollback
[zfsbootmenu]: https://zfsbootmenu.org/
[zfsbootmenu-docs]: https://docs.zfsbootmenu.org/
[zfsbootmenu-encryption]:
  https://docs.zfsbootmenu.org/en/latest/general/native-encryption.html
[zfsbootmenu-uefi]:
  https://docs.zfsbootmenu.org/en/latest/general/uefi-booting.html
[zfsbootmenu-uki]:
  https://github.com/zbm-dev/zfsbootmenu/blob/master/docs/general/uefi-booting.rst
