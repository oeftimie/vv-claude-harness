# Installation Guide

The VV Claude Code Harness is distributed as a native Claude Code plugin. The old
Python installer is retired as of v4.0.0 (the `install` script now only prints these
instructions).

**Compatibility:** developed against Claude Code v2.1.175; the Agent Teams
documentation reflects the implicit-team model introduced in v2.1.178+ (teams form on
the first teammate spawn — the `TeamCreate`/`TeamDelete` tools were removed). Agent
Teams is experimental and may change between CLI versions; `plugin.json` has no
version-pin field — the platform's model is graceful degradation (older CLIs ignore
unknown manifest fields), and `/harness-continue` falls back to non-experimental
worktree-isolated subagents when Agent Teams coordination is unavailable.

## Prerequisites

- Claude Code CLI installed and working
- Git initialized in your project
- `python3` installed (used by all three plugin hooks and the per-project hook scripts)
- `jq` installed (used only by the per-project PostToolUse build hooks that
  `/harness-init` writes into `.claude/settings.json`): `brew install jq` on macOS

## Install

From inside any Claude Code session:

```
/plugin marketplace add oeftimie/vv-claude-harness
/plugin install vv-harness
```

That's it. Claude Code auto-discovers the plugin's skills (`/harness-init`,
`/harness-continue`), agents, and hooks. The two rule files ship as plugin content that
the SessionStart orientation points to by absolute path — no plugin "rules" mechanism
exists.

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

# Rule replaced by the plugin copy (the SessionStart orientation pointer and the
# harness-continue instruction cover it)
rm -f ~/.claude/rules/agent-teams-protocol.md
```

**Keep `~/.claude/rules/code-quality.md`** — that is the default. There is no plugin
mechanism for always-on rules, so removing it loses code-quality enforcement outside
harness sessions. Inside harness projects the SessionStart orientation points to the
plugin copy at `rules/code-quality.md`. Remove it only if you accept that loss:

```bash
# Optional — removing this drops code-quality enforcement outside harness sessions
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

## Upgrading an existing harness project

Run `/harness-doctor` in a Claude Code session inside the project: it reports every
gap between the project's current state and the current plugin version (missing
hooks, stale settings blocks, gitignore rules, `.harness/` validity) and, on request,
fixes them with `/harness-doctor --fix`. It replaces the manual upgrade steps this
section used to require.

Under the hood, `--fix` applies exactly these mechanical steps (for projects
initialized under v3, run without the plugin's install mechanism):

1. Remove the PostCompact block from `.claude/settings.json` (the plugin's SessionStart
   hook now covers post-compaction recovery, so it is redundant).
2. Copy the plugin statusline: `cp "${CLAUDE_PLUGIN_ROOT}/hooks/statusline.sh"
   .claude/hooks/` (ask Claude to run it — the plugin root path is visible in-session).
3. Add the `statusLine`, `env`, and `permissions` wiring to `.claude/settings.json` per
   harness-init Step 3.6.
4. Append `.harness/SESSION_INCOMPLETE` to `.gitignore`.
5. Copy the shared state module: `cp "${CLAUDE_PLUGIN_ROOT}/skills/harness-init/harness_state.py.template"
   .claude/hooks/harness_state.py && chmod +x .claude/hooks/harness_state.py` — `verify-task-quality.sh`
   and `check-remaining-tasks.sh` consume it if present; re-copy the two templates from the
   current plugin version too, since older per-project copies still have the old inline logic.

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
setup the v3 installer used to handle now live in your own settings. In harness
projects, `/harness-init` writes both into the project's `.claude/settings.json`
for you; set them globally only if you want them outside harness projects:

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

## Optional: Cost Telemetry

Claude Code can export token and cost metrics over OpenTelemetry. Telemetry is opt-in
and OFF by default. Enable it in `~/.claude/settings.json` (user scope) or a project's
`.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4317"
  }
}
```

The HTTP protocols (`http/json`, `http/protobuf`) use port 4318 instead of 4317.
Metrics export every 60000 ms by default (`OTEL_METRIC_EXPORT_INTERVAL`). Optionally
add `"OTEL_LOGS_EXPORTER": "otlp"` to export logs too.

For a minimal local collector that just prints what it receives, one `docker run` is
enough — the image's default config receives OTLP on 4317 and dumps metrics with the
debug exporter:

```bash
docker run --rm -p 4317:4317 otel/opentelemetry-collector
```

**Why this matters for the harness:** the exported `claude_code.token.usage` and
`claude_code.cost.usage` (USD) metrics break down by `model`, `query_source`
(`main`|`subagent`|`auxiliary`), and `agent.name` — so per-model and main-vs-subagent
cost in a team session is measured, not estimated (per-agent names are redacted to
`"custom"` for personal marketplaces). Two caveats:

- **agent.name redaction**: user-defined agent names are reported as `"custom"`;
  agents from official-marketplace plugins appear verbatim. Per-model and
  per-query-source breakdowns are unaffected.
- **Subprocesses**: Claude Code does not pass `OTEL_*` variables to subprocesses it
  spawns — hook scripts and build commands won't inherit them.

**Zero-infrastructure alternative:** the in-session `/usage` command shows session
token/cost stats plus a usage breakdown attributing recent usage to skills, subagents,
plugins, and MCP servers as percentages (24h/7d views, from local history). No
collector required. The session token/cost stats are universal; the plan-usage
breakdown view is available on subscription plans (Pro/Max/Team/Enterprise).

## Optional: spec gate for an external runner

Everything below is optional and macOS-specific (it uses the Keychain and `launchctl`).
Skip it entirely if you only use the spec gate locally: `/harness-init` Step 5.1 and
`harness-issue-prep` work with no configuration, writing an unsigned `spec` field to
`features.json`. Configure this section only if a separate, external issue-to-PR runner
needs a trustworthy signal that a Linear issue is ready for unattended implementation.

Add a `prep` key to `.harness/harness.json`. Every sub-key is optional; a missing
`prep` key, or a missing sub-key within it, degrades the relevant capability rather than
failing:

```json
{
  "prep": {
    "linear": {
      "ready_label": "agent:ready",
      "needs_prep_label": "agent:needs-prep"
    },
    "stamp": {
      "keychain_service": "vv-harness-stamp",
      "stamper": "<your name>"
    },
    "runner": {
      "kickstart_label": "com.you.linear-agent",
      "enabled": false
    }
  }
}
```

- `prep.linear`: labels `harness-issue-prep` applies to a Linear issue as it moves through the
  gate. Omit it and labeling is skipped.
- `prep.stamp`: enables minting a signed readiness stamp. Requires a one-time Keychain
  setup, done by hand and never automated:

  ```bash
  security add-generic-password -a "$USER" -s vv-harness-stamp -w "$(openssl rand -hex 32)"
  ```

  `keychain_service` must match the service name used above (`vv-harness-stamp` by
  default). If the key is unreadable at stamp time, `harness-issue-prep` aborts stamping (the
  spec stays normalized, no label is applied) and prints this same setup command.
- `prep.runner`: set `enabled: true` and `kickstart_label` to the `Label` in your
  runner's launchd plist to have `harness-issue-prep` nudge it after a successful stamp
  (`launchctl kickstart -k "gui/$(id -u)/<kickstart_label>"`). A failed kickstart is a
  one-line note, never fatal; the runner's own poll cycle is the fallback path.

See [schemas/readiness-stamp.md](./schemas/readiness-stamp.md) for the stamp format, the
canonical hashing recipe, and the HMAC recipe the Keychain key feeds.

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
6. Install quality gate hooks (`TaskCompleted`, `TeammateIdle`)
7. Wire the status line, Agent Teams env flag, and permissions allowlist into
   `.claude/settings.json`; gitignore `.harness/SESSION_INCOMPLETE`
8. Verify hooks execute correctly
9. Propose initial features with scope and dependencies
10. Commit

After initialization, verify per-project hooks by checking their exit codes:

```bash
echo '{}' | bash .claude/hooks/verify-task-quality.sh; echo "verify-task-quality exit: $?"
echo '{}' | bash .claude/hooks/check-remaining-tasks.sh; echo "check-remaining-tasks exit: $?"
```

Expected exit codes:
- `verify-task-quality.sh`: 0 when tests pass; 2 when tests fail
- `check-remaining-tasks.sh`: 2 with pending features is healthy (it sends the next
  assignment by design); 0 when no features remain

## Continuing Work

At the start of every session on a harness project:

```bash
cd ~/Projects/MyApp
claude
/harness-continue
```

This orients to current state, verifies git identity, and picks single-session or Agent Teams mode.
