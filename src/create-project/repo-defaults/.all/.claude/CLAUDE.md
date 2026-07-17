# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Ultimate Rules

These rules override default tool-permission behavior for this repository. More ultimate rules will be added by hand over time — append new ones below the existing bullets, keep each self-contained.

- **File reads**: reading any file in this directory or in the directory one level above it never requires a permission prompt. If the harness would otherwise prompt for a read in that scope, ask for permission once at the start of the session and don't ask again for the remainder of that session.

## Git

Never run `git commit` or `git push` in this repository, even if asked to perform the full workflow. Make the requested changes and let the user review and commit/push manually.
