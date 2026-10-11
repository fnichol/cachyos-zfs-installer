#!/usr/bin/env bash
# Test helper utilities for shUnit2

# shellcheck disable=SC2034
commonOneTimeSetUp() {
  set -u

  # Define root of project tree
  SRC_ROOT="${0%/*}/.."

  __ORIG_FLAGS="$-"
  __ORIG_PATH="$PATH"
  __ORIG_PWD="$(pwd)"

  tmpdir="$SHUNIT_TMPDIR/tmp"

  stdout="$tmpdir/stdout"
  stderr="$tmpdir/stderr"
  isolated_path="$tmpdir/isolated_path"
}

commonSetUp() {
  # Reset set flags to its original value
  set "-$__ORIG_FLAGS"
  # Reset the value of $PATH to its original value
  PATH="$__ORIG_PATH"
  # Restore the original working directory
  cd "$__ORIG_PWD" || return 1
  # Clean any prior test file/directory state
  rm -rf "$tmpdir"
  # Unset any prior test variable state
  unset return_status
  # Create a scratch directory that will be removed on every test
  mkdir -p "$tmpdir"
}

assertStdoutEquals() {
  if [ "$#" -eq 2 ]; then
    assertEquals "$1" "$2" "$(cat "$stdout")"
  else
    assertEquals 'stdout not equal' "$1" "$(cat "$stdout")"
  fi
}

assertStdoutContains() {
  if [ "$#" -eq 2 ]; then
    assertTrue "$1" "grep -E '$2' <'$stdout'"
  else
    assertTrue 'stdout does not contain' "grep -E '$1' <'$stdout'"
  fi
}

assertStdoutNull() {
  assertTrue 'stdout is not empty' "[ ! -s '$stdout' ]"
}

assertStderrContains() {
  if [ "$#" -eq 2 ]; then
    assertTrue "$1" "grep -E '$2' <'$stderr'"
  else
    assertTrue 'stderr does not contain' "grep -E '$1' <'$stderr'"
  fi
}

assertStderrNull() {
  assertTrue 'stderr is not empty' "[ ! -s '$stderr' ]"
}

# Run command and capture stdout/stderr
run() {
  # Implementation inspired by `run` in bats
  # See: https://git.io/fjCcr
  _origFlags="$-"
  set +eET
  "$@" >"$stdout" 2>"$stderr"
  return_status=$?
  set "-$_origFlags"
  unset _origFlags

  return "$return_status"
}

debugLastRun() {
  echo "======================"
  echo "Last 'run' invocation:"
  echo "----------------------"
  echo
  echo "return_status=$return_status"
  echo
  echo "stdout:"
  echo "---"
  cat "$stdout"
  echo "---"
  echo
  echo "stderr:"
  echo "---"
  cat "$stderr"
  echo "---"
  echo "======================"
}

# shellcheck disable=SC2034
shunit2RelRoot="tmp/shunit2/shunit2"
shunit2="${0%/*}/../$shunit2RelRoot"
