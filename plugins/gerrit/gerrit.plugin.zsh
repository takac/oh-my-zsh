#! /bin/bash

# Need to export url for your gerrit, example
# export GERRIT_URL=https://review.openstack.org
#
# Your git config will also need to contain you gerrit username, you can set it with
# git config --global gitreview.username
#
# To use any of the more advanced commands you will need to have you ssh key
# added to gerrit as this plugin uses gerrits ssh API
#
# Example usage:
# gerrit-patch 38409 tripleo-heat-templates
# gerrit-patch 38676
#
# gerrit-get-latest-patch

# $1 change number
# $2 dir name (optional, will use current dir if not provided)
function gerrit-fetch-patch()
{
    if [[ -z "${GERRIT_URL}" ]]; then echo "GERRIT_URL must be set"; return 1; fi
    local git_dir repo_url repo_tmp ref
    git_dir="${2:-$(pwd)}"
    repo=$(repo-name "${git_dir}")
    ref=$(git ls-remote ${GERRIT_URL}/${repo} | grep ${1} | cut -f2 | sort -rnt '/' -k 5 /tmp/rf | head -n1)
    echo "Change ${1} in ${repo} has lastest ref: ${ref}"
    git -C "${git_dir}" fetch ${GERRIT_URL}/${repo} ${ref}
}

# $1 change id
# $2 optional dir name
# This will reset the current branch to HEAD~1 if change id of HEAD matches
# that of FETCH head
# WIP
function gerrit-reset-and-patch()
{
    local git_dir="${2:-$(pwd)}"
    gerrit-fetch-patch "${1}" "${git_dir}"

    local cid=$(change-id "HEAD" "${git_dir}")
    local rcid=$(change-id "FETCH_HEAD" "${git_dir}")
    if [[ "${cid}" == "${rcid}" ]]; then
        git -C "${git_dir}" reset --hard HEAD~1
    fi
    git -C "${git_dir}" cherry-pick FETCH_HEAD
    # git -C rev-list --pretty=oneline HEAD --reverse -4 --all | grep -v 7c37ab9
    # git -C ${git_dir} cherry-pick FETCH_HEAD
}


# $1 git reference
# $2 dir name
function gerrit-change-id()
{
    local git_dir="${2:-$(pwd)}"
    git -C "${git_dir}" --no-pager log -1 --format="%b" ${1} | awk '/[cC]hange-[iI]d:/{print $2}'
}

# $1 dir name
function repo-name()
{
    local git_dir repo_url repo_tmp
    git_dir="${1:-$(pwd)}"
    repo_url="$(git -C "${git_dir}" remote -v | head -n1 | cut -f2 | cut -d' ' -f1)"
    repo_tmp="${repo_url%/*}"
    echo "${repo_tmp##*/}/${repo_url##*/}"
}

# $1 change number
# $2 dir name (optional, will use current dir if not provided)
function gerrit-patch() {
    local git_dir="${2:-$(pwd)}"
    gerrit-fetch-patch "${1}" "${git_dir}"
    git -C "${git_dir}" cherry-pick FETCH_HEAD
}

function gerrit-list-open-patches()
{
    local json gerrit_user
    gerrit_user=$(git config gitreview.username)
    json=$(gerrit-ssh-query "status:open owner:${gerrit_user}")
    jq -s ".[]|select(.subject)|{subject, project, number, id}" <<< $json
}


function gerrit-ssh-query()
{
    local gerrit_user
    gerrit_user=$(git config gitreview.username)
    ssh -p 29418 ${gerrit_user}@${GERRIT_URL##*//} "gerrit query --format=JSON ${1}" | tee /tmp/gerritquery.json
}

# $1 git dir
# $2 optional ref, defaults to HEAD
function gerrit-patch-from-ref
{
    local git_dir ref cid
    git_dir="${1:-$(pwd)}"
    ref=${2:-HEAD}
    cid=$(gerrit-change-id ${ref})
    gerrit-ssh-query "${cid}" | jq -s ".[0]|select(.subject)|{subject, project, number, id}" <<< $json

}

# $1 optional git dir
function gerrit-get-latest-patchset()
{
    local change_number git_dir
    git_dir="${1:-$(pwd)}"
    change_number=$(gerrit-patch-from-ref "${git_dir}" | jq -r .number)
    gerrit-fetch-patch "${change_number}" "${git_dir}"
    git -C "${git_dir}" reset --hard HEAD~1
    git -C ${git_dir} cherry-pick FETCH_HEAD
}
