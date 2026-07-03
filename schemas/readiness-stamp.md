# vv-harness data contracts: readiness stamp, park, and debug resolution

Version-bearing contracts between the vv-harness spec gate (the mint) and any external
consumer, primarily an autonomous issue-to-PR runner. The runner validates these formats;
it imports no code from this repository. Producers: the `issue-prep` and `issue-debug`
skills. This document is the single source of truth for field meanings and the canonical
hash and HMAC recipes.

## Canonical hashing (both sides MUST use exactly this)

sha256 over UTF-8 bytes, no trimming, no normalization. Any edit, including whitespace,
invalidates a hash; that is intentional (edits must re-enter the gate).

- Linear spec hash: `sha256(title + "\n" + description)` with title and description
  exactly as the Linear API returns them at hashing time. Producers MUST hash re-fetched
  content after any write-back, never a local draft.
- Local feature hash: `sha256(description)` over the feature's `description` string
  exactly as stored in `features.json`.

Reference implementation:

    python3 -c 'import sys, hashlib; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'

## Readiness stamp v1

A Linear comment. Line 1 is the literal marker `vv-harness-readiness-stamp v1`, followed
by one fenced json block:

```json
{
  "stamp_version": "1",
  "issue": "ENG-123",
  "spec_hash": "<sha256 hex, Linear domain>",
  "base_sha": "<git ls-remote <repo_url> HEAD at stamp time, or the string unknown>",
  "verdict": "PASS",
  "sv_version": "1.0",
  "lane": "code",
  "repo": "org/name",
  "risk": "standard",
  "stamper": "ovidiu",
  "ts": "2026-07-03T10:00:00Z",
  "hmac": "<HMAC-SHA256 hex, recipe below>"
}
```

Field notes: `lane` is `code` or `non-code` (kills the runner's riskiest classification
inference). `risk` is `standard` or `elevated`; elevated maps, on the consumer side, to a
stricter path (in vv-harness terms: `require_plan_approval: true` plus an Opus
implementer). `sv_version` is the version of the SV-01..SV-06 check set that verified the
spec; consumers set a minimum floor. `verdict` is always `PASS`; an issue that did not
pass gets no stamp.

## HMAC recipe

- Key: macOS Keychain generic password, service `vv-harness-stamp`. One-time setup by the
  human, never automated:
  `security add-generic-password -a "$USER" -s vv-harness-stamp -w "$(openssl rand -hex 32)"`
- Message: `spec_hash|base_sha|lane|repo` (pipe-joined, exactly that order, UTF-8).
- Algorithm: HMAC-SHA256, lowercase hex digest.
- The key is shared between the mint and the consumer on the same machine. Anyone with
  Linear access but without the key cannot forge readiness; anyone who edits the issue
  description after stamping breaks `spec_hash` and the stamp dies with it.

## Consumer verification rules (what a runner MUST check before acting)

1. Marker line and parseable json; `stamp_version` is `"1"`.
2. `hmac` recomputes correctly from the key and the message fields.
3. `spec_hash` recomputes correctly from the CURRENT issue title and description (a
   mismatch means a post-stamp edit: bounce, do not build).
4. `sv_version` is at or above the consumer's floor.
5. `repo` is in the consumer's allow-list; `base_sha` drift against the current default
   branch is within the consumer's threshold (skip with a note when `unknown`).
6. Labels are queue hints only; the stamp is the authority.

## Park bundle v1 (runner -> humans)

Posted by the runner when it parks an issue after exhausting self-heal attempts. Line 1:
`vv-harness-park v1`, then one fenced json block:

```json
{
  "park_version": "1",
  "issue": "ENG-123",
  "branch": "claude/eng-123-slug",
  "heal_attempts": 3,
  "confirmed_findings": [
    {"gate": "SE", "rule": "SE-03", "evidence": "path/file.py:41-44 'quoted span'"}
  ],
  "transcript_hint": "~/agent/logs/eng-123-<ts>/",
  "ts": "2026-07-03T10:00:00Z"
}
```

Consumed by the `issue-debug` skill, which opens the branch and works the findings live.

## Debug resolution v1 (issue-debug -> runner)

Posted by `issue-debug` when a repair session concludes. Line 1:
`vv-harness-debug-resolution v1`, then one fenced json block:

```json
{
  "resolution_version": "1",
  "issue": "ENG-123",
  "disposition": "resume",
  "branch": "claude/eng-123-slug",
  "notes": "one-line summary of the fix",
  "ts": "2026-07-03T10:05:00Z",
  "hmac": "<HMAC-SHA256 over spec_hash|branch|disposition; required when disposition is resume, since a resume authorizes the runner to act; omitted otherwise>"
}
```

Dispositions: `resume` (branch pushed, findings addressed; runner re-verifies and
re-arms), `reprep` (the spec was the problem; a fresh stamp will follow via issue-prep),
`abandon` (runner closes out; humans decide the issue's fate).

## Versioning policy

`stamp_version`, `park_version`, and `resolution_version` bump on any breaking field
change. `sv_version` bumps when the meaning of the SV check set changes. Consumers reject
majors they do not know. This file is the changelog for all four.
