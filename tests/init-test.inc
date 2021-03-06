#!/bin/bash
# Author: Daniele Rondina, geaaru@sabayonlinux.org

reset_sark_envs () {
  REPOSITORY_DESCRIPTION=""
  KEEP_PREVIOUS_VERSIONS=""
  TOREMOVE=""
  TOREMOVE_BEFORE=""
  EIT_REMOVE_OPTS=""
  CLEAN_CACHE=""
  CHECK_BUILD_DIFFS=""
  SHARE_WORKSPACE=""
  BUILD_ARGS=""
  BUILD_INJECTED_ARGS=""
  BUILDER_VERBOSE=""
  DOCKER_IMAGE=""
  DOCKER_EIT_IMAGE=""
  EMERGE_DEFAULTS_ARGS=""
  EMERGE_SPLIT_INSTALL=""
  FEATURES=""
  BUILDER_PROFILE=""
  BUILDER_JOBS=""
  PRESERVED_REBUILD=""
  SKIP_PORTAGE_SYNC=""
  WEBRSYNC=""
  EMERGE_REMOVE=""
  REMOTE_OVERLAY=""
  REMOTE_PORTDIR=""
  REMOVE_REMOTE_OVERLAY=""
  REMOVE_LAYMAN_OVERLAY=""
  QA_CHECKS=""
  ENMAN_ADD_SELF=""
  ENMAN_REPOSITORIES=""
  REMOVE_ENMAN_REPOSITORIES=""
  ENTROPY_REPOSITORY=""
  USE_EQUO=""
  EQUO_INSTALL_ATOMS=""
  DEPENDENCY_SCAN_DEPTH=""
  PRUNE_VIRTUALS=""
  EQUO_INSTALL_VERSION=""
  EQUO_SPLIT_INSTALL=""
  EQUO_MASKS=""
  EQUO_UNMASKS=""
  ETP_NOCACHE=""
  PRE_SCRIPT_COMMANDS=""
  POST_SCRIPT_COMMANDS=""
}

include_sark_files () {
  local dir=`dirname $0`

  source $dir/../sark-functions.sh
}

# vim: ts=2 sw=2 expandtab filetype=sh
