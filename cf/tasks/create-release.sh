#!/bin/bash

set -o errexit
set -o nounset
set -o xtrace

mkdir bosh-cache

for var in FISSILE_REPOSITORY RELEASE_NAME RELEASE_DIR ; do
    has_missing=0
    if test -z "${!var:-}" ; then
        printf "Required variable %s is missing\n" "${var}" >&2
        has_missing=1
    fi
    if test "${has_missing}" = 1 ; then
        exit 1
    fi
done

RELEASE_DIR=${RELEASE_DIR}
RELEASE_NAME=${RELEASE_NAME:-$(basename "${RELEASE_DIR}" -release)}
if test -r "${RELEASE_DIR}/.ruby-version" ; then
    RUBY_VERSION=$(cat "${RELEASE_DIR}/.ruby-version")
    export RUBY_VERSION
fi

/usr/local/bin/create-release.sh \
    "$(id -u)" "$(id -g)" \
    "${PWD}/bosh-cache" \
    --dir "${RELEASE_DIR}" \
    --force \
    --name "${RELEASE_NAME}"

# Get the release name, version, and commit for the file name.
# The commit needs to be there for concourse to distinguish between builds.
# It's not used for anything else and should not be exposed outside CI.
release_info=$(awk '/latest_release_filename:/ { print $2 }' < "${RELEASE_DIR}/config/dev.yml" | tr -d '"')
function field() {
    # If a string consists of only digits, we get extra quoting around it for YAML
    # We need to delete that quoting
    awk "/^${1}:/ { print \$2 }" < "${release_info}" | tr -d \"\'
}
tar_name="${FISSILE_REPOSITORY}-${RELEASE_NAME}-release-tarball-$(field version)-$(field commit_hash).tgz"

mkdir stage
mv "${PWD}/bosh-cache"             stage/bosh-cache
mv "${RELEASE_DIR}/.dev_builds"    stage/dev-builds
mv "${RELEASE_DIR}/config/dev.yml" stage/dev.yml
mv "${RELEASE_DIR}/dev_releases"   stage/dev-releases
tar -czf "out/${tar_name}" --checkpoint=.1000 -C stage .
