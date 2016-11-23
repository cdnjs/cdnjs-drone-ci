#!/bin/sh

set -e

echo "node "$(node  --version)""
git   --version
echo "npm  "$(npm   --version)""
rsync --version | head -n 1

err() {
    >&2 echo "$@"
    exit 1
}

if [ "{$CI}" != "drone" ] && [ "${DRONE}" != "true" ]; then
    err "Not a Drone CI environment"
fi

[ -z "${PLUGIN_ACTION}" ] && err "cache action not set! test or restore-cache ?"

[ -z "${CDNJS_CACHE_HOST}" ] && {
    CDNJS_CACHE_HOST="$(ip route | awk '{ if ("default" == $1) print $3}')"
    echo "\"CDNJS_CACHE_HOST\" secret not set"
    echo "use ${CDNJS_CACHE_HOST} as it's default gateway, should be the host!"
}
[ -z "${CDNJS_CACHE_USERNAME}" ] && err  "\"CDNJS_CACHE_USERNAME\" secret not set!"
[ -z "${CDNJS_CACHE_PASSWORD}" ] && err  "\"CDNJS_CACHE_PASSWORD\" secret not set!"

BASEPATH="~/cache-cdnjs/"
export SSHPASS="${CDNJS_CACHE_PASSWORD}"

if [ "${PLUGIN_ACTION}" = "restore-cache" ]; then
    for FILE in .git/ node_modules/
    do
        echo "Trying to restore ${FILE} from cache"
        rsync -a -e="sshpass -e ssh -oStrictHostKeyChecking=no -l ${CDNJS_CACHE_USERNAME}" "${CDNJS_CACHE_HOST}":"${BASEPATH}${FILE}" "./${FILE}"
    done
    exit 0
elif [ "${PLUGIN_ACTION}" != "test" ]; then
    err "Can't recognize action ${PLUGIN_ACTION}"
fi

echo "npm install && npm update"
npm install && npm update

echo "re-create sparseCheckout config"
./tools/createSparseCheckoutConfig.js

echo "reset repository"
git reset --hard

echo "run npm test"
npm test -- --silent || npm test

if [ "${DRONE_COMMIT_BRANCH}" = "master" ] && [ "${DRONE_BUILD_EVENT}" = "push" ]; then
    sshpass -e ssh -oStrictHostKeyChecking=no -l ${CDNJS_CACHE_USERNAME} "${CDNJS_CACHE_HOST}" mkdir -p "${BASEPATH}"
    for FILE in .git/ node_modules/
    do
        echo "Trying to store ${FILE} as cache"
        rsync -a --delete -e="sshpass -e ssh -oStrictHostKeyChecking=no -l ${CDNJS_CACHE_USERNAME}" "./${FILE}" "${CDNJS_CACHE_HOST}":"${BASEPATH}${FILE}"
    done
fi
