# VV Claude Code Harness — Distribution Repository

This repo distributes VV Claude Code Harness — it is NOT an application codebase.

## What This Repo Contains

- `claude/CLAUDE.md` — Template for `~/.claude/CLAUDE.md` (do not treat as project instructions)
- `claude/rules/` — Rule files copied to `~/.claude/rules/`
- `claude/skills/` — Skill definitions copied to `~/.claude/skills/`
- `clips/` — Screenshots and videos for README
- `INSTALL.md` — Installation guide
- `README.md` — Project documentation and changelog

## Key Distinction

Files under `claude/` are **distribution templates**, not active project configuration. They describe how Claude should behave in *other* projects after installation. Do not follow their instructions when working on this repo.

## Working on This Repo

- No build system, no tests, no application code
- Changes are documentation and template edits only
- Version number lives in:
  - `install` — `HARNESS_VERSION` constant + module docstring banner
  - `claude/CLAUDE.md` — frontmatter `version:` + description line
  - `claude/skills/harness-init/SKILL.md` — frontmatter description, H1 title, `version:` field in the `harness.json` template, the init commit message, and the final report banner
  - `claude/skills/harness-continue/SKILL.md` — frontmatter description and H1 title
  - `README.md` — "Current version" header, download/unzip examples in "Getting started", and changelog header for the new entry
  - `INSTALL.md` — title
- Keep all version references in sync when bumping. Sanity check: `grep -rn "OLD\.VERSION" --include="*.md" --include="install"` should return only historical changelog entries; `grep -rn "NEW\.VERSION"` should hit every location above
- The installed global copy at `~/.claude/CLAUDE.md` must match `claude/CLAUDE.md` (minus personal sections like Slack config)
