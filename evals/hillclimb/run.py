#!/usr/bin/env python3
"""Hillclimb eval for the vv-harness plugin.

Scores the shipped harness on five suites and prints the aggregate as
``METRIC harness_score=<0..100>``:

    behavior     (0.30)  session-start/statusline/session-end/dashboard-log,
                         run against an adversarial fixture corpus
    gates        (0.20)  the enforcement surface -- enforce-scope, commit-gate,
                         verify-task-quality, verify-git-identity, doctor, and
                         harness_state's lock -- run against hostile input
    regression   (0.20)  test/run-tests.sh, the contract the plugin already ships
    static       (0.15)  the plugin's own contracts: manifests, frontmatter,
                         file pointers, link and reachability integrity
    determinism  (0.15)  identical inputs produce identical model context

Every check is a boolean, so the score is the weighted fraction of checks the
harness passes. Higher is better. Runs offline, with a hermetic environment per
fixture, and is a pure function of the repository contents.
"""

from __future__ import annotations

import shutil
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import suite_behavior  # noqa: E402
import suite_determinism  # noqa: E402
import suite_gates  # noqa: E402
import suite_regression  # noqa: E402
import suite_static  # noqa: E402
from harnesslib import CONTEXT_CAP, Recorder  # noqa: E402

WEIGHTS = {
    "behavior": 0.30,
    "gates": 0.20,
    "regression": 0.20,
    "static": 0.15,
    "determinism": 0.15,
}
MAX_FAILURES_SHOWN = 60


def main() -> int:
    started = time.monotonic()
    rec = Recorder()
    work = Path(tempfile.mkdtemp(prefix="vv-hillclimb."))
    try:
        behavior = suite_behavior.run(rec, work / "behavior")
        suite_gates.run(rec, work / "gates")
        suite_static.run(rec)
        suite_determinism.run(rec, work / "determinism")
        suite_regression.run(rec)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    totals = {suite: [0, 0] for suite in WEIGHTS}
    for suite, (passed, total) in rec.aggregates.items():
        bucket = totals.setdefault(suite, [0, 0])
        bucket[0] += passed
        bucket[1] += total
    for check in rec.checks:
        if not check.scored:
            continue
        bucket = totals.setdefault(check.suite, [0, 0])
        bucket[1] += 1
        bucket[0] += 1 if check.passed else 0

    failures = [c for c in rec.checks if not c.passed]
    print("=== vv-harness hillclimb eval ===")
    for suite in WEIGHTS:
        passed, total = totals[suite]
        pct = 100.0 * passed / total if total else 0.0
        print(f"  {suite:<12} {passed:>4}/{total:<4} {pct:6.2f}%  (weight {WEIGHTS[suite]:.2f})")

    if failures:
        print(f"\n--- {len(failures)} failing checks ---")
        for check in failures[:MAX_FAILURES_SHOWN]:
            detail = f"  [{check.detail}]" if check.detail else ""
            print(f"  FAIL {check.suite}: {check.name}{detail}")
        if len(failures) > MAX_FAILURES_SHOWN:
            print(f"  ... and {len(failures) - MAX_FAILURES_SHOWN} more")

    score = 0.0
    for suite, weight in WEIGHTS.items():
        passed, total = totals[suite]
        score += weight * (passed / total if total else 0.0)
    score *= 100.0

    sizes = behavior["sizes"]
    timings = behavior["timings"]
    canonical_ms = timings.get("canonical", 0.0)
    start_times = [v for k, v in timings.items() if not k.startswith("session-end")]

    print()
    print(f"METRIC harness_score={score:.3f}")
    for suite, weight in WEIGHTS.items():
        passed, total = totals[suite]
        print(f"METRIC {suite}_score={100.0 * passed / total if total else 0.0:.3f}")
    scored_total = sum(t[1] for t in totals.values())
    scored_failed = sum(t[1] - t[0] for t in totals.values())
    print(f"METRIC checks_failed={scored_failed}")
    print(f"METRIC checks_total={scored_total}")
    print(f"METRIC orientation_chars={sizes.get('canonical', 0)}")
    print(f"METRIC max_orientation_chars={max(sizes.values()) if sizes else 0}")
    print(f"METRIC context_headroom={CONTEXT_CAP - (max(sizes.values()) if sizes else 0)}")
    print(f"METRIC session_start_ms={canonical_ms:.1f}")
    print(f"METRIC session_start_p95_ms={_p95(start_times):.1f}")
    print(f"METRIC eval_wall_s={time.monotonic() - started:.2f}")

    by_suite = ",".join(f"{s}:{totals[s][0]}/{totals[s][1]}" for s in WEIGHTS)
    print(f"ASI suites={by_suite}")
    print(f"ASI top_failures={';'.join(c.name for c in failures[:8]) or 'none'}")
    return 0


def _p95(values: list[float]) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    idx = min(len(ordered) - 1, int(round(0.95 * (len(ordered) - 1))))
    return ordered[idx]


if __name__ == "__main__":
    sys.exit(main())
