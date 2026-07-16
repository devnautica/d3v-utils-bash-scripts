#!/usr/bin/env bash
# Functions specific to delete-project.sh (list + delete a repo under ORG_NAME).
# Depends on DELETE_PROJECT_DIR being exported by the caller (delete-project.sh) to this
# file's directory (so shell-utils/ resolves regardless of the caller's working directory).

# shellcheck source=../../shell-utils/utils.sh
source "${DELETE_PROJECT_DIR}/../shell-utils/utils.sh"

# populates the REPO_NAMES array with this org's repos, newest (most recently created) first
list_org_repos() {
    echo "Fetching repositories for ${ORG_NAME}..."
    REPO_NAMES=()
    local line
    while IFS= read -r line; do
        REPO_NAMES+=("${line}")
    done < <(gh repo list "${ORG_NAME}" --limit 1000 --json name,createdAt --jq 'sort_by(.createdAt) | reverse | .[].name')

    if [ "${#REPO_NAMES[@]}" -eq 0 ]; then
        echo "No repositories found under ${ORG_NAME}."
        exit 0
    fi
}

# shows the numbered list (1 = most recently pushed) plus "0 = exit", and sets
# SELECTED_REPO_NAME to the chosen one; choosing 0 exits the script immediately
prompt_repo_to_delete() {
    echo "Repositories in ${ORG_NAME} (newest first):"
    local i
    for i in "${!REPO_NAMES[@]}"; do
        echo "$((i + 1))) ${REPO_NAMES[$i]}"
    done
    echo "0) Exit"

    local choice
    while true; do
        read -rp "Select a repository to delete: " choice
        if [ "${choice}" = "0" ]; then
            echo "Exiting, nothing deleted."
            exit 0
        fi
        if [[ "${choice}" =~ ^[0-9]+$ ]] && [ "${choice}" -ge 1 ] && [ "${choice}" -le "${#REPO_NAMES[@]}" ]; then
            SELECTED_REPO_NAME="${REPO_NAMES[$((choice - 1))]}"
            export SELECTED_REPO_NAME
            break
        fi
        echo "Invalid selection, please enter a number from the list above."
    done
}

# a lightweight y/n confirmation (picking the repo from the numbered list above is
# already the main safety net) that skips gh's own "retype <org>/<repo>" prompt via --yes
delete_selected_repo() {
    local confirm
    read -rp "Delete ${ORG_NAME}/${SELECTED_REPO_NAME}? [y/N] " confirm
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
        echo "Exiting, nothing deleted."
        exit 0
    fi
    gh repo delete "${ORG_NAME}/${SELECTED_REPO_NAME}" --yes
}