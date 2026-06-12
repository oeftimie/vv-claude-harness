# Changelog

Version history for the VV Claude Code Harness. The current version lives in `.claude-plugin/plugin.json`.

### v4.0.0 (2026-06-12)

**The harness is now a native Claude Code plugin.** The story of every version since v3.1 has been promoting rules from instructional to mechanical enforcement. v4.0 applies that to the harness itself: distribution, session orientation, post-compaction recovery, discipline auditing, progress visibility, and teammate tool posture — all carried by prose and a custom installer until now — are handed to the platform. This release ships what was planned as the v4.0–v4.3 milestone series in one release.

**Breaking change: the v3 installer is retired.** `./install` is now a shim that only prints the new instructions; it modifies nothing. Install with `/plugin marketplace add oeftimie/vv-claude-harness` then `/plugin install vv-harness`. Manual steps for removing the files the v3 installer placed in `~/.claude/` are in [INSTALL.md](./INSTALL.md). The version number now lives only in `.claude-plugin/plugin.json`.

**Plugin packaging** — `.claude-plugin/plugin.json` (name `vv-harness`, version 4.0.0) and `marketplace.json`; the `claude/` directory layout moved to top-level `rules/`, `skills/`, and `templates/CLAUDE.md`; INSTALL.md rewritten for the `/plugin` flow; updates are atomic (each version gets its own cache directory).

**Continuity hooks** — plugin-level, firing in any project with a `.harness/` directory:
- `hooks/session-start.sh` injects orientation at session start: features passing count, next claimable feature, last handoff, Active Context, and a git identity warning on mismatch. Its `compact` matcher also handles post-compaction recovery.
- `hooks/session-end.sh` audits session discipline (handoff written, retrospective present, metadata committed) into `.harness/SESSION_INCOMPLETE`, which the next session start surfaces loudly. Self-healing by design: SessionEnd cannot block.
- `hooks/statusline.sh` renders live "⬡ N/M passing" feature progress. Wired per-project by `/harness-init` because plugins cannot set `statusLine`; `/harness-init` also writes the Agent Teams env flag and a permissions allowlist into project settings and gitignores `SESSION_INCOMPLETE`. The per-project PostCompact hook is gone — its output never reached the model.

**Declarative agents** — `agents/feature-implementer.md`, `layer-implementer.md`, `researcher.md`, and `reviewer.md` carry model, effort, and tool posture in frontmatter. The reviewer runs Opus at high effort and cannot edit files by construction (no Edit/Write tools; Bash restricted to test runs by instruction); the researcher is retrieval-only, with Write allowed only for its findings file. Teammates spawn by `vv-harness:*` agent type, and `team-spawn-prompts.md` shrank from 253 to 135 lines (per-feature specifics only). A spawn-time `model` parameter overrides frontmatter, so the Opus-upgrade heuristic survives.

**Measured cost and resilience** — INSTALL.md documents opt-in OTel telemetry (`claude_code.token.usage` and `claude_code.cost.usage`): per-model and main-vs-subagent cost is measured (per-agent names are redacted to `"custom"` for personal marketplaces), plus the zero-infrastructure `/usage` alternative. The Agent Teams protocol replaces the ~30-minute cost rule of thumb with a measured break-even, and reframes worktree isolation honestly: platform-documented for subagents, unverified for teammates. `/harness-continue` gains a supported, non-experimental fallback — worktree-isolated subagents using the same agent types — for when Agent Teams is unavailable. Compatibility is documented against Claude Code v2.1.175.

**Tests and CI** — `test/run-tests.sh` (51 fixture-based assertions over the hook scripts, no dependencies) and `.github/workflows/test.yml` running it on ubuntu-latest.

**Deviations from the original modernization plan**, each forced by a platform constraint verified June 2026:
- Plugin manifest keys for a global CLAUDE.md, rules, or settings (env, permissions, statusLine) don't exist — the core-standards file ships as `templates/CLAUDE.md` (documented manual copy) and `/harness-init` writes env, permissions, and statusLine per-project.
- PreCompact prompt injection is impossible (PreCompact stdout never reaches the model) — replaced by SessionStart `compact`-matcher recovery.
- No CLI version-pin manifest key exists — the tested CLI version (v2.1.175) is documented instead.
- The plan's optional TaskCreated metadata-enforcement hook was dropped — the TaskCreated payload carries no metadata field to check.

### v3.6.0 (2026-04-26)

**Stale-file detection in the installer.** Before v3.6.0, the installer silently auto-deleted a small list of deprecated files (`engineering-standards.md`, `non-harness-workflow.md`) and missed the v2.x module-lock residue entirely (`orchestrator.md`, `scheduling.md`, `coding-agent.md`, the `context-graph` skill). Anyone who upgraded from v2.x kept those dead files in `~/.claude/` and could end up with two competing harness models loaded at once — exactly the conflict that surfaced in a real session and prompted this work.

**Behavior change** — the installer no longer auto-deletes. Stale files are now **detected and reported** by default, listing each one with its `~/.claude/` path. Pass `--clean-stale` to remove them; the regular backup pass picks them up first. This is a deliberate trade: silent cleanup hid both the problem and the fix from users. The new default surfaces the decision.

**Updated stale manifest:**
- v2.x module-lock era (retired in v3.0): `rules/orchestrator.md`, `rules/scheduling.md`, `rules/coding-agent.md`, `skills/context-graph/`, `harness/`, `templates/`, `commands/project-harness-init.md`, `commands/project-harness-continue.md`
- v3.2.x cleanup (retired in v3.2.2): `rules/engineering-standards.md`, `rules/non-harness-workflow.md`

**Scope:** global files only (`~/.claude/`). Per-project residue (`.context/modules.yaml`, old `.harness/` schemas, project-local `.claude/rules/scheduling.md`) is intentionally left alone — projects contain user data and the upgrade flow needs more thought before it touches them.

### v3.5.1 (2026-04-25)

**Hotfix:** v3.5.0 shipped without bumping `install` (`HARNESS_VERSION` constant + banner), `INSTALL.md` title, and the README download/unzip examples. Running `./install` from a v3.5.0 directory reported "Upgrade (v3.5.0 -> v3.4.0)" — a downgrade against the installed copy. No functional changes; version strings only. Repo `CLAUDE.md` updated to add `install` to the version-sync list so this regression can't repeat.

### v3.5.0 (2026-04-06)

**Session discipline improvements** based on root cause analysis of 11 harness violations observed during a real iOS project session (voice fix, test expansion, app icon work).

**Five serious violation remediations:**

1. **Pre-commit features.json audit** — Session end now requires diffing `features.json` against actual work done. Any code change relating to a tracked feature must update that feature's metadata. Work that doesn't map to any feature gets a new entry with `discovered_via`. This is a gate before `git commit`, not an afterthought.

2. **Inline context_summary.md updates** — `context_summary.md` updates are now part of the task, not after the task. After every bug fix revealing a non-obvious root cause, write the gotcha to `context_summary.md` BEFORE moving to the next request.

3. **Mandatory retrospective for all session types** — The retrospective is now explicitly mandatory at session end regardless of whether the session used Agent Teams or single-session mode. Minimum viable: 3-5 bullets covering actual vs planned scope, unanticipated discoveries, and transferable patterns.

4. **Task updates at moment of state change** — Task updates must happen immediately when state changes, not in batch. When you finish something, the NEXT action is `TaskUpdate`. Stale tasks are explicitly called out as worse than no tasks.

5. **Smoke test gate at session start** — `init.sh` is now a dedicated Step 2.5 in the orient flow, run within the first 5 actions of every session. Its purpose is to establish known-good state before changes, not to diagnose problems.

**Four moderate/minor violation remediations:**

6. **Single-session mode declaration** — When choosing single-session over Agent Teams, the lead must explicitly declare it to make the decision conscious and documented.

7. **Bug fix diagnosis before editing** — Debugging Phase 1 now requires stating diagnosis and proposed fix in 2-3 sentences before editing code, even for seemingly obvious fixes.

8. **Commit at natural breakpoints** — Commit hygiene rules now require committing after each feature/fix passes tests, separating harness metadata from code, and checkpointing inherited uncommitted work before making new changes.

9. **Untracked file and task metadata audit at orient** — The orient step now checks for unknown untracked files (surfaced to user) and verifies inherited tasks have required `feature_id` metadata.

**Two standards improvements:**

10. **Coverage blocker documentation** — If coverage measurement isn't available in the project's tooling, document it as a gotcha in `context_summary.md` and create a feature to enable it. Silent coverage gate skipping is no longer acceptable.

11. **Strengthened task completion checklist** — Harness-specific checklist items now explicitly require features.json audit, context_summary.md updates, retrospective, and task list currency check.

### v3.4.0 (2026-04-02)

**Bug fixes and convention improvements** based on analysis of Claude Code's internal multi-agent implementation compared against the harness's external hook protocol.

**Four bug fixes:**

1. **Scope enforcement path normalization** — `enforce-scope.sh` now strips the project root from absolute paths before matching. Tool input always provides absolute paths; scope patterns are relative. The prefix match was silently passing everything through.

2. **`depends_on` enforcement in idle hook** — `check-remaining-tasks.sh` now filters claimable features by dependency chains. A feature is only offered if all its `depends_on` entries have `status: "passing"`. Previously, blocked features were assigned as if ready.

3. **Targeted `correction_cycles` increment** — `verify-task-quality.sh` now extracts the feature ID from task metadata or subject prefix and only increments `correction_cycles` for that feature. Previously, all in-progress features were incremented on any teammate's rejection, corrupting metrics in multi-teammate sessions.

4. **Consistent JSON parsing in init.sh** — Replaced the fragile `grep`/`sed` chain for reading `stack` from `harness.json` with `python3 -c "import json; ..."`, matching every other script in the harness.

**Three convention changes:**

5. **Context Management in spawn templates** — Feature Implementer and Layer Implementer templates now instruct teammates to compact proactively before starting a new feature (after TeammateIdle reassignment) to prevent mid-implementation context loss.

6. **PostCompact circuit breaker** — The PostCompact hook prompt now detects repeated compaction context collapse (third+ compaction in rapid succession) and instructs the teammate to save state and escalate to the lead rather than looping.

7. **TaskCreate metadata convention** — All TaskCreate examples now include `metadata: { feature_id: "FXXX" }` for task-to-feature correlation that survives compaction. Enables the targeted `correction_cycles` fix.

**One docs change:**

8. **Completion message deduplication** — Added guidance to the Agent Teams messaging protocol to prevent duplicate completion messages when the TeammateIdle hook fires immediately after task completion.

### v3.3.0 (2026-03-28)

**Metacognitive self-improvement**: The harness now learns from its own coordination patterns, not just from domain work. Inspired by [Facebook Research's HyperAgents framework](https://arxiv.org/abs/2603.19461), which demonstrated that systems whose improvement mechanisms are themselves improvable outperform fixed-meta alternatives.

**Five coordinated changes:**

1. **Operational metrics in features.json** — Five new fields track coordination quality:
   - `correction_cycles`: auto-incremented by TaskCompleted hook on rejection. Signals features harder than expected.
   - `scope_expansions`: files/dirs added to scope after initial assignment. Reveals initial scoping accuracy.
   - `approaches_tried`: brief notes on what worked/failed before the passing implementation.
   - `failure_reason`: why a feature reached `status: "failed"`. Root cause without re-reading history.
   - `discovered_via`: discovery lineage — which feature's implementation revealed the need for this one (distinct from `depends_on` technical dependencies).

2. **Structured retrospective (Phase 5.5)** — Runs after all features pass, before teardown. Analyzes `correction_cycles`, `scope_expansions`, `discovered_via`, and `approaches_tried` across the session. Writes findings to `context_summary.md` under:
   - `## Meta-Session [DATE]`: session-specific insights (scope accuracy, model calibration, discovery patterns, approach successes/failures, plan approval value)
   - `## Meta-Patterns`: generalizable coordination insights that transfer to new projects (when to use Opus, how to scope, when plan approval pays off)
   - Applies to both single-session and Agent Teams workflows. Skipped on first session (no data yet).

3. **Tiered test evaluation in init.sh** — Split test runs into two stages (inspired by HyperAgents' staged evaluation):
   - `smoke_test`: compile/syntax check only, completes in <15s
   - `full_test`: complete suite with coverage (existing behavior)
   - TaskCompleted hook now runs smoke first; only runs full if smoke passes. Reduces cost of early rejection for compile errors.

4. **Meta-Patterns section in context_summary.md** — Dedicated section for coordination insights, distinct from domain-specific patterns. Populated by retrospective step. Intended to transfer to new projects as starting context.

5. **Dynamic model selection heuristics** — Phase 1 planning now reviews historical operational metrics before assigning Sonnet vs Opus:
   - `correction_cycles >= 3` in same scope → upgrade implementer to Opus
   - `scope_expansions >= 3` → assign broader initial scope, note as "expansion-prone"
   - `failure_reason` mentions interface misunderstandings → set `require_plan_approval: true`
   - `discovered_via` depth > 1 → consider folding into parent scope
   - All judgment calls for the lead, not mechanical rules.

**What this enables:** The harness accumulates coordination wisdom across sessions. After 3-4 Agent Teams sessions, it knows which scopes are tricky, which features need Opus, where to probe for hidden features at init. This is the practical version of HyperAgents' "metacognitive self-modification" — improving how the system improves, not just what it produces.

### v3.2.2 (2026-03-21)
- Replaced TodoWrite with TaskCreate/TaskUpdate (TodoWrite no longer exists in Claude Code)
- Renamed "delegate mode" to "plan mode" to match current Claude Code terminology
- Added worktree isolation for teammate scope enforcement (`isolation: "worktree"` in Task() calls)
- Added PostCompact hook for automatic context re-injection after compaction
- Made PostToolUse build-check hooks async (non-blocking)
- Added Auto-Memory vs context_summary.md guidance
- Synced CLAUDE.md template with installed global copy (Agent Autonomy override callout, git identity mismatch fix, context_summary.md anti-patterns)
- Added path-scoped frontmatter to agent-teams-protocol.md (already had `globs: [.harness/**]`)
- Removed `non-harness-workflow.md` rule; core loop folded into CLAUDE.md (saves ~3K tokens per session)
- Removed `engineering-standards.md` rule; 100% redundant with CLAUDE.md (saves ~3K tokens per session)
- Fixed TaskCreate API shape: dependencies set via TaskUpdate addBlockedBy, not TaskCreate blocked_by
- Fixed TeammateIdle documentation: hook prompts reassignment, doesn't auto-assign
- Fixed PostCompact hook: uses `type: "prompt"` for mechanical context injection
- Added PreToolUse scope enforcement hook (`enforce-scope.sh`) — blocks edits outside assigned scope
- Added PreToolUse git identity hook (`verify-git-identity.sh`) — blocks push/pull with wrong identity
- Added native `owner` field on TaskUpdate for task assignment alongside features.json `assigned_to`
- Added `activeForm` to TaskCreate examples for better spinner UX
- Added usage recommendations section to README
- Updated enforcement tier documentation with honest hook classification (mechanical vs prompted)

### v3.2.1 (2026-02-18)
- Fixed PostToolUse hook schema: PascalCase event name, proper nested `hooks` array
- Fixed hook commands to parse `tool_input.file_path` from stdin JSON via `jq`
- Documented `plan_approval_response` delivery bug; all plan approvals use direct messages

### v3.2 (2026-02-18)
- Extended features.json schema: `scope`, `depends_on`, `assigned_to` fields
- Defined exhaustive status enum: pending, in-progress, blocked, passing, failed
- Unified on `context_summary.md` across all modes (replaces `decisions.md`)
- Added hook verification step to harness-init
- Added Integration Failure Recovery protocol
- Recalibrated cost framing: "5x per implementer" not "5x overall"
- Tightened TodoWrite discipline: update after every TDD step
- Added delegation decision framework
- Extracted non-harness workflow to separate rules file
- Fixed plan-and-wait contradiction for teammate spawns

### v3.1 (2026-02-18)
- Added TaskCompleted and TeammateIdle hooks for mechanical quality enforcement
- Added plan-first workflow with user approval before spawning teammates
- Added model mixing guidance (Opus lead/reviewer, Sonnet implementers)
- Replaced custom messaging with native SendMessage protocol
- Added delegate mode as default for lead agents
- Added task dependency chains via TaskCreate blocked_by
- Added plan approval protocol for complex features

### v3.0 (2026-02-17)
- Replaced module locking with native Agent Teams integration
- Replaced 4-file pattern with compaction-aware approach (TodoWrite)
- Simplified features.json
- Added global engineering rules
- Added git identity capture and verification

### v2.1 (2025-02-01)
- Added module locking for parallel agent coordination
- Added `.context/modules.yaml` for defining code boundaries
- Added context-graph skill (claim/release/status/force-release)
- Restructured to use Claude Code's native memory system (`rules/`, `@imports`)

### v2.0 (2025-01-24)
- Initial public release
- Two-phase architecture (initializer + coding agents)
- 4-file pattern integration
- Multi-language init.sh support
