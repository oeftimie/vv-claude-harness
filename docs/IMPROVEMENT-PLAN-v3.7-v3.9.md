# VV Claude Code Harness — Improvement Plan v3.7.0 → v3.9.0

**Theme:** Spec traceability via OpenSpec linkage, plus adjacent session-discipline tightening.
**Baseline:** v3.6.0 (released April 2026, current main). Session discipline improvements from violation analysis (v3.5.0) plus installer stale-file detection (v3.6.0).
**Drafted:** 2026-05-02. Owner: Ovidiu.

---

## 1. Goal

Add durable, mechanically-enforceable spec traceability to the harness without merging it with OpenSpec. After v3.9.0, an agent starting work on a feature reaches for an authoritative spec instead of inventing intent from a one-line `description`, and months later you can answer "what spec does this code satisfy?" with three deterministic queries against files in git.

## 2. Problem statement

The harness's `features.json[i].description` is by nature lossy — a single sentence cannot carry the constraints, scenarios, and acceptance criteria that define a feature. When a session starts and an agent reads only the description, it fills the gap with plausible-sounding intuition. By the time tests pass, the deviation is baked in. Neither v3.5.0's session-discipline work nor v3.6.0's installer hardening addresses this; both tighten execution discipline, not intent fidelity.

OpenSpec already solves the intent-state problem (proposals, deltas, capabilities, archive lineage) but has no model of execution state, coverage, or coordination metrics. Each tool earns its keep on a different dimension. The gap is the linkage: the harness has no awareness of where a feature's spec lives, and OpenSpec has no awareness of which features implement which changes.

## 3. Design principles

These constrain every decision in this plan. Push back on any change that violates one.

1. **Link, don't merge.** features.json owns execution state; OpenSpec owns intent state. The integration is two pointer fields and a read-before-write protocol — nothing more.
2. **Default-on `spec_required`.** Once "spec is optional" becomes the norm, the failure mode leaks back in for the features that needed a spec most. Opt-out must be a deliberate edit per feature.
3. **Spec drafting and implementation in separate sessions.** Letting the same agent draft and implement is exactly how LLM-invents-intent comes back through the back door. Different prompts, different agents, human approval gate between them.
4. **Sync on PR merge, not on feature pass.** The interval between tests-green and merged is the review window. Archiving on pass promotes the spec before review.
5. **Path encodes state.** `spec_path` pointing inside `openspec/changes/` means "in flight." Pointing inside `openspec/specs/` means "archived." No redundant `spec_archived` field — three sources of truth drift faster than two.
6. **Mechanical only after prose has been validated.** Add hooks (PreToolUse, archive validation) only once the prompt-layer convention has been observed working. v3.7.0 ships with prose; v3.9.0 promotes to mechanism.
7. **Optional, not mandatory.** OpenSpec integration is opt-in at `harness-init`. Existing v3.6.0 projects keep working unchanged. Throwaway projects skip it.
8. **Delegate domain logic to OpenSpec.** The harness orchestrates *when* to invoke OpenSpec; OpenSpec owns *what* proposals, specs, deltas, and validation look like. Wrap all OpenSpec invocations in a `.harness/openspec.sh` shim so version differences absorb in one place. Never duplicate OpenSpec's content conventions (file names, section structure, validation rules) in harness prompts or code. If OpenSpec already has a verb for it (`/opsx:propose`, `/opsx:verify`, `/opsx:archive`), invoke the verb — don't reimplement.

## 4. Schema additions

### 4.1 `features.json` — new fields per feature

```json
{
  "id": "F003",
  "description": "Add session token rotation",
  "...": "(existing fields unchanged)",
  "spec_path": "openspec/changes/add-session-rotation/",
  "spec_required": true
}
```

- `spec_path` (string | null): Path to the change folder during implementation; updated to the archived capability spec (path returned by OpenSpec; follows OpenSpec's `specs_dir` convention) after PR merge. Null until a spec is drafted.
- `spec_required` (boolean, default `true`): Whether implementation may proceed without a spec. False reserved for trivial work (dep bumps, formatting, tiny refactors). Setting to false must be an explicit edit, not a default.

Both fields are nullable for backwards compatibility — existing v3.6.0 features without these fields are treated as `spec_required: false, spec_path: null`. This prevents v3.7.0 from breaking projects that don't opt in.

### 4.2 `harness.json` — new top-level block

```json
{
  "...": "(existing fields)",
  "openspec": {
    "enabled": true,
    "cli_required": true,
    "specs_dir": "openspec/specs",
    "changes_dir": "openspec/changes",
    "config_synced_at": "2026-05-02T14:30:00Z"
  }
}
```

Absent block = OpenSpec disabled for this project. All spec-related logic in `harness-continue` no-ops when this block is missing or `enabled: false`.

**Field ownership:**
- `enabled` and `cli_required` are harness-owned settings (the user's choices about how the harness should behave).
- `specs_dir` and `changes_dir` are *not* hand-edited. They are populated and refreshed by the OpenSpec shim's `sync-config` verb (see §6 v3.7.0 — The OpenSpec shim). The shim queries OpenSpec for its current configured paths and writes them into harness.json. This avoids hardcoding OpenSpec's directory layout in the harness.
- `config_synced_at` is an ISO-8601 timestamp written by the shim on each sync, used by drift detection to flag stale config.

`cli_required: true` means `harness-continue` Phase 0 fails loudly if `openspec` is not on PATH. Setting to `false` allows file-only workflows (you read/write specs as plain Markdown without the CLI). Default: `true` when opted in.

`harness-continue` Phase 0 runs `.harness/openspec.sh sync-config` every session when `enabled: true`, so the mirrored paths refresh automatically. Cost: one CLI call per session. Benefit: harness.json is never out of date with OpenSpec's actual configuration.

## 5. Lifecycle (definitive reference)

```
Feature created in features.json
  spec_required: true
  spec_path: null
  status: "pending"
                ↓
Spec-drafting pass (separate agent, narrow prompt: "invoke OpenSpec's
  proposal flow")
  → drafter invokes /opsx:propose <change-name>
  → OpenSpec produces its proposal artifacts under its changes directory
    (the harness does not define what files are produced)
  → drafter SendMessages the lead with the change-name and folder path
  → lead presents to user
  → human approves
                ↓
features.json updated:
  spec_path: "openspec/changes/F003-session-rotation/"
  (status unchanged; now claimable by an implementer)
                ↓
Implementer spawned with spec_path in prompt
  → Reads spec FIRST (mechanical in v3.9.0; prose in v3.7.0)
  → writes failing test
  → implements
  → tests pass
                ↓
features.json updated:
  status: "passing"
  spec_path: unchanged (still inside changes/)
                ↓
PR opened, reviewed, possibly delta updated alongside code changes
                ↓
PR merged → invoke OpenSpec's archive flow (/opsx:sync then /opsx:archive,
  or whatever OpenSpec's current canonical sequence is)
  → OpenSpec promotes the delta into the source-of-truth spec
                ↓
features.json updated:
  spec_path: updated to point at the archived capability spec returned by OpenSpec
  (now points permanently at archived capability — exact path is OpenSpec's
   convention, not the harness's)
```

Five transitions. Each one explicit. Each one git-blame-able. No invented intent.

## 6. Phased rollout

Three releases, each independently shippable. Earlier phases must not regress when later phases ship.

---

### v3.7.0 — Linkage Layer

**Goal:** features.json knows about specs; agents see the spec_path in their spawn prompt and have prose instructions to read it before writing code. No mechanical enforcement.

**Ship criterion:** A fresh `harness-init` on a new project, opting into OpenSpec, produces correct structure. A subsequent session claims a feature with `spec_path` set, the spawn prompt includes the path, and the agent reads the spec file before its first Edit/Write tool call. Verified by inspecting agent transcripts on at least one real project.

#### Files to change

| File | Change |
|---|---|
| `claude/skills/harness-init/SKILL.md` | Add Step 1.5 (OpenSpec opt-in prompt). Update Step 3 (`.harness/harness.json` and `features.json` schemas with new fields). Add Step 3.1 (create `.harness/openspec.sh` shim from inlined template; run `sync-config` to populate paths). Update Step 7 if it documents schema. |
| `claude/skills/harness-continue/SKILL.md` | Add Step 0 (read `harness.json` openspec block; verify CLI presence if `cli_required: true`; run `.harness/openspec.sh sync-config` to refresh mirrored paths). Update Step 1 to surface `spec_path` per feature when summarizing state. |
| `claude/rules/agent-teams-protocol.md` | Update spawn prompt template (Lead Agent Responsibilities section) to include "Spec: `<spec_path>`" line and "Before writing any code, Read the spec at `<spec_path>`. Do not proceed on intuition." instruction. Update Teammate Responsibilities to make the read step explicit. |
| `claude/CLAUDE.md` | Add `## Spec Discipline` section between `## Operating Modes` and `## Testing Standards`. Document the linkage convention, default-on `spec_required`, the read-first protocol. |
| `README.md` | Add v3.7.0 changelog section. Update version badge. Add brief "OpenSpec integration" subsection to evolution narrative. |
| `INSTALL.md` | Add OpenSpec prerequisite note (optional dependency). Note that `openspec init` installs its own artifacts into `.claude/skills/openspec-*/SKILL.md` and `.claude/commands/opsx/` — these sit alongside the harness's `harness-init` and `harness-continue` skills with distinct names, so no collision is expected. Document install order: install harness first, then `openspec init` per-project when opting in. |
| `install` script | No change unless adding new files (none in v3.7.0). |

#### Concrete prompt additions

**Spawn prompt template addition (in `agent-teams-protocol.md`):**

```
Feature: F003 — Add session token rotation
Scope: src/auth/, tests/auth/
Spec: openspec/changes/add-session-rotation/  (OpenSpec change folder)

BEFORE writing any code:
1. Read the spec materials at the path above. The folder structure follows
   OpenSpec's conventions for that change — read whatever files OpenSpec
   placed there. If you need a canonical view, you can also invoke OpenSpec's
   own commands (e.g., `/opsx:apply <change-name>` to follow OpenSpec's
   implementation flow).
2. If the spec is missing, ambiguous, or contradicts this feature description,
   SendMessage to the lead and stop.
3. Do not proceed on intuition. The spec is the source of truth for intent.
```

The prompt names the path and the responsibility (read before write). It does NOT enumerate which files exist inside the change folder — that's OpenSpec's content model, and the harness must not duplicate it. If OpenSpec adds or renames artifacts, the prompt stays correct.

**`harness-init` opt-in prompt (Step 1.5):**

```
Optional: enable OpenSpec spec traceability for this project?

OpenSpec is a lightweight spec-driven framework that pairs well with the harness.
When enabled:
- Each feature points at a spec via the spec_path field.
- Agents read the spec before writing code.
- Specs are checked into git as living documentation.

Recommended for: projects spanning >2 weeks, multi-developer projects, projects
where intent fidelity matters (security, compliance, public APIs).
Skip for: throwaway prototypes, single-session work, formatting-only repos.

Enable OpenSpec? (yes/no)
```

**`CLAUDE.md` template — new `## Spec Discipline` section:**

```markdown
## Spec Discipline

If `harness.json` has `openspec.enabled: true`, every feature has either:
- `spec_path` pointing inside OpenSpec's changes directory (in-flight), or
- `spec_path` pointing inside OpenSpec's specs directory (archived), or
- `spec_required: false` (explicit opt-out for trivial work).

The exact directory paths come from OpenSpec's configuration; the harness does not
define them. The two states are distinguished by which configured directory the path
lives under.

A feature with `spec_required: true` and `spec_path: null` is BLOCKED. Implementation
cannot start. The harness-continue protocol triggers a spec-drafting pass first.

**Before writing any code on a claimed feature**: Read the spec materials at `spec_path`.
The folder structure follows OpenSpec's conventions — read whatever files OpenSpec placed
there. Do not proceed on intuition. If the spec is unclear, ask before coding.

**On feature pass**: spec_path remains unchanged (still in OpenSpec's changes directory).
The review window between tests-green and PR-merged is when reviewers may demand spec
updates.

**On PR merge**: invoke OpenSpec's archive flow (e.g., `/opsx:sync` then `/opsx:archive`,
or whatever OpenSpec's current canonical sequence is — defer to OpenSpec's docs and the
`.harness/openspec.sh` shim). Then update the feature's spec_path to the path OpenSpec
returned. This is the long-term traceability anchor.
```

#### The OpenSpec shim

`.harness/openspec.sh` is the single integration boundary between the harness and OpenSpec. All OpenSpec invocations from harness code go through it. When OpenSpec changes (CLI verbs, config layout, slash command names), only this file changes.

The shim is created by `harness-init` from a template inlined in `claude/skills/harness-init/SKILL.md`, written to `.harness/openspec.sh` in the user's project, and made executable. It is committed to the project repo (it's part of the harness's per-project state, not user-edited config).

**Verbs the shim must expose:**

| Verb | Purpose | Used by |
|---|---|---|
| `sync-config` | Query OpenSpec for its current configured paths; write `specs_dir`, `changes_dir`, and `config_synced_at` into `harness.json`'s openspec block. Idempotent. | `harness-init` Step 3.1; `harness-continue` Phase 0 |
| `validate <change-name>` | Delegate to OpenSpec's validator (current: `openspec validate <name>` or equivalent). Exit 0 on success, non-zero with stderr message on failure. | `verify-task-quality.sh` (v3.9.0) |
| `verify <change-name>` | Delegate to OpenSpec's implementation-vs-artifacts check (current: `/opsx:verify` or CLI equivalent). Exit 0 on success, non-zero with message on failure. If OpenSpec doesn't expose this verb, exit 0 with a stderr note (degrades to no-op). | `pre-archive-check.sh` (v3.9.0) |
| `archive <change-name>` | Delegate to OpenSpec's archive flow (current: `/opsx:sync` then `/opsx:archive`, or whatever OpenSpec's canonical sequence is). Print the resulting archived spec path on stdout for the caller to capture. | post-merge archive automation (v3.8.0+) |

**Implementation notes:**

- The shim is a single bash script. All OpenSpec-version-specific logic lives in it.
- When OpenSpec ships a breaking change, only the shim updates. Harness logic, prompts, and hooks are unaffected.
- The shim should `set -euo pipefail` and emit useful diagnostics on failure.
- The `sync-config` verb is the most version-sensitive (it depends on how OpenSpec exposes its config). For v3.7.0, implement it by parsing the output of whichever current OpenSpec command reveals config (e.g., `openspec config show` or reading a config file directly). Document the assumption in the shim itself so future maintainers know what to update.

#### Validation for v3.7.0

1. Run modified `harness-init` on a fresh project, opt into OpenSpec, confirm `harness.json` and `features.json` have correct structure. Confirm `.harness/openspec.sh` was created and is executable. Confirm `sync-config` ran and `specs_dir` / `changes_dir` are populated with OpenSpec's actual configured paths (not hardcoded defaults).
2. Run `.harness/openspec.sh sync-config` manually a second time — confirm idempotent (no errors, `config_synced_at` updates).
3. Add a feature manually with `spec_path` pointing at a real change folder.
4. Run `harness-continue`, confirm Phase 0 invokes `sync-config` and refreshes the timestamp. Claim the feature, confirm spawn prompt includes spec path and read instruction.
5. In agent transcript, confirm `Read` tool was called on a file inside `spec_path` before any `Edit`/`Write` on scope files. (Which file OpenSpec produced is OpenSpec's business; the harness only checks that *something* under the spec_path was read.)
6. Run on a v3.6.0 project (no OpenSpec opt-in) — confirm zero behavior change. Phase 0 detects no openspec block and skips shim invocation.
7. Manually change OpenSpec's configured paths (rename `openspec/` to `specs/` via OpenSpec config). Run `harness-continue` again — confirm Phase 0 picks up the new paths via `sync-config`, drift detection reflects the new layout.

---

### v3.8.0 — Spec-Drafting & Sync

**Goal:** Handle the "no spec yet" case explicitly. Sync archive to the right moment. Detect drift between features.json and the openspec/ tree.

**Ship criterion:** A project with a feature `spec_required: true, spec_path: null` runs `harness-continue` and the protocol blocks implementation, runs a separate spec-drafting pass with a human approval gate, then unblocks. PR-merge archive updates spec_path correctly. Drift report appears at session start.

#### New protocol elements

**Spec-drafting pass.** A new role, distinct from implementer. The drafter's job is to *invoke OpenSpec's own proposal flow* — not to write proposal artifacts directly. Prompt template:

```
You are a spec drafter for feature [F003]: [description].

Invoke OpenSpec's proposal flow:
  /opsx:propose [change-name]

Where [change-name] is a kebab-case identifier you choose for this feature
(e.g., add-session-rotation). Follow OpenSpec's prompts. OpenSpec owns the
content, format, and structure of the proposal — your job is to drive its
flow, answer its questions accurately, and let it produce its artifacts.

When OpenSpec signals completion (the change folder exists at the path
OpenSpec reports), validate it:
  openspec validate [change-name]
  (or invoke /opsx:verify if your project has it)

Then SendMessage to the lead with:
  - The change-name
  - The folder path OpenSpec produced
  - A one-paragraph summary of intent (in your own words, for the human
    approval gate — not a replacement for the spec OpenSpec just wrote)

DO NOT:
- Write or modify proposal/spec/design files manually. OpenSpec writes them.
- Bypass OpenSpec's flow with manual file creation in openspec/changes/.
- Define proposal format yourself — that's OpenSpec's job.
- Touch any files outside openspec/.
- Write code or tests (this is the drafting phase, not implementation).
```

The lead receives the SendMessage, presents the draft to Ovidiu (who reads what OpenSpec produced, not a harness-formatted summary), approves or requests revision. Only after approval does features.json get updated with `spec_path`.

If OpenSpec's slash command names change in a future release, only the prompt template above needs updating — none of the harness's logic depends on `proposal.md` existing or having any particular structure.

**Drift detection at session start.** New step in `harness-continue` Phase 1:

```bash
# Pseudo-logic. CHANGES_DIR and SPECS_DIR are read from harness.json's
# openspec block (which mirrors OpenSpec's configured paths) — never
# hardcoded.

for feature in features.json:
  if feature.spec_path is set:
    if not file_exists(feature.spec_path):
      flag "feature F003 spec_path points at missing file"

for change_dir in $CHANGES_DIR/*:
  if no feature in features.json has spec_path matching change_dir:
    flag "orphan change: no feature implements [change_dir]"

for spec_file in $SPECS_DIR/*:
  if no feature in features.json has spec_path matching spec_file:
    # not necessarily a problem — old archived specs may have no live feature
    note "no live feature points at [spec_file] (informational)"
```

Flags surface in the session-start summary. Drift = surfaced for resolution, not blocking.

**Archive flow on PR merge.** Primary mechanism: git post-merge hook in `.harness/`. Manual step is documented as a fallback only.

**Primary: `.harness/post-merge.sh`** (installed by harness-init when openspec is enabled). On `main` branch merge:
1. Parse the merged commits for `[F00X]` references via `git log` since last sync.
2. For each referenced feature: read its `spec_path` from features.json. If it points inside OpenSpec's changes directory, invoke `.harness/openspec.sh archive <change-name>`.
3. Capture the archived path the shim returns on stdout.
4. Update features.json: rewrite `spec_path` to the archived path.
5. Commit the features.json update with message `docs: archive specs for [F003, F004, ...]` (separate commit from the merge itself).

If the hook fails for any feature (shim returns non-zero, OpenSpec rejects the archive), the hook surfaces the failure but does not abort the merge. Failed archives go into a queue file `.harness/.pending-archives.json` for the next `harness-continue` session to retry.

**Fallback (manual step in session-end checklist):** for cases where the post-merge hook didn't run (merge performed on remote without local hook execution, force-push scenarios, etc.). The checklist instructs the user to invoke OpenSpec's archive flow manually for each merged feature and update spec_path by hand.

The harness never decides what "archive" means — it just calls OpenSpec via the shim and records where OpenSpec moved the spec. If OpenSpec changes its archive flow (e.g., merges sync and archive into one command, splits into three), only the shim updates.

This is a behavioral change from the prior plan draft: archive automation lands in v3.8.0, not deferred to v3.9.0. The shim's `archive` verb is therefore a v3.8.0 ship requirement.

**Retrospective additions.** `Phase 5.5` (retrospective) gets a new "Spec Lineage" section:

```markdown
### Spec Lineage (this session)
- Capabilities touched: [list]
- Changes archived: [list]
- Drift detected: [count, surfaced where]
- Spec drafts approved on first pass: [N/M]
- Spec drafts rejected and revised: [N/M]
```

Patterns ("spec drafts in scope X always need 2+ revisions") feed Meta-Patterns for future model selection.

#### Files to change

| File | Change |
|---|---|
| `claude/skills/harness-continue/SKILL.md` | New Phase 1 substep: spec-state check (block if drafting needed). New Phase 1 substep: drift detection. New Phase 1 substep: replay `.harness/.pending-archives.json` if non-empty. New role section: spec-drafter. New Phase 5.5 substep: Spec Lineage retrospective. |
| `claude/rules/agent-teams-protocol.md` | New "Spec Drafter" role section (default model: Opus). New "Plan Approval" subcase: spec drafts always require approval. |
| `claude/CLAUDE.md` | Expand `## Spec Discipline` with drafting protocol, archive timing, and the post-merge hook behavior. |
| `claude/skills/harness-init/SKILL.md` | Extend Step 3.1 (shim creation) to add the `archive` verb to the inlined shim template. Add Step 3.6 (install `.harness/post-merge.sh` hook) when openspec is enabled. |
| `claude/scripts/post-merge.sh` (template) | NEW — installed at `.harness/post-merge.sh` per project. Parses commits, invokes shim's archive verb, updates features.json, queues failures. |
| `claude/skills/harness-init/templates/migrate-to-openspec.sh` | NEW — optional migration script for existing v3.6.0 projects. Walks features.json, prompts the user to invoke `/opsx:propose` for each `passing` feature, records resulting `spec_path`. |
| `README.md` | v3.8.0 changelog. |

#### Validation for v3.8.0

1. Project with `spec_required: true, spec_path: null` for some feature: confirm implementation is blocked, drafter spawns (on Opus), approval gate works, post-approval implementation proceeds normally.
2. Manually break a `spec_path` (rename the change folder): confirm drift detection flags it.
3. Add a change folder not referenced by any feature: confirm orphan flag.
4. Complete a feature, merge a PR locally on `main`: confirm `.harness/post-merge.sh` fires, invokes `.harness/openspec.sh archive`, captures the returned path, updates `spec_path` in features.json, commits the update with `docs:` prefix.
5. Force a shim archive failure (e.g., manually corrupt the change folder before merge): confirm post-merge.sh appends to `.harness/.pending-archives.json` and does not abort the merge. Run `harness-continue` next session: confirm Phase 1 replays the queue and surfaces the failure.
6. Run `harness-migrate-to-openspec.sh` on a copy of an existing v3.6.0 project with passing features: confirm it loops over features, prompts for each, records spec_path correctly when the user invokes `/opsx:propose`.
7. Retrospective output includes Spec Lineage section.

---

### v3.9.0 — Mechanical Enforcement

**Goal:** Promote spec discipline from prose to physical mechanism. An agent that tries to skip the spec read is blocked at the tool layer.

**Ship criterion:** PreToolUse hook blocks Edit/Write to scope files unless `spec_path` was Read in the current session, OR the user has activated `--bypass-spec-check` for the current session/window. TaskCompleted hook delegates validation to OpenSpec via the shim. Pre-archive gate delegates implementation-vs-artifacts checking to OpenSpec's `/opsx:verify` (or its CLI equivalent) — the harness does not roll its own heuristic.

#### New hooks

**1. `enforce-spec-read.sh` (PreToolUse on Edit/Write):**

```
Inputs: tool name, file path, current session's tool call history.
Logic:
  - Read .harness/harness.json: if openspec.enabled false, exit 0.
  - Check for active bypass: if .harness/.bypass-spec-check exists and is
    not expired (TTL or remaining-call-count not exhausted), decrement the
    counter, log the bypass to .harness/bypass-usage.log, exit 0.
  - Read .harness/teammate-feature.txt: get current feature_id (set by lead
    at spawn).
  - Read features.json: get feature.spec_path and feature.spec_required.
  - If spec_required false, exit 0.
  - If spec_path null, exit 2 with feedback: "Feature requires a spec.
    spec_path is null. Cannot proceed."
  - If file path matches feature.scope:
    - Check session's prior Read tool calls. If spec_path is a folder, any
      Read inside that folder counts (the harness does not assert which file
      OpenSpec produced). If spec_path is a file (post-archive), only a Read
      of that file counts.
    - If no qualifying Read found, exit 2 with feedback: "Read the spec at
      [path] before editing scope files. To bypass for emergencies, run:
      .harness/bypass-spec-check --enable [--calls=N | --duration=Tm]"
  - Otherwise exit 0.
```

**Override mechanism (`--bypass-spec-check`):** A small CLI utility installed at `.harness/bypass-spec-check` accepts:

- `--enable [--calls=N] [--duration=Tm]` — write `.harness/.bypass-spec-check` marker file with TTL (default: 5 calls or 10 minutes, whichever expires first). Mutually-exclusive constraint to prevent permanent disablement.
- `--disable` — remove the marker.
- `--status` — show current state.

The hook reads the marker, decrements the call counter, and self-clears when exhausted. Each bypass is logged to `.harness/bypass-usage.log` (one line: timestamp, feature_id, file_path, reason if provided). The retrospective reads this log and emits a "bypass rate" metric: bypasses per total scope-file edits. If >5%, the calibration is off (per §9 risk row).

The flag is not an environment variable because env vars persist across sessions and are easy to forget; the marker-file approach is auditable and self-clearing.

This is the load-bearing mechanism. Without it, prose discipline drifts within 2 sessions on tired Fridays.

**2. Spec validation extension to existing `verify-task-quality.sh`:**

After tests pass, if feature has `spec_path` inside the OpenSpec changes directory, delegate to OpenSpec's own validator:
```bash
# Pseudo — actual call goes through .harness/openspec.sh shim
.harness/openspec.sh validate "$change_name" || {
  echo "OpenSpec validation failed. Fix before marking complete." >&2
  exit 2
}
```

The harness does not define what "valid" means. OpenSpec does. The shim wraps whichever CLI verb OpenSpec exposes for validation (`openspec validate`, `openspec verify`, or future equivalents).

**3. `pre-archive-check.sh` (called by archive automation):**

Before invoking OpenSpec's archive flow, run OpenSpec's own implementation-vs-artifacts check via the shim:
```bash
# Pseudo
.harness/openspec.sh verify "$change_name"
```

OpenSpec's `/opsx:verify` (or its CLI equivalent) is documented as "Validate implementation matches artifacts" — exactly the check we need. The harness must not roll its own heuristic for this. If the shim call returns failure, surface the message as a warning (not a blocker — humans may legitimately need to override). If OpenSpec doesn't expose a verify verb in some future release, the shim degrades to a no-op and the check is skipped.

#### Files to change

| File | Change |
|---|---|
| `claude/hooks/enforce-spec-read.sh` | NEW — PreToolUse hook on Edit/Write. |
| `claude/hooks/verify-task-quality.sh` | Extend with spec validation step (delegate to shim). |
| `claude/hooks/pre-archive-check.sh` | NEW — invoked by archive automation. Delegates to shim's `verify` verb. |
| `claude/scripts/bypass-spec-check.sh` (template) | NEW — installed at `.harness/bypass-spec-check` per project. Toggles TTL'd marker file, logs usage. |
| `claude/skills/harness-init/SKILL.md` | Install new hooks and bypass utility during init when openspec_enabled. Extend shim template with `validate` and `verify` verbs. Update post-merge.sh template to invoke `pre-archive-check.sh` before calling the shim's archive verb. Add hook verification step. |
| `claude/skills/harness-continue/SKILL.md` | Reference new hook behavior in Phase 0 verification. Phase 5.5 retrospective reads bypass-usage.log and emits bypass-rate metric. |
| `claude/rules/agent-teams-protocol.md` | Document `teammate-feature.txt` (the per-spawn marker file). |
| `README.md` | v3.9.0 changelog. |

#### Per-spawn marker file

The `enforce-spec-read.sh` hook needs to know which feature the current agent is working on. The lead writes `.harness/teammate-feature.txt` (or similar) when spawning each teammate, mirroring the existing `.claude/teammate-scope.txt` pattern documented in `agent-teams-protocol.md`. Single-line file, just the feature ID.

#### Validation for v3.9.0

1. Spawn an agent on a feature with valid spec_path. Try to Edit a scope file before reading the spec — confirm hook blocks.
2. Read the spec, then Edit — confirm hook allows.
3. Mark a task complete with an invalid delta (manually corrupt) — confirm validate-spec-on-complete rejects.
4. Run pre-archive-check on a clean change — passes. Run on a divergent change — surfaces warning.
5. Run on a non-OpenSpec project — all hooks no-op cleanly.

---

## 7. Backwards compatibility & migration

**v3.6.0 projects without OpenSpec opt-in:** zero changes. The new fields are nullable; absent `harness.json` openspec block disables all spec logic. v3.7.0 → v3.9.0 are pure additions for non-OpenSpec projects.

**Existing harness projects opting in mid-stream:** add the openspec block to `harness.json`, run `openspec init`, set `spec_required: true` for new features, leave existing features at `spec_required: false` (they were built without specs and trying to retrofit specs to passing code creates fiction). The retrospective `Spec Lineage` section will show "0/N features had specs at session start" for the first session, gradually filling in as new features are added.

**Migration script (ships in v3.8.0):** `harness-migrate-to-openspec.sh` walks features.json and, for each `passing` feature, prompts the user to invoke OpenSpec's proposal flow (`/opsx:propose <name>`) to write a retroactive spec, then records the resulting `spec_path`. The script orchestrates the loop; OpenSpec writes the specs. Treated as documentation work, not code work. Optional from the user's perspective (they can opt in feature-by-feature or skip), but the tooling itself is shipped — not gated on "if demand exists."

## 8. Testing strategy

This repo has no application tests because it's a distribution repo. Validation must happen in real harness projects.

**Test matrix per phase:**

| Test | v3.7.0 | v3.8.0 | v3.9.0 |
|---|---|---|---|
| Fresh init, OpenSpec enabled, schema correct | ✓ | ✓ | ✓ |
| Fresh init, OpenSpec disabled, behaves as v3.5.0 | ✓ | ✓ | ✓ |
| Existing v3.6.0 project unchanged after upgrade | ✓ | ✓ | ✓ |
| Spawn prompt includes spec_path | ✓ | ✓ | ✓ |
| Agent reads spec before edit (transcript verified) | ✓ | ✓ | ✓ |
| Spec-drafting blocks implementation when needed | — | ✓ | ✓ |
| Drift detection surfaces broken pointers | — | ✓ | ✓ |
| Post-merge archive updates spec_path | — | ✓ | ✓ |
| Hook blocks edit without spec read | — | — | ✓ |
| Hook validates spec on task complete | — | — | ✓ |
| Pre-archive check surfaces divergence | — | — | ✓ |

**Validation projects:** propose two real projects to dogfood each phase before tagging release. v3.7.0 on a small project to validate prose layer; v3.8.0 on a multi-week project to validate drafting and drift; v3.9.0 on a security-sensitive project where mechanical enforcement earns its complexity.

## 9. Risks & mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| OpenSpec API churn (CLI breaking changes) | Medium | High | Wrap all `openspec` calls in `.harness/openspec.sh` shim. One file changes when CLI shifts. |
| OpenSpec abandoned upstream | Low | High | Specs are plain Markdown in git; archive lineage survives. `cli_required: false` mode lets workflow continue without the CLI. |
| Spec drafting becomes tedious paperwork, team skips it | Medium | High | Resist mandatory templates. proposal.md can be 3 lines if intent is simple. Default-on `spec_required` is the floor, not the ceiling. Retrospective tracks "spec drafts approved first pass" as a fluency metric. |
| `enforce-spec-read.sh` hook false-positives on legitimate edits | Medium | Medium | Hook only fires on files matching feature.scope. Override via `.harness/bypass-spec-check --enable` (TTL'd marker file with call-count or duration limit; self-clearing; not an env var, to avoid persistent disablement). Each bypass logged to `.harness/bypass-usage.log`. Retrospective tracks bypass rate; if >5%, the hook is mis-calibrated. |
| 1:1 feature:change assumption breaks for big changes | Medium | Low | Convention not constraint. Multiple features can share `spec_path` (same change folder). Retrospective flags features with shared spec_path as candidates for splitting. |
| Pre-merge spec drift (code changes during review without delta updates) | High | Medium | Pre-archive check is a heuristic warning, not a blocker. Reviewers are the real check. Document the responsibility in CLAUDE.md. |
| OpenSpec installation friction blocks adoption | Medium | Low | Opt-in, not default. INSTALL.md notes it's optional. Projects without OpenSpec keep working. |
| Spec-drafter agent invents intent the same way | Medium | High | Drafter prompt explicitly forbids implementation thinking and forbids manual file creation (must go through OpenSpec's `/opsx:propose`). Human approval gate is mandatory. Drafter has no Edit/Write access outside the change folder OpenSpec produced. Default model: Opus (drafting is reasoning-heavy on intent capture; cost is worth it). Implementer remains on Sonnet by default. |

## 10. Adjacent improvements (parking lot, not committed)

Surfaced from reading v3.5.0 and the README evolution narrative. Not part of v3.6–3.8 but worth tracking:

1. **Smoke test caching.** v3.5.0 makes smoke test mandatory at session start. If init.sh is slow on some projects, cache last-run hash and skip if no relevant files changed. Optimization, not correctness.
2. **Compaction-aware retrospective.** Currently the retrospective runs at session end. If session compacts mid-flight, retrospective signals get lost. Consider a "mini retrospective" snapshot at compaction points.
3. **Dynamic model selection enrichment.** v3.3 introduced operational metrics for model selection. Could fold spec_required and spec drafting outcomes into the same signal (a feature whose spec required 3 revisions probably needs Opus for implementation too).
4. **Agent Teams permissions hardening.** Teammates inherit lead permission mode. Worth documenting which permissions to deny by default for spec drafters (no Edit access outside changes/<id>/).
5. **MCP server for harness state.** Surfacing features.json, context_summary.md, and spec state through an MCP server would let agents query state with structured tools instead of cat-ing files. Worth prototyping after v3.9.0 ships.
6. **Cost telemetry.** No real measurement of "how much does Agent Teams cost vs single session" exists. Adding a token/cost summary to the retrospective would let dynamic model selection optimize for cost too.

These are scoped out of this plan deliberately — each could be its own minor release.

## 11. Open questions (all resolved as of 2026-05-02)

All decisions made. Plan is executable.

1. **Default `spec_required` for features added mid-project (not at init)?** RESOLVED. Default-on confirmed. Setting to false requires a deliberate edit per feature. This is consistent with §3 Principle 2.
2. **Spec-drafter model:** RESOLVED. Default = Opus. Drafting is reasoning-heavy on intent capture and the cost is worth it. Per-project override possible by setting model in the spawn call, but Opus is the recommended default. This affects model selection logic in `harness-continue` Phase 1 when the drafter is spawned.
3. **Archive trigger:** RESOLVED. Git post-merge hook ships in v3.8.0 (not deferred to v3.9.0). The shim's `archive` verb is required for v3.8.0 ship. Manual fallback documented for cases where the hook can't run (e.g., merges done outside local git).
4. **Hook override mechanism:** RESOLVED. `--bypass-spec-check` flag. Implementation: a small CLI utility (`.harness/bypass-spec-check`) toggles a TTL'd marker file (`.harness/.bypass-spec-check`) that `enforce-spec-read.sh` checks for and respects. Self-clearing after a small number of tool calls or session end, whichever comes first, to prevent permanent disablement. Override usage tracked for the >5% calibration metric.
5. **Multi-repo / monorepo / non-default OpenSpec layouts:** RESOLVED. The `.harness/openspec.sh` shim exposes a `sync-config` verb that queries OpenSpec for its configured paths and writes them into `harness.json`'s openspec block. `harness-init` runs it during setup; `harness-continue` runs it in Phase 0 every session to keep the mirror fresh. Harness code reads `specs_dir` / `changes_dir` from harness.json — never hardcoded. Monorepo edge case (per-package OpenSpec configs) handled if OpenSpec itself supports it; the shim relays whatever OpenSpec reports. See §6 v3.7.0 — The OpenSpec shim.
6. **Spec versioning:** RESOLVED. spec_path points at the *current* archived capability spec (live file in OpenSpec's specs directory). When a capability is later modified by another change, spec_path continues to track the live file — the historical version a feature originally implemented is recoverable via OpenSpec's archive lineage and git history of the spec file, both of which OpenSpec owns. The harness does not version or snapshot spec contents.
7. **Onboarding existing harness projects:** RESOLVED. The optional migration script ships in v3.8.0 (not v3.7.0). v3.7.0 ships only the linkage layer for new projects and projects opting in fresh. Existing v3.6.0 projects can opt in mid-stream by running the v3.8.0 migration script, which orchestrates retroactive `/opsx:propose` invocations for `passing` features. v3.7.0 is intentionally narrow — get the schema and prompt layer right first, before tackling retroactive migration.

## 12. Success criteria (six months out)

Ship is complete and successful when, six months after v3.9.0 lands:

- At least three real projects use OpenSpec integration through full feature lifecycle (drafting → implementation → archive).
- "What spec does this code satisfy?" answerable in <30 seconds via three deterministic queries (grep + jq + read).
- Zero reported cases of LLM-invents-intent on opted-in projects with `spec_required: true`.
- Hook override rate <5% on opted-in projects (mechanical enforcement is well-calibrated).
- Retrospective Spec Lineage data shows >70% of spec drafts approved on first pass (drafter prompt is well-calibrated).
- v3.6.0 projects opted out: zero behavior change reports.

If success criteria are not met after six months, re-open this plan and revise. Specifically: if intent-fidelity failures are still happening on opted-in projects, the read-before-write protocol is insufficient and a more aggressive intervention is needed (e.g., surfacing spec content directly in spawn prompt body, not just as a path).

---

## Appendix A: File-by-file change manifest summary

| File | v3.7.0 | v3.8.0 | v3.9.0 |
|---|---|---|---|
| `claude/skills/harness-init/SKILL.md` | Schema + opt-in prompt + inlined `openspec.sh` shim template + Step 3.1 (create shim) | Extend shim template with `archive` verb; install post-merge hook + migration script | Extend shim template with `validate` and `verify` verbs; install enforce-spec-read hook + bypass utility |
| `claude/skills/harness-continue/SKILL.md` | Phase 0 (shim sync-config) + spec_path surfacing | Drafting blocker + drift detection + pending-archives replay + Spec Lineage retrospective | Hook references; bypass-rate metric in retrospective |
| `claude/rules/agent-teams-protocol.md` | Spawn prompt addition | Drafter role (Opus default) | `teammate-feature.txt` marker docs |
| `claude/CLAUDE.md` | New `## Spec Discipline` section | Expand drafting protocol + post-merge hook docs | (no change) |
| `.harness/openspec.sh` (per-project) | NEW — verbs: sync-config | + verb: archive | + verbs: validate, verify |
| `.harness/post-merge.sh` (per-project) | — | NEW — git post-merge hook | — |
| `.harness/bypass-spec-check` (per-project) | — | — | NEW — TTL'd override CLI |
| `claude/scripts/post-merge.sh` (template) | — | NEW | — |
| `claude/scripts/bypass-spec-check.sh` (template) | — | — | NEW |
| `claude/skills/harness-init/templates/migrate-to-openspec.sh` | — | NEW — optional migration for v3.6.0 projects | — |
| `claude/hooks/enforce-spec-read.sh` | — | — | NEW |
| `claude/hooks/verify-task-quality.sh` | — | — | Extend (delegate to shim) |
| `claude/hooks/pre-archive-check.sh` | — | — | NEW (delegates to shim) |
| `README.md` | Changelog | Changelog | Changelog |
| `INSTALL.md` | Optional dep note | — | Hook docs |
| `install` script | — | — | Deploy new hooks |

## Appendix B: Sequencing & dependencies

```
v3.7.0 — independent. Ships first.
  ↓
v3.8.0 — depends on v3.7.0 schema + spawn prompts.
  ↓
v3.9.0 — depends on v3.8.0 drift detection + archive flow.
```

Each phase is independently shippable in the sense that v3.7.0 alone is useful (spec linkage + prose discipline). But sequencing is strict: don't ship v3.8.0 before v3.7.0 has been validated on at least one real project, and don't ship v3.9.0 (mechanical hooks) before v3.8.0's manual archive flow has been observed working.

## Appendix C: `spec_path` value conventions

`spec_path` holds a path string the harness reads from features.json and passes to agents. The path structure follows OpenSpec's own directory layout — the harness does not define it.

Currently observed shapes (per OpenSpec's current conventions):

- During drafting/implementation: typically `"<openspec-changes-dir>/<change-name>/"` — points at the change folder.
- After archive: typically `"<openspec-specs-dir>/<capability>.md"` — points at the archived capability spec.
- Trivial work / opted out: `null` with `spec_required: false`.

The exact directory names and structure come from OpenSpec; if OpenSpec changes them, the harness keeps working as long as the shim and `harness.json` openspec block reflect the new layout. Drift detection only checks file existence at the recorded path — it does not validate the path's shape.

Schema enforcement (the only thing the harness asserts): `spec_path` is either `null` or a string pointing at an existing file or folder under the `openspec_dir` declared in `harness.json`. Anything else is a schema violation.
