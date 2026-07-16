#!/usr/bin/env bash
set -e

CREATE_PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CREATE_PROJECT_DIR
# shellcheck source=./create-project-utils.sh
source "${CREATE_PROJECT_DIR}/utils/create-project-utils.sh"

# This script is being run locally by the user.
# It accounts with user having configured gh in command line to the given organization

require_command git gh
require_gh_auth
detect_host_os
resolve_shell_profile
ensure_env_var "${GH_ACTIONS_SECRET_NAME}" "Enter your ${GH_ACTIONS_SECRET_NAME}"

prompt_project_name
select_project_type
derive_project_full_name

create_github_repo
set_actions_secret
clone_new_repo
copy_repo_defaults
apply_template_placeholders
commit_and_push_new_project
cleanup_local_clone
