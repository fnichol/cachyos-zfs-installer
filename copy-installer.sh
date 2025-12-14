#!/usr/bin/env bash

print_usage() {
  local program="$1"
  local version="$2"
  local author="$3"

  cat <<-EOF
	$program $version

	Copies CachyOS ZFS installer to live ISO.

	USAGE:
	    $program [FLAGS] <HOST>

	FLAGS:
	    -h, --help      Prints this message
	    -v, --verbose   Prints verbose output of the \`install.sh' program
	    -V, --version   Prints version information

	ARGS:
	    <HOST>      Host running the CachyOS live image.

	AUTHOR:
	    $author
	EOF
}

main() {
  set -euo pipefail
  if [[ -n "${DEBUG:-}" ]]; then set -x; fi
  if [[ -n "${TRACE:-}" ]]; then set -xv; fi

  # shellcheck source=vendor/lib/libsh.full.sh
  . "${0%/*}/vendor/lib/libsh.full.sh"

  local program version author
  program="$(basename "$0")"
  version="0.1.0"
  author="Fletcher Nichol <fnichol@nichol.ca>"

  # Parse CLI arguments and set local variables
  parse_cli_args "$program" "$version" "$author" "$@"
  local host="$HOST"
  unset HOST

  need_cmd basename
  need_cmd scp
  need_cmd ssh
  need_cmd ssh-copy-id

  authenticate "$host"
  copy_installation_files "$host"

  section "CachyOS ZFS installer files copied to $host under ~/installer"
  info "Run installer on live ISO directlywith: 'cd installer; sudo -E ./bin/install'"
}

parse_cli_args() {
  local program version author
  program="$1"
  shift
  version="$1"
  shift
  author="$1"
  shift

  OPTIND=1
  # Parse command line flags and options
  while getopts ":hV-:" opt; do
    case $opt in
      h)
        print_usage "$program" "$version" "$author"
        exit 0
        ;;
      V)
        print_version "$program" "$version"
        exit 0
        ;;
      -)
        case "$OPTARG" in
          help)
            print_usage "$program" "$version" "$author"
            exit 0
            ;;
          '')
            # "--" terminates argument processing
            break
            ;;
          *)
            print_usage "$program" "$version" "$author" >&2
            die "invalid argument --$OPTARG"
            ;;
        esac
        ;;
      \?)
        print_usage "$program" "$version" "$author" >&2
        die "invalid option: -$OPTARG"
        ;;
    esac
  done
  # Shift off all parsed token in `$*` so that the subcommand is now `$1`.
  shift "$((OPTIND - 1))"

  if [[ -z "${1:-}" ]]; then
    print_usage "$program" "$version" "$author" >&2
    die "required argument: <HOST>"
  fi
  HOST="$1"
  shift
}

authenticate() {
  local host="$1"

  section "Authenticating 'liveuser@$host'"
  ssh-copy-id \
    -f \
    -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=no \
    "liveuser@$host"
}

copy_installation_files() {
  local host="$1"

  section "Uploading installation files"
  ssh \
    -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=no \
    -t \
    "liveuser@$host" \
    mkdir installer
  scp \
    -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=no \
    -r \
    ./bin \
    ./conf \
    ./lib \
    ./vendor \
    "liveuser@$host:installer"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@" || exit 99
fi
