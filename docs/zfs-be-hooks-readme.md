# ZFS Boot Environment Hooks

Automatic ZFS boot environment creation for CachyOS using pacman hooks.

## What This Does

Before any package installation, upgrade, or removal, the system automatically:

1. **Creates a boot environment** - A ZFS snapshot + clone of your current
   system state
2. **Tags it with metadata** - Records what packages changed and which kernel
   was running
3. **Makes it bootable** - Adds it to ZFSBootMenu for easy recovery
4. **Cleans up old BEs** - Keeps only the configured number of boot environments
5. **Updates boot menu** - Regenerates ZFSBootMenu when needed

## Why This Matters

- **Safety**: Every package change gets a snapshot you can boot back to
- **Transparency**: Uses only native `zfs` commands (no third-party tools)
- **Reliability**: Transaction aborts if BE creation fails (no BE = no upgrade)
- **Efficiency**: ZFS copy-on-write means snapshots are fast and space-efficient
- **Debuggability**: Each BE is tagged with package info and kernel version

## Architecture

Three components work together:

1. **Pre-transaction hook** (`/etc/pacman.d/hooks/zfs-pre-upgrade.hook`)
   - Triggers: Before any package install/upgrade
   - Runs: `/usr/local/bin/pacman-zfs-pre`
   - Action: Creates boot environment, aborts on failure

2. **Post-transaction hook** (`/etc/pacman.d/hooks/zfs-post-cleanup.hook`)
   - Triggers: After package install/upgrade completes
   - Runs: `/usr/local/bin/pacman-zfs-post`
   - Action: Cleans old BEs, regenerates ZFSBootMenu

3. **Configuration file** (`/etc/pacman-zfs-hooks.conf`)
   - Settings: Retention count, ZFS pool path
   - User-editable for customization

## Boot Environment Naming

Format: `be-YYYYMMDD-HHMMSS-pre-TYPE`

Types:

- `kernel` - Boot-critical changes (kernel, ZFS modules, microcode)
- `upgrade` - Package upgrades only
- `install` - New package installations only
- `remove` - Package removals only
- `mixed` - Any combination of installs, upgrades, and/or removals

Examples:

```
zroot/ROOT/be-20251216-050436-pre-kernel
zroot/ROOT/be-20251216-123045-pre-upgrade
zroot/ROOT/be-20251216-143022-pre-install
zroot/ROOT/be-20251216-154500-pre-remove
zroot/ROOT/be-20251216-181234-pre-mixed
```

## Configuration

Edit `/etc/pacman-zfs-hooks.conf`:

```bash
# Number of boot environments to retain (default: 24)
RETENTION_COUNT=24

# ZFS pool and ROOT dataset path (no trailing slash)
ZFS_ROOT_POOL="zroot/ROOT"
```

Current boot environment is auto-detected from the root mountpoint.

## Usage

### Automatic (Recommended)

Just use pacman normally. The hooks run automatically:

```bash
sudo pacman -Syu     # System upgrade creates BE automatically
sudo pacman -S vim   # Package install creates BE automatically
sudo pacman -R vim   # Package removal creates BE automatically
```

### Viewing Boot Environments

```bash
# List all boot environments
zfs list -t filesystem | grep /be-

# Show with creation time
zfs list -t filesystem -s creation | grep /be-

# Show with descriptions
zfs get org.zfsbootmenu:description zroot/ROOT/be-*

# Show with kernel versions
zfs get org.zfsbootmenu:kernel zroot/ROOT/be-*
```

### Booting from a Different BE

1. Reboot your system
2. ZFSBootMenu appears
3. Select desired boot environment
4. Press Enter to boot

### Rolling Back Permanently

From ZFSBootMenu or after booting a different BE:

```bash
# Check current BE
zfs list -o name,mountpoint | grep "/$"

# Set desired BE as default
sudo zpool set bootfs=zroot/ROOT/be-20251216-050436-pre-kernel zroot
```

## File Structure

```
/etc/
  pacman.d/
    hooks/
      zfs-pre-upgrade.hook       # Pre-transaction hook definition
      zfs-post-cleanup.hook      # Post-transaction hook definition
  pacman-zfs-hooks.conf          # Configuration file

/usr/local/
  bin/
    pacman-zfs-pre               # Pre-transaction script
    pacman-zfs-post              # Post-transaction script
  lib/
    pacman-zfs-common.sh         # Shared library functions
```

## Testing

Run the integration tests:

```bash
cd ~/installer
./tests/test-integration.sh
```

## Troubleshooting

### Hook not running

Check hook files exist and are readable:

```bash
ls -la /etc/pacman.d/hooks/zfs-*.hook
```

### BE creation fails

Check ZFS pool name matches config:

```bash
cat /etc/pacman-zfs-hooks.conf
zfs list
```

### Too many BEs accumulating

Adjust retention count:

```bash
sudo nano /etc/pacman-zfs-hooks.conf
# Change RETENTION_COUNT to desired value
```

## References

- [ZFSBootMenu](https://docs.zfsbootmenu.org/)
- [Pacman Hooks](https://man.archlinux.org/man/alpm-hooks.5)
- [ZFS Properties](https://openzfs.github.io/openzfs-docs/man/master/7/zfsprops.7.html)
