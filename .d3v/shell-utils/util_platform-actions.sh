#!/usr/bin/env bash
# Name/version/build actions scoped to whichever platform util_resolve-platform.sh
# detected (via $PLATFORM). Depends on constants.sh and util_resolve-platform.sh.

platform_build() {
    case "${PLATFORM}" in
        java)
            mvn clean install
            ;;
        kmp)
            ./gradlew build
            ;;
        android)
            ./gradlew assembleRelease
            ;;
        ios)
            xcodebuild -scheme "$(platform_name)" build
            ;;
        react)
            npm run build
            ;;
        python)
            echo "python: no build step"
            ;;
        *)
            echo "unknown platform: nothing to build"
            ;;
    esac
}

platform_version() {
    case "${PLATFORM}" in
        java)
            mvn help:evaluate -Dexpression=project.version -q -DforceStdout
            ;;
        kmp|android)
            grep -m1 "versionName" "${GRADLE_KTS_FILE}" "${GRADLE_FILE}" 2>/dev/null \
                | sed -E 's/.*versionName[[:space:]]*=?[[:space:]]*"([^"]+)".*/\1/'
            ;;
        ios)
            /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${IOS_INFO_PLIST_FILE}" 2>/dev/null
            ;;
        react)
            node -p "require('./${REACT_PACKAGE_FILE}').version"
            ;;
        python)
            cat "${PYTHON_VERSION_FILE}"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

platform_name() {
    case "${PLATFORM}" in
        java)
            mvn help:evaluate -Dexpression=project.artifactId -q -DforceStdout
            ;;
        kmp|android)
            grep -m1 "rootProject.name" "${SETTINGS_GRADLE_KTS_FILE}" "${SETTINGS_GRADLE_FILE}" 2>/dev/null \
                | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/'
            ;;
        ios)
            basename -- ${XCODEPROJ_GLOB} .xcodeproj 2>/dev/null
            ;;
        react)
            node -p "require('./${REACT_PACKAGE_FILE}').name"
            ;;
        python)
            echo "python"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}