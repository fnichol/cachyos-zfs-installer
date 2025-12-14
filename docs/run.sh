#!/usr/bin/env bash

print_usage() {
  local program="$1"
  local version="$2"
  local author="$3"

  cat <<-EOF
	$program $version

	Downloads and runs CachyOS ZFS installer on live ISO.

	USAGE:
	    $program [FLAGS] <ARGS>...

	FLAGS:
	    -h, --help      Prints this message
	    -v, --verbose   Prints verbose output of the \`install.sh' program
	    -V, --version   Prints version information

	ARGS:
	    <ARGS>      Arguments are passed to the \`install' program.

	AUTHOR:
	    $author
	EOF
}

main() {
  set -euo pipefail
  if [[ -n "${DEBUG:-}" ]]; then set -x; fi
  if [[ -n "${TRACE:-}" ]]; then set -xv; fi

  local program version author
  program="cachyos-zfs-installer-run"
  version="0.1.0"
  author="Fletcher Nichol <fnichol@nichol.ca>"

  local repo="fnichol/cachyos-zfs-installer"
  local branch="main"
  local asset_url="https://github.com/$repo/archive/refs/heads/$branch.tar.gz"

  # Parse CLI arguments and set local variables
  parse_cli_args "$program" "$version" "$author" "$@"
  local args=("${ARGS[@]}")
  unset ARGS

  setup_cleanups
  setup_traps trap_cleanups

  need_cmd basename
  need_cmd tar

  local tmpdir
  tmpdir="$(mktemp_directory)"
  cleanup_directory "$tmpdir"

  local codedir tarball
  codedir="$tmpdir/$(basename "$repo")-$branch"
  tarball="$codedir.tar.gz"

  download "$asset_url" "$tarball"
  tar xzf "$tarball" -C "$tmpdir"

  section "Running installer on live ISO"
  cd "$codedir"
  ./bin/install "${args[@]}"
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
          version)
            print_version "$program" "$version" "true"
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

  ARGS=("$@")
}

# BEGIN: libsh.sh

#
# Copyright 2019 Fletcher Nichol and/or applicable contributors.
#
# Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
# http://www.apache.org/licenses/LICENSE-2.0> or the MIT license (see
# <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your option. This
# file may not be copied, modified, or distributed except according to those
# terms.
#
# libsh.sh
# --------
# project: https://github.com/fnichol/libsh
# author: Fletcher Nichol <fnichol@nichol.ca>
# version: 0.10.1
# distribution: libsh.full-minified.sh
# commit-hash: 46134771903ba66967666ca455f73ffc10dd0a03
# commit-date: 2021-05-08
# artifact: https://github.com/fnichol/libsh/releases/download/v0.10.1/libsh.full.sh
# source: https://github.com/fnichol/libsh/tree/v0.10.1
# archive: https://github.com/fnichol/libsh/archive/v0.10.1.tar.gz
#
if [ -n "${KSH_VERSION:-}" ]; then
  eval "local() { return 0; }"
fi
# shellcheck disable=SC2120
mktemp_directory() {
  need_cmd mktemp
  if [ -n "${1:-}" ]; then
    mktemp -d "$1/tmp.XXXXXX"
  else
    mktemp -d 2>/dev/null || mktemp -d -t tmp
  fi
}
# shellcheck disable=SC2120
mktemp_file() {
  need_cmd mktemp
  if [ -n "${1:-}" ]; then
    mktemp "$1/tmp.XXXXXX"
  else
    mktemp 2>/dev/null || mktemp -t tmp
  fi
}
trap_cleanup_files() {
  set +e
  if [ -n "${__CLEANUP_FILES__:-}" ] && [ -f "$__CLEANUP_FILES__" ]; then
    local _file
    while read -r _file; do
      rm -f "$_file"
    done <"$__CLEANUP_FILES__"
    unset _file
    rm -f "$__CLEANUP_FILES__"
  fi
}
need_cmd() {
  if ! check_cmd "$1"; then
    die "Required command '$1' not found on PATH"
  fi
}
trap_cleanups() {
  set +e
  trap_cleanup_directories
  trap_cleanup_files
}
print_version() {
  local _program _version _verbose _sha _long_sha _date
  _program="$1"
  _version="$2"
  _verbose="${3:-false}"
  _sha="${4:-}"
  _long_sha="${5:-}"
  _date="${6:-}"
  if [ -z "$_sha" ] || [ -z "$_long_sha" ] || [ -z "$_date" ]; then
    if check_cmd git \
      && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      if [ -z "$_sha" ]; then
        _sha="$(git show -s --format=%h)"
        if ! git diff-index --quiet HEAD --; then
          _sha="${_sha}-dirty"
        fi
      fi
      if [ -z "$_long_sha" ]; then
        _long_sha="$(git show -s --format=%H)"
        case "$_sha" in
          *-dirty) _long_sha="${_long_sha}-dirty" ;;
        esac
      fi
      if [ -z "$_date" ]; then
        _date="$(git show -s --format=%ad --date=short)"
      fi
    fi
  fi
  if [ -n "$_sha" ] && [ -n "$_date" ]; then
    echo "$_program $_version ($_sha $_date)"
  else
    echo "$_program $_version"
  fi
  if [ "$_verbose" = "true" ]; then
    echo "release: $_version"
    if [ -n "$_long_sha" ]; then
      echo "commit-hash: $_long_sha"
    fi
    if [ -n "$_date" ]; then
      echo "commit-date: $_date"
    fi
  fi
  unset _program _version _verbose _sha _long_sha _date
}
warn() {
  case "${TERM:-}" in
    *term | alacritty | rxvt | screen | screen-* | tmux | tmux-* | xterm-*)
      printf -- "\033[1;31;40m!!! \033[1;37;40m%s\033[0m\n" "$1"
      ;;
    *)
      printf -- "!!! %s\n" "$1"
      ;;
  esac
}
section() {
  case "${TERM:-}" in
    *term | alacritty | rxvt | screen | screen-* | tmux | tmux-* | xterm-*)
      printf -- "\033[1;36;40m--- \033[1;37;40m%s\033[0m\n" "$1"
      ;;
    *)
      printf -- "--- %s\n" "$1"
      ;;
  esac
}
setup_cleanup_directories() {
  if [ "${__CLEANUP_DIRECTORIES_SETUP__:-}" != "$$" ]; then
    unset __CLEANUP_DIRECTORIES__
    __CLEANUP_DIRECTORIES_SETUP__="$$"
    export __CLEANUP_DIRECTORIES_SETUP__
  fi
  if [ -z "${__CLEANUP_DIRECTORIES__:-}" ]; then
    __CLEANUP_DIRECTORIES__="$(mktemp_file)"
    if [ -z "$__CLEANUP_DIRECTORIES__" ]; then
      return 1
    fi
    export __CLEANUP_DIRECTORIES__
  fi
}
setup_cleanup_files() {
  if [ "${__CLEANUP_FILES_SETUP__:-}" != "$$" ]; then
    unset __CLEANUP_FILES__
    __CLEANUP_FILES_SETUP__="$$"
    export __CLEANUP_FILES_SETUP__
  fi
  if [ -z "${__CLEANUP_FILES__:-}" ]; then
    __CLEANUP_FILES__="$(mktemp_file)"
    if [ -z "$__CLEANUP_FILES__" ]; then
      return 1
    fi
    export __CLEANUP_FILES__
  fi
}
setup_cleanups() {
  setup_cleanup_directories
  setup_cleanup_files
}
setup_traps() {
  local _sig
  for _sig in HUP INT QUIT ALRM TERM; do
    trap "
      $1
      trap - $_sig EXIT
      kill -s $_sig "'"$$"' "$_sig"
  done
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval "zshexit() { eval '$1'; }"
  else
    # shellcheck disable=SC2064
    trap "$1" EXIT
  fi
  unset _sig
}
trap_cleanup_directories() {
  set +e
  if [ -n "${__CLEANUP_DIRECTORIES__:-}" ] \
    && [ -f "$__CLEANUP_DIRECTORIES__" ]; then
    local _dir
    while read -r _dir; do
      rm -rf "$_dir"
    done <"$__CLEANUP_DIRECTORIES__"
    unset _dir
    rm -f "$__CLEANUP_DIRECTORIES__"
  fi
}
check_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    return 1
  fi
}
cleanup_directory() {
  setup_cleanup_directories
  echo "$1" >>"$__CLEANUP_DIRECTORIES__"
}
cleanup_file() {
  setup_cleanup_files
  echo "$1" >>"$__CLEANUP_FILES__"
}
die() {
  case "${TERM:-}" in
    *term | alacritty | rxvt | screen | screen-* | tmux | tmux-* | xterm-*)
      printf -- "\n\033[1;31;40mxxx \033[1;37;40m%s\033[0m\n\n" "$1" >&2
      ;;
    *)
      printf -- "\nxxx %s\n\n" "$1" >&2
      ;;
  esac
  exit 1
}
download() {
  local _url _dst _code _orig_flags
  _url="$1"
  _dst="$2"
  need_cmd sed
  if check_cmd curl; then
    info "Downloading $_url to $_dst (curl)"
    _orig_flags="$-"
    set +e
    curl -sSfL "$_url" -o "$_dst"
    _code="$?"
    # shellcheck disable=SC2001
    set "-$(echo "$_orig_flags" | sed s/s//g)"
    if [ $_code -eq 0 ]; then
      unset _url _dst _code _orig_flags
      return 0
    else
      local _e
      _e="curl failed to download file, perhaps curl doesn't have"
      _e="$_e SSL support and/or no CA certificates are present?"
      warn "$_e"
      unset _e
    fi
  fi
  if check_cmd wget; then
    info "Downloading $_url to $_dst (wget)"
    _orig_flags="$-"
    set +e
    wget -q -O "$_dst" "$_url"
    _code="$?"
    # shellcheck disable=SC2001
    set "-$(echo "$_orig_flags" | sed s/s//g)"
    if [ $_code -eq 0 ]; then
      unset _url _dst _code _orig_flags
      return 0
    else
      local _e
      _e="wget failed to download file, perhaps wget doesn't have"
      _e="$_e SSL support and/or no CA certificates are present?"
      warn "$_e"
      unset _e
    fi
  fi
  if check_cmd ftp; then
    info "Downloading $_url to $_dst (ftp)"
    _orig_flags="$-"
    set +e
    ftp -o "$_dst" "$_url"
    _code="$?"
    # shellcheck disable=SC2001
    set "-$(echo "$_orig_flags" | sed s/s//g)"
    if [ $_code -eq 0 ]; then
      unset _url _dst _code _orig_flags
      return 0
    else
      local _e
      _e="ftp failed to download file, perhaps ftp doesn't have"
      _e="$_e SSL support and/or no CA certificates are present?"
      warn "$_e"
      unset _e
    fi
  fi
  unset _url _dst _code _orig_flags
  warn "Downloading requires SSL-enabled 'curl', 'wget', or 'ftp' on PATH"
  return 1
}
indent() {
  local _ecfile _ec _orig_flags
  need_cmd cat
  need_cmd rm
  need_cmd sed
  _ecfile="$(mktemp_file)"
  _orig_flags="$-"
  set +e
  {
    "$@" 2>&1
    echo "$?" >"$_ecfile"
  } | sed 's/^/       /'
  # shellcheck disable=SC2001
  set "-$(echo "$_orig_flags" | sed s/s//g)"
  _ec="$(cat "$_ecfile")"
  rm -f "$_ecfile"
  unset _ecfile _orig_flags
  return "${_ec:-5}"
}
info() {
  case "${TERM:-}" in
    *term | alacritty | rxvt | screen | screen-* | tmux | tmux-* | xterm-*)
      printf -- "\033[1;36;40m  - \033[1;37;40m%s\033[0m\n" "$1"
      ;;
    *)
      printf -- "  - %s\n" "$1"
      ;;
  esac
}
info_end() {
  case "${TERM:-}" in
    *term | alacritty | rxvt | screen | screen-* | tmux | tmux-* | xterm-*)
      printf -- "\033[1;37;40m%s\033[0m\n" "done."
      ;;
    *)
      printf -- "%s\n" "done."
      ;;
  esac
}
info_start() {
  case "${TERM:-}" in
    *term | alacritty | rxvt | screen | screen-* | tmux | tmux-* | xterm-*)
      printf -- "\033[1;36;40m  - \033[1;37;40m%s ... \033[0m" "$1"
      ;;
    *)
      printf -- "  - %s ... " "$1"
      ;;
  esac
}

# END: libsh.sh

main "$@" || exit 99
