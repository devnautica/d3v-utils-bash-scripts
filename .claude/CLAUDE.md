# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Ultimate Rules

These rules override default tool-permission behavior for this repository. More ultimate rules will be added by hand over time — append new ones below the existing bullets, keep each self-contained.

- **File reads**: reading any file, anywhere, never requires a permission prompt — enforced via `.claude/settings.json`'s `permissions.allow: ["Read"]` (the bare tool-name rule, not a glob pattern — globs like `Read(**)` proved unreliable and still prompted). The only exception is `.env`-style files (`.env`, `.env.*`, and the same at any depth), which are in `permissions.ask` and should still prompt. Don't rely on a text instruction alone to suppress this prompt — fix it in `settings.json`.

- **Command history**: every user prompt is logged verbatim to `.claude/command-history.txt` (entries separated by `----`). This happens automatically via a `UserPromptSubmit` hook in `.claude/settings.json` — it runs before the prompt is processed, so it captures every message first thing, every session. If that hook is ever unavailable, append the user's message to that file yourself before doing anything else.

- **Root `.d3v/` folder**: this repo has its own top-level `.d3v/` (sibling of `src/`), populated by running `create-project`/`update-scripts` against this repo itself for local dogfooding/testing. It is not source — `src/` is the single source of truth (see Purpose below). Don't read, `find`/`grep` into, or otherwise use `.d3v/` as context when reasoning about this repo's code; if a task specifically involves inspecting or modifying that dogfood output, only then look at it, and say so.

## Git

Never run `git commit` or `git push` in this repository, even if asked to perform the full workflow. Make the requested changes and let the user review and commit/push manually.

Always `git add` any file you create, so new files are staged for the user's review. A `PostToolUse` hook in `.claude/settings.json` already does this automatically after every `Write`; keep doing it explicitly too if you create a file by other means. Staging only — never `git commit`/`git push` (see above).

## Purpose

This repo (`d3v-utils-bash-scripts`) is devnautica's source of truth for local tooling + CI/CD scripts shared across their projects (java, react, python, kmp, ios native, android/kotlin native — see root `README.md`). It is licensed under PolyForm Noncommercial 1.0.0 (`LICENSE`) — noncommercial use only; commercial use requires contacting `boss@devnautica.com`.

There is no build system, package manager, or test suite here — it's plain shell + YAML. Validate changes by reading the script logic and, where possible, tracing through the workflow steps manually; `bash -n <file>` for a quick syntax check.

Two kinds of scripts live under `src/`:
- **Local tooling**, run by a developer on their own machine: `src/create-project/` (scaffold a new devnautica GitHub repo) and its sibling `delete-project.sh`.
- **CI scripts**, copied into a consuming repo and run by GitHub Actions: `src/version/version.sh` (auto-versioning).

Both kinds share one library: `src/shell-utils/`.

## `src/shell-utils/` — the shared library

- `constants.sh` — every fixed config value used anywhere in this repo (org name, file names, path prefixes, the `PROJECT_TYPE_ARRAY` enumeration, etc). Sourced first, before anything else.
- `util_host-env.sh` — CLI/host checks: `require_command`, `require_gh_auth`, `detect_host_os`, `resolve_shell_profile`, `ensure_env_var` (prompt for + persist a missing secret to the user's shell rc file).
- `util_git.sh` — `branch_exists`.
- `util_resolve-platform.sh` — detects what kind of project the *current directory* is (`java`/`kmp`/`android`/`ios`/`react`/`python`/`unknown`) into `$PLATFORM`, based on marker files (`pom.xml`, `build.gradle(.kts)` + `multiplatform`/`src/commonMain`, `AndroidManifest.xml`, `Package.swift`/`Podfile`/`*.xcodeproj`, `package.json` + `"react"`, `src/*.py`). Order matters — more specific platforms (kmp, android) are checked before the generic java/gradle case.
- `util_platform-actions.sh` — `platform_build`/`platform_version`/`platform_name`, dispatching on `$PLATFORM`.
- `utils.sh` — the entry point: sources `constants.sh` then every `util_*.sh`. Don't add functions directly to `utils.sh`; add a new `util_<topic>.sh` and source it there instead.

**Sourcing pattern used everywhere in this repo**: a runner script (`version.sh`, `create-project.sh`, `delete-project.sh`) computes its own directory via `BASH_SOURCE`, exports it (`SCRIPT_DIR`, `CREATE_PROJECT_DIR`, `DELETE_PROJECT_DIR`), and sources its one `<topic>-utils.sh` file. That `-utils.sh` file itself sources `shell-utils/utils.sh` (using the exported dir var to find `../shell-utils/utils.sh`), pulling in constants + shared helpers transitively. The runner script ends up being **just an ordered list of function calls** — all the actual logic lives in the `-utils.sh` files, not the runner.

## `src/version/` — auto-versioning (see `src/version/README.md` + `resources/versioning-flow.png` for the full picture)

- `version.sh` — runner: `increment_version` → `copy_version_to_platform_file` → `publish_new_version_branch` → `finalize_version_merge`.
- `utils/version-utils.sh` — all the logic.

Key facts (don't relearn these by re-reading the code every time):
- **Source of truth is `.d3v/app.properties`** (a `key=value` file), *not* `pom.xml` directly. Fields: `version.current.tag`, `version.current.buildnumber`, `version.previous.tag`, `version.previous.buildnumber`. `get_version_field`/`set_version_field` read/write it.
- `increment_version` bumps `PATCH` (scheme `MAJOR.MINOR.PATCH[.BUGFIX]`); if branch `v<version>` already exists remotely, it escalates to a `BUGFIX` segment instead and sets `MERGE_TO_MAIN=0` (a bugfix version implies a human needs to merge manually).
- `copy_version_to_platform_file` then writes that tag into whatever file `$PLATFORM` actually uses: `java` → `pom.xml`'s own `<version>` (skips a `<parent>`'s `<version>` if present); `android`/`kmp` → `versionName`/`versionCode` in `build.gradle(.kts)` (buildnumber → versionCode, since gradle wants an integer). `ios` is detected but **not wired up yet** (no writer, no template).
- `publish_new_version_branch` pushes **both** the branch and the tag explicitly — pushing a branch does not push unrelated tags along with it, this was a real bug once already.
- `check_if_there_is_forward_commit_and_act` rolls back the branch/tag if a non-bot commit landed on `origin/main` mid-run (race), setting `SKIP_DEPLOY=1` in `create-new-version.env`.

## `src/create-project/` — scaffold a new repo

- `create-project.sh` — runner: pre-flight checks (`require_command git gh`, `require_gh_auth`, `detect_host_os`, `resolve_shell_profile`, `ensure_env_var` for the GitHub Actions PAT) → prompt for name/type → `create_github_repo` → `set_actions_secret` → `clone_new_repo` → `copy_repo_defaults` → `apply_template_placeholders` → `commit_and_push_new_project` → `cleanup_local_clone`.
- `delete-project.sh` — lists the org's repos (newest-created first, numbered, `0` = exit) and deletes the chosen one; relies on `gh repo delete --yes` for the actual delete, with its own lightweight y/n confirmation first (not gh's "retype org/repo" prompt).
- `PROJECT_TYPE_ARRAY` (in `constants.sh`) enumerates `"<language>:<app-type>"` pairs (currently `java:lib`, `java:api-be`, `java:th-be`, `python:api-be`) shown in a `select` menu.
- **`repo-defaults/` layering** — `copy_repo_defaults` layers three things into the new repo, in order: `repo-defaults/.all/` (always), `repo-defaults/langs/<language>/` (if it exists), `repo-defaults/app-types/<language>/<app-type>/` (if it exists) — missing folders are skipped with a message, not an error.
- **Important**: `copy_repo_defaults` *also* directly `cp -R`s this repo's own `src/version/` → `<new-repo>/.d3v/version/` and `src/shell-utils/` → `<new-repo>/.d3v/shell-utils/`. This — not `repo-defaults/.all/.d3v/download-scripts.sh` — is how a new project actually gets a working `version.sh`. `download-scripts.sh` is currently just a stub (`wget ...`) and does nothing; don't assume it runs anything in CI unless you implement it.
- `repo-defaults/app-types/<language>/<app-type>/` can carry its own `CLAUDE.md` (eg. `app-types/java/lib/CLAUDE.md`) that gets scaffolded straight into the new project — that's guidance for *that generated project*, not for this repo; don't confuse it with this file.
- **`$d3v{VAR_NAME}` templating**: `apply_template_placeholders` walks every copied file and replaces `$d3v{VAR_NAME}` with the matching shell variable already in scope (`ORG_NAME`, `PROJECT_NAME`, `PROJECT_FULL_NAME`, `PROJECT_LANGUAGE`, `PROJECT_APP_TYPE`, ...); unresolved placeholders are left as-is with a warning. `TEMPLATE_PLACEHOLDER_PREFIX` (constants.sh) is `"d3v"` — the actual regex/sed construction had a real "bad substitution" bug from nesting `${TEMPLATE_PLACEHOLDER_PREFIX}` inside another parameter expansion; it's fixed via an intermediate `placeholder_prefix` variable — don't "simplify" that back.
- Only `java/lib` has a real `app-types` template today (`pom.xml`, `HelloWorld.java`, `.github/workflows/maven-publish.yml`). Other combos in `PROJECT_TYPE_ARRAY` (`java:api-be`, `java:th-be`, `python:api-be`) don't have templates yet — `copy_repo_defaults` will just skip them.

## `maven-publish.yml` (the one real workflow template, `repo-defaults/app-types/java/lib/`)

Two jobs: `create-new-version` (runs `version.sh`, exposes the resulting version as a job `output`) → `build` (`needs: create-new-version`). **`build`'s checkout uses an explicit `ref: "version-${{ needs.create-new-version.outputs.version }}"`** — without that, `actions/checkout` defaults to `github.sha`, the commit that triggered the run, which is *before* `create-new-version`'s own commits exist. This was a real, hard-to-spot bug (build silently building the pre-bump code) — don't remove the explicit `ref:` or the `needs:`.

## Known gaps (current, unfinished state — not hidden failures, just not built yet)

- `download-scripts.sh` is an unimplemented stub.
- `maven-publish.yml`'s `build` job references `$GITHUB_WORKSPACE/settings.xml` for `mvn deploy -s`, but no `settings.xml` is scaffolded anywhere in `repo-defaults` — a new project won't have one unless added by hand.
- `ios` has platform detection but no `copy_version_to_platform_file` writer and no repo-defaults template.
- `react`, `kmp`, `android`, and the non-`java:lib` `PROJECT_TYPE_ARRAY` entries have no `repo-defaults` templates yet.
