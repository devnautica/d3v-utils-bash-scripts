# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Ultimate Rules

These rules override default tool-permission behavior for this repository. More ultimate rules will be added by hand over time — append new ones below the existing bullets, keep each self-contained.

- **File reads**: reading any file in this directory or in the directory one level above it never requires a permission prompt. If the harness would otherwise prompt for a read in that scope, ask for permission once at the start of the session and don't ask again for the remainder of that session.

- **`.d3v/` is off-limits**: the `.d3v/` directory at the project root is a copy of devnautica's shared tooling, downloaded and kept up to date remotely (by `.d3v/update-scripts/update-scripts.sh`) — not authored in this project. Ignore it: don't read, edit, or reference its contents, and never treat its scripts as this project's code. Any local change is overwritten on the next update. A `permissions.deny` rule in `.claude/settings.json` enforces this.

## Git

Never run `git commit` or `git push` in this repository, even if asked to perform the full workflow. Make the requested changes and let the user review and commit/push manually.

Always `git add` any file you create, so new files are staged for the user's review. A `PostToolUse` hook in `.claude/settings.json` already does this automatically after every `Write`; keep doing it explicitly too if you create a file by other means. Staging only — never `git commit`/`git push` (see above).
