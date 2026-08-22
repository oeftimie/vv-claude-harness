#!/usr/bin/env python3
"""Hillclimb eval for the vv-harness plugin.

Scores the shipped harness on six suites and prints the aggregate as
``METRIC harness_score=<0..100>``:

    behavior     (0.25)  session-start/statusline/session-end/dashboard-log,
                         run against an adversarial fixture corpus
    gates        (0.20)  the enforcement surface -- enforce-scope, commit-gate,
                         verify-task-quality, verify-git-identity, doctor, and
                         harness_state's lock -- run against hostile input
    regression   (0.20)  test/run-tests.sh, the contract the plugin already ships
    contracts    (0.15)  the features.json oracle (validate-features.py, its
                         agreement with the schema) and the initializer's
                         new/upgrade write promises
    static       (0.10)  the plugin's own contracts: manifests, frontmatter,
                         file pointers, link and reachability integrity
    determinism  (0.10)  identical inputs produce identical model context

Every check is a boolean, so the score is the weighted fraction of checks the
harness passes. Higher is better. Runs offline, with a hermetic environment per
fixture, and is a pure function of the repository contents.
"""

from __future__ import annotations

import argparse
import shutil
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import suite_behavior  # noqa: E402
import suite_contracts  # noqa: E402
import suite_determinism  # noqa: E402
import suite_gates  # noqa: E402
import suite_regression  # noqa: E402
import suite_static  # noqa: E402
from harnesslib import CONTEXT_CAP, Recorder  # noqa: E402

WEIGHTS = {
    "behavior": 0.25,
    "gates": 0.20,
    "regression": 0.20,
    "contracts": 0.15,
    "static": 0.10,
    "determinism": 0.10,
}
MAX_FAILURES_SHOWN = 60


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="run.py",
        description="Conformance suite over the shipped vv-harness plugin.",
    )
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument(
        "--suite",
        metavar="A,B",
        help="run only these suites (comma-separated) -- for iterating on one area",
    )
    # A denylist rather than a longhand --suite list: CI skips the regression
    # aggregate because its own `test` job already runs test/run-tests.sh, and a
    # spelled-out allowlist there would silently stop covering any suite added
    # later. --skip keeps new suites included by default.
    selection.add_argument(
        "--skip",
        metavar="A,B",
        help="run every suite except these (comma-separated)",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help=(
            "exit 1 when any check fails. Off by default: the research harness reads "
            "the METRIC lines, so a failing check is data rather than an error. CI "
            "wants the opposite."
        ),
    )
    parser.add_argument(
        "--list", action="store_true", help="print the suite names and weights, then exit"
    )
    return parser


def select_suites(args, parser) -> list:
    """The suites to run, in the canonical order WEIGHTS declares."""
    if args.suite:
        wanted = {name.strip() for name in args.suite.split(",") if name.strip()}
    elif args.skip:
        skipped = {name.strip() for name in args.skip.split(",") if name.strip()}
        unknown = skipped - set(WEIGHTS)
        if unknown:
            parser.error(f"unknown suite(s): {', '.join(sorted(unknown))}")
        wanted = set(WEIGHTS) - skipped
    else:
        return list(WEIGHTS)
    unknown = wanted - set(WEIGHTS)
    if unknown:
        parser.error(f"unknown suite(s): {', '.join(sorted(unknown))}")
    if not wanted:
        parser.error("no suites selected")
    return [name for name in WEIGHTS if name in wanted]


def main(argv=None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)
    if args.list:
        for name, weight in WEIGHTS.items():
            print(f"{name:<12} weight {weight:.2f}")
        return 0

    selected = select_suites(args, parser)
    partial = len(selected) != len(WEIGHTS)

    started = time.monotonic()
    rec = Recorder()
    behavior = None
    work = Path(tempfile.mkdtemp(prefix="vv-hillclimb."))
    runners = {
        "behavior": lambda: suite_behavior.run(rec, work / "behavior"),
        "gates": lambda: suite_gates.run(rec, work / "gates"),
        "contracts": lambda: suite_contracts.run(rec, work / "contracts"),
        "static": lambda: suite_static.run(rec),
        "determinism": lambda: suite_determinism.run(rec, work / "determinism"),
        "regression": lambda: suite_regression.run(rec),
    }
    try:
        for name in selected:
            result = runners[name]()
            if name == "behavior":
                behavior = result
    finally:
        shutil.rmtree(work, ignore_errors=True)

    totals = {suite: [0, 0] for suite in selected}
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
    for suite in selected:
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

    scored_total = sum(t[1] for t in totals.values())
    scored_failed = sum(t[1] - t[0] for t in totals.values())

    print()
    if partial:
        # No harness_score on a partial run, deliberately. The score is a
        # weighted sum over ALL suites; renormalizing it across a subset would
        # produce a number that looks like the real one and is not, and the
        # cheapest way to raise a renormalized score would be to drop the suite
        # you are failing.
        skipped = [name for name in WEIGHTS if name not in selected]
        print(f"PARTIAL run: {', '.join(selected)} (skipped: {', '.join(skipped)})")
        print("PARTIAL no harness_score -- the score is only defined over every suite")
    else:
        score = 100.0 * sum(
            WEIGHTS[suite] * (totals[suite][0] / totals[suite][1] if totals[suite][1] else 0.0)
            for suite in selected
        )
        print(f"METRIC harness_score={score:.3f}")
    for suite in selected:
        passed, total = totals[suite]
        print(f"METRIC {suite}_score={100.0 * passed / total if total else 0.0:.3f}")
    print(f"METRIC checks_failed={scored_failed}")
    print(f"METRIC checks_total={scored_total}")
    if behavior is not None:
        sizes = behavior["sizes"]
        timings = behavior["timings"]
        start_times = [v for k, v in timings.items() if not k.startswith("session-end")]
        print(f"METRIC orientation_chars={sizes.get('canonical', 0)}")
        print(f"METRIC max_orientation_chars={max(sizes.values()) if sizes else 0}")
        print(f"METRIC context_headroom={CONTEXT_CAP - (max(sizes.values()) if sizes else 0)}")
        print(f"METRIC session_start_ms={timings.get('canonical', 0.0):.1f}")
        print(f"METRIC session_start_p95_ms={_p95(start_times):.1f}")
    print(f"METRIC eval_wall_s={time.monotonic() - started:.2f}")

    by_suite = ",".join(f"{s}:{totals[s][0]}/{totals[s][1]}" for s in selected)
    print(f"ASI suites={by_suite}")
    print(f"ASI top_failures={';'.join(c.name for c in failures[:8]) or 'none'}")
    return 1 if (args.strict and scored_failed) else 0


def _p95(values: list[float]) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    idx = min(len(ordered) - 1, int(round(0.95 * (len(ordered) - 1))))
    return ordered[idx]


if __name__ == "__main__":
    sys.exit(main())
