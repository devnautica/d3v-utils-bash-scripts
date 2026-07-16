#!/usr/bin/env bash
# Host/CLI environment checks: required tools, gh auth, OS detection, shell
# profile resolution, and a generic "prompt for and persist a missing env var".

require_command() {
    local cmd
    for cmd in "$@"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            echo "Error: '${cmd}' is not installed or not on PATH. Please install it and try again." >&2
            exit 1
        fi
    done
}

require_gh_auth() {
    if ! gh auth status >/dev/null 2>&1; then
        echo "Error: gh is not authenticated. Run 'gh auth login' and try again." >&2
        exit 1
    fi
}

# exports HOST_OS ("macos" or "linux"); only these two platforms are supported
detect_host_os() {
    case "$(uname -s)" in
        Darwin) export HOST_OS="macos" ;;
        Linux)  export HOST_OS="linux" ;;
        *)
            echo "Error: unsupported platform '$(uname -s)'. Only macOS and Ubuntu Linux are supported." >&2
            exit 1
            ;;
    esac
}

# exports SHELL_PROFILE, the rc file env vars should be persisted into; based on
# the user's login shell, falling back to each HOST_OS's typical default shell.
# call detect_host_os first.
resolve_shell_profile() {
    case "${SHELL:-}" in
        */zsh)  export SHELL_PROFILE="${HOME}/.zshrc" ;;
        */bash) export SHELL_PROFILE="${HOME}/.bashrc" ;;
        *)
            if [ "${HOST_OS}" = "macos" ]; then
                export SHELL_PROFILE="${HOME}/.zshrc"
            else
                export SHELL_PROFILE="${HOME}/.bashrc"
            fi
            ;;
    esac
}

# ensure_env_var <VAR_NAME> <prompt text>
# if VAR_NAME isn't already set, prompts for it (hidden input, since these are
# typically secrets/tokens), exports it, and persists it to SHELL_PROFILE so
# future shells/runs don't have to ask again. Call resolve_shell_profile first.
ensure_env_var() {
    local var_name="$1" prompt_text="$2"
    local current_value="${!var_name:-}"
    if [ -n "${current_value}" ]; then
        return 0
    fi

    echo "${var_name} is not set in your environment."
    local input_value
    read -rsp "${prompt_text}: " input_value
    echo
    export "${var_name}=${input_value}"
    echo "export ${var_name}=\"${input_value}\"" >> "${SHELL_PROFILE}"
    echo "Saved ${var_name} to ${SHELL_PROFILE}. Run 'source ${SHELL_PROFILE}' (or restart your shell) so future sessions pick it up."
}