#!/bin/bash

# This code makes use of gnu parallel
# O. Tange (2011): GNU Parallel - The Command-Line Power Tool,
#  ;login: The USENIX Magazine, February 2011:42-47.

DOCKER_COMMIT_IMAGE=${DOCKER_COMMIT_IMAGE:-true}

VAGRANT_DIR="${VAGRANT_DIR:-/vagrant}"

export DEPLOY_PHASE=${DEPLOY_PHASE:-false}
export CREATEREPO_PHASE=${CREATEREPO_PHASE:-true}
export GENMETADATA_PHASE=${GENMETADATA_PHASE:-true}
export CLEAN_PHASE=${CLEAN_PHASE:-true}
export COMMIT_EIT_IMAGE=${COMMIT_EIT_IMAGE:-false}
export GENKEY_PHASE=${GENKEY_PHASE:-true}
export CHECK_BUILD_DIFFS=${CHECK_BUILD_DIFFS:-1}

export ENTRYPOINT="--entrypoint ${ENTRYPOINT:-/usr/sbin/builder}"
export DOCKER_OPTS="${DOCKER_OPTS:---cap-add=SYS_PTRACE -t $ENTRYPOINT}" # Remember to set --rm if DOCKER_COMMIT_IMAGE: false
export DISTFILES="${DISTFILES:-${VAGRANT_DIR}/distfiles}"
export ENTROPY_DOWNLOADED_PACKAGES="${VAGRANT_DIR}/entropycache"
export DOCKER_EIT_IMAGE="${DOCKER_EIT_IMAGE:-sabayon/eit-amd64}"
export PORTAGE_CACHE="${PORTAGE_CACHE:-${VAGRANT_DIR}/portagecache}"
export EMERGE_DEFAULTS_ARGS="${EMERGE_DEFAULTS_ARGS:---accept-properties=-interactive -t --verbose --update --noreplace --nospinner --oneshot --complete-graph --buildpkg}"
export FEATURES="parallel-fetch protect-owned userpriv -distcc -distcc-pump -splitdebug -nostrip -compressdebug"
export WEBRSYNC="${WEBRSYNC:-1}"
export REPOSITORY_SPECS="${REPOSITORY_SPECS:-https://github.com/Sabayon/community-repositories.git}"
export ARCHES="amd64"
export KEEP_PREVIOUS_VERSIONS=${KEEP_PREVIOUS_VERSIONS:-1} #you can override this in build.sh
export EMERGE_SPLIT_INSTALL=0 #by default don't split emerge installation
#Irc configs, optional.
export IRC_IDENT="${IRC_IDENT:-bot sabayon scr builder}"
export IRC_NICK="${IRC_NICK:-SCRBuilder}"
export DOCKERHUB_PUSH="${DOCKERHUB_PUSH:-0}"
export ETP_NOCACHE="${ETP_NOCACHE:-1}"
export CLEAN_CACHE="${CLEAN_CACHE:-0}"
export PRETEND="${PRETEND:-0}"
export PKGS_CHECKER_OPTS="${PKGS_CHECKER_OPTS:--L ERROR -c -v}"
export PKGS_CHECKER_BIN="${PKGS_CHECKER_BIN:-pkgs-checker}"

URI_BASE="${URI_BASE:-http://mirror.de.sabayon.org/community/}"

[ "$DOCKER_COMMIT_IMAGE" = true ]  && export DOCKER_OPTS=${DOCKER_OPTS#--rm}
[ -e ${VAGRANT_DIR}/confs/env ] && . ${VAGRANT_DIR}/confs/env

if [ "$DOCKER_COMMIT_IMAGE" = true ]; then
  export DOCKER_PULL_IMAGE=0
fi

die() { echo "$@" 1>&2 ; exit 1; }

env_parallel() {
  export PARALLEL_ENV="$(echo "shopt -s expand_aliases 2>/dev/null"; alias;typeset -p |
  grep -vFf <(readonly) |
  grep -v 'declare .. (GROUPS|FUNCNAME|DIRSTACK|_|PIPESTATUS|USERNAME|BASH_[A-Z_]+) ';
typeset -f)";
`which parallel` --will-cite "$@";
unset PARALLEL_ENV;
}

update_repositories() {
REPOSITORIES=( $(find ${VAGRANT_DIR}/repositories -maxdepth 1 -type d -printf '%P\n' | grep -v '^\.' | sort) )
export REPOSITORIES
}

update_vagrant_repo() {
pushd ${VAGRANT_DIR}
git fetch --all
git reset --hard origin/master
rm -rf ${VAGRANT_DIR}/repositories
git clone ${REPOSITORY_SPECS} ${VAGRANT_DIR}/repositories
[ -z "${REPOSITORIES}" ] && update_repositories
popd
}

irc_msg() {

local IRC_MESSAGE="${1}"

[ -z "$IRC_MESSAGE" ] && return 1
[ -z "$IRC_CHANNEL" ] && return 1

echo -e "USER ${IRC_IDENT}\nNICK ${IRC_NICK}${RANDOM}\nJOIN ${IRC_CHANNEL}\nPRIVMSG ${IRC_CHANNEL} :${IRC_MESSAGE}\nQUIT\n" \
| nc irc.freenode.net 6667 > /dev/null || true

}

deploy() {

local ARTIFACTS="${1}"
local SERVER="${2}"
local PORT="${3}"
# soft quit. deploy is optional for now
[ -z "$ARTIFACTS" ] && exit 0
[ -z "$SERVER" ] && exit 0
[ -z "$PORT" ] && exit 0
rsync -avPz --delete -e "ssh -q -p $PORT" $ARTIFACTS/* $SERVER

}

system_upgrade() {
# upgrade
# rsync -av -H -A -X --delete-during "rsync://rsync.at.gentoo.org/gentoo-portage/licenses/" "/usr/portage/licenses/"
# ls /usr/portage/licenses -1 | xargs -0 > /etc/entropy/packages/license.accept
# equo up && equo u
# echo -5 | equo conf update
bash ${VAGRANT_DIR}/scripts/provision.sh || true # best-effort, it does not invalidate container states at all.
equo cleanup
}

vagrant_cleanup() {
#cleanup log and artifacts
rm -rf ${VAGRANT_DIR}/artifacts/*
rm -rf ${VAGRANT_DIR}/logs/*
}

deploy_all() {
local REPO="${1}"

[ -d "${VAGRANT_DIR}/artifacts/${REPO}/" ] || mkdir -p ${VAGRANT_DIR}/artifacts/${REPO}/

# Remote deploy:
deploy "${VAGRANT_DIR}/repositories/${REPO}/entropy_artifacts" "$DEPLOY_SERVER" "$DEPLOY_PORT"
deploy "${VAGRANT_DIR}/logs/" "$DEPLOY_SERVER_BUILDLOGS" "$DEPLOY_PORT"
}

packages_hash() {
  local VAGRANT_DIR="${1}"
  local REPOSITORY_NAME="${2}"
  local HASH_OUTPUT="${3}"

  # cksum '{}' | awk '{ print \$10 \$2 \$3 }'

  echo "[*] Creating hash for $REPOSITORY_NAME in $VAGRANT_DIR at $HASH_OUTPUT"
  # let's do the hash of the tbz2 without xpak data
  local dir=${VAGRANT_DIR}/artifacts/${REPOSITORY_NAME}-binhost/
  # Exclude .pyc/.pyo object from hashing"
  local checker_opts="-e .pyc -e .pyo -e .mo"
  # Exclude .bz2 for man files with timestamp string
  checker_opts="${checker_opts} -e .bz2"

  ${PKGS_CHECKER_BIN} ${checker_opts} ${PKGS_CHECKER_OPTS} -d ${dir} -f ${HASH_OUTPUT}

  cat ${HASH_OUTPUT}
}

function get_image(){
local DOCKER_IMAGE="${1}"
local DOCKER_TAGGED_IMAGE="${2}"

if docker images | grep -q "$DOCKER_IMAGE"; then
  echo "[*] The base image '$DOCKER_IMAGE' exists"
else
  docker pull "$DOCKER_IMAGE"
fi

if docker images | grep -q "$DOCKER_TAGGED_IMAGE"; then
  echo "[*] A tagged image '$DOCKER_TAGGED_IMAGE' already exists"
else
  if [ "$DOCKERHUB_PUSH" -eq 1 ] && docker pull "$DOCKER_TAGGED_IMAGE"; then
    echo "[*] Image '$DOCKER_TAGGED_IMAGE' didn't existed! Cache retrieved from dockerhub"
  else
    echo "[*] Image '$DOCKER_TAGGED_IMAGE' doesn't exists, creating from scratch!"
    docker tag "$DOCKER_IMAGE" "$DOCKER_TAGGED_IMAGE"
  fi
fi
}

function expire_image(){
local DOCKER_IMAGE="${1}"
local DOCKER_TAGGED_IMAGE="${2}"

if docker images | grep -q "$DOCKER_TAGGED_IMAGE"; then
  echo "*** Removing $DOCKER_TAGGED_IMAGE ***"
  docker rmi -f "$DOCKER_TAGGED_IMAGE"
fi
docker pull "$DOCKER_IMAGE"
docker tag "$DOCKER_IMAGE" "$DOCKER_TAGGED_IMAGE"
}

function gen_gpg_keys(){
local REPOSITORY_NAME="${1}"
local PRIVKEY="${2}"
local PUBKEY="${3}"

local TEMPDIR=$(mktemp -d)
pushd ${TEMPDIR}
cat >gpgbatch <<EOF
    %echo Generating a basic OpenPGP key for ${REPOSITORY_NAME}
    Key-Type: RSA
    Key-Length: 2048
    Name-Real: ${REPOSITORY_NAME}
    Name-Comment: ${REPOSITORY_NAME}
    Name-Email: ${REPOSITORY_NAME}@sabayon.org
    Expire-Date: 0
    %commit
    %echo done
EOF
gpg --no-tty --no-permission-warning --homedir .  --verbose --batch --gen-key gpgbatch 2>&1
gpg --no-tty --no-permission-warning --homedir . --armor --export-secret-keys > ${PRIVKEY} 2>&1
gpg --no-tty --no-permission-warning --homedir . --armor --export > ${PUBKEY} 2>&1
popd

rm -rf ${TEMPDIR}
}

build_all() {
local BUILD_ARGS="$@"

local TEMPDIR=$(mktemp -d)

local JOB_ID=$RANDOM

[ -z "$REPOSITORY_NAME" ] && echo "warning: repository name (REPOSITORY_NAME) not defined, using your current working directory name"
export REPOSITORY_NAME="${REPOSITORY_NAME:-$(basename $(pwd))}"
local DOCKER_BUILDER_IMAGE="${DOCKER_IMAGE:-sabayon/builder-amd64}"
local DOCKER_BUILDER_TAGGED_IMAGE="${DOCKER_BUILDER_IMAGE}-$REPOSITORY_NAME"

local DOCKER_EIT_IMAGE="${DOCKER_EIT_IMAGE:-sabayon/eit-amd64}"
local DOCKER_EIT_TAGGED_IMAGE="${DOCKER_EIT_IMAGE}-$REPOSITORY_NAME"
local DOCKER_USER_OPTS="${DOCKER_OPTS}"

local OLD_BINHOST_MD5=$(mktemp -t "$(basename $0).XXXXXXXXXX")
local NEW_BINHOST_MD5=$(mktemp -t "$(basename $0).XXXXXXXXXX")
local PRE_SCRIPT_FILE=$(mktemp -t "$(basename $0).XXXXXXXXXX")
local POST_SCRIPT_FILE=$(mktemp -t "$(basename $0).XXXXXXXXXX")


# Generate keys if not present
export PRIVATEKEY="${PRIVATEKEY:-${VAGRANT_DIR}/confs/${REPOSITORY_NAME}.key}"
export PUBKEY="${PUBKEY:-${VAGRANT_DIR}/confs/${REPOSITORY_NAME}.pub}"
( [ ! -f ${PRIVATEKEY} ] || [ ! -f ${PUBKEY} ] ) && [ "$GENKEY_PHASE" = true ] && gen_gpg_keys "${REPOSITORY_NAME}" "${PRIVATEKEY}" "${PUBKEY}"


#we need to get rid of Packages during md5sum, it contains TIMESTAMP that gets updated on each build (and thus changes, also if the compiled files remains the same)
#here we are trying to see if there are diffs between the bins, not by the metas.
# let's do the hash of the tbz2 without xpak data
[ "$CHECK_BUILD_DIFFS" -eq 1 ] && packages_hash $VAGRANT_DIR $REPOSITORY_NAME $OLD_BINHOST_MD5

# Remove packages. maintainance first.
# Sets the docker image that we will use from now on
[ "$CREATEREPO_PHASE" = true ] && docker pull $DOCKER_EIT_IMAGE
[ "$CREATEREPO_PHASE" = true ] && [ "$COMMIT_EIT_IMAGE" = true ] && get_image $DOCKER_EIT_IMAGE $DOCKER_EIT_TAGGED_IMAGE

[ "$COMMIT_EIT_IMAGE" = true ] && \
export DOCKER_IMAGE=$DOCKER_EIT_TAGGED_IMAGE || export DOCKER_IMAGE=$DOCKER_EIT_IMAGE

[ -n "${TOREMOVE}" ] && \
export DOCKER_OPTS="-t --name ${REPOSITORY_NAME}-remove-${JOB_ID}" && \
package_remove ${TOREMOVE} && \
[ "$COMMIT_EIT_IMAGE" = true ] && \
docker commit "${REPOSITORY_NAME}-remove-${JOB_ID}" $DOCKER_EIT_TAGGED_IMAGE && \
docker rm -f "${REPOSITORY_NAME}-remove-${JOB_ID}"


# Free the cache of builder if requested.
[ -n "$CLEAN_CACHE" ] && [ "$CLEAN_CACHE" -eq 1 ] && [ "$DOCKER_COMMIT_IMAGE" = true ] && expire_image $DOCKER_BUILDER_IMAGE $DOCKER_BUILDER_TAGGED_IMAGE

get_image $DOCKER_BUILDER_IMAGE $DOCKER_BUILDER_TAGGED_IMAGE
export DOCKER_IMAGE=$DOCKER_BUILDER_TAGGED_IMAGE

export DOCKER_OPTS="${DOCKER_USER_OPTS} --name ${REPOSITORY_NAME}-build-${JOB_ID}"

# Prepare and post script
[ -n "${PRE_SCRIPT_COMMANDS}" ] && \
  printf '%s\n' "${PRE_SCRIPT_COMMANDS[@]}" > $PRE_SCRIPT_FILE && \
  export PRE_SCRIPT=$PRE_SCRIPT_FILE

[ -n "${POST_SCRIPT_COMMANDS}" ] && \
  printf '%s\n' "${POST_SCRIPT_COMMANDS[@]}" > $POST_SCRIPT_FILE && \
  export POST_SCRIPT=$POST_SCRIPT_FILE

# Build packages
OUTPUT_DIR="${VAGRANT_DIR}/artifacts/${REPOSITORY_NAME}-binhost" sabayon-buildpackages $BUILD_ARGS
local BUILD_STATUS=$?
[ "$DOCKER_COMMIT_IMAGE" = true ] && docker commit "${REPOSITORY_NAME}-build-${JOB_ID}" $DOCKER_BUILDER_TAGGED_IMAGE && docker rm -f "${REPOSITORY_NAME}-build-${JOB_ID}"

[ -n "${PRE_SCRIPT_COMMANDS}" ] && rm -rf $PRE_SCRIPT_FILE
[ -n "${POST_SCRIPT_COMMANDS}" ] && rm -rf $POST_SCRIPT_FILE

[ "$DOCKERHUB_PUSH" -eq 1 ] && docker push $DOCKER_BUILDER_TAGGED_IMAGE &

if [ $BUILD_STATUS -eq 0 ]
then
  echo "Build successfully"
else
  echo "Build phase failed. Exiting"
  docker rm -f $CID
  exit 1
fi

# Checking diffs
if [ "$CHECK_BUILD_DIFFS" -eq 1 ]; then
  echo "*** Checking tbz2 diffs ***"
  # let's do the hash of the tbz2 without xpak data
  packages_hash $VAGRANT_DIR $REPOSITORY_NAME $NEW_BINHOST_MD5

  local TO_INJECT=($(diff -ru $OLD_BINHOST_MD5 $NEW_BINHOST_MD5 | grep -v -e '^\+[\+]' | grep -e '^\+' | awk '{print $2}'))
  #if diffs are detected, regenerate the repository
  if diff -q $OLD_BINHOST_MD5 $NEW_BINHOST_MD5 >/dev/null ; then
    echo "No changes where detected, repository generation prevented"
    rm -rf $TEMPDIR $OLD_BINHOST_MD5 $NEW_BINHOST_MD5
    exit 0
  else
    echo "${TO_INJECT[@]} packages needs to be injected"
    cp -rf "${TO_INJECT[@]}" $TEMPDIR/
  fi
else
  # Creating our permanent binhost
  cp -rf ${VAGRANT_DIR}/artifacts/${REPOSITORY_NAME}-binhost/* $TEMPDIR
fi

if [ "$CREATEREPO_PHASE" = true ]; then
  echo "*** Generating repository ***"
  # Preparing Eit image.
  [ "$COMMIT_EIT_IMAGE" = true ] && \
  export DOCKER_IMAGE=$DOCKER_EIT_TAGGED_IMAGE || export DOCKER_IMAGE=$DOCKER_EIT_IMAGE
  [ "$COMMIT_EIT_IMAGE" = true ] && get_image $DOCKER_EIT_IMAGE $DOCKER_EIT_TAGGED_IMAGE

  # Create repository
  export DOCKER_OPTS="-t --name ${REPOSITORY_NAME}-eit-${JOB_ID}"
  PORTAGE_ARTIFACTS="$TEMPDIR" OUTPUT_DIR="${VAGRANT_DIR}/artifacts/${REPOSITORY_NAME}" sabayon-createrepo
  # Eit containers are cheap, not pushing to dockerhub.
  [ "$COMMIT_EIT_IMAGE" = true ] && docker commit "${REPOSITORY_NAME}-eit-${JOB_ID}" $DOCKER_EIT_TAGGED_IMAGE || docker rm -f "${REPOSITORY_NAME}-eit-${JOB_ID}"
fi

rm -rf $TEMPDIR
[ "$CHECK_BUILD_DIFFS" -eq 1 ] && rm -rf $OLD_BINHOST_MD5 $NEW_BINHOST_MD5

# Generating metadata
[ "$GENMETADATA_PHASE" = true ] && generate_repository_metadata

if [ "$CLEAN_PHASE" = true ]; then
  echo "*** Cleanup cruft from repository ***"
  [ "$COMMIT_EIT_IMAGE" = true ] && \
  export DOCKER_IMAGE=$DOCKER_EIT_TAGGED_IMAGE || export DOCKER_IMAGE=$DOCKER_EIT_IMAGE
  [ "$COMMIT_EIT_IMAGE" = true ] && get_image $DOCKER_EIT_IMAGE $DOCKER_EIT_TAGGED_IMAGE

  # Cleanup - old cruft/Maintenance
  export DOCKER_OPTS="-t --name ${REPOSITORY_NAME}-clean-${JOB_ID}"
  build_clean
  [ "$COMMIT_EIT_IMAGE" = true ] && docker commit "${REPOSITORY_NAME}-clean-${JOB_ID}" $DOCKER_EIT_TAGGED_IMAGE || docker rm -f "${REPOSITORY_NAME}-clean-${JOB_ID}"
  purge_old_packages
fi

if [ "$DEPLOY_PHASE" = true ]; then
  echo "*** Deploying artifacts/logs from the build ***"
  # Deploy repository inside "repositories"
  deploy_all "${REPOSITORY_NAME}"
fi

unset DOCKER_IMAGE
unset DOCKER_OPTS
}

build_clean() {
[ -z "$REPOSITORY_NAME" ] && die "No Repository name passed (1 arg)"
OUTPUT_DIR="${VAGRANT_DIR}/artifacts/${REPOSITORY_NAME}" sabayon-createrepo-cleanup
}

package_remove() {
[ -z "$REPOSITORY_NAME" ] && die "No Repository name passed (1 arg)"
OUTPUT_DIR="${VAGRANT_DIR}/artifacts/${REPOSITORY_NAME}" sabayon-createrepo-remove "$@"
}

set_var_from_yaml_if_nonempty() {
	local _YAML_FILE=$1
	shift

	local _do_export=0
	local _do_postprocess=0

	while true; do
		case $1 in
		-e)
			_do_export=1
			shift
			;;
		-p)
			_do_postprocess=1
			shift
			;;
		*)
			break
			;;
		esac
	done

	local _shyaml_cmd=$1
	local _key=$2
	# Make sure it doesn't clash with this function's variable or there's a bug.
	# (Variables in this function start with _, so best to avoid such ones.)
	local _out_var=$3

	# Using eval, so...
	[[ $_out_var =~ ^[A-Za-z0-9_]+$ ]] || { echo "no way: '$_out_var'"; exit 1; }

	local _tmp
	_tmp=$(cat "$_YAML_FILE" | shyaml "$_shyaml_cmd" "$_key" 2> /dev/null) || true

	if [[ -n $_tmp ]]; then
		[[ $_do_postprocess = 1 ]] && _tmp=$(echo "$_tmp" | xargs echo)
		eval "$_out_var=\$_tmp"
		[[ $_do_export = 1 ]] && export "$_out_var"
	fi
	return 0
}

load_env_from_yaml() {
local YAML_FILE=$1
local tmp_overlay
local tmp_pkginstall
local tmp_pkgremove

# Check if shyaml is available
[[ ! `which shyaml 2>/dev/null` ]] && { echo "ERROR!!: Missing shyaml tool"; exit 1; }

# repository.*
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value repository.description REPOSITORY_DESCRIPTION  # REPOSITORY_DESCRIPTION
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value repository.maintenance.keep_previous_versions KEEP_PREVIOUS_VERSIONS # KEEP_PREVIOUS_VERSIONS
set_var_from_yaml_if_nonempty "$YAML_FILE" -e -p get-values repository.maintenance.remove TOREMOVE # replaces package_remove
set_var_from_yaml_if_nonempty "$YAML_FILE" -e -p get-values repository.maintenance.remove_before_inject TOREMOVE_BEFORE # TOREMOVE_BEFORE
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value repository.maintenance.remove_opts EIT_REMOVE_OPTS # EIT_REMOVE_OPTS
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value repository.maintenance.clean_cache CLEAN_CACHE # CLEAN_CACHE
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value repository.maintenance.check_diffs CHECK_BUILD_DIFFS # CHECK_BUILD_DIFFS

# recompose our BUILD_ARGS
# build.*
set_var_from_yaml_if_nonempty "$YAML_FILE" -e -p get-value build.share_workspace SHARE_WORKSPACE
if [ -n "$OVERRIDE_BUILD_TARGET" ] ; then
  BUILD_ARGS="$OVERRIDE_BUILD_TARGET"
else
  set_var_from_yaml_if_nonempty "$YAML_FILE" -p get-values build.target BUILD_ARGS  #mixed toinstall BUILD_ARGS
fi
set_var_from_yaml_if_nonempty "$YAML_FILE" -p get-values build.injected_target BUILD_INJECTED_ARGS  #mixed toinstall BUILD_ARGS
set_var_from_yaml_if_nonempty "$YAML_FILE" -p get-values build.overlays tmp_overlay; [[ -n ${tmp_overlay} ]] && BUILD_ARGS="${BUILD_ARGS} --layman ${tmp_overlay}" #--layman options
set_var_from_yaml_if_nonempty "$YAML_FILE" -e -p get-value build.verbose BUILDER_VERBOSE

# build.docker.*
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value build.docker.image DOCKER_IMAGE # DOCKER_IMAGE
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value build.docker.entropy_image DOCKER_EIT_IMAGE # DOCKER_EIT_IMAGE

# build.emerge.*
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value build.emerge.default_args EMERGE_DEFAULTS_ARGS # EMERGE_DEFAULTS_ARGS
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value build.emerge.split_install EMERGE_SPLIT_INSTALL # EMERGE_SPLIT_INSTALL
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value build.emerge.features FEATURES # FEATURES
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value build.emerge.profile BUILDER_PROFILE # BUILDER_PROFILE
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value build.emerge.jobs BUILDER_JOBS # BUILDER_JOBS
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value build.emerge.preserved_rebuild PRESERVED_REBUILD # PRESERVED_REBUILD
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value build.emerge.skip_sync SKIP_PORTAGE_SYNC # SKIP_PORTAGE_SYNC
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value build.emerge.webrsync WEBRSYNC # WEBRSYNC
set_var_from_yaml_if_nonempty "$YAML_FILE" -e -p get-values build.emerge.remove EMERGE_REMOVE
set_var_from_yaml_if_nonempty "$YAML_FILE" -e -p get-values build.emerge.remote_overlay REMOTE_OVERLAY
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value build.emerge.remote_conf_portdir REMOTE_CONF_PORTDIR
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value build.emerge.remote_portdir REMOTE_PORTDIR
set_var_from_yaml_if_nonempty "$YAML_FILE" -e -p get-values build.emerge.remove_remote_overlay REMOVE_REMOTE_OVERLAY
set_var_from_yaml_if_nonempty "$YAML_FILE" -e -p get-values build.emerge.remove_layman_overlay REMOVE_LAYMAN_OVERLAY
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value build.qa_checks QA_CHECKS # QA_CHECKS, default 0

# build.equo.*
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value build.equo.enman_self ENMAN_ADD_SELF # ENMAN_ADD_SELF, default 1.
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-values build.equo.repositories ENMAN_REPOSITORIES # ENMAN_REPOSITORIES
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-values build.equo.remove_repositories REMOVE_ENMAN_REPOSITORIES # REMOVE_ENMAN_REPOSITORIES
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value build.equo.repository ENTROPY_REPOSITORY # ENTROPY_REPOSITORY
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value build.equo.dependency_install.enable USE_EQUO # USE_EQUO
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value build.equo.dependency_install.install_atoms EQUO_INSTALL_ATOMS # EQUO_INSTALL_ATOMS
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value build.equo.dependency_install.dependency_scan_depth DEPENDENCY_SCAN_DEPTH # DEPENDENCY_SCAN_DEPTH
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value build.equo.dependency_install.prune_virtuals PRUNE_VIRTUALS # PRUNE_VIRTUALS
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value build.equo.dependency_install.install_version EQUO_INSTALL_VERSION # EQUO_INSTALL_VERSION
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value build.equo.dependency_install.split_install EQUO_SPLIT_INSTALL # EQUO_SPLIT_INSTALL
set_var_from_yaml_if_nonempty "$YAML_FILE" -p get-values build.equo.package.install tmp_pkginstall; [[ -n ${tmp_pkginstall} ]] && BUILD_ARGS="${BUILD_ARGS} --install ${tmp_pkginstall}"  #mixed --install BUILD_ARGS
set_var_from_yaml_if_nonempty "$YAML_FILE" -p get-values build.equo.package.remove tmp_pkgremove; [[ -n ${tmp_pkgremove} ]] && BUILD_ARGS="${BUILD_ARGS} --remove ${tmp_pkgremove}"   #mixed --remove BUILD_ARGS
set_var_from_yaml_if_nonempty "$YAML_FILE" -e -p get-values build.equo.package.mask EQUO_MASKS
set_var_from_yaml_if_nonempty "$YAML_FILE" -e -p get-values build.equo.package.unmask EQUO_UNMASKS
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-value build.equo.no_cache ETP_NOCACHE # ETP_NOCACHE

# build.script.pre
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-values build.script.pre PRE_SCRIPT_COMMANDS
# build.script.post
set_var_from_yaml_if_nonempty "$YAML_FILE" -e get-values build.script.post POST_SCRIPT_COMMANDS

export BUILD_ARGS
export BUILD_INJECTED_ARGS
}

automated_build() {
local REPO_NAME=$1
local TEMPLOG=$(mktemp)
[ -z "$REPO_NAME" ] && die "You called automated_build() blindly, without a reason, huh?"
pushd ${VAGRANT_DIR}/repositories/$REPO_NAME
### XXX: Libchecks in there!
irc_msg "Repository \"${REPO_NAME}\" build starting."
env -i REPOSITORY_NAME=$REPO_NAME CLEAN_CACHE=$CLEAN_CACHE REPOSITORIES=$REPOSITORIES TEMPLOG=$TEMPLOG /bin/bash -c "
  . /sbin/sark-functions.sh
  load_env_from_yaml \"build.yaml\"
{ build_all \"\$BUILD_ARGS\"; } 1>&2 > \$TEMPLOG "
NOW=$(date +"%Y-%m-%d")
[ ! -d "${VAGRANT_DIR}/logs/$NOW" ] && mkdir -p ${VAGRANT_DIR}/logs/$NOW && chmod -R 755 ${VAGRANT_DIR}/logs/$NOW
mytime=$(date +%s)
ansifilter $TEMPLOG > "${VAGRANT_DIR}/logs/$NOW/$REPO_NAME.$mytime.log"
chmod 755 ${VAGRANT_DIR}/logs/$NOW/$REPO_NAME.$mytime.log
irc_msg "Repository \"${REPO_NAME}\" build completed. Log is available at: ${URI_BASE}/logs/$NOW/$REPO_NAME.$mytime.log"
popd
rm -rf $TEMPLOG
}

generate_metadata() {
echo "Generating metadata"
[ -z "${REPOSITORIES}" ] && update_repositories
# Generate repository list
printf "%s\n" "${REPOSITORIES[@]}" > ${VAGRANT_DIR}/artifacts/AVAILABLE_REPOSITORIES

echo "REPOSITORY LIST"
echo "@@@@@@@@@@@@@@@"
cat ${VAGRANT_DIR}/artifacts/AVAILABLE_REPOSITORIES
# \.[a-f0-9]{40}

sark-genreposmeta
}

generate_repository_metadata() {
local REPOSITORY=$REPOSITORY_NAME
local PKGLISTS=($(find ${VAGRANT_DIR}/artifacts/$REPOSITORY | grep packages.db.pkglist))

for i in "${PKGLISTS[@]}"
do
  IFS=$*/ command eval 'plist=($i)'
  local arch=${plist[-3]}
  local repo=${plist[-7]}
  local outputpkglist=${VAGRANT_DIR}/artifacts/$repo/PKGLIST-$arch
  cp -rf "$i" "${outputpkglist}"
  perl -pi -e 's/\.[a-f0-9]{40}//g' "${outputpkglist}"
  perl -pi -e 's/.*\/|\/|\.tbz2//g' "${outputpkglist}"
  perl -pi -e 's/\:/\//' "${outputpkglist}"
  echo "Generated packagelist: ${outputpkglist}"
done
}

purge_old_packages() {
  export DOCKER_OPTS="-t --name ${REPOSITORY_NAME}-removeclean-${JOB_ID}"
  local PKGLISTS=($(find ${VAGRANT_DIR}/artifacts/$REPOSITORY_NAME/ | grep PKGLIST))
  local REMOVED=0
  for i in "${PKGLISTS[@]}"
  do
    local REPO_CONTENT=$(cat ${i} | perl -lpe 's:\~.*::g' | xargs echo );
    local TOREMOVE=$(OUTPUT_REMOVED=1 PACKAGES=$REPO_CONTENT sark-version-sanitizer );
    [ -n "${TOREMOVE}" ] && let REMOVED+=1 && package_remove ${TOREMOVE}
  done

  [ $REMOVED != 0 ] && generate_repository_metadata
  [ "$DOCKER_COMMIT_IMAGE" = true ] && \
    docker commit "${REPOSITORY_NAME}-removeclean-${JOB_ID}" $DOCKER_EIT_TAGGED_IMAGE || \
    docker rm -f "${REPOSITORY_NAME}-removeclean-${JOB_ID}"

  purge_binhost_packages "${VAGRANT_DIR}/artifacts/${REPOSITORY_NAME}-binhost/"
}

purge_binhost_packages () {
  local repodir=$1

  local binhost_pkgs=$(find ${repodir} | grep '.tbz2' | perl -lpe 's:.*-binhost/|\.tb.*::g' | xargs echo)
  local pkgs2remove=($(OUTPUT_REMOVED=1 PACKAGES="${binhost_pkgs}" sark-version-sanitizer))

  for i in "${pkgs2remove[@]}"
  do
    rm -rfv "${repodir}/${i}.tbz2"
  done

}

docker_clean() {
# Best effort - cleaning orphaned containers
docker ps -a -q | xargs -n 1 -I {} docker rm {}

# Best effort - cleaning orphaned images
local images=$(docker images | grep '<none>' | tr -s ' ' | cut -d ' ' -f 3)
if [ -n "${images}" ]; then
  docker rmi ${images}
fi

}

# Temporary workaround for mask of packages with ::repos from overlay profile
# until portage support this directly.
# (yeah, i know it's bad)
sabayon_mask_upstream_pkgs () {
  local maskfile=${1:-/var/lib/layman/sabayon-distro/profiles/targets/sabayon/arm/package.mask}
  local outfile=${2:-/etc/portage/package.mask/00-sabayon.package.mask}

  grep GLOBAL_MASK ${maskfile} | awk '{ print  $3 }'  | tail -n +2 > ${outfile}
}

