# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Git

Never run `git commit` or `git push` in this repository, even if asked to perform the full workflow. Make the requested changes and let the user review and commit/push manually.

## `.d3v/version/version.sh` logic (important when touching it)

This script runs inside GitHub Actions (relies on `CI_COMMIT_SHA`, `CI_COMMIT_BRANCH` being set in the environment) and assumes the working directory is a checked-out git repo with a `pom.xml` at its root.

- Reads/writes the version directly via `awk`/`sed` on `pom.xml` (`get_current_version` / `create_branch_and_set_version`) rather than shelling out to `mvn versions:set` / `mvn help:evaluate` — this is a deliberate perf tradeoff to avoid JVM startup cost per invocation. Both functions specifically target the **project's own** `<version>`, i.e. the first `<version>` tag *after* `</parent>`, skipping the parent POM's version.
- Version scheme is `MAJOR.MINOR.PATCH[.BUGFIX]`. On each run it increments `PATCH`; if a branch `v<MAJOR.MINOR.PATCH>` already exists remotely, it escalates to (or increments) a `BUGFIX` segment instead, and in that case does **not** merge to main (`MERGE_TO_MAIN=0`) since a bugfix version implies the newer patch already had an issue.
- Creates a branch `v<version>`, commits the bumped `pom.xml`, tags it `version-<version>`, pushes with `-o ci.skip` (to avoid retriggering CI), and — only when `MERGE_TO_MAIN=1` — merges that branch into `main` and pushes.
- `check_if_there_is_forward_commit_and_act` detects if a non-bot commit landed on `origin/main` after the versioning commit (i.e. someone pushed while the version bump was in flight) and, if so, rolls back the just-created tag/branch and sets `SKIP_DEPLOY=1` in `create-new-version.env` so the pipeline still builds/tests but skips deploy.
- Known open issue (see inline `TODO`): `git checkout -b v<version>` will fail if that branch already exists locally — not yet handled.

## `maven-publish.yml` notes

- Triggers on push/PR to `main`.
- `delete-old-packages` job prunes old GitHub Packages Maven versions (keeps latest 20) before versioning/building — checks package existence via the GitHub Packages API first so it doesn't fail on a repo with no published versions yet.
- The Maven repo cache key is computed from a hash of `pom.xml` with the volatile project `<version>` line stripped out — otherwise the default `setup-java` cache (keyed on raw `pom.xml` hash) would miss on every run, since `create-new-version` bumps the version every time.
- Publishing uses `settings.xml` from this same bundle (`-s $GITHUB_WORKSPACE/.github/workflows/settings.xml`), which points at GitHub Packages using `GH_PAT_FOR_ACTIONS_TOKEN`.

Note: `maven-publish.yml` and `settings.xml` currently reference a specific package (`com.devnautica.ui.d3v-ui` / `thymeleaf-component-dialect`) — when copying this bundle into a new repo, update those references accordingly.
