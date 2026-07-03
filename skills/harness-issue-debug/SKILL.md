---
name: harness-issue-debug
description: Open a failed or parked piece of work in a live repair session. Input is a features.json feature id (harness project) or a Linear issue key parked by the external runner. Loads the failure context, checks out the branch, iterates the fix with the human, and exits by resuming the runner, routing back through harness-issue-prep, or marking the work failed. Use when a feature is status failed or a runner-parked issue needs hands-on debugging.
---

# Issue Debug

Opens a live, interactive repair session on a piece of work that stopped: a harness
feature marked `failed`, or a Linear issue the external runner parked after exhausting
its self-heal attempts. This skill is the hands-on counterpart to `harness-issue-prep`: where
`harness-issue-prep` fixes a spec before implementation starts, `harness-issue-debug` fixes an
implementation (or the spec behind it) after something already went wrong.

Mode is selected by the shape of the argument:

- `F0NN` (matches a feature id in `.harness/features.json`): **local mode**.
- An issue key matching `^[A-Z]+-[0-9]+$` (for example `ENG-123`): **runner mode**.

If the argument matches neither shape, ask which mode the user means before proceeding.

## Local Mode (`F0NN`)

**Step 1: Load context.** Read the feature from `.harness/features.json` and surface, in
one block, everything a debugging session needs before touching code:

```
Feature F0NN: [description]
Status: failed
Failure reason: [failure_reason]
Notes: [notes]
Correction cycles: [correction_cycles]
Scope: [scope]
```

**Step 2: Check out the branch.** If `notes` names a branch, check it out. If it does not,
ask the user which branch to use before continuing; do not guess.

**Step 3: Establish the baseline.** Run `./.harness/init.sh` to confirm the checked-out
branch builds and to see the current failure state directly, not secondhand through
`failure_reason`.

**Step 4: Iterate the fix.** This is a normal interactive session: write a failing test,
implement, confirm green, refactor, repeat. No special ceremony beyond the harness's
usual TDD discipline applies here; the only thing that distinguishes this session from any
other feature work is that it starts from a known failure instead of a blank feature.

**Step 5: Exit route.** Exactly one of three, decided with the human present:

- **Fixed and the human is satisfied.** Set `status` to `"pending"`, not `"passing"`; the
  quality gate (`verify-task-quality.sh` on `TaskCompleted`) is what earns `"passing"`,
  and this skill does not shortcut it. Clear `failure_reason`.
- **The spec was the real problem, not the code.** Run `harness-issue-prep F0NN` to fix the
  description before any further implementation attempt.
- **Abandoned this session.** Keep `status: "failed"`. Update `failure_reason` with what
  was learned this round, even if the answer is still "unresolved": a stale
  `failure_reason` from a prior attempt is worse than an updated one that says what was
  ruled out.

## Runner Mode (`ISSUE-KEY`)

**Step 1: Fetch the issue.** Discover the connected Linear MCP's tools at runtime; never
hardcode tool names (the harness's spec-gate tooling makes this same choice for the same
reason: MCP surfaces change across integrations and versions). Fetch the issue's
description and comments.

**Step 2: Find the park bundle.** Locate the newest comment whose first line is the
literal marker `vv-harness-park v1`. Parse its fenced json block per the
`${CLAUDE_PLUGIN_ROOT}/schemas/readiness-stamp.md` contract: `branch`, `confirmed_findings`, `heal_attempts`,
`transcript_hint`.

If no such comment exists, or it exists but the json does not parse: say so plainly, offer
to fall back to local-style manual debugging against the issue (ask for the branch, then
proceed as in Local Mode Steps 2 through 4), and post no resolution comment. A missing or
broken park bundle is not itself an error to fix silently; it means the runner never
successfully parked this issue, and the human should know that before debugging blind.

**Step 3: Get the repo locally.** If the repo is not already cloned on this machine, ask
the user for its local path, or offer to clone it. Then check out `branch` from the park
bundle.

**Step 4: Present the worklist.** Show `confirmed_findings` as the starting worklist for
the session (each finding names a gate, a rule id, and evidence). Use `transcript_hint` if
the human wants to see the runner's prior attempts before continuing. `heal_attempts`
tells you how many self-heal rounds the runner already burned; treat a high count as a
signal that the earlier findings may need more than a local patch.

**Step 5: Iterate the fix.** Same as Local Mode Step 4: normal TDD, interactive, no extra
ceremony.

**Step 6: Post the resolution.** When the session concludes, post a comment on the issue
per the `vv-harness-debug-resolution v1` contract in `${CLAUDE_PLUGIN_ROOT}/schemas/readiness-stamp.md`: line 1
is the literal marker `vv-harness-debug-resolution v1`, followed by one fenced json block.
Disposition is exactly one of:

- **`resume`**: the branch is pushed and the confirmed findings are addressed. This is the
  only disposition that authorizes the runner to act again, so it is the only one that
  carries an `hmac`. Compute it with the same recipe and Keychain service
  (`vv-harness-stamp`) as the readiness stamp:

  ```bash
  python3 - "$SPEC_HASH" "$BRANCH" "resume" <<'PYEOF'
  import hmac, hashlib, subprocess, sys
  key = subprocess.check_output(
      ["security", "find-generic-password", "-s", "vv-harness-stamp", "-w"]
  ).strip()
  msg = "|".join(sys.argv[1:4]).encode("utf-8")
  print(hmac.new(key, msg, hashlib.sha256).hexdigest())
  PYEOF
  ```

  `spec_hash` here is the value from the issue's current `vv-harness-readiness-stamp v1`
  comment, the same hash the original stamp authorized; do not compute a new one. If the
  Keychain key is unreadable, do not post a `resume` disposition; report the failure and
  offer `reprep` or `abandon` instead.
- **`reprep`**: the spec, not the code, turned out to be the problem. Post the comment
  with no `hmac`, then run `harness-issue-prep ISSUE-KEY` to fix the spec and re-stamp it.
- **`abandon`**: the runner should stop trying and a human decides the issue's fate. Post
  the comment with no `hmac`.

Runner-side consumption of this comment (deciding to act on a `resume`, reconciling its
own state) is out of scope for this skill; the contract in `${CLAUDE_PLUGIN_ROOT}/schemas/readiness-stamp.md` is
the deliverable, not a running consumer.

## Degradation

| Situation | End state |
|---|---|
| Argument matches neither `F0NN` nor an issue key | Ask the user which mode is intended before doing anything |
| Local mode, `notes` has no branch | Ask for the branch; do not guess or invent one |
| Runner mode, no park comment found | Say so, offer local-style manual debugging, post no resolution comment |
| Runner mode, park comment json does not parse | Same as above: report it, fall back, post nothing |
| Runner mode, repo not cloned and user has no path | Ask again or stop; do not clone speculatively |
| Runner mode, `resume` disposition but Keychain key unreadable | Do not post `resume`; report the failure and offer `reprep` or `abandon` |
