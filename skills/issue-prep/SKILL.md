---
name: issue-prep
description: Interactively verify a spec until it is buildable, then mark it ready for implementation. Sources: a Linear issue (via the Linear MCP), a pasted spec, or an existing features.json feature. On PASS it normalizes the spec, records verification (spec field locally; a signed readiness stamp plus label on Linear), and can kick the external runner. Use when an issue or feature needs to be made ready for unattended or team implementation.
---

# Issue Prep

Follow these steps in order. This skill is the mint: it turns a spec (Linear issue,
pasted text, or a features.json feature) into a verified, normalized spec, plus proof of
that verification for whichever consumer needs it (local `spec` field, or a signed
readiness stamp on Linear).

## Step 1: Load configuration

Read the optional `prep` key from `.harness/harness.json`:

```bash
python3 - <<'PYEOF'
import json

try:
    with open(".harness/harness.json") as f:
        config = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    config = {}

print(json.dumps(config.get("prep", {})))
PYEOF
```

No `prep` key at all: announce local-only mode up front (features.json output only; no
stamp, no label, no kickstart) and proceed. A partial block (some sub-keys missing) is
not an error: announce specifically which capabilities are off. `prep.linear` absent
disables labeling; `prep.stamp` absent disables stamping (Step 7 becomes a no-op);
`prep.runner` absent or `enabled: false` disables Step 8.

## Step 2: Acquire the spec

Three sources, selected by the argument passed to this skill:

- **`ISSUE-KEY`** (matches `^[A-Z]+-[0-9]+$`): remote mode. Discover the connected Linear
  MCP's tools at runtime (never hardcode tool names; D12 in the implementation plan).
  Required capabilities checklist, all four must resolve:
  - fetch an issue by key, returning title, description, and labels
  - update an issue's description
  - create a comment on an issue
  - add and remove a label on an issue

  If any capability is missing, degrade to paste mode (below) with an explicit notice
  naming which capability was missing. If all four resolve, fetch the issue and hold
  `title` and `description` exactly as returned: no trimming, no whitespace
  normalization, ever. The stamp's `spec_hash` depends on the exact bytes (see
  `schemas/readiness-stamp.md`).
- **`F0NN`**: local mode. Load that feature from `.harness/features.json`; the spec under
  test is its `description` field. Its `scope` and `depends_on` travel along as context
  for the verification agent, not as part of the hashed spec.
- **No argument, or the Linear MCP is unavailable**: paste mode. Ask the user to paste
  the spec text, and ask whether the destination is local (a new or updated feature) or a
  Linear issue they will paste the normalized result back into by hand.

## Step 3: Verify

Spawn the spec-verification agent as a read-only subagent with the spec under test in the
prompt:

```
Agent({
  description: "Spec-verify issue for prep",
  subagent_type: "vv-harness:spec-verification",
  model: "opus",
  prompt: "[the spec under test in full: title and description (remote), or the
            feature's description plus scope and depends_on (local), or the pasted
            text. State the source and destination mode.]"
})
```

Parse the fixed SPEC-VERIFICATION REPORT block. The last `VERDICT :` line in the report is
authoritative; do not infer a verdict from prose elsewhere in the report.

## Step 4: The human loop

On `ASK` or `BLOCK`, present the numbered OPEN QUESTIONS or grounds to the user verbatim
(do not paraphrase, soften, or pre-answer them). The user answers; draft the amended spec
text incorporating their answers.

Every amended revision, with no exception, goes to the reverification-guard agent before
you treat it as resolved. Its verdict governs, not the fact that the human replied:

```
Agent({
  description: "Re-verify amended spec",
  subagent_type: "vv-harness:reverification-guard",
  model: "sonnet",
  prompt: "[the original SPEC-VERIFICATION REPORT and its OPEN QUESTIONS; the human's
            answers, verbatim; the full amended specification text.]"
})
```

RV's verdict (`PASS` / `ASK` / `BLOCK`) governs the loop. A reply is not a resolution: do
not soften RV's verdict on the user's behalf, and do not advance past `ASK` or `BLOCK`
because the human sounded confident.

Cap the loop at 5 revision cycles (one call to reverification-guard per cycle). On hitting
the cap:
- Summarize the STILL-OPEN questions from the final RV report.
- Remote mode: post them to the issue as a plain comment (no marker line, this is not a
  stamp).
- Local mode: write them into the feature's `notes` field.
- Apply the `needs_prep_label` if `prep.linear.needs_prep_label` is configured.
- Stop. The spec stays unnormalized and unstamped; nothing in Step 5 onward runs.

## Step 5: Normalize

On `PASS` (from SV directly, or from RV after the human loop), rewrite the spec into this
canonical template:

```markdown
## Problem
## Acceptance criteria   (numbered; each one testable as written)
## Edge and error cases
## Non-functional requirements
## Dependencies
## Assumptions ledger    (decisions made during prep, dated)
## Out of scope
```

Fill each section from the verified spec content and the human loop's answers; do not
invent requirements that were not established during verification. Populate the
Assumptions ledger with every decision made during prep, each dated.

Show the user a before/after diff of the full spec text. Require explicit confirmation
before any write-back happens (D14): no silent rewrite of someone's ticket or feature.
If the user declines at this point, stop; nothing is written, nothing is stamped.

## Step 6: Write back and record

- **Remote**: update the Linear issue's description via MCP with the normalized text.
  Then re-fetch the issue: compute `spec_hash = sha256(title + "\n" + description)` over
  the RE-FETCHED content, never the local draft (the API may normalize line endings or
  other bytes on write; hashing the draft would silently desync from what the runner
  later re-fetches).
- **Local**: write or update the feature's `description` with the normalized text. Set
  its `spec` object:
  ```
  spec = {
    "hash": sha256(description),
    "verdict": "PASS",
    "sv_version": "1.0",
    "verified_at": "<ISO8601 UTC>",
    "source": "linear:KEY" | "conversation"
  }
  ```
  `source` is `linear:KEY` when the local feature mirrors a Linear issue you prepped in
  paste mode, `conversation` otherwise.

## Step 7: Mint the stamp

Only in remote mode, and only when `prep.stamp` is configured. If either condition is
false, skip this step entirely (local mode has no stamp; there is no keying material
configured to sign one).

Ask the user two questions if they are not inferable from the spec or issue labels:
`lane` (`code` or `non-code`) and `risk` (`standard` or `elevated`; offer the
plan-approval trigger list from the Agent Teams protocol's Dynamic overrides table as the
elevation heuristic: 10+ files, cross-cutting refactors, security-sensitive code, first
feature in a new codebase).

Resolve `base_sha`:

```bash
git ls-remote <repo_url> HEAD | cut -f1
```

If this fails or returns nothing, use the literal string `unknown`; consumers treat drift
checks as skipped-with-note in that case (`schemas/readiness-stamp.md`).

Compute the HMAC:

```bash
python3 - "$SPEC_HASH" "$BASE_SHA" "$LANE" "$REPO" <<'PYEOF'
import hmac, hashlib, subprocess, sys
key = subprocess.check_output(
    ["security", "find-generic-password", "-s", "vv-harness-stamp", "-w"]
).strip()
msg = "|".join(sys.argv[1:5]).encode("utf-8")
print(hmac.new(key, msg, hashlib.sha256).hexdigest())
PYEOF
```

On Keychain failure (the `security` call errors, no key found): print the setup command
below, skip stamping entirely, and finish in a normalized-but-unstamped state:

```bash
security add-generic-password -a "$USER" -s vv-harness-stamp -w "$(openssl rand -hex 32)"
```

On success, assemble the stamp JSON (shape in `schemas/readiness-stamp.md`), with `ts` in
ISO8601 UTC:

```json
{
  "stamp_version": "1",
  "issue": "ENG-123",
  "spec_hash": "<from Step 6>",
  "base_sha": "<from above>",
  "verdict": "PASS",
  "sv_version": "1.0",
  "lane": "code",
  "repo": "org/name",
  "risk": "standard",
  "stamper": "<prep.stamp.stamper>",
  "ts": "<ISO8601 UTC>",
  "hmac": "<from above>"
}
```

Post it as a Linear comment: line 1 is the literal marker `vv-harness-readiness-stamp v1`,
followed by one fenced ```json block containing the stamp. Then apply `ready_label` and
remove `needs_prep_label` if it was previously applied (Step 4's cap path may have set
it).

## Step 8: Kickstart (optional)

If `prep.runner.enabled` is `true`, nudge the external runner's launchd job:

```bash
launchctl kickstart -k "gui/$(id -u)/<kickstart_label>"
```

using `prep.runner.kickstart_label`. Any failure here is a one-line note in the final
report, never fatal to the run: the runner's own poll cycle is the fallback path, and a
missed kickstart only delays pickup, it does not lose the stamp.

## Step 9: Report

Summarize the run in a block covering: source (issue key, feature id, or paste) and
destination mode; the verdict trail (SV, then each RV round in order); the count of
questions asked and answered; the final spec hash; whether a stamp was minted (yes/no,
and why not if applicable); whether a label was applied; the kickstart result if
attempted.

If run inside a harness project (a `.harness/` directory exists), append one line to
`claude-progress.txt` summarizing the prep outcome (source, verdict, stamped or not).

## Degradation table

| Condition | End state |
|---|---|
| No Linear MCP, or a required capability is missing | Paste mode: spec is verified and normalized in conversation; write-back is manual; no stamp, no label |
| No `prep` key in `harness.json` | Local-only mode: `features.json` gets the normalized description and `spec` object; no stamp, no label, no kickstart |
| Keychain lookup fails at Step 7 | Spec is normalized and written back; setup command is printed; run ends unstamped |
| RV loop cap (5 cycles) hit | Spec stays unnormalized; still-open questions posted as a plain comment (remote) or written to `notes` (local); `needs_prep_label` applied if configured; unstamped |
| User declines the Step 5 diff confirmation | Nothing is written back; no normalization, no stamp, no label; the run ends where the human stopped it |
