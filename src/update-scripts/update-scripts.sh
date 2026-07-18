#!/usr/bin/env bash
# update-scripts.sh — refresh a consuming project's .d3v/ tooling from the latest
# d3v-utils-bash-scripts GitHub release.
#
# It downloads the latest release archive (built by this repo's publish workflow:
# <app.fullname>-<version>.tar.gz, containing src/, LICENSE, README.md), unpacks
# it, and:
#   1. copies the runnable script folders into the project's .d3v/ root, and
#   2. if the archive carries an app-type template matching this project's
#      language+type (from app.properties), refreshes that template's .github/
#      (CI workflows) into the project root.
# The .d3v/ root is the directory this script is run from.
#
# app.properties (the project's own version state) is NEVER touched, and only
# .github/ is refreshed at the project root — pom.xml, sources, etc. are left alone.
#
# Self-contained on purpose: it must be able to (re)install shell-utils, so it
# does NOT source constants.sh / utils.sh. Runs in CI and locally. GH_TOKEN or
# GITHUB_TOKEN, if set, authenticates against a private source repo.
set -euo pipefail

# ---- config -----------------------------------------------------------------
readonly SOURCE_REPO="devnautica/d3v-utils-bash-scripts"
# folders inside the archive's src/ that a consuming project's .d3v/ needs.
# update-scripts itself is intentionally NOT refreshed here: removing the folder
# of the currently-running script mid-run is unsafe (bash reads scripts lazily).
readonly REFRESH_DIRS=("version" "shell-utils" "github-actions")
# mirrors shell-utils/constants.sh's TEMPLATE_PLACEHOLDER_PREFIX; duplicated (not
# sourced) on purpose — see the self-contained note above.
readonly TEMPLATE_PLACEHOLDER_PREFIX="d3v"

# ---- locate the project's .d3v root -----------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# walk up from this script until a directory named ".d3v" is found — works whether
# this lives at .d3v/update-scripts/update-scripts.sh or flat at .d3v/update-scripts.sh
resolve_d3v_dir() {
    local d="${SCRIPT_DIR}"
    while [ "${d}" != "/" ]; do
        if [ "$(basename "${d}")" = ".d3v" ]; then
            printf '%s' "${d}"
            return 0
        fi
        d="$(dirname "${d}")"
    done
    return 1
}

if ! D3V_DIR="$(resolve_d3v_dir)"; then
    echo "update-scripts: ERROR — not inside a project's .d3v/ directory; nothing to update." >&2
    echo "update-scripts: run this from within a project's .d3v/ (e.g. ./.d3v/update-scripts/update-scripts.sh)." >&2
    exit 1
fi
echo "update-scripts: target .d3v root = ${D3V_DIR}"

# read a single key=value from the project's app.properties (self-contained)
_get_prop() {
    grep -m1 "^$1=" "${D3V_DIR}/app.properties" 2>/dev/null | cut -d= -f2-
}

# ---- template-placeholder vars -----------------------------------------------
# create-project resolved these once at scaffold time and wrote them as literal
# values into app.properties (org.name, app.name, app.fullname, app.language,
# app.type — see repo-defaults/.all/.d3v/app.properties). Re-export them under
# the same names create-project used (ORG_NAME, PROJECT_NAME, PROJECT_FULL_NAME,
# PROJECT_LANGUAGE, PROJECT_APP_TYPE) so apply_template_placeholders below can
# fill in any $d3v{...} placeholder refreshed files carry, exactly as create-project does.
export ORG_NAME PROJECT_NAME PROJECT_FULL_NAME PROJECT_LANGUAGE PROJECT_APP_TYPE
ORG_NAME="$(_get_prop org.name)"
PROJECT_NAME="$(_get_prop app.name)"
PROJECT_FULL_NAME="$(_get_prop app.fullname)"
PROJECT_LANGUAGE="$(_get_prop app.language)"
PROJECT_APP_TYPE="$(_get_prop app.type)"

# replace a single occurrence of a $<TEMPLATE_PLACEHOLDER_PREFIX>{VAR_NAME} placeholder
# in-place, without relying on `sed -i` (its syntax differs between BSD sed on macOS and
# GNU sed on Ubuntu). Mirrors create-project-utils.sh's _replace_placeholder_in_file.
_replace_placeholder_in_file() {
    local file="$1" var_name="$2" var_value="$3"
    local escaped_value
    escaped_value=$(printf '%s' "${var_value}" | sed -e 's/[\&|]/\\&/g')
    sed "s|\\\$"${TEMPLATE_PLACEHOLDER_PREFIX}"{${var_name}}|${escaped_value}|g" "${file}" > "${file}.${TEMPLATE_PLACEHOLDER_PREFIX}_tmp" \
        && mv "${file}.${TEMPLATE_PLACEHOLDER_PREFIX}_tmp" "${file}"
}

# walk every file under a directory and fill in any $<TEMPLATE_PLACEHOLDER_PREFIX>{VAR_NAME}
# placeholder (eg. $d3v{ORG_NAME}, $d3v{PROJECT_NAME}) with the matching variable already
# exported above; a placeholder whose variable isn't set is left untouched with a warning.
# Mirrors create-project-utils.sh's apply_template_placeholders, generalized to take a
# target directory instead of hard-coding PROJECT_FULL_NAME (update-scripts refreshes
# into an existing project rather than a freshly cloned one).
apply_template_placeholders() {
    local target_dir="$1"
    [ -d "${target_dir}" ] || return 0
    echo "update-scripts: substituting \$${TEMPLATE_PLACEHOLDER_PREFIX}{...} placeholders under ${target_dir}..."
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
                echo "update-scripts: WARNING — ${placeholder} found in ${file} but \$${var_name} is not set; leaving as-is" >&2
                continue
            fi
            _replace_placeholder_in_file "${file}" "${var_name}" "${var_value}"
        done
    done < <(find "${target_dir}" -type f -not -path "*/.git/*" -print0)
}

# ---- token (optional for public repos, required for private) ----------------
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

# ---- temp workspace ---------------------------------------------------------
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
archive="${tmp_dir}/d3v-utils-latest.tar.gz"

# curl with the auth header only when a token is present (avoids empty-array pitfalls)
_curl() {
    if [ -n "${TOKEN}" ]; then
        curl -fsSL -H "Authorization: Bearer ${TOKEN}" "$@"
    else
        curl -fsSL "$@"
    fi
}

# ---- download the latest release archive ------------------------------------
download_latest_archive() {
    # gh CLI is the preferred path: handles auth + private repos + "latest" for us.
    # It is present on GitHub Actions runners and on machines that use create-project.
    if command -v gh >/dev/null 2>&1; then
        echo "update-scripts: downloading latest release via gh CLI..."
        GH_TOKEN="${TOKEN}" gh release download \
            --repo "${SOURCE_REPO}" \
            --pattern '*.tar.gz' \
            --output "${archive}" \
            --clobber
        return
    fi

    echo "update-scripts: gh CLI not found, falling back to the GitHub REST API..."
    local api="https://api.github.com/repos/${SOURCE_REPO}/releases/latest"
    local release_json
    release_json="$(_curl -H "Accept: application/vnd.github+json" "${api}")"

    if command -v jq >/dev/null 2>&1; then
        # asset .url + octet-stream works for private repos too
        local asset_api_url
        asset_api_url="$(printf '%s' "${release_json}" \
            | jq -r '.assets[] | select(.name | endswith(".tar.gz")) | .url' | head -n1 || true)"
        [ -n "${asset_api_url}" ] || { echo "update-scripts: ERROR — no .tar.gz asset on latest release." >&2; exit 1; }
        _curl -L -H "Accept: application/octet-stream" "${asset_api_url}" -o "${archive}"
    else
        # no jq: best-effort parse of browser_download_url (public repos)
        local dl_url
        dl_url="$(printf '%s' "${release_json}" \
            | grep -Eo '"browser_download_url":[[:space:]]*"[^"]+\.tar\.gz"' \
            | head -n1 | sed -E 's/.*"(https?:\/\/[^"]+)"$/\1/' || true)"
        [ -n "${dl_url}" ] || { echo "update-scripts: ERROR — no .tar.gz asset on latest release." >&2; exit 1; }
        _curl -L "${dl_url}" -o "${archive}"
    fi
}

download_latest_archive

# ---- unpack -----------------------------------------------------------------
echo "update-scripts: unpacking archive..."
tar -xzf "${archive}" -C "${tmp_dir}"

# the archive's top dir is <app.fullname>-<version>/ ; find its src/ robustly
src_dir="$(find "${tmp_dir}" -maxdepth 2 -type d -name src | head -n1)"
if [ -z "${src_dir}" ]; then
    echo "update-scripts: ERROR — archive contains no src/ directory." >&2
    exit 1
fi

# ---- refresh script folders into .d3v (never touching app.properties) -------
# app.properties lives directly in .d3v/ and is not one of REFRESH_DIRS, so it is
# left exactly as-is; only the whole script subfolders are replaced.
for d in "${REFRESH_DIRS[@]}"; do
    if [ -d "${src_dir}/${d}" ]; then
        rm -rf "${D3V_DIR:?}/${d}"
        cp -R "${src_dir}/${d}" "${D3V_DIR}/${d}"
        echo "update-scripts: refreshed .d3v/${d}"
    else
        echo "update-scripts: WARNING — '${d}' not found in archive, skipping."
    fi
done

apply_template_placeholders "${D3V_DIR}"

# ---- refresh this project's app-type CI (.github) from the archive ----------
# The archive carries per-project-type CI templates under
# github-actions/<language>/<app-type>/. If one matches this project's
# language+type (from app.properties), refresh only its .github/ (CI workflows)
# into the project root — pom.xml, sources, and other root files are left
# untouched. Same-named workflow files are overwritten; unrelated files already
# under the project's .github/ are kept.
apply_app_type_github() {
    local project_root language app_type app_type_github
    project_root="$(dirname "${D3V_DIR}")"
    language="$(_get_prop app.language)"
    app_type="$(_get_prop app.type)"

    if [ -z "${language}" ] || [ -z "${app_type}" ]; then
        echo "update-scripts: app.language/app.type missing from app.properties, skipping CI refresh."
        return
    fi

    app_type_github="${src_dir}/github-actions/${language}/${app_type}/.github"
    if [ -d "${app_type_github}" ]; then
        echo "update-scripts: refreshing .github/ from github-actions template ${language}/${app_type}..."
        mkdir -p "${project_root}/.github"
        cp -R "${app_type_github}/." "${project_root}/.github/"
        apply_template_placeholders "${project_root}/.github"
        echo "update-scripts: refreshed ${language}/${app_type} CI into ${project_root}/.github"
    else
        echo "update-scripts: no .github/ template for '${language}/${app_type}' in github-actions, skipping CI refresh."
    fi

  # Add everything to the VCS, we want to keep version within VCS
  git add -A "${project_root}/.d3v"

  # Remove github actions, since they are not required once update is done
  rm -fr "${project_root}/.github-actions"
}
apply_app_type_github


echo "update-scripts: done. app.properties left untouched."
