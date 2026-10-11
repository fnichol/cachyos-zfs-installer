#!/usr/bin/env bash

oneTimeSetUp() {
  commonOneTimeSetUp
}

setUp() {
  commonSetUp

  ZFS_FIXTURES="$tmpdir/zfs"
  export ZFS_FIXTURES
  mkdir -p "$ZFS_FIXTURES" "$isolated_path"
  cp "$SRC_ROOT/tests/fixtures/zfs_stub.sh" "$isolated_path/zfs"
  chmod +x "$isolated_path/zfs"
  PATH="$isolated_path:$PATH"

  # shellcheck source=src/pacman-zfs/usr/local/lib/pacman-zfs-common.sh
  . "$SRC_ROOT/src/pacman-zfs/usr/local/lib/pacman-zfs-common.sh"

  ZFS_ROOT_POOL="zroot/ROOT"
  RETENTION_COUNT=2

  be1="zroot/ROOT/be-20260101-000000-pre-upgrade"
  be2="zroot/ROOT/be-20260102-000000-pre-install"
  be3="zroot/ROOT/be-20260103-000000-pre-kernel"
  be4="zroot/ROOT/be-20260104-000000-pre-mixed"
}

# Appends a filesystem (in creation order) with an optional origin snapshot.
addFilesystem() {
  printf '%s\t%s\n' "$1" "${2:--}" >>"$ZFS_FIXTURES/filesystems"
}

# Appends a snapshot with its comma-separated clones (`-` when omitted).
addSnapshot() {
  printf '%s\t%s\n' "$1" "${2--}" >>"$ZFS_FIXTURES/snapshots"
}

# Makes `zfs destroy` fail for the given dataset.
mockDestroyFailure() {
  echo "$1" >>"$ZFS_FIXTURES/destroy_fail"
}

assertDestroyCalls() {
  assertEquals 'zfs destroy calls' "$1" \
    "$(cat "$ZFS_FIXTURES/calls.log" 2>/dev/null || true)"
}

testIsBootEnvSnapshotMatchesHookSnapshots() {
  local snapshot

  for snapshot in \
    "zroot/ROOT/default@be-20260101-000000-pre-upgrade" \
    "zroot/ROOT/default@be-20260101-000000-pre-install" \
    "zroot/ROOT/default@be-20260101-000000-pre-remove" \
    "zroot/ROOT/default@be-20260101-000000-pre-mixed" \
    "$be1@be-20260101-000000-pre-kernel"; do
    is_boot_env_snapshot "$snapshot"
    assertTrue "should match: $snapshot" $?
  done
}

testIsBootEnvSnapshotRejectsOtherSnapshots() {
  local snapshot

  for snapshot in \
    "zroot/ROOT/default@baseline" \
    "zroot/ROOT/default@be-manual" \
    "zroot/ROOT/default@be-20260101-000000-pre-upgrade-keep" \
    "zroot/ROOT/default@before-upgrade" \
    "$be1"; do
    is_boot_env_snapshot "$snapshot"
    assertFalse "should not match: $snapshot" $?
  done
}

testSelectNothingWithinRetention() {
  addFilesystem "zroot/ROOT/default"
  addFilesystem "$be1"
  addFilesystem "$be2"

  run select_boot_envs_to_prune "default"

  assertTrue 'function failed' "$return_status"
  assertStdoutNull
  assertStderrNull
}

testSelectOldestBeyondRetention() {
  addFilesystem "zroot/ROOT/default"
  addFilesystem "zroot/ROOT/baseline" "zroot/ROOT/default@baseline"
  addFilesystem "$be1"
  addFilesystem "$be2"
  addFilesystem "$be3"
  addFilesystem "$be4"

  run select_boot_envs_to_prune "default"

  assertTrue 'function failed' "$return_status"
  assertStdoutEquals "$(printf '%s\n' "$be1" "$be2")"
  assertStderrNull
}

testSelectIgnoresSnapshotsWithoutClones() {
  addFilesystem "$be1"
  addFilesystem "$be2"
  addFilesystem "$be3"
  addSnapshot "$be1@be-20260105-000000-pre-upgrade" "-"

  run select_boot_envs_to_prune "default"

  assertTrue 'function failed' "$return_status"
  assertStdoutEquals "$be1"
}

testSelectSkipsCurrentBootEnv() {
  addFilesystem "$be1"
  addFilesystem "$be2"
  addFilesystem "$be3"
  addFilesystem "$be4"

  run select_boot_envs_to_prune "be-20260101-000000-pre-upgrade"

  assertTrue 'function failed' "$return_status"
  assertStdoutEquals "$(printf '%s\n' "$be2" "$be3")"
  assertStderrContains \
    'Skipping be-20260101-000000-pre-upgrade: currently booted'
}

testSelectSkipsBootEnvWithDependentClones() {
  addFilesystem "$be1"
  addFilesystem "$be2"
  addFilesystem "$be3" "$be1@be-20260103-000000-pre-kernel"
  addFilesystem "$be4"
  addSnapshot "$be1@be-20260103-000000-pre-kernel" "$be3"

  run select_boot_envs_to_prune "default"

  assertTrue 'function failed' "$return_status"
  assertStdoutEquals "$(printf '%s\n' "$be2" "$be3")"
  assertStderrContains \
    'Skipping be-20260101-000000-pre-upgrade: has dependent clones'
}

testSelectWarnsWhenTooFewEligible() {
  RETENTION_COUNT=1

  # Booted be1, upgraded (cloning be2 from be1), then booted be2
  addFilesystem "$be1"
  addFilesystem "$be2" "$be1@be-20260102-000000-pre-install"
  addSnapshot "$be1@be-20260102-000000-pre-install" "$be2"

  run select_boot_envs_to_prune "be-20260102-000000-pre-install"

  assertTrue 'function failed' "$return_status"
  assertStdoutNull
  assertStderrContains 'only 0 of 1 boot environment'
}

testDestroyBootEnvRemovesOrphanedOrigin() {
  local origin="zroot/ROOT/default@be-20260101-000000-pre-upgrade"

  addFilesystem "$be1" "$origin"
  addSnapshot "$origin" "-"

  run destroy_boot_env "$be1"

  assertTrue 'function failed' "$return_status"
  assertDestroyCalls "$(printf '%s\n' "destroy -r $be1" "destroy $origin")"
  assertStdoutContains "Removed snapshot: $origin"
}

testDestroyBootEnvKeepsOriginWithRemainingClones() {
  local origin="zroot/ROOT/default@be-20260101-000000-pre-upgrade"

  addFilesystem "$be1" "$origin"
  addSnapshot "$origin" "zroot/ROOT/other"

  run destroy_boot_env "$be1"

  assertTrue 'function failed' "$return_status"
  assertDestroyCalls "destroy -r $be1"
}

testDestroyBootEnvKeepsNonHookOrigin() {
  addFilesystem "$be1" "zroot/ROOT/default@baseline"
  addSnapshot "zroot/ROOT/default@baseline" "-"

  run destroy_boot_env "$be1"

  assertTrue 'function failed' "$return_status"
  assertDestroyCalls "destroy -r $be1"
}

testDestroyBootEnvWithoutOrigin() {
  # A promoted boot environment has no origin
  addFilesystem "$be1" "-"

  run destroy_boot_env "$be1"

  assertTrue 'function failed' "$return_status"
  assertDestroyCalls "destroy -r $be1"
}

testDestroyBootEnvReportsFailure() {
  local origin="zroot/ROOT/default@be-20260101-000000-pre-upgrade"

  addFilesystem "$be1" "$origin"
  addSnapshot "$origin" "-"
  mockDestroyFailure "$be1"

  run destroy_boot_env "$be1"

  assertFalse 'function should fail' "$return_status"
  assertDestroyCalls "destroy -r $be1"
  assertStderrContains "Failed to destroy boot environment: $be1"
}

testSweepRemovesOrphanedSnapshots() {
  addSnapshot "zroot/ROOT/default@baseline" "zroot/ROOT/baseline"
  addSnapshot "zroot/ROOT/default@be-20260101-000000-pre-upgrade" "-"
  addSnapshot "zroot/ROOT/default@be-20260102-000000-pre-install" "$be2"
  addSnapshot "$be2@be-20260103-000000-pre-kernel" "-"

  run sweep_orphaned_snapshots

  assertTrue 'function failed' "$return_status"
  assertDestroyCalls "$(printf '%s\n' \
    "destroy zroot/ROOT/default@be-20260101-000000-pre-upgrade" \
    "destroy $be2@be-20260103-000000-pre-kernel")"
  assertStdoutContains 'Removed 2 orphaned snapshot'
}

testSweepTreatsEmptyClonesAsOrphaned() {
  addSnapshot "zroot/ROOT/default@be-20260101-000000-pre-upgrade" ""

  run sweep_orphaned_snapshots

  assertTrue 'function failed' "$return_status"
  assertDestroyCalls \
    "destroy zroot/ROOT/default@be-20260101-000000-pre-upgrade"
}

testSweepKeepsNonHookSnapshots() {
  addSnapshot "zroot/ROOT/default@baseline" "-"
  addSnapshot "zroot/ROOT/default@be-manual" "-"
  addSnapshot "zroot/ROOT/default@be-20260101-000000-pre-upgrade-keep" "-"

  run sweep_orphaned_snapshots

  assertTrue 'function failed' "$return_status"
  assertDestroyCalls ""
  assertStdoutNull
}

testSweepContinuesAfterFailure() {
  local first="zroot/ROOT/default@be-20260101-000000-pre-upgrade"
  local second="zroot/ROOT/default@be-20260102-000000-pre-install"

  addSnapshot "$first" "-"
  addSnapshot "$second" "-"
  mockDestroyFailure "$first"

  run sweep_orphaned_snapshots

  assertTrue 'function failed' "$return_status"
  assertDestroyCalls "$(printf '%s\n' "destroy $first" "destroy $second")"
  assertStderrContains "Failed to destroy snapshot: $first"
  assertStdoutContains "Removed orphaned snapshot: $second"
}

# shellcheck source=tests/test_helpers.sh
. "${0%/*}/test_helpers.sh"

# shellcheck source=/dev/null
. "$shunit2"
