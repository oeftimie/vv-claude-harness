# Engineering Standards

These rules apply to all projects, all sessions. They're non-negotiable defaults that can be overridden by project-level CLAUDE.md when explicitly stated.

## Git Workflow

Always check for branch protection rules before pushing. Default to a PR-based workflow: create a feature branch, push there, open a PR. Never push directly to main unless the user explicitly says otherwise.

Before any git push, pull, or clone: verify the active SSH identity by running `ssh -T git@github.com` and checking `git config user.name` and `git config user.email`. Never assume which SSH key is active. In multi-account setups, confirm the identity matches the target repo's org before proceeding.

When gitleaks blocks a push due to false positives, add entries to `.gitleaks.toml` allowlist rather than restructuring code. After committing, confirm push succeeded and verify remote state with `git log --oneline origin/<branch>`.

## Propose Before Editing

When a task involves modifying descriptions, configurations, READMEs, or user-facing content: ALWAYS present proposed changes for review BEFORE editing files. Never start editing without explicit approval for content changes.

This does not apply to code implementation where the user has already approved the approach.

## Approach Discipline

If your first approach fails, stop. Explain what went wrong and present alternatives before trying a second approach. Do not silently retry with a different strategy.

Do not access keychain, credential stores, or sensitive system resources unless the user explicitly requests it and confirms.

Before editing files, confirm you're in the correct directory by listing it first. Do not assume directory context from previous commands.

## Research Tasks

When assigned research or documentation tasks, structure the work in a single focused pass rather than spawning excessive web fetches. If a URL fails (JS-rendered pages, timeouts), immediately try alternative sources: PDFs, GitHub docs, cached versions, official documentation. Do not retry the same failing URL.

Limit web fetches to essential sources. Quality over quantity.

## Agent Autonomy

When spawned as a sub-agent or teammate:

1. Execute immediately. Do not wait for "Go ahead" confirmations.
2. Do not poll TaskList more than 5 times. If a blocking task hasn't completed, proceed independently or report the blocker.
3. Write output to a file before finishing so results are preserved even if the agent terminates unexpectedly.
4. Verify your output was actually produced before reporting success.

## Testing Defaults

When tests exist in a project, run them before committing. If tests fail after your changes, fix the failures before committing. Do not commit code with failing tests unless explicitly instructed to do so.

When writing new code in a project with existing test patterns, write tests that follow those patterns. Match the project's testing conventions for file naming, assertion style, and test organization.
