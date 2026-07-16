#!/usr/bin/env bash
set -e

DELETE_PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DELETE_PROJECT_DIR
# shellcheck source=./utils/delete-project-utils.sh
source "${DELETE_PROJECT_DIR}/utils/delete-project-utils.sh"

require_command git gh
require_gh_auth

list_org_repos
prompt_repo_to_delete
delete_selected_repo