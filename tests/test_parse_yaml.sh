#!/bin/bash
# Author: Daniele Rondina, geaaru@sabayonlinux.org

testdir=`dirname $0`

. $testdir/init-test.inc

include_sark_files

testParse1 () {

  reset_sark_envs

  load_env_from_yaml ${testdir}/examples/build1.yaml

  local features="assume-digests binpkg-logs -userpriv config-protect-if-modified distlocks ebuild-locks fixlafiles merge-sync parallel-fetch preserve-libs protect-owned sandbox sfperms splitdebug strict"

  assertEquals "Sabayon Community SCR" "${REPOSITORY_DESCRIPTION}" || return 1
  assertEquals "app-misc/neofetch" "${TOREMOVE}" || return 1
  assertEquals "$features" "${FEATURES}" || return 1

  # TO COMPLETE
  return 0
}

testOverrideTargets () {

  reset_sark_envs

  OVERRIDE_BUILD_TARGET="sys-devel/gcc"
  OVERRIDE_BUILDER_JOBS="1"

  load_env_from_yaml ${testdir}/examples/build1.yaml

  assertEquals "$OVERRIDE_BUILD_TARGET" "${BUILD_TARGET}" || return 1
  assertEquals "$OVERRIDE_BUILDER_JOBS" "${BUILDER_JOBS}" || return 1

  return 0
}


. shunit2
