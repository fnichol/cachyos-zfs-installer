# CachyOS ZFS Installer

|         |                                           |
| ------: | ----------------------------------------- |
|      CI | [![CI Status][badge-ci-overall]][ci]      |
| License | [![Crate license][badge-license]][github] |

**Table of Contents**

<!-- toc -->

## Usage

### Download and Run Installer

This program needs to run in a shell on the CachyOS live ISO environment as the
root user, allowing it to run `pacman` commands etc.

```sh
curl -sSf https://fnichol.github.io/cachyos-zfs-installer/run.sh | sudo -E bash -s --
```

### `install`

You can use the `-h`/`--help` flag to get:

```console
install 0.1.0

CachyOS ZFS installer.

USAGE:
    install [FLAGS]

FLAGS:
    -h, --help        Prints help information
    -V, --version     Prints version information

AUTHOR:
    Fletcher Nichol <fnichol@nichol.ca>
```

### `copy-installer.sh`

You can use the `-h`/`--help` flag to get:

```sh
./copy-installer.sh --help

```

## References

TBD

## Code of Conduct

This project adheres to the Contributor Covenant [code of
conduct][code-of-conduct]. By participating, you are expected to uphold this
code. Please report unacceptable behavior to fnichol@nichol.ca.

## Issues

If you have any problems with or questions about this project, please contact us
through a [GitHub issue][issues].

## Contributing

You are invited to contribute to new features, fixes, or updates, large or
small; we are always thrilled to receive pull requests, and do our best to
process them as fast as we can.

Before you start to code, we recommend discussing your plans through a [GitHub
issue][issues], especially for more ambitious contributions. This gives other
contributors a chance to point you in the right direction, give you feedback on
your design, and help you find out if someone else is working on the same thing.

## Authors

Created and maintained by [Fletcher Nichol][fnichol] (<fnichol@nichol.ca>).

## License

Licensed under the Mozilla Public License Version 2.0 ([LICENSE.txt][license]).

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in the work by you, as defined in the MPL-2.0 license, shall be
licensed as above, without any additional terms or conditions.

[badge-check-format]:
  https://img.shields.io/cirrus/github/fnichol/cachyos-zfs-installer.svg?style=flat-square&task=check&script=format
[badge-check-lint]:
  https://img.shields.io/cirrus/github/fnichol/cachyos-zfs-installer.svg?style=flat-square&task=check&script=lint
[badge-ci-overall]:
  https://img.shields.io/cirrus/github/fnichol/cachyos-zfs-installer.svg?style=flat-square
[badge-license]: https://img.shields.io/badge/License-MPL%202.0%20-blue.svg
[ci]: https://cirrus-ci.com/github/fnichol/cachyos-zfs-installer
[ci-main]: https://cirrus-ci.com/github/fnichol/cachyos-zfs-installer/main
[code-of-conduct]:
  https://github.com/fnichol/cachyos-zfs-installer/blob/main/CODE_OF_CONDUCT.md
[fnichol]: https://github.com/fnichol
[github]: https://github.com/fnichol/cachyos-zfs-installer
[issues]: https://github.com/fnichol/cachyos-zfs-installer/issues
[license]:
  https://github.com/fnichol/cachyos-zfs-installer/blob/main/LICENSE.txt
