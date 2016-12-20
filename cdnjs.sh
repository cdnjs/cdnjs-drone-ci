#!/bin/sh

. /ColorEcho.sh

set -e
export GPG_TTY=/dev/console

echo
echoBoldCyan "Tool versions:"
echoCyan "node  $(node  --version)"
echoCyan "git   v$(git   --version | awk '{print $3}')"
echoCyan "npm   v$(npm   --version)"
echoCyan "rsync v$(rsync --version | head -n 1 | awk '{print $3}')"

err() {
    >&2 echoBoldRed "\n==========ERROR==========\n";
    >&2 echo "$@";
    >&2 echoBoldRed "\n==========ERROR==========\n";
    exit 1;
}

if [ "${CI}" != "drone" ] && [ "${DRONE}" != "true" ]; then err "Not a Drone CI environment"; fi

[ -z "${PLUGIN_ACTION}" ] && err "cache action not set! test or restore-cache ?"

CDNJS_CACHE_HOST="$(ip route | awk '{ if ("default" == $1) print $3}')"
echoCyan "use ${CDNJS_CACHE_HOST} as it's default gateway, should be the host!"
[ -z "${CDNJS_CACHE_USERNAME}" ] && err  "\"CDNJS_CACHE_USERNAME\" secret not set!"
[ -z "${CDNJS_CACHE_PASSWORD}" ] && err  "\"CDNJS_CACHE_PASSWORD\" secret not set!"

if [ "${DRONE_COMMIT_REFSPEC}" ] && [ "${DRONE_BUILD_EVENT}" = "pull_request" ]; then
    DRONE_COMMIT_BRANCH="$(echo "${DRONE_COMMIT_REFSPEC}" | awk -F':' '{print $1}')"
    if [ "${DRONE_COMMIT_BRANCH}" = "master" ]; then
        err "Please do not send pull request from master branch!\nYou should create a new branch with meaningful name for pull request!"
    else
        echoCyan "PR branch: ${DRONE_COMMIT_BRANCH}"
    fi
fi

# shellcheck disable=SC2088
BASEPATH='~/cache-cdnjs/'
export SSHPASS="${CDNJS_CACHE_PASSWORD}"

if [ "${PLUGIN_ACTION}" = "restore-cache" ]; then
    for FILE in .git/ node_modules/
    do
        echoLightBoldMagenta "Trying to restore ${FILE} from cache"
        rsync -aq -e="sshpass -e ssh -oStrictHostKeyChecking=no -l ${CDNJS_CACHE_USERNAME}" "${CDNJS_CACHE_HOST}:${BASEPATH}${FILE}" "./${FILE}" > /dev/null 2>&1
    done
    exit 0
fi

if [ "${PLUGIN_ACTION}" != "test" ]; then err "Can't recognize action ${PLUGIN_ACTION}"; fi

if [ ! -f ".git/info/sparse-checkout" ]; then
    err "Didn't detect sparse-checkout config, should be created from previous stage!"
fi

if [ "$(git ls-tree "${DRONE_COMMIT_SHA}" ajax/ | awk '{print $4}')" != "ajax/libs" ]; then
    err "There should be only one directory - 'libs' under 'ajax', please make sure you put the files under correct path."
fi

echoCyan "make sure git pagination disabled"
git config core.pager cat

echoCyan "make sure git gc.auto disabled"
git config gc.auto 0

echoCyan "make sure git core.sparseCheckout enabled"
git config core.sparseCheckout true

echoCyan "re-create sparseCheckout config"
if [ "${DRONE_BUILD_EVENT}" = "pull_request" ]; then
    if [ "$(git log --pretty='%an' "${DRONE_COMMIT_SHA}".."origin/${DRONE_REPO_BRANCH}" | grep -cv '^PeterBot$' )" -gt 20 ]; then
        err "The branch ${DRONE_COMMIT_BRANCH} for this pull request is too old, please rebase this branch with the latest ${DRONE_REPO_BRANCH} branch from upstream!"
    fi
    SPARSE_CHECKOUT="$(git log --name-only --pretty='format:' origin/"${DRONE_REPO_BRANCH}".."${DRONE_COMMIT_SHA}" | awk -F'/' '{ if ($1 == "ajax" && $2 == "libs" && $4) print "/ajax/libs/"$3"/package.json"}' | sort | uniq)"
    if [ "${SPARSE_CHECKOUT}" = "" ]; then
        echoBoldYellow "No library change detected, will checkout all the libraries!"
        echo '/ajax/libs/*/package.json' >> .git/info/sparse-checkout
    else
        echo "${SPARSE_CHECKOUT}" >> .git/info/sparse-checkout
        echoBoldGreen "Library change detected, use sparseCheckout to checkout path as below:"
        echoBlue "${SPARSE_CHECKOUT}"
    fi
else
    echo '/ajax/libs/*/package.json' >> .git/info/sparse-checkout
fi

echoGreen "Phase one file checkout"
git checkout -qf "${DRONE_COMMIT_SHA}"
./tools/createSparseCheckoutConfigForCI.js

if [ "${DRONE_BUILD_EVENT}" = "pull_request" ] && [ "${SPARSE_CHECKOUT}" != '/ajax/libs/*/package.json' ] ; then
    for PACKAGE in ${SPARSE_CHECKOUT}
    do
        if [ ! -f "${PWD}${PACKAGE}" ]; then
            err "${PACKAGE} not found!!!"
        fi
    done
fi

echoGreen "reset repository (phase two checkout)"
git reset --hard

echoCyan "npm install && npm update"
npm install && npm update

echoCyan "run npm test"
npm test -- --silent > /dev/null 2>&1 || npm test -- --color

if [ "${DRONE_COMMIT_BRANCH}" = "master" ] && [ "${DRONE_BUILD_EVENT}" = "push" ]; then
    sshpass -e ssh -oStrictHostKeyChecking=no -l "${CDNJS_CACHE_USERNAME}" "${CDNJS_CACHE_HOST}" mkdir -p "${BASEPATH}" > /dev/null 2>&1
    for FILE in .git/ node_modules/
    do
        echoLightBoldMagenta "Trying to store ${FILE} as cache"
        rsync -aq --delete --delete-after -e="sshpass -e ssh -oStrictHostKeyChecking=no -l ${CDNJS_CACHE_USERNAME}" "./${FILE}" "${CDNJS_CACHE_HOST}:${BASEPATH}${FILE}" > /dev/null 2>&1
    done
else
    echo "Branch: ${DRONE_COMMIT_BRANCH}"
    echo "Event:  ${DRONE_BUILD_EVENT}"
    echoBoldYellow "No cache store here"
fi
