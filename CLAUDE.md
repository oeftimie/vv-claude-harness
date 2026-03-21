# Ovidiu's Claude Code Harness — Distribution Repository

This repo distributes Ovidiu's Claude Code Harness — it is NOT an application codebase.

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
- Version number lives in: `claude/CLAUDE.md` frontmatter, `README.md` header, and `README.md` changelog
- Keep all three version references in sync when bumping
- The installed global copy at `~/.claude/CLAUDE.md` must match `claude/CLAUDE.md` (minus personal sections like Slack config)
