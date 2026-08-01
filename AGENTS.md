# VV Claude Code Harness — Distribution Repository

This repo distributes VV Claude Code Harness — it is NOT an application codebase.

## What This Repo Contains

- `.claude-plugin/` — Plugin manifest (`plugin.json`) and marketplace manifest (`marketplace.json`)
- `agents/` — Declarative teammate definitions shipped with the plugin (spawned as `vv-harness:*`)
- `hooks/` — Plugin continuity hooks: session-start, session-end, statusline, `hooks.json`
- `rules/` — Rule files shipped with the plugin
- `schemas/` — Data contracts published for external consumers (readiness stamp, park/resolution formats)
- `skills/` — Skill definitions shipped with the plugin (auto-discovered at plugin root)
- `templates/CLAUDE.md` — Template for a user's personal `~/.claude/CLAUDE.md` (do not treat as project instructions; users copy and personalize it manually)
- `test/` — Fixture-based test suite for the hook scripts (`test/run-tests.sh`)
- `CHANGELOG.md` — Version history
- `INSTALL.md` — Installation and migration guide
- `docs/maintenance-runbook.md` — The repo's own maintenance loop (retirement-condition checks, drift probes)
- `README.md` — Project documentation
- `install` — Deprecation shim; prints the `/plugin` install instructions and exits
- `clips/` — Screenshots and videos for README

## Key Distinction

Files under `templates/`, `rules/`, and `skills/` are **distribution content**, not
active project configuration. They describe how an agent should behave in *other*
projects after the plugin is installed. Do not follow their instructions when working
on this repo.

## Working on This Repo

- No build system, no application code
- Tests live at `test/run-tests.sh` (dependency-free shell runner covering the hook
  scripts, plugin manifests, and agent frontmatter). Run `bash test/run-tests.sh` and
  make sure it passes before committing changes to `hooks/` or the `.claude-plugin/`
  manifests
- Other changes are documentation and template edits
- The version number lives ONLY in `.claude-plugin/plugin.json` (`version`) — the
  canonical plugin version and the update cache key: users only receive updates when it
  is bumped. Do not introduce other version locations that need syncing.
- `templates/CLAUDE.md` keeps its `{{USER_NAME}}` placeholders; personalization is a
  documented manual step in `INSTALL.md`, not installer templating
- Git identity: Ovidiu Eftimie <eovidiu@gmail.com> (GitHub account `eovidiu`), HTTPS
  with the gh credential helper, no SSH in this environment. Verify before any
  push/pull/clone. Never push directly to main — PR-based flow only.
- A documented workaround (a pattern adopted to route around a platform bug or gap, as
  opposed to a permanent design limitation) MUST name the version or event that removes
  it — never leave one pinned to "confirmed as of vX.Y+" with no condition for
  revisiting it. `docs/maintenance-runbook.md`, `MAINTENANCE_LOG.md`, and
  `.github/workflows/maintenance.yml` check these retirement conditions on a schedule; a
  workaround without one can't be checked. Retiring a workaround is always an explicit,
  approval-required change — never performed automatically by a probe run, even when a
  probe reports the underlying bug fixed.
