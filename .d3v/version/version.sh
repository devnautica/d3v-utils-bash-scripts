#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR
# shellcheck source=./utils/version-utils.sh
source "${SCRIPT_DIR}/utils/version-utils.sh"

echo "CURRENT BRANCH: $CI_COMMIT_BRANCH"

increment_version
echo "NEW VERSION: ${NEW_VERSION}"

copy_version_to_platform_file

publish_new_version_branch "${NEW_VERSION}"
finalize_version_merge "${NEW_VERSION}"
