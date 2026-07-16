#!/usr/bin/env bash
# All fixed configuration values used across this repo's scripts, in one place.
# Sourced first by shell-utils/utils.sh, before any util_*.sh function file.

# ---- github / org ----
readonly ORG_NAME="devnautica"
readonly MAIN_NAMING="main"
readonly GH_ACTIONS_SECRET_NAME="GH_PAT_FOR_ACTIONS_TOKEN"

# ---- create-project ----
readonly INITIAL_COMMIT_MESSAGE="initial commit"
readonly REPO_DEFAULTS_ALL_DIR=".all"
readonly REPO_DEFAULTS_LANGS_DIR="langs"
readonly REPO_DEFAULTS_APP_TYPES_DIR="app-types"
readonly TEMPLATE_PLACEHOLDER_PREFIX="d3v"
# each entry pairs a language with an app type: "<language>:<app-type>"
readonly PROJECT_TYPE_ARRAY=(
    "java:lib"
    "java:api-be"
    "java:th-be"
    "python:api-be"
    "bash:scripts"
)

# ---- version.sh ----
readonly VERSION_PROPERTIES_FILE=".d3v/app.properties"
readonly VERSION_ENV_FILE="create-new-version.env"
readonly VERSION_BRANCH_PREFIX="v"
readonly VERSION_TAG_PREFIX="version-"
readonly BOT_COMMIT_AUTHOR="bot@devnautica"

# ---- version.sh: per-platform version file (copy_version_to_platform_file) ----
readonly POM_XML_FILE="pom.xml"

# ---- project platform detection (shell-utils) ----
readonly GRADLE_KTS_FILE="build.gradle.kts"
readonly GRADLE_FILE="build.gradle"
readonly SETTINGS_GRADLE_KTS_FILE="settings.gradle.kts"
readonly SETTINGS_GRADLE_FILE="settings.gradle"
readonly ANDROID_MANIFEST_FILE="AndroidManifest.xml"
readonly SWIFT_PACKAGE_FILE="Package.swift"
readonly COCOAPODS_FILE="Podfile"
readonly XCODEPROJ_GLOB="*.xcodeproj"
readonly XCWORKSPACE_GLOB="*.xcworkspace"
readonly IOS_INFO_PLIST_FILE="Info.plist"
readonly REACT_PACKAGE_FILE="package.json"
readonly PYTHON_SRC_DIR="src"
readonly PYTHON_FILE_GLOB="*.py"
readonly PYTHON_VERSION_FILE="src/config/version.txt"
readonly KMP_COMMON_MAIN_DIR="src/commonMain"
