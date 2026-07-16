#!/usr/bin/env bash
# Entry point for shell-utils: sources constants.sh, then every util_*.sh file.
# Sourced by version-utils.sh and create-project-utils.sh - don't put functions
# directly in this file, add a new util_<topic>.sh instead and source it below.

UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./constants.sh
source "${UTILS_DIR}/constants.sh"

# shellcheck source=./util_host-env.sh
source "${UTILS_DIR}/util_host-env.sh"
# shellcheck source=./util_git.sh
source "${UTILS_DIR}/util_git.sh"
# shellcheck source=./util_resolve-platform.sh
source "${UTILS_DIR}/util_resolve-platform.sh"
# shellcheck source=./util_platform-actions.sh
source "${UTILS_DIR}/util_platform-actions.sh"