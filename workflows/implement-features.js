export const meta = {
  name: 'implement-features',
  description: 'Implement a batch of verified features in parallel worktree agents, then review each; return per-feature results for the lead to integrate. Never merges, commits, or edits features.json.',
  phases: [
    { title: 'Implement', detail: 'one Sonnet implementer per feature, isolated worktree, strict TDD' },
    { title: 'Review', detail: 'one reviewer per feature over the branch diff, spec-derived, author-blind to the implementer rationale' },
  ],
}

// args arrives as a JSON-ENCODED STRING on the current CLI, not a parsed object
// (Phase 0 / OVI-141 Q7). Parse defensively; a bare object is tolerated too so the
// script stays correct if a future CLI marshals args as an object. Exported-by-name
// via a sentinel so test/run-tests.sh can execute this pure helper (see the
// node-guarded workflow-helper tests).
function parseArgs(raw) {
  if (raw && typeof raw === 'object') return raw
  if (typeof raw !== 'string' || raw.length === 0) return null
  try {
    return JSON.parse(raw)
  } catch (e) {
    return null
  }
}

// Classify one pipeline result into the lead-facing outcome. Pure and total: every
// input shape maps to exactly one of died | blocked | unreviewed | needs-lead |
// approved. `result` is the pipeline entry (null if BOTH stages threw); `impl`/`review`
// are its stages (either may be null if that stage's agent died — agent() resolves to
// null on skip/terminal error, e.g. a rate limit).
function classifyOutcome(result) {
  if (!result || !result.implement) return { outcome: 'died', reviewed: false }
  if (result.implement.status === 'blocked') return { outcome: 'blocked', reviewed: true }
  if (!result.review) return { outcome: 'unreviewed', reviewed: false } // reviewer died
  return { outcome: result.review.verdict === 'APPROVE' ? 'approved' : 'needs-lead', reviewed: true }
}

const IMPLEMENT_SCHEMA = {
  type: 'object',
  required: ['feature_id', 'status', 'files_changed', 'worktree_branch'],
  properties: {
    feature_id: { type: 'string' },
    status: { type: 'string', enum: ['implemented', 'blocked'] },
    files_changed: { type: 'array', items: { type: 'string' } },
    test_file: { type: 'string' },
    tests_run: {
      type: 'object',
      properties: { passed: { type: 'integer' }, failed: { type: 'integer' } },
    },
    worktree_branch: { type: 'string' },
    head_sha: { type: 'string' },
    notes: { type: 'string' },
    blocker: { type: 'string', description: 'why it is blocked, when status is blocked' },
  },
}

const REVIEW_SCHEMA = {
  type: 'object',
  required: ['feature_id', 'verdict', 'findings', 'rounds_used'],
  properties: {
    feature_id: { type: 'string' },
    verdict: { type: 'string', enum: ['APPROVE', 'REVISE', 'REJECT'] },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['summary'],
        properties: {
          summary: { type: 'string' },
          file: { type: 'string' },
          line: { type: 'integer' },
          severity: { type: 'string', enum: ['critical', 'major', 'minor'] },
        },
      },
    },
    rounds_used: { type: 'integer' },
  },
}

// The implementer receives the feature's own verified spec. It never sees the other
// features, and its committed worktree branch is the durable deliverable (so a dead
// run's work survives — OVI-140 run-continuity). Prompt text derives only from `spec`
// so a resume replays it byte-for-byte from cache.
function implementPrompt(spec) {
  return [
    'You are a feature implementer in an ISOLATED GIT WORKTREE of a harness-managed repo.',
    'Confirm your location with `git rev-parse --show-toplevel` and record your branch with `git branch --show-current`.',
    '',
    '## Feature ' + spec.id,
    'Scope (stay within these paths plus the test file): ' + (spec.scope || []).join(', '),
    '',
    'Verified specification:',
    spec.spec,
    '',
    '## Process (strict TDD)',
    '1. Read the existing code and the project test conventions.',
    '2. Write the failing test(s) that define done; run them to confirm they fail (RED).',
    '3. Implement the minimum to pass; confirm GREEN. Commit at RED and again at GREEN as TDD checkpoints (a `git add <files>` call, then a SEPARATE `git commit` call — repo hooks reject compound stage-and-commit) so your branch survives even if this agent is interrupted.',
    '4. Run the full project test suite; it must end fully green.',
    '',
    '## Deliverable',
    'Your committed worktree branch IS the deliverable — do not leave work uncommitted. Do NOT merge, do NOT edit features.json, do NOT touch any branch but your own. Report the structured result: status implemented (green) or blocked (with a blocker reason), files changed, test file, pass/fail counts, your branch name, and HEAD sha.',
  ].join('\n')
}

// The reviewer reads the feature's spec and the branch's own diff against the supplied
// merge base — that is its job. It is NOT given the implementer's completion notes or
// approach rationale: the author-blindness that matters here is to the implementer's
// REASONING, so the review can't be talked into agreeing. (Full spec-only author-
// blindness to the code itself is the conformance-tester's job, not the reviewer's.)
function reviewPrompt(spec, branch) {
  return [
    'You are a senior code reviewer. Review the work on git branch `' + branch + '` for feature ' + spec.id + '.',
    'Inspect it with read-only git only: `git diff ' + spec.mergeBase + '...' + branch + '`, `git show`, and file reads. You may run the test suite. Do NOT edit files. Do NOT read or ask for the implementer\'s own notes, approach, or completion message — judge the code and tests against the spec alone.',
    '',
    '## The verified specification (your only source of truth for intent)',
    spec.spec,
    '',
    '## Judge',
    'Correctness against the spec, scope adherence, test quality (do the tests actually pin the behavior, or would they pass against broken code?), and the coverage bar. Return verdict APPROVE (ship it), REVISE (fixable findings), or REJECT (wrong approach), with concrete findings (file, line, severity). Set rounds_used to 1 — the lead owns any fix-and-recheck loop, you do a single pass.',
  ].join('\n')
}

// The pure helpers above (parseArgs, classifyOutcome) are defined before this marker
// and depend on no workflow globals — test/run-tests.sh slices everything above the
// marker into a temp module and executes them directly (node-guarded), so the
// classification and arg-parsing logic has real coverage, not just source greps.
// ---- run --------------------------------------------------------------------
const parsed = parseArgs(args)

// Preflight (no agent): fail fast and clearly on bad input.
if (!parsed || typeof parsed !== 'object') {
  throw new Error('implement-features: args did not parse to an object. Pass {features:[...], featureSpecs:{id:{spec,scope,risk}}} (JSON).')
}
const featureIds = parsed.features
if (!Array.isArray(featureIds) || featureIds.length === 0) {
  throw new Error('implement-features: args.features must be a non-empty array of feature IDs.')
}
const featureSpecs = parsed.featureSpecs || {}

// Build one spec object per feature. The lead passes the verified spec text in via
// args (the script has no sanctioned way to read project state from inside a workflow,
// and dynamic module loading is forbidden) — a feature with no supplied spec is a hard
// error, never silently implemented from its ID alone.
const specs = featureIds.map((id) => {
  const fs = featureSpecs[id] || {}
  if (!fs.spec) {
    throw new Error('implement-features: no verified spec supplied for ' + id + ' in args.featureSpecs.')
  }
  return {
    id: id,
    spec: fs.spec,
    scope: fs.scope || [],
    risk: fs.risk === 'elevated' ? 'elevated' : 'standard',
    mergeBase: fs.mergeBase || parsed.mergeBase || 'HEAD',
  }
})

phase('Implement')

// pipeline: each feature flows Implement -> Review independently (no barrier), so a
// fast feature is reviewed while a slow one still implements. A thrown stage drops that
// item to null; survivors are never discarded (OVI-140 partial-result contract).
const results = await pipeline(
  specs,
  (spec) => agent(implementPrompt(spec), {
    label: 'impl:' + spec.id,
    phase: 'Implement',
    schema: IMPLEMENT_SCHEMA,
    isolation: 'worktree',
    agentType: 'vv-harness:feature-implementer',
    model: 'sonnet',
  }),
  (impl, spec) => {
    // A blocked implementer short-circuits its own review — nothing to review.
    if (!impl || impl.status === 'blocked') {
      return { feature_id: spec.id, implement: impl, review: null }
    }
    // Reviewer runs on its agentType's own model (reviewer = Opus per its definition);
    // an explicit reviewModel override downgrades it (e.g. 'sonnet' for a cheap pass).
    // An elevated-risk feature gets a higher-effort review pass.
    const reviewOpts = {
      label: 'review:' + spec.id,
      phase: 'Review',
      schema: REVIEW_SCHEMA,
      agentType: 'vv-harness:reviewer',
    }
    if (parsed.reviewModel) reviewOpts.model = parsed.reviewModel
    if (spec.risk === 'elevated') reviewOpts.effort = 'high'
    return agent(reviewPrompt(spec, impl.worktree_branch), reviewOpts)
      .then((review) => ({ feature_id: spec.id, implement: impl, review: review }))
  }
)

// Classify. Every feature that did not reach an approved+reviewed state and is not a
// clean `blocked` (which the lead surfaces intentionally) goes on `unfinished`, so the
// lead's resume/reconcile path fires — a dead implementer OR a dead reviewer both count.
const perFeature = []
const unfinished = []
for (let i = 0; i < specs.length; i++) {
  const id = specs[i].id
  const r = results[i]
  const c = classifyOutcome(r)
  perFeature.push({
    feature_id: id,
    implement: r ? r.implement : null,
    review: r ? r.review : null,
    outcome: c.outcome,
  })
  if (c.outcome === 'died' || c.outcome === 'unreviewed') unfinished.push(id)
}

log('implement-features: '
  + perFeature.filter((f) => f.outcome === 'approved').length + ' approved, '
  + perFeature.filter((f) => f.outcome === 'blocked').length + ' blocked, '
  + perFeature.filter((f) => f.outcome === 'needs-lead').length + ' needs-lead, '
  + unfinished.length + ' unfinished — ' + (unfinished.length ? unfinished.join(',') : 'none'))

// The lead integrates: for each approved feature, run its focused test + smoke, merge
// its worktree_branch, flip features.json, mark the mirrored task complete, commit.
// blocked / non-APPROVE / unfinished features are surfaced, never auto-merged. A
// non-empty `unfinished` means the lead should resume this run (resumeFromRunId) or
// reconcile from the committed branches after the rate window resets.
return {
  per_feature: perFeature,
  unfinished: unfinished,
  complete: unfinished.length === 0,
}
