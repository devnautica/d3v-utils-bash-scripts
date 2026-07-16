#!/usr/bin/env bash
# Detects what kind of project the *current directory* is. Order matters: more
# specific platforms (kmp, android) are checked before the generic gradle/java
# case would otherwise misclassify them. Depends on constants.sh.

_has_file() {
    [ -f "$1" ]
}

_find_first() {
    # usage: _find_first <start-dir> <name-pattern>
    find "$1" -type f -name "$2" -print -quit 2>/dev/null
}

is_kmp_platform() {
    if _has_file "${GRADLE_KTS_FILE}" && grep -q "multiplatform" "${GRADLE_KTS_FILE}" 2>/dev/null; then
        return 0
    fi
    [ -d "${KMP_COMMON_MAIN_DIR}" ]
}

is_android_platform() {
    [ -n "$(_find_first . "${ANDROID_MANIFEST_FILE}")" ]
}

is_ios_platform() {
    if _has_file "${SWIFT_PACKAGE_FILE}" || _has_file "${COCOAPODS_FILE}"; then
        return 0
    fi
    [ -n "$(_find_first . "${XCODEPROJ_GLOB}")" ] || [ -n "$(_find_first . "${XCWORKSPACE_GLOB}")" ]
}

is_maven_platform() {
    _has_file "${POM_XML_FILE}"
}

is_react_platform() {
    _has_file "${REACT_PACKAGE_FILE}" && grep -q '"react"' "${REACT_PACKAGE_FILE}"
}

is_python_platform() {
    [ -n "$(_find_first "${PYTHON_SRC_DIR}" "${PYTHON_FILE_GLOB}")" ]
}

resolve_platform() {
    if is_kmp_platform; then
        echo "kmp"
    elif is_android_platform; then
        echo "android"
    elif is_ios_platform; then
        echo "ios"
    elif is_maven_platform; then
        echo "java"
    elif is_react_platform; then
        echo "react"
    elif is_python_platform; then
        echo "python"
    else
        echo "unknown"
    fi
}

PLATFORM="$(resolve_platform)"
echo "shell-utils: detected platform '${PLATFORM}'"