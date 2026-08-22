"""Determinism suite: identical inputs must produce identical model context.

Two things are checked. Reproducibility -- the same fixture must yield the same
orientation regardless of timezone, working subdirectory, or repetition, since
an orientation that varies with ambient state is unreviewable. And path parity
-- session-start.sh computes feature counts and the next claimable feature
twice, once by delegating to a project's harness_state.py and once inline; the
two must agree, or half of all projects get a different picture from the same
features.json.
"""

from __future__ import annotations

import json
from pathlib import Path

from fixtures import FIXTURES, STARTUP
from harnesslib import (
    HOOKS,
    STATE_MODULE_TEMPLATE,
    Recorder,
    build_project,
    canonical_features,
    git_commit_all,
    run_hook,
)

SUITE = "determinism"
SESSION_START = HOOKS / "session-start.sh"
SESSION_END = HOOKS / "session-end.sh"
STATUSLINE = HOOKS / "statusline.sh"


def _install_state_module(project) -> None:
    hooks_dir = project.path / ".claude" / "hooks"
    hooks_dir.mkdir(parents=True, exist_ok=True)
    hooks_dir.joinpath("harness_state.py").write_bytes(STATE_MODULE_TEMPLATE.read_bytes())


def check_reproducibility(rec: Recorder, root: Path) -> None:
    project = build_project(root, "repro", features=canonical_features())
    baseline = run_hook(SESSION_START, project.path, project.home, stdin=STARTUP)

    again = run_hook(SESSION_START, project.path, project.home, stdin=STARTUP)
    rec.add(SUITE, "session-start repeats identically", baseline.out == again.out)

    other_tz = run_hook(
        SESSION_START, project.path, project.home, stdin=STARTUP, env_extra={"TZ": "Asia/Kathmandu"}
    )
    rec.add(SUITE, "session-start ignores the local timezone", baseline.out == other_tz.out)

    subdir = project.path / "src" / "badges"
    subdir.mkdir(parents=True, exist_ok=True)
    from_subdir = run_hook(SESSION_START, project.path, project.home, stdin=STARTUP, cwd=subdir)
    rec.add(SUITE, "session-start ignores the working subdirectory", baseline.out == from_subdir.out)

    other_home = root / "other-home"
    other_home.mkdir(parents=True, exist_ok=True)
    home_swap = run_hook(SESSION_START, project.path, other_home, stdin=STARTUP)
    rec.add(SUITE, "session-start ignores HOME", baseline.out == home_swap.out)

    payload = json.dumps({"workspace": {"project_dir": str(project.path)}}).encode()
    s1 = run_hook(STATUSLINE, project.path, project.home, stdin=payload)
    s2 = run_hook(STATUSLINE, project.path, project.home, stdin=payload, env_extra={"TZ": "Asia/Kathmandu"})
    rec.add(SUITE, "statusline repeats identically", s1.out == s2.out)

    ended = build_project(root, "repro-end", features=canonical_features())
    git_commit_all(ended.path)
    e1 = run_hook(SESSION_END, ended.path, ended.home)
    gap1 = (ended.path / ".harness" / "SESSION_INCOMPLETE")
    first = gap1.read_text() if gap1.is_file() else ""
    e2 = run_hook(SESSION_END, ended.path, ended.home)
    second = gap1.read_text() if gap1.is_file() else ""
    rec.add(SUITE, "session-end repeats identically", e1.out == e2.out)
    rec.add(SUITE, "session-end's gap file is stable across runs", first == second)


def check_path_parity(rec: Recorder, root: Path) -> None:
    """The delegated and inline state paths must describe the same project."""
    for fx in [f for f in FIXTURES if f.both_paths]:
        inline_project = fx.build(root / "inline")
        delegated_project = fx.build(root / "delegated")
        _install_state_module(delegated_project)
        a = run_hook(SESSION_START, inline_project.path, inline_project.home, stdin=fx.stdin)
        b = run_hook(SESSION_START, delegated_project.path, delegated_project.home, stdin=fx.stdin)
        # Only the project path differs between the two runs; normalize it out.
        norm_a = a.out.replace(str(inline_project.path).encode(), b"<PROJECT>")
        norm_b = b.out.replace(str(delegated_project.path).encode(), b"<PROJECT>")
        rec.add(
            SUITE,
            f"state-module parity [{fx.name}]",
            norm_a == norm_b,
            _first_difference(norm_a, norm_b),
        )


def _first_difference(a: bytes, b: bytes) -> str:
    a_lines = a.decode("utf-8", "replace").split("\n")
    b_lines = b.decode("utf-8", "replace").split("\n")
    for left, right in zip(a_lines, b_lines):
        if left != right:
            return f"inline={left[:70]!r} delegated={right[:70]!r}"
    if len(a_lines) != len(b_lines):
        return f"line count {len(a_lines)} vs {len(b_lines)}"
    return ""


def run(rec: Recorder, root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)
    check_reproducibility(rec, root / "repro")
    check_path_parity(rec, root / "parity")
