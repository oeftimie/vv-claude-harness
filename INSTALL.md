# Installation Guide

The VV Claude Code Harness is distributed as a native Claude Code plugin. The old
Python installer is retired as of v4.0.0 (the `install` script now only prints these
instructions).

**Compatibility:** workflow mode (the parallel path) needs Claude Code ≥ 2.1.154 with
the `Workflow` tool available (not org-disabled via `disableWorkflows`).
`plugin.json` has no version-pin field — the platform's model is graceful degradation
(older CLIs ignore unknown manifest fields), and `/harness-continue` falls back to
non-experimental worktree-isolated subagents when the Workflow tool is unavailable.
The experimental Agent Teams path is retired as of v6 (see "What the plugin cannot
do" below for the legacy env-flag note).

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

### Installing a specific version (alpha/pre-release/pinned), in one project only

The commands above always install whatever's on this repo's default branch, and
`/plugin update` tracks it going forward. To pin one project to a specific tagged
version instead — for example to try a pre-release before it's the default, without
affecting any other project's installed version — add an `extraKnownMarketplaces`
entry to that project's `.claude/settings.json` (or `.claude/settings.local.json` to
keep it out of version control), naming the tag as the `ref`:

```json
{
  "extraKnownMarketplaces": {
    "vv-harness-alpha": {
      "source": {
        "source": "github",
        "repo": "oeftimie/vv-claude-harness",
        "ref": "v5.3.0-alpha"
      }
    }
  },
  "enabledPlugins": {
    "vv-harness@vv-harness-alpha": true
  }
}
```

Restart the Claude Code session in that project (or run `/plugin marketplace update`)
for the pinned marketplace to take effect. This installs and pins to exactly the
commit tagged `v5.3.0-alpha`; `/plugin update` from that point only moves within that
same pinned marketplace, so the project stays on the alpha until you change the `ref`
yourself. A marketplace `ref` accepts any branch or tag name, not just a release tag —
useful for pointing a single test project at an in-progress feature branch too.

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

# Rule retired in v6 (its surviving mechanism-agnostic content ships as the
# plugin's rules/parallel-work.md)
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

1. Remove stale blocks from `.claude/settings.json` (writing a `settings.json.bak`
   backup first): the PostCompact block (the plugin's SessionStart hook now covers
   post-compaction recovery), and — for projects initialized before the v6 Agent Teams
   retirement — the `TeammateIdle` hook block and the
   `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var, plus the leftover
   `check-remaining-tasks.sh` hook and `.claude/teammate-scope.txt` file if present.
2. Copy the plugin statusline: `cp "${CLAUDE_PLUGIN_ROOT}/hooks/statusline.sh"
   .claude/hooks/` (ask Claude to run it — the plugin root path is visible in-session).
3. Add the `statusLine` and `permissions` wiring to `.claude/settings.json`: see
   `skills/harness-init/templates/settings.json.tmpl` for the canonical wiring (it is a
   template, not pasteable JSON -- its `{{PLACEHOLDER}}` spots need substituting), or run
   `scripts/stamp.sh` with `mode=upgrade` to apply it mechanically.
4. Append `.harness/SESSION_INCOMPLETE` to `.gitignore`.
5. Copy the shared state module: `cp "${CLAUDE_PLUGIN_ROOT}/skills/harness-init/harness_state.py.template"
   .claude/hooks/harness_state.py && chmod +x .claude/hooks/harness_state.py` — `verify-task-quality.sh`
   consumes it if present; re-copy that template from the
   current plugin version too, since older per-project copies still have the old inline logic.
6. Update the recorded plugin version: set `.harness/harness.json`'s `plugin_version`
   field (F068) to the currently installed plugin's version, so the next `harness-doctor`
   run compares against the version you're actually on rather than a stale one.

`.harness/init.sh` is never auto-refreshed by `--fix` — it's the one genuinely
decision-shaped per-project file (it mixes in project-specific stack logic), so
upgrades to it are always hand-applied. In particular, a project that adopted the
`focused_test` target before v5.5.0 (F106) may still carry the pre-F106 exit-0 skip
arms instead of the exit-3 skip contract (a `skipped (exit 3)` marker, a `run_focused`
exit-3 remap); `harness-doctor` reports the gap, but closing it means comparing
`.harness/init.sh`'s `focused_test` block against
`skills/harness-init/init.sh.template`'s by hand.

## Personalize your CLAUDE.md

`templates/CLAUDE.md` in this repo is a starting template for your personal
`~/.claude/CLAUDE.md` (core engineering standards). The plugin does NOT install it —
plugins cannot ship a global CLAUDE.md; that is a platform constraint. If you want it:

```bash
cp templates/CLAUDE.md ~/.claude/CLAUDE.md
# Then edit ~/.claude/CLAUDE.md and replace every {{USER_NAME}} with your name
```

## What the plugin cannot do (configure these yourself)

Plugins cannot set environment variables or permission allowlists.
**Permission allowlists** live in your own settings: in harness projects,
`/harness-init` writes them into the project's `.claude/settings.json` for you;
configure them under `permissions` in `~/.claude/settings.json` only if you want
them outside harness projects.

**Legacy note — Agent Teams env var**: earlier versions instructed setting
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` here. The flag is no longer used as of v6
(Agent Teams is retired; workflow mode is the parallel path). If it is still present
in an existing project's `.claude/settings.json`, `/harness-doctor` flags it as stale
wiring and `--fix` removes it.

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

## Optional: Live Session Dashboard

An opt-in, local-only, animated view of a session's agent activity: a node for
the lead and one for each spoke, pulsing on tool use, badged for quality-gate
verdicts, judge subagents, and permission prompts.

**The env var must be set before the session you want to watch is launched.** The
hooks that write the event log are wired at Claude Code startup, so enabling this
mid-session has no effect:

```bash
export VV_HARNESS_DASHBOARD=1
claude
```

From a second terminal (or after that session ends), run `/harness-dashboard`. It
checks `.harness/dashboard/` for a log file, starts a local server or reuses one
already running on `127.0.0.1:8765`, and opens the page in a browser. See
`skills/harness-dashboard/SKILL.md` for the exact steps, including how to stop the
server.

**Event log**: one JSON-line file per session, at
`.harness/dashboard/<session_id>.jsonl`. This feature adds `.harness/dashboard/` to
`.gitignore`, and `/harness-doctor --fix` adds the same line for existing projects
that upgrade the plugin — so the directory is gitignored once one of those has run.
A project that upgraded without re-running doctor since may not have that ignore rule
yet; run `/harness-doctor` to pick it up. The log holds only short, redacted
summaries (a file path, a Bash command's `description`) rather than raw command text,
file content, or prompts. Nothing rotates or deletes these files automatically; clean
up `.harness/dashboard/` by hand when old session logs are no longer needed.

**Known limitations**:

- The graph is a flat hub-and-spoke layout — the hook payload set has no
  parent-agent field, so spawn ancestry (which agent spawned which) can't be
  reconstructed.
- Agent nodes are labeled by `agent_type` only, never a custom agent name —
  the two identities aren't correlated anywhere in the hook payloads.
- The view is live-only: it replays one session's backlog on connect, then streams
  new events. There's no cross-session history or aggregation.
- One session, one server: the dashboard shows whichever session's log file was most
  recently modified, not a combined multi-session view.
- The server binds to `127.0.0.1:8765` only, with no authentication — loopback-only
  bind is its sole access control, matching this environment's existing trust model
  for local dev tooling.

## Optional: spec gate for an external runner

Everything below is optional. Skip it entirely if you only use the spec gate locally:
`/harness-init` Step 5.1 and `harness-issue-prep` work with no configuration, writing an
unsigned `spec` field to `features.json`. Configure this section only if a separate,
external issue-to-PR runner needs a trustworthy signal that a Linear issue is ready for
unattended implementation. Stamp signing works on Linux/CI as well as macOS (see the key
resolution chain below); only the Keychain source is macOS-specific.

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
    "kick_command": "launchctl kickstart -k \"gui/$(id -u)/com.you.linear-agent\""
  }
}
```

- `prep.linear`: labels `harness-issue-prep` applies to a Linear issue as it moves through the
  gate. Omit it and labeling is skipped.
- `prep.stamp`: enables minting a signed readiness stamp via a 3-source key resolution
  chain (first source that yields a key wins): macOS Keychain, then a file named by the
  `VV_HARNESS_STAMP_KEY_FILE` env var (must be mode `0600`), then the discouraged
  `VV_HARNESS_STAMP_KEY` env var. The Keychain source is a one-time setup, done by hand
  and never automated:

  ```bash
  security add-generic-password -a "$USER" -s vv-harness-stamp -w "$(openssl rand -hex 32)"
  ```

  `keychain_service` must match the service name used above (`vv-harness-stamp` by
  default). See [schemas/readiness-stamp.md](./schemas/readiness-stamp.md) for the file
  and env-var sources, needed on Linux/CI where the Keychain doesn't exist. If none of
  the three sources yields a key, `harness-issue-prep` aborts stamping (the spec stays
  normalized, no label is applied) and prints setup guidance for all three.
- `prep.kick_command`: a shell command that nudges your external runner after a
  successful stamp, executed verbatim via `bash -c "$KICK_COMMAND"`. Its presence is
  what enables Step 8 -- there is no separate on/off flag. The `launchctl kickstart`
  line above is just one example value (a macOS launchd runner); any shell command
  works. Absent, Step 8 is skipped. A failed kickstart is a one-line note, never fatal;
  the runner's own poll cycle is the fallback path. Treat this value as trusted-input
  only: it runs verbatim, so a `harness.json` from an untrusted source (e.g. a cloned
  repo) executes arbitrary commands on the next prep.

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
6. Install the quality gate hook (`TaskCompleted`)
7. Wire the status line and permissions allowlist into
   `.claude/settings.json`; gitignore `.harness/SESSION_INCOMPLETE`
8. Verify hooks execute correctly
9. Propose initial features with scope and dependencies
10. Commit

After initialization, verify per-project hooks by checking their exit codes:

```bash
echo '{}' | bash .claude/hooks/verify-task-quality.sh; echo "verify-task-quality exit: $?"
```

Expected exit codes:
- `verify-task-quality.sh`: 0 when tests pass; 2 when tests fail

## Continuing Work

At the start of every session on a harness project:

```bash
cd ~/Projects/MyApp
claude
/harness-continue
```

This orients to current state, verifies git identity, and picks single-session or workflow mode.
