"""Regression suite: the repository's own assertion suite, folded into the score.

test/run-tests.sh is the shipped behavioral contract -- every guarantee the
plugin has already made and paid for. Scoring the adversarial suites without it
would reward trading an existing guarantee for a new one, so its pass fraction
is carried as this suite's aggregate. Its individual FAIL lines are surfaced for
diagnosis only and are not counted a second time.
"""

from __future__ import annotations

import re
import subprocess

from harnesslib import REPO_ROOT, Recorder

SUITE = "regression"
SUMMARY = re.compile(r"Summary: (\d+)/(\d+) assertions passed, (\d+) failed")
TIMEOUT_S = 900
MAX_FAILS_SURFACED = 20


def run(rec: Recorder) -> int:
    try:
        proc = subprocess.run(
            ["bash", "test/run-tests.sh"],
            cwd=str(REPO_ROOT),
            capture_output=True,
            timeout=TIMEOUT_S,
        )
        output = proc.stdout.decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        rec.add(SUITE, "test/run-tests.sh runs to completion", False, f"timed out after {TIMEOUT_S}s")
        return -1

    match = SUMMARY.search(output)
    if not match:
        rec.add(SUITE, "test/run-tests.sh runs to completion", False, "no summary line in output")
        return -1

    passed, total, failed = (int(g) for g in match.groups())
    rec.add(SUITE, "test/run-tests.sh runs to completion", True)
    rec.aggregates[SUITE] = (passed, total)

    surfaced = [l for l in output.split("\n") if l.startswith("FAIL")][:MAX_FAILS_SURFACED]
    for line in surfaced:
        rec.add(SUITE, line[6:170].strip(), False, "", scored=False)
    return failed
