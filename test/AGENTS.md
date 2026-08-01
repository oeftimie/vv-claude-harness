# test/

One file: `run-tests.sh`. A single dependency-free bash script (bash 3.2+, python3
stdlib, no jq) organized into `echo "== section =="`-delimited groups, each covering
one hook, skill, or feature. Run it with `bash test/run-tests.sh`.

## Adding a fixture case

- Reuse the existing helpers rather than re-deriving them: `make_fixture DIR` builds a
  committed git fixture from `test/fixtures/harness-project/`; `install_hooks DIR`
  copies the real hook templates in; `run_hook DIR HOOK_NAME JSON_INPUT` invokes a
  hook the way `.claude/settings.json` does (`CLAUDE_PROJECT_DIR` set, stdin piped).
- Assert with `pass "label"` / `fail "label"`, or the `assert_*` helpers
  (`assert_contains`, `assert_not_contains`, `assert_empty`, `assert_rc0`,
  `assert_rc2`, `assert_rc_nonzero`) -- these keep the pass/fail count and the final
  summary line accurate.
- A check that would be satisfied by content unrelated to what it's testing is worse
  than no check: scope greps to the specific section/block being tested (extract it
  first, e.g. via a regex capturing between two headers), not the whole file -- a
  whole-file grep can pass even after the real content it's meant to verify is
  deleted, if an unrelated sentence elsewhere happens to share a keyword.
- Mutation-test anything non-trivial before considering it done: revert the fix (or
  delete/reword the content a new check asserts), confirm exactly the expected
  assertion(s) fail, then restore.
