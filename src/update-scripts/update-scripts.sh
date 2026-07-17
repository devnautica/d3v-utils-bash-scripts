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
        echo "update-scripts: refreshed ${language}/${app_type} CI into ${project_root}/.github"
    else
        echo "update-scripts: no .github/ template for '${language}/${app_type}' in github-actions, skipping CI refresh."
    fi
}
apply_app_type_github

echo "update-scripts: done. app.properties left untouched."