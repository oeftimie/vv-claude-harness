#!/usr/bin/env bash
# Benchmark entrypoint: the vv-harness hillclimb eval.
# Scores the shipped plugin (hooks under adversarial fixtures, manifest and
# pointer contracts, output determinism) and prints METRIC lines. Offline,
# hermetic, and a pure function of the repository contents.
set -uo pipefail

cd "$(dirname "$0")" || exit 1
exec python3 evals/hillclimb/run.py
