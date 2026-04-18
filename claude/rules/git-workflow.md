---
globs:
  - "**/.git/**"
  - "**/.gitignore"
  - "**/.gitleaks.toml"
  - "**/COMMIT_EDITMSG"
---

# Git Workflow

Always check for branch protection rules before pushing. Default to a PR-based workflow: create a feature branch, push there, open a PR. Never push directly to main unless the user explicitly says otherwise.

## Identity Verification

Before any git push, pull, or clone: verify the active SSH identity by running `ssh -T git@github.com` and checking `git config user.name` and `git config user.email`. Never assume which SSH key is active. In multi-account setups, confirm the identity matches the target repo's org before proceeding. If the identity doesn't match, fix `git config user.name`, `git config user.email`, and the remote URL to use the correct SSH host alias before proceeding — do not push with the wrong identity.

In harness projects, the confirmed identity is stored in `.harness/harness.json` under `git_identity`. Compare against it at session start.

When gitleaks blocks a push due to false positives, add entries to `.gitleaks.toml` allowlist rather than restructuring code. After committing, confirm push succeeded and verify remote state with `git log --oneline origin/<branch>`.

## Commit Hygiene
- No auto-generated signatures
- No "Generated with Claude Code" or "Co-Authored-By: Claude"
- Write commits as if a human wrote them
- Commit at natural breakpoints, not at the end of a session. Specifically: (1) commit after each feature/fix passes tests, (2) commit harness metadata separately from code with `docs:` prefix, (3) if you inherit uncommitted work from a previous session, commit it as-is first ("checkpoint: uncommitted work from session N") before making new changes
- Separate documentation commits from code when practical
- Prefix: `docs:` for pure documentation changes

## PR Workflow
- Each sub-agent creates a PR or delegates to orchestrator
- Sequence PRs by dependencies (dependencies first)
- PRs should be ready for review, not draft
- PR description: what changed, why, testing done, dependencies
