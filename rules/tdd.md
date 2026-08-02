# TDD Required

Use TDD for features and bugfixes unless blocked or the benefit is clearly absent.

## The 5-step process

1. Write failing test
2. Confirm it fails
3. Write minimum code to pass
4. Confirm success
5. Refactor

No exceptions unless tooling is broken.

## Coverage

Match the project's existing test patterns for file naming, assertion style, and
organization. Run existing tests before committing. Where the project defines a coverage
threshold, meet it on the code you touch; if the tooling cannot measure coverage,
report that as a blocker rather than skipping it silently.

## Why this is a gate, not prose

Prose alone does not move behavior. This exact discipline lived as always-on text in
Ovidiu's personal CLAUDE.md for a full measurement window, and `buggy_code` still led the
project's own friction table at 33%. What measurably worked instead was wiring TDD to a
gate: the coverage threshold check and adversarial review. Prefer wiring TDD to a gate
over restating it as prose wherever the harness can do so.
