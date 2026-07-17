#!/usr/bin/env bash
# Functions specific to version.sh (app.properties bump / branch+tag/merge flow).
# Depends on SCRIPT_DIR being exported by the caller (version.sh) to this file's directory.

# shellcheck source=../shell-utils/utils.sh
source "${SCRIPT_DIR}/../shell-utils/utils.sh"

# ---- app.properties (key=value) helpers --------------------------------

get_version_field() {
    local key="$1"
    grep -m1 "^${key}=" "${VERSION_PROPERTIES_FILE}" 2>/dev/null | cut -d= -f2-
}

set_version_field() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "${VERSION_PROPERTIES_FILE}" 2>/dev/null; then
        sed "s|^${key}=.*|${key}=${value}|" "${VERSION_PROPERTIES_FILE}" > "${VERSION_PROPERTIES_FILE}.tmp" \
            && mv "${VERSION_PROPERTIES_FILE}.tmp" "${VERSION_PROPERTIES_FILE}"
    else
        echo "${key}=${value}" >> "${VERSION_PROPERTIES_FILE}"
    fi
}

# ---- version bump ------------------------------------------------------------

# resolves the next MAJOR.MINOR.PATCH[.BUGFIX] tag from version.current.tag, bumps
# version.current.buildnumber by 1, and moves the old tag/buildnumber into
# version.previous.tag/version.previous.buildnumber - all persisted to
# app.properties. Exports NEW_VERSION and MERGE_TO_MAIN (0 if this ends up being
# a bugfix version, since that implies the newer patch already had a problem and a
# human should merge manually).
increment_version() {
    local old_tag old_build_number new_build_number
    old_tag="$(get_version_field "version.current.tag")"
    old_build_number="$(get_version_field "version.current.buildnumber")"
    [ -z "${old_build_number}" ] && old_build_number=0

    export MAJOR_MINOR_VERSION=$(echo "${old_tag}" | awk -F . '{print $1 "." $2}')
    export PATCH_VERSION=$(echo "${old_tag}" | awk -F . '{print $3}')
    export BUGFIX_VERSION=$(echo "${old_tag}" | awk -F . '{print $4}')
    export NEW_PATCH_VERSION=$(($PATCH_VERSION + 1))
    export NEW_VERSION="${MAJOR_MINOR_VERSION}.${NEW_PATCH_VERSION}"
    echo "Proposed new version: ${NEW_VERSION}"

    export MERGE_TO_MAIN=1
    local keep_looking=1
    while [ ${keep_looking} -gt 0 ]; do
        if [ $(branch_exists "${VERSION_BRANCH_PREFIX}${NEW_VERSION}") = "1" ]
        then
            echo "Proposed new version ${NEW_VERSION} already exist"
            if [ -z ${BUGFIX_VERSION} ]
            then
                echo "This is a bugfix version"
                export BUGFIX_VERSION=1
            else
                echo "Incrementing bugfix version"
                export BUGFIX_VERSION=$((BUGFIX_VERSION + 1))
            fi
            export NEW_VERSION="${MAJOR_MINOR_VERSION}.${PATCH_VERSION}.${BUGFIX_VERSION}"
            export MERGE_TO_MAIN=0
        else
            echo "Branch ${NEW_VERSION} doesn't exist, creating"
            keep_looking=0
        fi
    done

    new_build_number=$((old_build_number + 1))
    set_version_field "version.previous.tag" "${old_tag}"
    set_version_field "version.previous.buildnumber" "${old_build_number}"
    set_version_field "version.current.tag" "${NEW_VERSION}"
    set_version_field "version.current.buildnumber" "${new_build_number}"
}

# ---- per-platform version file -----------------------------------------------

# copies version.current.tag (from app.properties) into whichever file the
# detected $PLATFORM actually stores its version in. android/kmp also get
# version.current.buildnumber, since gradle's versionCode wants an integer.
copy_version_to_platform_file() {
    local version_tag build_number
    version_tag="$(get_version_field "version.current.tag")"
    build_number="$(get_version_field "version.current.buildnumber")"

    case "${PLATFORM}" in
        java)
            _write_version_to_pom "${version_tag}"
            ;;
        android|kmp)
            _write_version_to_gradle "${version_tag}" "${build_number}"
            ;;
        ios)
            echo "copy_version_to_platform_file: platform 'ios' not wired up yet, skipping"
            ;;
        *)
            echo "copy_version_to_platform_file: unknown platform '${PLATFORM}', nothing to update"
            ;;
    esac
}

# resolves the language for the current repo: $PLATFORM when util_resolve-platform.sh
# recognized it, or app.language out of app.properties when it didn't (PLATFORM=unknown -
# eg. this repo's own plain bash scripts, which has no marker file for
# util_resolve-platform.sh to detect).
resolve_platform_language() {
    if [ "${PLATFORM}" = "unknown" ]; then
        get_version_field "app.language"
    else
        echo "${PLATFORM}"
    fi
}

# writes the given version into pom.xml's own <version> tag - if there's a <parent>
# block, its own <version> is skipped; works for pom.xml with or without a <parent>
# (eg. a standalone java-lib pom.xml has none). Edits directly instead of shelling
# out to `mvn versions:set` (JVM start + plugin resolution cost several seconds).
_write_version_to_pom() {
    #TODO: git checkout might throw: fatal: A branch named 'v1.0.20' already exists., then we need to do something about it ;-)
    local new_version="${1}"
    awk -v new="${new_version}" '
        /<parent>/ { in_parent=1 }
        /<\/parent>/ { in_parent=0 }
        (!in_parent && !done && /<version>/) { sub(/<version>[^<]*<\/version>/, "<version>" new "</version>"); done=1 }
        { print }
    ' "${POM_XML_FILE}" > "${POM_XML_FILE}.tmp" && mv "${POM_XML_FILE}.tmp" "${POM_XML_FILE}"
}

# echoes whichever gradle build file this project actually has (kts preferred)
_resolve_gradle_file() {
    if [ -f "${GRADLE_KTS_FILE}" ]; then
        echo "${GRADLE_KTS_FILE}"
    else
        echo "${GRADLE_FILE}"
    fi
}

# writes versionName (the tag) and versionCode (the buildnumber) into build.gradle(.kts) -
# handles both the Kotlin DSL ("versionName = \"x\"") and Groovy DSL ("versionName \"x\"") styles
_write_version_to_gradle() {
    local new_version="${1}" new_build_number="${2}" gradle_file
    gradle_file="$(_resolve_gradle_file)"
    sed -E \
        -e "s/(versionName[[:space:]]*=?[[:space:]]*)\"[^\"]*\"/\1\"${new_version}\"/" \
        -e "s/(versionCode[[:space:]]*=?[[:space:]]*)[0-9]+/\1${new_build_number}/" \
        "${gradle_file}" > "${gradle_file}.tmp" && mv "${gradle_file}.tmp" "${gradle_file}"
}

# app.properties is always modified; the per-platform file (eg. pom.xml for java,
# build.gradle(.kts) for android/kmp) is added on top of that, if this platform has one
add_version_file_to_git() {
    git add "${VERSION_PROPERTIES_FILE}"
    case "${PLATFORM}" in
        java)
            git add "${POM_XML_FILE}"
            ;;
        android|kmp)
            git add "$(_resolve_gradle_file)"
            ;;
    esac
}

# ---- branch / merge flow ------------------------------------------------------

# checks whether a non-bot commit landed on origin/$MAIN_NAMING after this run's commit
# (ie. someone pushed while the version bump was in flight); if so, rolls back the
# branch/tag just created and marks the deploy to be skipped
# pokud je po tomto commitu comit co neni od bota
# zaroven pokud je po tomto commitu comit - posledni commit, ktery je od bota
# ceka pipelina, ktera chce zvednout verzi ( z puvodni stare )
# chci smazat branch
check_if_there_is_forward_commit_and_act() {
    local NEW_VERSION=${1}
    git fetch
    #Check for commit
    local rev_list_results=$(git rev-list ${CI_COMMIT_SHA}..origin/${MAIN_NAMING} -n 10 --author="^((?!${BOT_COMMIT_AUTHOR}).)*\$" --perl-regexp)

    # Variable is not empty
    if [ ! -z ${rev_list_results} ]
    then
        echo "There is commit after versioning ${rev_list_results}"
        local commit_to_be_removed=$(git rev-list ${CI_COMMIT_SHA}..origin/${MAIN_NAMING} -n 10 --author="${BOT_COMMIT_AUTHOR}" --perl-regexp)

        if [ ! -z ${rev_list_results} ]
        then
            echo "There is commit from robot ${commit_to_be_removed}"
            #version 1.0.136
            git stash
            echo "Drop version (commit:${commit_to_be_removed}) and changes, build, test, but skip deploy"
            #git revert ${commit_to_be_removed} --no-commit
            git push -d origin "${VERSION_BRANCH_PREFIX}${NEW_VERSION}"
            git branch -d "${VERSION_BRANCH_PREFIX}${NEW_VERSION}"
            #git tag -d version-${NEW_VERSION}
            #git push --delete origin version-${NEW_VERSION}
            git tag --delete "${VERSION_TAG_PREFIX}${NEW_VERSION}"
            # skip publish, skip deploy
            echo "SKIP_DEPLOY=1" >>"${VERSION_ENV_FILE}"
        fi
    fi
}

# creates the v<version> branch, commits the bumped version files, tags it, and pushes
publish_new_version_branch() {
    local new_version="${1}"
    git checkout -b "${VERSION_BRANCH_PREFIX}${new_version}" HEAD --
    add_version_file_to_git
    echo "ADDED FILES"
    git commit -m "Updated version to ${new_version}"
    echo "COMMITED FILES"
    git tag "${VERSION_TAG_PREFIX}${new_version}"
    echo "TAGGED FILES"
    git push --set-upstream origin "${VERSION_BRANCH_PREFIX}${new_version}" -o ci.skip #required to push creation of the branch
    # pushing the branch does NOT also push this tag - it needs its own explicit push,
    # and other jobs (eg. build) rely on this tag existing on origin to check it out
    git push origin "${VERSION_TAG_PREFIX}${new_version}"
    echo "BUILD_VERSION=${new_version}" >>"${VERSION_ENV_FILE}"
    echo "PLATFORM_LANGUAGE=$(resolve_platform_language)" >>"${VERSION_ENV_FILE}"
}

# TODO If version doesn't contain bug version (only major.minor.patch) check for duplicates on the main and resolve atomicity
#  If version contains bug version, then don't merge and send notification to slack
finalize_version_merge() {
    local new_version="${1}"
    if [ ${MERGE_TO_MAIN} = 1 ]
    then
        git checkout -B "${MAIN_NAMING}" "origin/${MAIN_NAMING}" --
        git merge "${VERSION_BRANCH_PREFIX}${new_version}"
        git push -o ci.skip
    else
        echo ""
        echo "=========================NOTE FOR DEVELOPERS==============================="
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "NO MERGE TO MAIN AS THERE MIGHT BE ISSUES"
        echo "Merge manually"
        echo "=========================NOTE FOR DEVELOPERS==============================="
        echo "==========================================================================="
    fi
    check_if_there_is_forward_commit_and_act "${new_version}"
}
