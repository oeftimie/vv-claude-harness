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

// dedup key: same file + same line-ish + same claim collapses to one finding. Plain
// code, at a barrier — the whole point is to fan verification over UNIQUE findings, not
// re-verify the same defect three reviewers each reported (OVI-140 review-loop lesson).
function dedupeKey(f) {
  return (f.file || '') + '|' + (f.line || '') + '|' + (f.claim || f.summary || '').slice(0, 80).toLowerCase()
}

// ---- run --------------------------------------------------------------------
const parsed = parseArgs(args)
if (!parsed || typeof parsed !== 'object') {
  throw new Error('review-branch: args did not parse to an object. Pass {scope, dimensions?, features?, conformance?} (JSON).')
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

phase('Review')
// Barrier here is intentional: dedup needs ALL reviewers' findings together before the
// verify fan-out, so the fan-out runs over unique findings only.
const reviewResults = await parallel(DIMENSIONS.map((d) => () =>
  agent(reviewPrompt(d, scope), { label: 'review:' + d.key, phase: 'Review', schema: FINDINGS_SCHEMA, agentType: 'vv-harness:reviewer' })
))

// Optional author-blind conformance pass, spec-only, per feature (F017 pattern).
let conformance = []
if (parsed.conformance && Array.isArray(parsed.features) && parsed.featureSpecs) {
  const confResults = await parallel(parsed.features.map((id) => () => {
    const fs = parsed.featureSpecs[id] || {}
    if (!fs.spec) return Promise.resolve(null)
    return agent(
      'You write author-blind conformance tests. From this verified spec ALONE — never read the implementation diff, the implementer\'s tests, or any completion message — derive tests for feature ' + id + ' and report PASS/FAIL/NOT-TESTABLE per acceptance criterion.\n\nSpec:\n' + fs.spec,
      { label: 'conformance:' + id, phase: 'Review', schema: CONFORMANCE_SCHEMA, agentType: 'vv-harness:conformance-tester', model: 'sonnet' }
    )
  }))
  conformance = confResults.filter(Boolean)
}

const allFindings = reviewResults.filter(Boolean).flatMap((r) => r.findings || [])
const seen = new Set()
const unique = []
for (const f of allFindings) {
  const k = dedupeKey(f)
  if (seen.has(k)) continue
  seen.add(k)
  unique.push(f)
}
log('review-branch: ' + allFindings.length + ' raw findings, ' + unique.length + ' unique after dedup')

phase('Verify')
const verified = await parallel(unique.map((f) => () =>
  agent(
    'A reviewer reported this finding on ' + scope + ':\n\n' + (f.summary || f.claim) + '\nFile: ' + (f.file || '?') + (f.line ? (' line ' + f.line) : '') + '\n\nTry to REFUTE it. Reproduce the claimed failure against the actual code (read-only git + file reads; you may run tests). If you cannot demonstrate it concretely, is_real=false. Default to false when uncertain.',
    { label: 'verify:' + (f.file || 'finding'), phase: 'Verify', schema: VERDICT_SCHEMA }
  ).then((v) => ({ finding: f, verdict: v }))
))

const confirmed = verified.filter(Boolean).filter((v) => v.verdict && v.verdict.is_real)
const rank = { critical: 0, major: 1, minor: 2 }
confirmed.sort((a, b) => (rank[a.finding.severity] || 3) - (rank[b.finding.severity] || 3))

return {
  scope: scope,
  confirmed: confirmed.map((v) => ({ ...v.finding, reasoning: v.verdict.reasoning })),
  rejected_count: verified.filter(Boolean).length - confirmed.length,
  conformance: conformance,
}
