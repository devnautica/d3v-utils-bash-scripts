#!/usr/bin/env bash
# Generic git helpers, not tied to any single script.

# branch_exists <branch-name>
# echoes "1" if the branch exists on the "origin" remote, "0" otherwise.
# Ref: https://stackoverflow.com/questions/8223906/how-to-check-if-remote-branch-exists-on-a-given-remote-repository
branch_exists() {
    local branch="${1}"
    local existed_in_remote
    existed_in_remote=$(git ls-remote --heads origin "${branch}")
    if [ -z "${existed_in_remote}" ]; then
        echo "0"
    else
        echo "1"
    fi
}