# Eval: Workflow-mode gate & hook verification (OVI-141, Phase 0)

Empirical de-risking of the Agent Teams → Dynamic Workflows migration (OVI-140).
Every verdict below is grounded in an observed run this session (workflow run IDs
cited), not in documentation. Where a claim could not be exercised from a plugin-repo
session, it is marked PARTIAL with the reason and the deferred validation point.

**Environment**: Claude Code 2.1.226, macOS, `/bin/bash` 3.2 for hooks. Spikes ran as
`Workflow` runs against this repo itself with `isolation: 'worktree'` as the disposable
surface. A separate `/harness-init` toy project was **not** used: PreToolUse/TaskCompleted
hooks bind to the *launch* project (`CLAUDE_PROJECT_DIR` / settings.json of the session
that started), so a toy project opened from this session cannot exercise this session's
hooks — the plugin repo's own live hooks are the correct surface, and worktree isolation
kept every probe write off the main checkout. Deviation from OVI-141's "toy project"
instruction, recorded here per the grounding rule.

## Q1 — PreToolUse gates fire for workflow-spawned subagents · VERIFIED-YES

Run `wf_fb726f39-06a` (3 parallel probes) and `wf_07bd5d47-c4e` (secret-scan probe).

- **commit-gate.sh**: a compound `git add X && git commit` was **DENIED** with the
  `compound-stage-and-commit` reason both in an isolated worktree agent and in a
  main-checkout agent. The split form (`git add` then a separate `git commit`)
  **succeeded** in the worktree (commit `94b56d3`). So the gate fires for workflow
  agents and its exit-2 deny blocks the tool call (also answers Q5).
- **Secret scan sees the correct index**: a worktree agent staged a synthetic
  `sk-ant-` + 20×`a` fixture line and attempted commit → **DENIED**, "anthropic key
  (sk-ant-) (staged diff line 7)". The gate scanned the *worktree's* index, not the
  launch checkout's.
- **`CLAUDE_PROJECT_DIR` is empty inside workflow agents** (confirmed via
  `printenv CLAUDE_PROJECT_DIR` → exit 1). The hooks resolve
  `PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"`
  (`commit-gate.sh:179`, `verify-task-quality.sh:30`), so with the env unset the
  git-toplevel fallback resolves to the **worktree** — which is why the worktree index
  was the one scanned.

  **Load-bearing fragility (flag for the workflow-protocol rule)**: this correct
  behavior depends on `CLAUDE_PROJECT_DIR` being *unset* for workflow agents. A manual
  control — invoking `commit-gate.sh` with `CLAUDE_PROJECT_DIR` **set** to the launch
  root while cwd was the worktree — returned `rc=0` (allow), because `PROJECT_ROOT`
  then pointed at the clean launch index. If a future CLI sets `CLAUDE_PROJECT_DIR` to
  the launch root for workflow agents, the commit gate would scan the wrong index and
  silently allow a worktree secret. Doctor/version probe (Q8) should watch for this.

## Q2 — TaskCompleted gate fires on lead self-completion · VERIFIED-YES (focused stage PARTIAL)

Mirrored passing feature F109 as a TaskCreate task (`metadata.feature_id: F109`) and
marked it complete. `.harness/last_gate.json` was **rewritten** (mtime 19:35 → 22:32,
content `{"smoke":"pass"}`), proving `verify-task-quality.sh` fired for a lead
self-completed task in a non-Teams session and ran `smoke_test`.

- **Focused-test stage: PARTIAL, and correctly so.** No `focused:F109` entry appeared
  because *this repo's own* `.harness/init.sh` has no `focused_test` target (this is
  exactly the F108 condition). So "smoke ran, focused skipped" is the correct,
  expected result here — but it means the *focused* stage firing under workflow
  orchestration is confirmable only on a `focused_test`-capable project. Deferred to
  the Phase 2 toy-project run (OVI-143 AC1). The gate mechanism itself is VERIFIED-YES;
  only the focused branch is unexercised on this repo.
- **Correlation caveat (grounds a Phase 2 test)**: the focused/coverage stages key on
  `metadata.task.metadata.feature_id` (`verify-task-quality.sh:143-145`). A mirrored
  task created *without* `feature_id` passes the "one task per feature" instruction
  while leaving those stages inert — so "mirror with `feature_id`" must be a hard,
  tested step in the workflow-protocol rule, not prose.

## Q3 — SubagentStart/SubagentStop reach plugin hooks · VERIFIED-YES

Temporarily wired logging `SubagentStart`/`SubagentStop` hooks (restored to committed
state afterward — `git status` clean). A trivial workflow agent (`wf_830369ee-070`)
produced both events. Payload carries `agent_id` (always present) and `agent_type`:

- plain workflow agent → `agent_type: "workflow-subagent"` (generic);
- typed Agent-tool subagents → their real type (`vv-harness:spec-verification`).

The dashboard graph keys on `agent_id` (present for all), so Phase 5 rendering is
viable. Caveat: some `SubagentStop` lines carried an empty `agent_type` with no paired
`Start` (orchestration/fork agents) — Phase 5 must tolerate Stop-without-Start and a
blank type (it already labels a missing type "(unknown agent)").

## Q4 — Worktree lifecycle · VERIFIED-YES

- Location: `.claude/worktrees/wf_<runId>-<n>`; branch `worktree-wf_<runId>-<n>`.
- **Unchanged worktree is auto-removed**: probe 3 made no writes; its worktree
  (`wf_fb726f39-06a-3`) was gone after the run. **Changed worktrees persist** until the
  lead removes them (probes that committed remained). → the lead **must** remove changed
  worktrees after merge, before any repo-wide suite run (the F094/F108-session bug where
  leftover worktrees gave 7 copies of every `*.md`; also cost a cwd-orphaned shell this
  session when a `git worktree remove` deleted the dir under an active `cd`). Written
  rule step, per OVI-140's run-continuity/worktree-hygiene additions.
- No clobber: two parallel implementers got distinct worktrees/branches; the lead
  stayed on its own branch (`eovidiu/ovi-140-phases-0-2`) throughout — the shared-checkout
  hazard that motivated the migration does not occur.

## Q5 — acceptEdits + deny still blocks · VERIFIED-YES

Worktree agents wrote files via the Write tool with no permission prompt (acceptEdits
in effect) yet the exit-2 commit-gate deny still blocked their compound commit (Q1). So
"agents auto-accept edits" and "PreToolUse denies still bind" hold simultaneously.

## Q6 — Structured-output reliability · VERIFIED-YES

Every schema in every spike this session validated and returned the declared object
shape. `null` semantics on kill/error are established from the prior session's review
workflow (`wf_62aae2ac-e3b`): 11 of 34 agents hit a session rate limit and their
`agent()` calls resolved to `null`, survivors returned intact — the exact contract the
run-continuity protocol (OVI-140) is built on.

## Q7 — args marshalling & plugin discovery · VERIFIED-YES (discovery PARTIAL)

- **`args` arrives as a JSON-ENCODED STRING, not a parsed object** (`wf_42a89151-b5e`:
  passed `{features:[...]}`, script observed `typeof args === "string"`,
  `Array.isArray(args.features) === false`). **Hard constraint for Phase 1**: scripts
  must `JSON.parse(args)` (guarded) before any field access. OVI-142 Preflight as
  written ("validate `args.features` is a non-empty array") would reject every valid
  call without the parse.
- **Plugin-root `workflows/` auto-discovery as `/vv-harness:<name>`: PARTIAL** — cannot
  be exercised until a build ships and is installed. Deferred to the Phase 1 release +
  a post-install manual check (OVI-142 AC1). Mitigation: keep the scripts invocable by
  path (`Workflow({scriptPath})`) regardless, so the feature is testable pre-discovery.

## Q8 — version / availability probing · VERIFIED-YES (org-disable PARTIAL)

- `claude --version` → `2.1.226` ≥ the 2.1.154 workflows floor. Parse the first token,
  compare minor — the same defensive pattern the worker-epoch check already uses.
- **`disableWorkflows` (org/settings): PARTIAL** — cannot be force-tested from here.
  Runtime detection is by capability, not by reading the flag: if the `Workflow` tool
  is absent, fall back to the worktree-isolated plain-subagent path. Doctor records the
  version; the skill degrades on tool-absence.

---

## Go / No-Go

**GO for Phase 1**, with the design amendments the spikes force (all already folded
into OVI-140's improved plan and carried into the Phase-1 feature specs):

1. Scripts `JSON.parse(args)` defensively (Q7) — non-negotiable.
2. Worktree hygiene (lead removes changed worktrees post-merge, before suite) is a
   written rule step, not tribal knowledge (Q4).
3. Mirrored tasks must carry `metadata.feature_id` or the focused/coverage gate stages
   go inert (Q2) — a tested requirement.
4. Enforcement (Q1) is confirmed present, so OVI-140's hard-gate condition ("if Q1 or
   Q2 is VERIFIED-NO, move enforcement into script verify phases") is **not** triggered
   — hooks stay the enforcement layer. Flag the `CLAUDE_PROJECT_DIR`-unset dependency
   for doctor.
5. Focused-stage firing and plugin auto-discovery are the two PARTIALs; both are
   release-/toy-gated and owned by the Phase 2 (OVI-143) end-to-end run, not blockers
   for shipping Phase 1 scripts.
