# Installation Guide

The VV Claude Code Harness is distributed as a native Claude Code plugin. The old
Python installer is retired as of v4.0.0 (the `install` script now only prints these
instructions).

## Prerequisites

- Claude Code CLI installed and working
- Git initialized in your project
- `jq` installed (used by hook scripts): `brew install jq` on macOS

## Install

From inside any Claude Code session:

```
/plugin marketplace add oeftimie/vv-claude-harness
/plugin install vv-harness
```

That's it. The plugin ships the `/harness-init` and `/harness-continue` skills and the
rule files; Claude Code discovers them automatically.

## Update

```
/plugin update vv-harness
```

Version semantics:

- The plugin version lives in `.claude-plugin/plugin.json`. Updates arrive only when
  that version is bumped — it is the update cache key.
- Updates are atomic: each version gets its own cache directory under
  `~/.claude/plugins/cache`. There is no stale-file mixing between versions; the old
  version's directory is orphaned and auto-removed about 7 days later.

## Uninstall

```
/plugin uninstall vv-harness
```

This removes the plugin cleanly. Anything you copied by hand (e.g., your personal
`~/.claude/CLAUDE.md`) is yours and is not touched.

## Migrating from the v3 installer

The v3 installer copied files directly into `~/.claude/`. The plugin does not manage
those copies, so they will shadow or duplicate the plugin's skills and rules. Remove
them by hand — **nothing is deleted silently; you run these commands yourself**:

```bash
# Skills installed by the v3 installer (now shipped by the plugin)
rm -rf ~/.claude/skills/harness-init
rm -rf ~/.claude/skills/harness-continue

# Rules installed by the v3 installer (now shipped by the plugin)
rm -f ~/.claude/rules/agent-teams-protocol.md
rm -f ~/.claude/rules/code-quality.md
```

`~/.claude/CLAUDE.md` was also installed (and personalized) by the v3 installer, but
it is your live personal global instructions file. Keep it. Only remove it if you want
to start over from the fresh template (see "Personalize your CLAUDE.md" below):

```bash
# Optional — this is YOUR personal file; only remove it deliberately
rm -f ~/.claude/CLAUDE.md
```

If you've been here a while, even older harness versions (pre-v3.x) may have left
these behind. Remove any that exist:

```bash
# Retired rules (pre-v3.0 through v3.2.2)
rm -f ~/.claude/rules/orchestrator.md
rm -f ~/.claude/rules/scheduling.md
rm -f ~/.claude/rules/coding-agent.md
rm -f ~/.claude/rules/non-harness-workflow.md
rm -f ~/.claude/rules/engineering-standards.md

# Retired skills and directories (pre-v3.0 layout)
rm -rf ~/.claude/skills/context-graph
rm -rf ~/.claude/harness
rm -rf ~/.claude/templates

# Retired slash commands (pre-v3.0)
rm -f ~/.claude/commands/project-harness-init.md
rm -f ~/.claude/commands/project-harness-continue.md
```

Then enable the plugin:

```
/plugin marketplace add oeftimie/vv-claude-harness
/plugin install vv-harness
```

## Personalize your CLAUDE.md

`templates/CLAUDE.md` in this repo is a starting template for your personal
`~/.claude/CLAUDE.md` (core engineering standards). The plugin does NOT install it —
plugins cannot ship a global CLAUDE.md; that is a platform constraint. If you want it:

```bash
cp templates/CLAUDE.md ~/.claude/CLAUDE.md
# Then edit ~/.claude/CLAUDE.md and replace every {{USER_NAME}} with your name
```

## What the plugin cannot do (configure these yourself)

Plugins cannot set environment variables or permission allowlists. Two pieces of
setup the v3 installer used to handle now live in your own settings (a later phase
will document per-project automation for these):

1. **Agent Teams env var** — add to `~/.claude/settings.json` (or a project's
   `.claude/settings.json`):

   ```json
   {
     "env": {
       "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
     }
   }
   ```

2. **Permission allowlists** — configure under `permissions` in the same
   user/project `settings.json` files.

## Per-Project Setup

```bash
cd ~/Projects/MyApp
claude
/harness-init
```

The initializer will:
1. Detect your tech stack
2. Capture and confirm git identity
3. Create `.harness/` scaffolding (features.json, context_summary.md, init.sh, progress log)
4. Install async PostToolUse build hooks in `.claude/settings.json`
5. Install PreToolUse hooks (`enforce-scope.sh`, `verify-git-identity.sh`)
6. Install quality gate hooks (`TaskCompleted`, `TeammateIdle`, `PostCompact`)
7. Verify hooks execute correctly
8. Propose initial features with scope and dependencies
9. Commit

After initialization, verify per-project hooks:

```bash
echo '{}' | bash .claude/hooks/verify-task-quality.sh && echo "TaskCompleted hook: OK"
echo '{}' | bash .claude/hooks/check-remaining-tasks.sh && echo "TeammateIdle hook: OK"
```

## Continuing Work

At the start of every session on a harness project:

```bash
cd ~/Projects/MyApp
claude
/harness-continue
```

This orients to current state, verifies git identity, and picks single-session or Agent Teams mode.
