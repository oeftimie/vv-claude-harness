"""Fixture construction and hook invocation for the vv-harness hillclimb eval.

Every hook runs in a hermetic environment: a per-run HOME, no global or system
git config, LC_ALL=C, TZ=UTC, and a synthetic CLAUDE_PLUGIN_ROOT whose length
does not vary by machine (the footer only echoes that path, never reads it).
Hook output is therefore a pure function of the fixture, which is what makes
the score comparable between runs and between machines.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOKS = REPO_ROOT / "hooks"
STATE_MODULE_TEMPLATE = REPO_ROOT / "skills" / "harness-init" / "harness_state.py.template"

# Echoed into the orientation footer, never opened. A fixed literal keeps the
# footer length identical on every machine.
PLUGIN_ROOT_STUB = "/opt/vv-harness"

# The platform truncates SessionStart stdout at this many characters.
CONTEXT_CAP = 10000


@dataclass
class HookRun:
    rc: int
    out: bytes
    err: bytes
    ms: float

    @property
    def text(self) -> str:
        return self.out.decode("utf-8", "replace")

    @property
    def stderr_text(self) -> str:
        return self.err.decode("utf-8", "replace")

    @property
    def valid_utf8(self) -> bool:
        try:
            self.out.decode("utf-8")
            return True
        except UnicodeDecodeError:
            return False


def hook_env(project: Path, home: Path, **extra: str) -> dict:
    env = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": str(home),
        "TMPDIR": os.environ.get("TMPDIR", "/tmp"),
        "LC_ALL": "C",
        "LANG": "C",
        "TZ": "UTC",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_SYSTEM": "/dev/null",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_TERMINAL_PROMPT": "0",
        "CLAUDE_PROJECT_DIR": str(project),
        "CLAUDE_PLUGIN_ROOT": PLUGIN_ROOT_STUB,
    }
    env.update(extra)
    return env


def run_hook(
    script: Path,
    project: Path,
    home: Path,
    stdin: bytes = b"",
    env_extra: dict | None = None,
    cwd: Path | None = None,
    timeout: float = 120.0,
) -> HookRun:
    env = hook_env(project, home, **(env_extra or {}))
    start = time.monotonic()
    try:
        proc = subprocess.run(
            ["bash", str(script)],
            input=stdin,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=str(cwd or project),
            env=env,
            timeout=timeout,
        )
        rc, out, err = proc.returncode, proc.stdout, proc.stderr
    except subprocess.TimeoutExpired:
        rc, out, err = 124, b"", b"timeout"
    return HookRun(rc, out, err, (time.monotonic() - start) * 1000.0)


# --- fixture building -------------------------------------------------------


def git_init(project: Path, name: str = "Fixture User", email: str = "fixture@example.com") -> None:
    quiet = {"stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL}
    env = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null")
    subprocess.run(["git", "-c", "init.defaultBranch=main", "init", "-q", str(project)], env=env, **quiet)
    subprocess.run(["git", "-C", str(project), "config", "user.name", name], env=env, **quiet)
    subprocess.run(["git", "-C", str(project), "config", "user.email", email], env=env, **quiet)
    subprocess.run(["git", "-C", str(project), "config", "commit.gpgsign", "false"], env=env, **quiet)


def git_commit_all(project: Path, message: str = "fixture") -> None:
    quiet = {"stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL}
    env = dict(
        os.environ,
        GIT_CONFIG_GLOBAL="/dev/null",
        GIT_CONFIG_SYSTEM="/dev/null",
        GIT_AUTHOR_DATE="2020-01-01T00:00:00Z",
        GIT_COMMITTER_DATE="2020-01-01T00:00:00Z",
    )
    subprocess.run(["git", "-C", str(project), "add", "-A"], env=env, **quiet)
    subprocess.run(["git", "-C", str(project), "commit", "-q", "-m", message], env=env, **quiet)


def feature(fid: str, **over) -> dict:
    base = {
        "id": fid,
        "description": f"Feature {fid}",
        "priority": 1,
        "status": "pending",
        "scope": [f"src/{fid.lower()}/"],
        "depends_on": [],
        "assigned_to": None,
        "test_file": None,
        "coverage": None,
        "notes": None,
    }
    base.update(over)
    return base


def canonical_features() -> list[dict]:
    return [
        feature(
            "F001",
            description="Parse pipeline definitions",
            status="passing",
            priority=1,
            scope=["src/parser/", "tests/parser/"],
            test_file="tests/parser/test_parser.py",
            coverage=97,
        ),
        feature(
            "F002",
            description="Hook coverage reporting",
            status="in-progress",
            priority=2,
            scope=["src/hooks/", "tests/hooks/"],
            depends_on=["F001"],
            test_file="tests/hooks/test_hooks.py",
        ),
        feature(
            "F003",
            description="Render status badges",
            status="pending",
            priority=1,
            scope=["src/badges/", "tests/badges/"],
        ),
    ]


CONTEXT_SUMMARY = """# Context Summary

## Active Context
- Currently working on: F002 hook coverage reporting
- Blocked on: nothing
- Next step: finish the reporter

## Meta-Patterns
- nothing yet
"""

PROGRESS = "Session 1: scaffolded the parser.\nSession 2: started the reporter.\n"


@dataclass
class Project:
    path: Path
    home: Path
    delegated: bool = False


def build_project(
    root: Path,
    name: str,
    features: list[dict] | str | None = None,
    harness_json: dict | str | None = "default",
    delegated: bool = False,
    git: bool = True,
    context_summary: str | None = CONTEXT_SUMMARY,
    progress: str | None = PROGRESS,
    session_incomplete: str | None = None,
    make_test_files: bool = True,
    harness_dir: bool = True,
) -> Project:
    """Materialize a harness project fixture under ``root/name``."""
    project = root / name
    project.mkdir(parents=True, exist_ok=True)
    home = root / f"{name}.home"
    home.mkdir(parents=True, exist_ok=True)
    if git:
        git_init(project)

    if harness_dir:
        h = project / ".harness"
        h.mkdir(parents=True, exist_ok=True)

        if features is not None:
            payload = features if isinstance(features, str) else json.dumps({"features": features}, indent=2)
            (h / "features.json").write_text(payload, encoding="utf-8")

        if harness_json is not None:
            if harness_json == "default":
                harness_json = {
                    "version": "6.0.0",
                    "git_identity": {"user_name": "Fixture User", "user_email": "fixture@example.com"},
                }
            payload = harness_json if isinstance(harness_json, str) else json.dumps(harness_json, indent=2)
            (h / "harness.json").write_text(payload, encoding="utf-8")

        if context_summary is not None:
            (h / "context_summary.md").write_text(context_summary, encoding="utf-8")
        if progress is not None:
            (h / "claude-progress.txt").write_text(progress, encoding="utf-8")
        if session_incomplete is not None:
            (h / "SESSION_INCOMPLETE").write_text(session_incomplete, encoding="utf-8")

    if make_test_files and isinstance(features, list):
        for f in features:
            tf = f.get("test_file") if isinstance(f, dict) else None
            if isinstance(tf, str) and tf:
                target = project / tf
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("# fixture test\n", encoding="utf-8")

    if delegated:
        hooks_dir = project / ".claude" / "hooks"
        hooks_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy(STATE_MODULE_TEMPLATE, hooks_dir / "harness_state.py")

    return Project(project, home, delegated)


# --- assertions -------------------------------------------------------------

ALLOWED_CONTROLS = {0x09, 0x0A}


def control_chars(data: bytes) -> list[int]:
    """C0/DEL bytes that are not tab or newline. These reach model context raw."""
    return sorted({b for b in data if (b < 0x20 and b not in ALLOWED_CONTROLS) or b == 0x7F})


@dataclass
class Check:
    suite: str
    name: str
    passed: bool
    detail: str = ""
    #: reporting-only checks are shown but excluded from the score, so a suite
    #: whose result arrives as an aggregate is never counted twice
    scored: bool = True


@dataclass
class Recorder:
    checks: list[Check] = field(default_factory=list)
    #: suite -> (passed, total) contributed outside the per-check tally
    aggregates: dict = field(default_factory=dict)

    def add(self, suite: str, name: str, passed: bool, detail: str = "", scored: bool = True) -> bool:
        self.checks.append(Check(suite, name, bool(passed), detail if not passed else "", scored))
        return bool(passed)
