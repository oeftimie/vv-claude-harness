# VV Claude Code Harness — Distribution Repository

This repo distributes VV Claude Code Harness — it is NOT an application codebase.

## What This Repo Contains

- `.claude-plugin/` — Plugin manifest (`plugin.json`) and marketplace manifest (`marketplace.json`)
- `agents/` — Declarative teammate definitions shipped with the plugin (spawned as `vv-harness:*`)
- `hooks/` — Plugin continuity hooks: session-start, session-end, statusline, `hooks.json`
- `rules/` — Rule files shipped with the plugin
- `skills/` — Skill definitions shipped with the plugin (auto-discovered at plugin root)
- `templates/CLAUDE.md` — Template for a user's personal `~/.claude/CLAUDE.md` (do not treat as project instructions; users copy and personalize it manually)
- `test/` — Fixture-based test suite for the hook scripts (`test/run-tests.sh`)
- `CHANGELOG.md` — Version history
- `INSTALL.md` — Installation and migration guide
- `README.md` — Project documentation
- `install` — Deprecation shim; prints the `/plugin` install instructions and exits
- `clips/` — Screenshots and videos for README

## Key Distinction

Files under `templates/`, `rules/`, and `skills/` are **distribution content**, not active project configuration. They describe how Claude should behave in *other* projects after the plugin is installed. Do not follow their instructions when working on this repo.

## Working on This Repo

- No build system, no application code
- Tests live at `test/run-tests.sh` (dependency-free shell runner covering the hook
  scripts, plugin manifests, and agent frontmatter). Run `bash test/run-tests.sh` and
  make sure it passes before committing changes to `hooks/` or the `.claude-plugin/`
  manifests
- Other changes are documentation and template edits
- The version number lives ONLY in `.claude-plugin/plugin.json` (`version`). It is the canonical plugin version and the update cache key: users only receive updates when it is bumped. Do not introduce other version locations that need syncing.
- `templates/CLAUDE.md` keeps its `{{USER_NAME}}` placeholders; personalization is a documented manual step in INSTALL.md, not installer templating
