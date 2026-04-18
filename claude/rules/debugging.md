---
globs:
  - "**/*.ts"
  - "**/*.py"
  - "**/*.go"
  - "**/*.js"
  - "**/*.rb"
  - "**/*.java"
  - "**/*.sh"
---

# Systematic Debugging

YOU MUST find the root cause. NEVER fix a symptom or add a workaround.

## Phase 1: Root Cause Investigation (BEFORE attempting fixes)
- Read error messages carefully; they often contain the exact solution
- Reproduce consistently before investigating
- Check recent changes: git diff, recent commits
- For user-reported bugs: state your diagnosis and proposed fix in 2-3 sentences BEFORE editing code. ("I think the crash is X because Y, I'll fix it by Z.") This gives the user a chance to correct your understanding and costs one message.

## Phase 2: Pattern Analysis
- Find working examples in the same codebase
- Compare against references; read implementation completely
- Identify differences between working and broken code
- Understand dependencies

## Phase 3: Hypothesis and Testing
1. Form single hypothesis; state it clearly
2. Make smallest possible change to test hypothesis
3. Verify before continuing; if it didn't work, form new hypothesis
4. Say "I don't understand X" rather than pretending to know

## Phase 4: Implementation Rules
- ALWAYS have the simplest possible failing test case
- NEVER add multiple fixes at once
- NEVER claim to implement a pattern without reading it completely
- ALWAYS test after each change
- IF first fix doesn't work, STOP and re-analyze

## Error Recovery Philosophy

A broken codebase is worse than a paused task. Fail fast, fail loud, fail safe.

**Retry autonomously (limited):**
- Network timeouts (max 2 retries)
- Rate limiting (backoff, max 3 attempts)
- Tool crashes with no state change (once)

**Do NOT retry:**
- Test failures
- Build errors
- Permission denied
- Anything that failed the same way twice

**Report immediately:**
- Sub-agent at 4 correction cycles
- Missing tools or capabilities
- Ambiguity revealed by failure
- Conflicts between sub-agent output and constraints

Report format: what was attempted, what failed and why, options (retry differently / user intervention / abandon), recommended path.
