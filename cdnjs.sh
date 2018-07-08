#!/bin/sh

. /ColorEcho.sh

set -e
export GPG_TTY=/dev/console
export FORCE_COLOR=1
export NPM_CONFIG_LOGLEVEL=warn

echo
echoCyan "Build date: $(cat /date)"
echoCyan "Tool versions:"
echoCyan "jq    $(jq --version)"
echoCyan "node  $(node  --version)"
echoCyan "git   v$(git   --version | awk '{print $3}')"
echoCyan "npm   v$(npm   --version)"
echoCyan "curl  v$(curl   --version)"
echoCyan "rsync v$(rsync --version | head -n 1 | awk '{print $3}')"

grep_return_true() {
    grep "$@" || true
}

err() {
    >&2 echoRed "==========ERROR=========="
    >&2 echo -e "$@"
    >&2 echoRed "==========ERROR=========="
    exit 1
}

if [ "${CI}" != "drone" ] && [ "${DRONE}" != "true" ]; then err "Not a Drone CI environment"; fi
[ -n "${PLUGIN_ACTION-}" ] && err "Your branch is out-dated! Please rebase with our latest master branch! Thanks!"

CDNJS_CACHE_HOST="$(ip route | awk '{ if ("default" == $1) print $3}')"
echoCyan "use ${CDNJS_CACHE_HOST} as it's default gateway, should be the host!"
[ -z "${CDNJS_CACHE_USERNAME}" ] && err "\"CDNJS_CACHE_USERNAME\" secret not set!"
[ -z "${CDNJS_CACHE_PASSWORD}" ] && err "\"CDNJS_CACHE_PASSWORD\" secret not set!"

if [ "${DRONE_COMMIT_REFSPEC}" ] && [ "${DRONE_BUILD_EVENT}" = "pull_request" ]; then
    DRONE_COMMIT_BRANCH="$(echo "${DRONE_COMMIT_REFSPEC}" | awk -F':' '{print $1}')"
    if [ "${DRONE_COMMIT_BRANCH}" = "master" ] && [ "${DRONE_PULL_REQUEST}" -gt 9999 ]; then
        err "Please do not send pull requests from a master branch!
You should create a new branch with a meaningful name for pull request!
\\n
'Creating and deleting branches within your repository' Reference:
https://help.github.com/articles/creating-and-deleting-branches-within-your-repository/
\\n
For the reason why we need to create a new branch for every pull request,
please refer to the GitHub Flow: https://guides.github.com/introduction/flow/index.html"
    else
        echoCyan "PR branch: ${DRONE_COMMIT_BRANCH}"
    fi
fi

if [ "${DRONE_BUILD_EVENT}" = "pull_request" ]; then

    PR_REPO="$(curl --compressed -s --retry 3 "https://api.github.com/repos/cdnjs/cdnjs/pulls/${DRONE_PULL_REQUEST}" | jq -r .head.repo.owner.login)"
    if [ "$(curl --compressed -s --retry 3 "https://api.github.com/repos/cdnjs/cdnjs/compare/${DRONE_REPO_BRANCH}...${PR_REPO}:${DRONE_COMMIT_BRANCH}" | jq -r .behind_by)" -gt 60 ]; then
        err "The branch ${DRONE_COMMIT_BRANCH} for this pull request is a little bit old, please rebase this branch with the latest ${DRONE_REPO_BRANCH} branch from upstream!"
    fi
fi

CACHE_LIST=".git/ node_modules/"

# shellcheck disable=SC2088
BASEPATH='~/cache/'
export SSHPASS="${CDNJS_CACHE_PASSWORD}"

# cache restore
for FILE in ${CACHE_LIST}; do
    echoMagenta "Trying to restore ${FILE} from cache"
    rsync -a -e="sshpass -e ssh -oStrictHostKeyChecking=no -l ${CDNJS_CACHE_USERNAME}" "${CDNJS_CACHE_HOST}:${BASEPATH}${FILE}" "./${FILE}" > /dev/null &
done

wait
echoMagenta "Cache restored!"

if [ ! -d ".git" ]; then
    2>&1 ls -al
    2>&1 pwd
    err "Cache .git directory not found!!! What's going on?"
fi

if [ -n "${DRONE_PULL_REQUEST}" ]; then
    DRONE_FETCH_TARGET="pull/${DRONE_PULL_REQUEST}/head"
else
    DRONE_FETCH_TARGET="${DRONE_COMMIT_BRANCH}"
fi

if echo "${DRONE_REPO_LINK}" | grep -q 'github.com'; then
    echoCyan "Clean up old .git/info/sparse-checkout and fetch new one ..."
    rm -f .git/info/sparse-checkout
    curl --compressed -s --retry 3 "$(echo "${DRONE_REPO_LINK}" | sed 's/github.com/raw.githubusercontent.com/g')/${DRONE_COMMIT_SHA}/${PLUGIN_SPARSECHECKOUT}" -o ".git/info/sparse-checkout" &
else
    err "When does CDNJS drop GitHub? No idea!"
fi

if [ "${DRONE_COMMIT_BRANCH}" = "master" ] && [ "${DRONE_BUILD_EVENT}" = "push" ]; then
    echoCyan "Configure git.gc for master branch"
    echoCyan "make sure git gc.auto enabled"
    git config gc.auto 1

    echoCyan "optimize git gc configs"
    git config gc.pruneExpire now
    git config gc.reflogExpire now
    git config gc.aggressiveDepth 1
    git config gc.reflogExpireUnreachable 0
else
    echoCyan "Disable git.gc for pull requests"
    git config gc.auto 0
fi

echoCyan "Fetch ${DRONE_REPO_BRANCH} branch updates ..."

wait

if git branch | grep -q "^* ${DRONE_REPO_BRANCH}"; then
    # we should not be on the target branch, so just jump to the latest commit
    git checkout -f "$(git log "${DRONE_REPO_BRANCH}" -1 --format=%H)"
fi

if git remote | grep -q pre-fetch; then
    if ! git fetch pre-fetch "${DRONE_REPO_BRANCH}":"${DRONE_REPO_BRANCH}" -f > /dev/null; then
        git fetch origin "${DRONE_REPO_BRANCH}":"${DRONE_REPO_BRANCH}" -f
    fi
else
    git fetch origin "${DRONE_REPO_BRANCH}":"${DRONE_REPO_BRANCH}" -f
fi

echoCyan "Fetch the target going to be tested ..."
git fetch origin "${DRONE_FETCH_TARGET}"

if [ ! -f ".git/info/sparse-checkout" ]; then
    err "Didn't detect sparse-checkout config, should be created from previous stage!"
fi

if [ "$(git ls-tree "${DRONE_COMMIT_SHA}" ajax/ | awk '{print $4}')" != "ajax/libs" ]; then
    echoYellow "Detected path under ajax/:"
    git ls-tree "${DRONE_COMMIT_SHA}" ajax/
    err "There should be only one directory - 'libs' under 'ajax', please make sure you put the files under correct path."
fi

echoCyan "make sure git pagination disabled"
git config core.pager cat

echoCyan "make sure git core.sparseCheckout enabled"
git config core.sparseCheckout true

echoCyan "re-create sparseCheckout config"
if [ "${DRONE_BUILD_EVENT}" = "pull_request" ]; then
    SPARSE_CHECKOUT="$(git log --name-only --pretty='format:' "${DRONE_REPO_BRANCH}".."${DRONE_COMMIT_SHA}" | awk -F'/' '{ if ($1 == "ajax" && $2 == "libs" && $4) print "/ajax/libs/"$3"/package.json"}' | sort | uniq)"
    if [ "${SPARSE_CHECKOUT}" = "" ]; then
        MARKDOWN_CHANGES="$(git log --name-only --pretty='format:' "${DRONE_REPO_BRANCH}".."${DRONE_COMMIT_SHA}" | grep_return_true -cE '(.(md|markdown))$')"
        TOTAL_CHANGES="$(git log --name-only --pretty='format:' "${DRONE_REPO_BRANCH}".."${DRONE_COMMIT_SHA}" | grep_return_true -cvE '^$')"
        if [ "${MARKDOWN_CHANGES}" = "${TOTAL_CHANGES}" ]; then
            echoYellow "No library change detected, only docs updated, no need to run tests"
            exit 0
        else
            echoYellow "No library change detected, will checkout all the libraries!"
            echo '/ajax/libs/*/package.json' >> .git/info/sparse-checkout
        fi
    elif [ "$(echo "${SPARSE_CHECKOUT}" | wc -l)" -gt 300 ]; then
        echoYellow "Changed more than 300 libraries, just checkout all the libraries to run the test!"
        echo '/ajax/libs/*/package.json' >> .git/info/sparse-checkout
    else
        echo "${SPARSE_CHECKOUT}" >> .git/info/sparse-checkout
        echoGreen "Library change detected, use sparseCheckout to checkout path as below:"
        for SPARSE_CHECKOUT_TMP in ${SPARSE_CHECKOUT}; do
            echoBlue "${SPARSE_CHECKOUT_TMP}"
        done
    fi
else
    echo '/ajax/libs/*/package.json' >> .git/info/sparse-checkout
fi

echo '/package.json' >> .git/info/sparse-checkout

echoGreen "Phase one file checkout"
git checkout -qf "${DRONE_COMMIT_SHA}"

if [ "${DRONE_BUILD_EVENT}" = "pull_request" ] && [ "${SPARSE_CHECKOUT}" != '/ajax/libs/*/package.json' ]; then
    for PACKAGE in ${SPARSE_CHECKOUT}
    do
        if [ ! -f "${PWD}${PACKAGE}" ]; then
            err "${PACKAGE} not found!!!"
        fi
    done
fi

echoCyan "npm install && npm update"
npm install && npm update

echoGreen "Phase two file checkout"
echoGreen " - Generate sparseCheckout config"
./tools/createSparseCheckoutConfigForCI.js
echoGreen " - Reset repository (phase two checkout)"
git reset --hard

{
    echoCyan "run npm test"
    if ! npm test -- --silent > /dev/null 2>&1; then
        npm test -- --color 2>&1 | sed 's/·//g'
        ./tools/fixFormat.js
        git diff --color
        err "npm test failed!"
    fi
} &

echoCyan "run file permission test"
if [ "$(git log --summary "${DRONE_REPO_BRANCH}".."${DRONE_COMMIT_SHA}" | grep_return_true 'ajax/libs/' | awk '{ if (NF == 4 && $2 == "mode" && $3 !~ /^.{3}[64]{3}$/ && $3 != "120000" ) print }' | wc -l )" != "0" ]; then
    >&2 echoRed "Static files for web hosting should not be executable!"
    >&2 echoRed "Please remove executable permission on the file(s) below:"
    >&2 echo
    git log --summary "${DRONE_REPO_BRANCH}".."${DRONE_COMMIT_SHA}" | grep_return_true 'ajax/libs/' | awk '{ if (NF == 4 && $2 == "mode" && $3 !~ /^.{3}[64]{3}$/ && $3 != "120000") print $4 " ("$3")" }' >&2
    exit 1
fi

if ! wait $(jobs -p); then
    exit 1
fi

if [ "${DRONE_COMMIT_BRANCH}" = "master" ] && [ "${DRONE_BUILD_EVENT}" = "push" ]; then
    sshpass -e ssh -oStrictHostKeyChecking=no -l "${CDNJS_CACHE_USERNAME}" "${CDNJS_CACHE_HOST}" mkdir -p "${BASEPATH}" > /dev/null 2>&1
    for FILE in ${CACHE_LIST}; do
        echoMagenta "Trying to store ${FILE} as cache"
        rsync -aq --delete --delete-after -e="sshpass -e ssh -oStrictHostKeyChecking=no -l ${CDNJS_CACHE_USERNAME}" "./${FILE}" "${CDNJS_CACHE_HOST}:${BASEPATH}${FILE}" > /dev/null 2>&1 &
    done
    wait
    echoMagenta "Cache store finished!"
else
    echo "Branch: ${DRONE_COMMIT_BRANCH}"
    echo "Event:  ${DRONE_BUILD_EVENT}"
    echoYellow "No cache store here"
fi
