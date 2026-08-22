"""Behavioral suite: run the shipped hooks against the adversarial corpus.

Generic invariants hold for every fixture, because a SessionStart hook that
crashes, writes to stderr, blows the platform's context cap, or lets untrusted
`.harness/features.json` text forge a harness-authored line is broken in the
same way regardless of which fixture provoked it.
"""

from __future__ import annotations

import json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from fixtures import FIXTURES, Expect, Fixture
from harnesslib import (
    CONTEXT_CAP,
    HOOKS,
    STATE_MODULE_TEMPLATE,
    Project,
    Recorder,
    build_project,
    canonical_features,
    control_chars,
    git_commit_all,
    run_hook,
)

SESSION_START = HOOKS / "session-start.sh"
SESSION_END = HOOKS / "session-end.sh"
STATUSLINE = HOOKS / "statusline.sh"
DASHBOARD_LOG = HOOKS / "dashboard-log.sh"

ORIENTATION_HEADER = "## Harness orientation"
FOOTER_MARK = "Run /harness-continue"


def _check_session_start(rec: Recorder, label: str, project: Project, run, expect: Expect) -> None:
    suite = "behavior"
    p = f"session-start[{label}]"
    text = run.text
    lines = text.split("\n")
    has_harness = (project.path / ".harness").is_dir()

    rec.add(suite, f"{p} exits 0", run.rc == 0, f"rc={run.rc}")
    rec.add(suite, f"{p} keeps stderr silent", not run.err.strip(), run.stderr_text[:200])
    rec.add(
        suite,
        f"{p} stays within the {CONTEXT_CAP}-char context cap",
        len(text) <= CONTEXT_CAP,
        f"{len(text)} chars",
    )
    rec.add(suite, f"{p} emits valid UTF-8", run.valid_utf8)
    ctrl = control_chars(run.out)
    rec.add(suite, f"{p} emits no raw control bytes", not ctrl, f"bytes={ctrl}")

    headers = [l for l in lines if l.startswith(ORIENTATION_HEADER)]
    if has_harness:
        rec.add(suite, f"{p} prints exactly one orientation header", len(headers) == 1, f"count={len(headers)}")
        rec.add(suite, f"{p} keeps the rule-pointer footer", FOOTER_MARK in text)
    else:
        rec.add(suite, f"{p} prints no orientation outside a harness project", not headers)

    if expect.empty_output:
        rec.add(suite, f"{p} prints nothing", not text.strip(), text[:120])
    if expect.max_lines is not None:
        nonempty = [l for l in lines if l.strip()]
        rec.add(
            suite,
            f"{p} prints at most {expect.max_lines} line(s)",
            len(nonempty) <= expect.max_lines,
            f"lines={len(nonempty)}",
        )
    for needle in expect.contains:
        rec.add(suite, f"{p} reports {needle!r}", needle in text)
    for needle in expect.absent:
        rec.add(suite, f"{p} withholds {needle[:40]!r}", needle not in text)
    for prefix, limit in expect.line_prefix_max.items():
        hits = [l for l in lines if l.lstrip().startswith(prefix)]
        rec.add(
            suite,
            f"{p} allows at most {limit} line(s) starting {prefix!r}",
            len(hits) <= limit,
            f"count={len(hits)}",
        )
    if expect.next_claimable:
        rec.add(
            suite,
            f"{p} still names the claimable feature",
            f"Next claimable: {expect.next_claimable}" in text,
        )


def _run_fixture(root: Path, fx: Fixture, delegated: bool) -> tuple:
    project = fx.build(root)
    if delegated:
        hooks_dir = project.path / ".claude" / "hooks"
        hooks_dir.mkdir(parents=True, exist_ok=True)
        hooks_dir.joinpath("harness_state.py").write_bytes(STATE_MODULE_TEMPLATE.read_bytes())
    run = run_hook(SESSION_START, project.path, project.home, stdin=fx.stdin)
    return fx, delegated, project, run


def run_session_start_corpus(rec: Recorder, root: Path, timings: dict, sizes: dict) -> None:
    jobs = []
    for fx in FIXTURES:
        jobs.append((fx, False))
        if fx.both_paths:
            jobs.append((fx, True))

    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = [
            pool.submit(_run_fixture, root / ("delegated" if d else "inline"), fx, d) for fx, d in jobs
        ]
        results = [f.result() for f in futures]

    for fx, delegated, project, run in results:
        label = f"{fx.name}+state" if delegated else fx.name
        _check_session_start(rec, label, project, run, fx.expect)
        timings[label] = run.ms
        sizes[label] = len(run.text)


def run_statusline(rec: Recorder, root: Path) -> None:
    suite = "behavior"
    cases = {
        "canonical": build_project(root, "sl_canonical", features=canonical_features()),
        "malformed": build_project(root, "sl_malformed", features="{oops"),
        "no_features": build_project(root, "sl_nofeatures", features=None),
        "unicode": build_project(
            root, "sl_unicode", features=[dict(canonical_features()[0], description="🚀" * 500)]
        ),
        "incomplete": build_project(
            root, "sl_incomplete", features=canonical_features(), session_incomplete="gap\n"
        ),
    }
    for label, project in cases.items():
        payload = json.dumps({"workspace": {"project_dir": str(project.path)}}).encode()
        run = run_hook(STATUSLINE, project.path, project.home, stdin=payload)
        p = f"statusline[{label}]"
        rec.add(suite, f"{p} exits 0", run.rc == 0, f"rc={run.rc}")
        rec.add(suite, f"{p} keeps stderr silent", not run.err.strip(), run.stderr_text[:200])
        rec.add(suite, f"{p} emits valid UTF-8", run.valid_utf8)
        rec.add(suite, f"{p} emits no raw control bytes", not control_chars(run.out))
        rec.add(
            suite,
            f"{p} prints a single line",
            len([l for l in run.text.split("\n") if l.strip()]) <= 1,
            run.text[:120],
        )
        rec.add(suite, f"{p} stays under 200 chars", len(run.text) <= 200, f"{len(run.text)} chars")

    # Malformed input must not produce a status line at all.
    project = cases["canonical"]
    for label, payload in [("garbage", b"not json"), ("empty", b""), ("array", b"[]")]:
        run = run_hook(STATUSLINE, project.path, project.home, stdin=payload)
        rec.add(suite, f"statusline[stdin-{label}] exits 0", run.rc == 0, f"rc={run.rc}")
        rec.add(suite, f"statusline[stdin-{label}] keeps stderr silent", not run.err.strip())


def run_session_end(rec: Recorder, root: Path, timings: dict) -> None:
    suite = "behavior"
    clean = build_project(root, "se_clean", features=canonical_features())
    git_commit_all(clean.path)
    dirty = build_project(root, "se_dirty", features=canonical_features())
    git_commit_all(dirty.path)
    (dirty.path / ".harness" / "features.json").write_text(
        json.dumps({"features": canonical_features()[:2]}), encoding="utf-8"
    )
    malformed = build_project(root, "se_malformed", features="{oops")
    git_commit_all(malformed.path)
    nogit = build_project(root, "se_nogit", features=canonical_features(), git=False)

    for label, project in [("clean", clean), ("dirty", dirty), ("malformed", malformed), ("nogit", nogit)]:
        before = {p.name for p in project.path.iterdir()}
        run = run_hook(SESSION_END, project.path, project.home)
        p = f"session-end[{label}]"
        timings[p] = run.ms
        rec.add(suite, f"{p} exits 0", run.rc == 0, f"rc={run.rc}")
        rec.add(suite, f"{p} keeps stderr silent", not run.err.strip(), run.stderr_text[:200])
        rec.add(suite, f"{p} emits valid UTF-8", run.valid_utf8)
        after = {p2.name for p2 in project.path.iterdir()}
        rec.add(suite, f"{p} creates nothing outside .harness/", before == after, f"new={sorted(after - before)}")

    incomplete = (dirty.path / ".harness" / "SESSION_INCOMPLETE")
    rec.add(suite, "session-end[dirty] records the gap in SESSION_INCOMPLETE", incomplete.is_file())
    rec.add(
        suite,
        "session-end[malformed] never writes an empty gap file",
        not (malformed.path / ".harness" / "SESSION_INCOMPLETE").is_file()
        or (malformed.path / ".harness" / "SESSION_INCOMPLETE").read_text().strip() != "",
    )


def run_dashboard_log(rec: Recorder, root: Path) -> None:
    suite = "behavior"
    project = build_project(root, "dash", features=canonical_features())
    payloads = {
        "valid": json.dumps({"hook_event_name": "SessionStart", "session_id": "s1"}).encode(),
        "garbage": b"not json",
        "empty": b"",
        "hostile": json.dumps(
            {"hook_event_name": "SessionStart", "session_id": "../../escape", "tool_name": "\x1b[31mx"}
        ).encode(),
    }
    for label, payload in payloads.items():
        run = run_hook(
            DASHBOARD_LOG, project.path, project.home, stdin=payload, env_extra={"VV_HARNESS_DASHBOARD": "1"}
        )
        p = f"dashboard-log[{label}]"
        rec.add(suite, f"{p} exits 0", run.rc == 0, f"rc={run.rc}")
        rec.add(suite, f"{p} keeps stderr silent", not run.err.strip(), run.stderr_text[:200])

    logs = sorted((project.path / ".harness" / "dashboard").glob("*.jsonl"))
    rec.add(suite, "dashboard-log writes a session log", bool(logs), "no .jsonl produced")
    for log in logs:
        rec.add(
            suite,
            f"dashboard-log[{log.name}] writes one JSON object per line",
            all(json.loads(line) for line in log.read_text().splitlines() if line.strip()),
        )
        rec.add(
            suite,
            f"dashboard-log[{log.name}] stays inside .harness/dashboard/",
            log.resolve().is_relative_to((project.path / ".harness" / "dashboard").resolve()),
        )


def run(rec: Recorder, root: Path) -> dict:
    timings: dict = {}
    sizes: dict = {}
    root.mkdir(parents=True, exist_ok=True)
    run_session_start_corpus(rec, root, timings, sizes)
    run_statusline(rec, root / "statusline")
    run_session_end(rec, root / "sessionend", timings)
    run_dashboard_log(rec, root / "dashboard")
    return {"timings": timings, "sizes": sizes}
