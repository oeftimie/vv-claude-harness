export const meta = {
  name: 'review-branch',
  description: 'Re-review an existing branch or diff scope: fan reviewers over it, dedup findings before an adversarial-verify pass, return ranked verdicts. Read-only; never edits, merges, or commits.',
  phases: [
    { title: 'Review', detail: 'reviewers (and optional conformance testers) over the diff scope' },
    { title: 'Verify', detail: 'adversarial skeptic per deduped finding' },
  ],
}

function parseArgs(raw) {
  if (raw && typeof raw === 'object') return raw
  if (typeof raw !== 'string' || raw.length === 0) return null
  try {
    return JSON.parse(raw)
  } catch (e) {
    return null
  }
}

// Severity rank: lower = more severe, sorted first. Uses ?? (not ||) so `critical`'s
// legitimate 0 is not treated as "missing" and pushed to the bottom.
const SEVERITY_RANK = { critical: 0, major: 1, minor: 2 }
function severityScore(sev) {
  const r = SEVERITY_RANK[sev]
  return r === undefined ? 3 : r
}

// dedup key: same file + same line + same claim collapses to one finding. Severity is
// deliberately NOT part of the key — duplicates are MERGED keeping the highest severity
// and the union of reporting dimensions, so a critical reported by a later dimension is
// never demoted to a minor reported first (OVI-140 review-loop lesson).
function dedupeKey(f) {
  return (f.file || '') + '|' + (f.line == null ? '' : f.line) + '|' + (f.claim || f.summary || '').slice(0, 80).toLowerCase()
}

function mergeFindings(findings) {
  const byKey = new Map()
  for (const f of findings) {
    const k = dedupeKey(f)
    const prev = byKey.get(k)
    if (!prev) {
      byKey.set(k, Object.assign({}, f, { dimensions: f.dimension ? [f.dimension] : [] }))
      continue
    }
    if (severityScore(f.severity) < severityScore(prev.severity)) {
      prev.severity = f.severity
      prev.summary = f.summary || prev.summary
    }
    if (f.dimension && prev.dimensions.indexOf(f.dimension) === -1) prev.dimensions.push(f.dimension)
  }
  return Array.from(byKey.values())
}

const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['summary', 'file'],
        properties: {
          summary: { type: 'string' },
          file: { type: 'string' },
          line: { type: 'integer' },
          severity: { type: 'string', enum: ['critical', 'major', 'minor'] },
          claim: { type: 'string', description: 'the one-line defect claim, used for dedup' },
        },
      },
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  required: ['is_real', 'reasoning'],
  properties: {
    is_real: { type: 'boolean' },
    reasoning: { type: 'string' },
  },
}

const CONFORMANCE_SCHEMA = {
  type: 'object',
  required: ['feature_id', 'criteria'],
  properties: {
    feature_id: { type: 'string' },
    criteria: {
      type: 'array',
      items: {
        type: 'object',
        required: ['criterion', 'result'],
        properties: {
          criterion: { type: 'string' },
          result: { type: 'string', enum: ['PASS', 'FAIL', 'NOT-TESTABLE'] },
          note: { type: 'string' },
        },
      },
    },
  },
}

function reviewPrompt(dimension, scope) {
  return [
    'You are a senior code reviewer. Review the changes described by this scope: ' + scope + '.',
    'Use read-only git (`git diff`, `git show`, `git log`) and file reads only; you may run the test suite. Do NOT edit anything.',
    'Your review dimension: ' + dimension.prompt,
    'Report only defects you can tie to a concrete failure scenario. For each finding set a one-line `claim` — the defect stated in a single sentence — used to deduplicate against other reviewers.',
  ].join('\n')
}

// The pure helpers above (parseArgs, severityScore, dedupeKey, mergeFindings) are
// defined before this marker and depend on no workflow globals — test/run-tests.sh
// slices everything above the marker into a temp module and executes them directly
// (node-guarded), so the severity ordering and dedup/merge logic has real coverage.
// ---- run --------------------------------------------------------------------
const parsed = parseArgs(args)
if (!parsed || typeof parsed !== 'object') {
  throw new Error('review-branch: args did not parse to an object. Pass {scope, dimensions?, features?, conformance?, featureSpecs?} (JSON).')
}
const scope = parsed.scope || parsed.branch || parsed.diffScope
if (!scope) {
  throw new Error('review-branch: args must name a `scope` (or `branch`/`diffScope`) to review.')
}
const DIMENSIONS = Array.isArray(parsed.dimensions) && parsed.dimensions.length
  ? parsed.dimensions
  : [
    { key: 'correctness', prompt: 'correctness and security — logic errors, unhandled inputs, silent failures.' },
    { key: 'tests', prompt: 'test quality and specification-gaming — assertions that would pass against broken code, hardcoded outputs, suppressed errors.' },
  ]
// Validate custom dimensions rather than degrade to "dimension: undefined" prompts.
DIMENSIONS.forEach((d, i) => {
  if (!d || typeof d !== 'object' || typeof d.prompt !== 'string' || !d.prompt || !d.key) {
    throw new Error('review-branch: dimensions[' + i + '] must be an object with a non-empty `prompt` and a `key`.')
  }
})
// Conformance requires per-feature specs; fail fast rather than silently skipping the
// requested author-blind pass (a false clean result on a safety check otherwise).
if (parsed.conformance) {
  if (!Array.isArray(parsed.features) || !parsed.features.length) {
    throw new Error('review-branch: conformance requires a non-empty `features` array.')
  }
  if (!parsed.featureSpecs) {
    throw new Error('review-branch: conformance requires `featureSpecs` mapping each feature ID to its verified spec.')
  }
}

phase('Review')
// Barrier here is intentional: dedup needs ALL reviewers' findings together before the
// verify fan-out, so the fan-out runs over unique findings only.
const reviewResults = await parallel(DIMENSIONS.map((d) => () =>
  agent(reviewPrompt(d, scope), { label: 'review:' + d.key, phase: 'Review', schema: FINDINGS_SCHEMA, agentType: 'vv-harness:reviewer' })
    .then((r) => ({ key: d.key, findings: (r && r.findings) || [] }))
))
const deadReviewers = reviewResults.filter((r) => !r).length

// Optional author-blind conformance pass, spec-only, per feature (F017 pattern). Runs
// in isolated worktrees so these WRITE-capable agents never touch the lead's checkout.
let conformance = []
if (parsed.conformance) {
  const confResults = await parallel(parsed.features.map((id) => () => {
    const fs = parsed.featureSpecs[id] || {}
    if (!fs.spec) {
      // Surface the gap explicitly — never silently drop a requested feature.
      return Promise.resolve({ feature_id: id, criteria: [], skipped: 'no spec supplied in featureSpecs' })
    }
    return agent(
      'You write author-blind conformance tests. From this verified spec ALONE — never read the implementation diff, any existing test file for this feature, or any completion message — derive tests for feature ' + id + ' and report PASS/FAIL/NOT-TESTABLE per acceptance criterion.\n\nSpec:\n' + fs.spec,
      { label: 'conformance:' + id, phase: 'Review', schema: CONFORMANCE_SCHEMA, agentType: 'vv-harness:conformance-tester', model: 'sonnet', isolation: 'worktree' }
    )
  }))
  conformance = confResults.filter(Boolean)
}

const allFindings = reviewResults.filter(Boolean).flatMap((r) =>
  (r.findings || []).map((f) => Object.assign({}, f, { dimension: r.key }))
)
const unique = mergeFindings(allFindings)
log('review-branch: ' + allFindings.length + ' raw findings, ' + unique.length + ' unique after dedup'
  + (deadReviewers ? (', ' + deadReviewers + ' reviewer(s) died') : ''))

phase('Verify')
// Verify agents are read-only (vv-harness:reviewer) so the "Read-only" contract holds.
const verified = await parallel(unique.map((f) => () =>
  agent(
    'A reviewer reported this finding on ' + scope + ':\n\n' + (f.summary || f.claim) + '\nFile: ' + (f.file || '?') + (f.line ? (' line ' + f.line) : '') + '\n\nTry to REFUTE it against the actual code (read-only git + file reads; you may run tests). If you cannot demonstrate it concretely, is_real=false. Default to false when uncertain.',
    { label: 'verify:' + (f.file || 'finding'), phase: 'Verify', schema: VERDICT_SCHEMA, agentType: 'vv-harness:reviewer' }
  ).then((v) => ({ finding: f, verdict: v }))
))

// Partition honestly: a null verify result (agent died — e.g. rate limit) is UNVERIFIED,
// not refuted. Never report a branch clean because its verifiers were killed.
const confirmed = []
const refuted = []
const unverified = []
for (let i = 0; i < unique.length; i++) {
  const v = verified[i]
  if (!v || !v.verdict) { unverified.push(unique[i]); continue }
  if (v.verdict.is_real) confirmed.push(Object.assign({}, v.finding, { reasoning: v.verdict.reasoning }))
  else refuted.push(unique[i])
}
confirmed.sort((a, b) => severityScore(a.severity) - severityScore(b.severity))

return {
  scope: scope,
  confirmed: confirmed,
  refuted_count: refuted.length,
  unverified: unverified,
  conformance: conformance,
  dropped: { reviewers: deadReviewers, verifiers: unverified.length },
  complete: deadReviewers === 0 && unverified.length === 0,
}
