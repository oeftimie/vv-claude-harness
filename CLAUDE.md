@AGENTS.md

## Claude Code

This section is Claude-specific overlay only; everything agent-agnostic lives in
`AGENTS.md` above (imported via the documented `@path` syntax -- see
`https://code.claude.com/docs/en/memory#agentsmd`). Do not restate a fact from
`AGENTS.md` here; if a Claude-specific detail and an `AGENTS.md` fact start to overlap,
fix `AGENTS.md`, don't duplicate it here.

## Harness

This project uses the Long-Running Agent Harness (vv-harness plugin) to manage its own v5 upgrade (Linear epic OVI-44). The distribution-content caveat above still applies: `templates/`, `rules/`, and `skills/` remain plugin source, but `.harness/` and `.claude/` are live project state for this repo.

- Feature tracking: `.harness/features.json` (F001–F021 mirror the OVI-44 sub-issues)
- Context and decisions: `.harness/context_summary.md` (READ THIS at session start)
- Progress handoff: `.harness/claude-progress.txt`
- Build/test: `.harness/init.sh` (`smoke_test` = shell syntax + manifest JSON checks; `full_test` = `bash test/run-tests.sh`)
- Quality gates: `.claude/hooks/` (TaskCompleted, TeammateIdle, scope, git identity)

## Harness Prep: Risk/Lane Self-Classification

When `/harness-issue-prep` needs `lane`/`risk` for a readiness stamp, apply the existing dynamic-override heuristic in `rules/agent-teams-protocol.md` (10+ files, cross-cutting concerns, security-sensitive code, first feature in a new codebase → elevated) without asking. Only ask when the call is genuinely close.

## Path Resolution and Hook Testing

Skill/rule/agent content shipped by this plugin references other shipped files via
`${CLAUDE_PLUGIN_ROOT}/path/to/file`, Claude Code's runtime plugin-cache variable --
never a bare repo-relative path, since the installed cache path differs from this
checkout. Use the same convention when editing `skills/`, `rules/`, or `agents/`.

Files under `hooks/` and the `.sh.template`/`.py.template` files under
`skills/harness-init/` are Claude Code lifecycle hooks (SessionStart, PreToolUse,
TaskCompleted, TeammateIdle). Test one directly the way `.claude/settings.json` invokes
it: `echo '{}' | CLAUDE_PROJECT_DIR=<project> bash <hook>.sh`, matching
`test/run-tests.sh`'s own `run_hook` helper.
