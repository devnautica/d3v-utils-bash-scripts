#!/usr/bin/env bash
# Functions specific to create-project.sh (scaffolding a new GitHub repo from repo-defaults/).
# Depends on CREATE_PROJECT_DIR being exported by the caller (create-project.sh) to this
# file's directory (so repo-defaults/ resolves regardless of the caller's working directory).

# shellcheck source=../shell-utils/utils.sh
source "${CREATE_PROJECT_DIR}/../shell-utils/utils.sh"

prompt_project_name() {
    read -rp "Enter the name of the new project: " PROJECT_NAME
    export PROJECT_NAME
}

# PROJECT_TYPE_ARRAY (from constants.sh) enumerates the available "<language>:<app-type>"
# combos; builds the human-readable choices shown in the select menu (eg. "java-lib")
select_project_type() {
    local project_types=()
    local entry
    for entry in "${PROJECT_TYPE_ARRAY[@]}"; do
        project_types+=("${entry/:/-}")
    done

    echo "Select project type:"
    local project_type_choice selected_entry
    select project_type_choice in "${project_types[@]}"; do
        if [ -n "${project_type_choice}" ]; then
            selected_entry="${PROJECT_TYPE_ARRAY[$((REPLY-1))]}"
            export PROJECT_LANGUAGE="${selected_entry%%:*}"
            export PROJECT_APP_TYPE="${selected_entry#*:}"
            break
        else
            echo "Invalid selection, please enter a number from the list above."
        fi
    done

    echo "Project name: ${PROJECT_NAME}"
    echo "Project language: ${PROJECT_LANGUAGE}"
    echo "Project app type: ${PROJECT_APP_TYPE}"
}

# local folder name: keep it distinct from PROJECT_NAME (the actual repo name on GitHub)
# in case multiple project types ever get cloned side by side
derive_project_full_name() {
    export PROJECT_FULL_NAME="${PROJECT_NAME}-${PROJECT_LANGUAGE}-${PROJECT_APP_TYPE}"
}

create_github_repo() {
    gh repo create "${ORG_NAME}/${PROJECT_FULL_NAME}" --private
}

# set the actions secret as a Repository secret (Settings > Secrets and variables > Actions)
# on the repository we just created, so workflows there (eg. maven-publish.yml) can use it
set_actions_secret() {
    echo "${!GH_ACTIONS_SECRET_NAME}" | gh secret set "${GH_ACTIONS_SECRET_NAME}" --repo "${ORG_NAME}/${PROJECT_FULL_NAME}"
}

# clone the repo created above into a local folder named PROJECT_FULL_NAME
clone_new_repo() {
    git clone "git@github.com:${ORG_NAME}/${PROJECT_FULL_NAME}.git" "${PROJECT_FULL_NAME}"
}

# layer in the shared defaults for the chosen language, then the defaults specific
# to the chosen project type; skip either cp -R if its template folder doesn't exist
copy_repo_defaults() {
    cp -R "${CREATE_PROJECT_DIR}/repo-defaults/${REPO_DEFAULTS_ALL_DIR}/" "${PROJECT_FULL_NAME}"


    cp -R "${CREATE_PROJECT_DIR}/../version/" "${PROJECT_FULL_NAME}/.d3v/version"
    cp -R "${CREATE_PROJECT_DIR}/../shell-utils/" "${PROJECT_FULL_NAME}/.d3v/shell-utils"

    if [ -d "${CREATE_PROJECT_DIR}/repo-defaults/${REPO_DEFAULTS_LANGS_DIR}/${PROJECT_LANGUAGE}" ]; then
        cp -R "${CREATE_PROJECT_DIR}/repo-defaults/${REPO_DEFAULTS_LANGS_DIR}/${PROJECT_LANGUAGE}/" "${PROJECT_FULL_NAME}"
    else
        echo "Skipping: repo-defaults/${REPO_DEFAULTS_LANGS_DIR}/${PROJECT_LANGUAGE} does not exist"
    fi

    if [ -d "${CREATE_PROJECT_DIR}/repo-defaults/${REPO_DEFAULTS_APP_TYPES_DIR}/${PROJECT_LANGUAGE}/${PROJECT_APP_TYPE}" ]; then
        cp -R "${CREATE_PROJECT_DIR}/repo-defaults/${REPO_DEFAULTS_APP_TYPES_DIR}/${PROJECT_LANGUAGE}/${PROJECT_APP_TYPE}/" "${PROJECT_FULL_NAME}"
    else
        echo "Skipping: repo-defaults/${REPO_DEFAULTS_APP_TYPES_DIR}/${PROJECT_LANGUAGE}/${PROJECT_APP_TYPE} does not exist"
    fi
}

# replace a single occurrence of a $<TEMPLATE_PLACEHOLDER_PREFIX>{VAR_NAME} placeholder
# in-place, without relying on `sed -i` (its syntax differs between BSD sed on macOS and
# GNU sed on Ubuntu)
_replace_placeholder_in_file() {
    local file="$1" var_name="$2" var_value="$3"
    local escaped_value
    escaped_value=$(printf '%s' "${var_value}" | sed -e 's/[\&|]/\\&/g')
    sed "s|\\\$"${TEMPLATE_PLACEHOLDER_PREFIX}"{${var_name}}|${escaped_value}|g" "${file}" > "${file}.${TEMPLATE_PLACEHOLDER_PREFIX}_tmp" \
        && mv "${file}.${TEMPLATE_PLACEHOLDER_PREFIX}_tmp" "${file}"
}

# walk every file copied from repo-defaults and fill in any $<TEMPLATE_PLACEHOLDER_PREFIX>{VAR_NAME}
# placeholder (eg. $d3v{ORG_NAME}, $d3v{PROJECT_FULL_NAME}) with the matching variable from
# this script's environment; a placeholder whose variable isn't set is left untouched with a warning
apply_template_placeholders() {
    echo "Substituting \$${TEMPLATE_PLACEHOLDER_PREFIX}{...} placeholders in copied template files..."
    local file placeholders placeholder var_name var_value
    local placeholder_prefix="\$${TEMPLATE_PLACEHOLDER_PREFIX}{"
    while IFS= read -r -d '' file; do
        grep -Iq . "${file}" 2>/dev/null || continue # skip binary files
        placeholders=$(grep -oE '\$'"${TEMPLATE_PLACEHOLDER_PREFIX}"'\{[A-Za-z_][A-Za-z0-9_]*\}' "${file}" | sort -u)
        for placeholder in ${placeholders}; do
            var_name="${placeholder#$placeholder_prefix}"
            var_name="${var_name%\}}"
            var_value="${!var_name:-}"
            if [ -z "${var_value}" ]; then
                echo "Warning: ${placeholder} found in ${file} but \$${var_name} is not set; leaving as-is" >&2
                continue
            fi
            _replace_placeholder_in_file "${file}" "${var_name}" "${var_value}"
        done
    done < <(find "${PROJECT_FULL_NAME}" -type f -not -path "*/.git/*" -print0)
}

commit_and_push_new_project() {
    cd "${PROJECT_FULL_NAME}"
    git add -A
    git commit -m "${INITIAL_COMMIT_MESSAGE}"
    git push
    cd ..
}

cleanup_local_clone() {
    rm -fr "${PROJECT_FULL_NAME}"
}
