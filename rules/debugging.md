# Systematic Debugging

Find the root cause. NEVER fix a symptom or add a workaround.

## Phase 1 — Root cause investigation (BEFORE attempting fixes)

- Read error messages carefully; they often contain the exact solution
- Reproduce consistently before investigating
- Check recent changes: `git diff`, recent commits
- For user-reported bugs: state the diagnosis and proposed fix in 2-3 sentences BEFORE
  editing code ("I think the crash is X because Y, I'll fix it by Z"). Costs one message
  and lets the human correct a wrong model early.
- An empty or clean result is not a negative result until the command is known to have run.
  A check that errors out must report UNKNOWN, never PASS — a silently-missing tool or a query
  that exits 0 without actually executing looks identical to a genuine clean result unless
  you confirm the command ran.

## Phase 2 — Pattern analysis

- Find working examples in the same codebase
- Compare against references; read the implementation completely
- Identify differences between working and broken code
- Understand dependencies

## Phase 3 — Hypothesis and testing

1. Form a single hypothesis; state it clearly
2. Make the smallest possible change to test it
3. Verify before continuing; if it did not work, form a new hypothesis
4. Say "I don't understand X" rather than pretending to know

## Phase 4 — Implementation rules

- Always have the simplest possible failing test case
- Never add multiple fixes at once
- Never claim to implement a pattern without reading it completely
- Test after each change
- If the first fix does not work, STOP and re-analyse
