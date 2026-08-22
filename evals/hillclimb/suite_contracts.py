"""Contracts suite: the harness's own data oracle and its initializer.

Two surfaces nothing else in this eval reaches. scripts/validate-features.py is
what every other reader trusts when it says a features.json is well formed, so a
document it wrongly accepts becomes a defect in each of them. scripts/stamp.sh
writes the files a project is governed by, and its two modes make opposite
promises -- new refuses to touch an existing file, upgrade overwrites only a
byte-identical one -- promises that are only worth as much as their enforcement.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
from pathlib import Path

from harnesslib import REPO_ROOT, Recorder, canonical_features

SUITE = "contracts"
VALIDATOR = REPO_ROOT / "scripts" / "validate-features.py"
SCHEMA = REPO_ROOT / "schemas" / "feature.schema.json"
STAMP = REPO_ROOT / "scripts" / "stamp.sh"
FIXTURE_FEATURES = REPO_ROOT / "test" / "fixtures" / "harness-project" / ".harness" / "features.json"

TRACEBACK = "Traceback (most recent call last)"


def _valid_feature(**over) -> dict:
    base = {
        "id": "F001",
        "description": "A feature",
        "priority": 1,
        "status": "pending",
        "scope": ["src/"],
        "depends_on": [],
        "assigned_to": None,
        "test_file": None,
        "coverage": None,
        "notes": None,
    }
    base.update(over)
    return base


def _doc(*features) -> dict:
    return {"features": list(features)}


#: (label, document, must_be_accepted). A document the validator accepts is a
#: document every downstream reader is entitled to assume is well formed.
CASES = [
    ("canonical", _doc(*canonical_features()), True),
    ("minimal-valid", _doc(_valid_feature()), True),
    ("empty-feature-list", _doc(), True),
    ("envelope-metadata", {"project": "p", "created": "2026-01-01", "features": []}, True),
    ("unknown-field-warns-only", _doc(_valid_feature(experimental_flag=True)), True),
    ("all-statuses", _doc(*[
        _valid_feature(id=f"F00{i}", status=s)
        for i, s in enumerate(("pending", "in-progress", "blocked", "passing", "failed"), start=1)
    ]), True),
    ("root-array", [], False),
    ("root-null", None, False),
    ("root-string", "features", False),
    ("features-not-a-list", {"features": "F001"}, False),
    ("features-object", {"features": {"F001": {}}}, False),
    ("entry-not-an-object", _doc("F001"), False),
    ("entry-null", _doc(None), False),
    ("missing-required-field", _doc({k: v for k, v in _valid_feature().items() if k != "status"}), False),
    ("id-wrong-pattern", _doc(_valid_feature(id="F1")), False),
    ("id-not-a-string", _doc(_valid_feature(id=1)), False),
    ("status-unknown", _doc(_valid_feature(status="almost-done")), False),
    ("status-not-a-string", _doc(_valid_feature(status=3)), False),
    ("priority-a-string", _doc(_valid_feature(priority="high")), False),
    ("priority-a-bool", _doc(_valid_feature(priority=True)), False),
    ("scope-a-string", _doc(_valid_feature(scope="src/")), False),
    ("scope-mixed-types", _doc(_valid_feature(scope=["src/", 7])), False),
    ("depends_on-a-string", _doc(_valid_feature(depends_on="F002")), False),
    ("duplicate-ids", _doc(_valid_feature(), _valid_feature()), False),
    ("dangling-depends_on", _doc(_valid_feature(depends_on=["F999"])), False),
    ("coverage-a-bool", _doc(_valid_feature(coverage=True)), False),
    ("envelope-total-negative", {"features": [], "total_features": -1}, False),
    ("envelope-project-not-a-string", {"features": [], "project": 7}, False),
]


def run_validator(rec: Recorder, root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)
    for label, document, accepted in CASES:
        path = root / f"{label}.json"
        path.write_text(json.dumps(document), encoding="utf-8")
        proc = subprocess.run(
            ["python3", str(VALIDATOR), str(path)],
            capture_output=True,
            timeout=60,
        )
        err = proc.stderr.decode("utf-8", "replace")
        rec.add(SUITE, f"validator[{label}] raises no traceback", TRACEBACK not in err, err[-200:])
        rec.add(SUITE, f"validator[{label}] exits 0 or 1", proc.returncode in (0, 1), f"rc={proc.returncode}")
        verdict = "accepts" if accepted else "rejects"
        rec.add(
            SUITE,
            f"validator[{label}] {verdict} the document",
            (proc.returncode == 0) == accepted,
            f"rc={proc.returncode} stderr={err[:160]!r}",
        )
        if not accepted:
            rec.add(
                SUITE,
                f"validator[{label}] explains the rejection",
                "ERROR:" in err,
                err[:160],
            )

    # A document it cannot even read is a failure, not a pass.
    for label, raw in [("truncated", "{ not json"), ("empty-file", ""), ("binary", "\ufffd\x00")]:
        path = root / f"raw-{label}.json"
        path.write_text(raw, encoding="utf-8")
        proc = subprocess.run(["python3", str(VALIDATOR), str(path)], capture_output=True, timeout=60)
        rec.add(SUITE, f"validator[raw-{label}] rejects", proc.returncode != 0, f"rc={proc.returncode}")
        rec.add(
            SUITE,
            f"validator[raw-{label}] raises no traceback",
            TRACEBACK not in proc.stderr.decode("utf-8", "replace"),
        )

    missing = root / "does-not-exist.json"
    proc = subprocess.run(["python3", str(VALIDATOR), str(missing)], capture_output=True, timeout=60)
    rec.add(SUITE, "validator[missing-file] exits non-zero", proc.returncode != 0, f"rc={proc.returncode}")

    # The shipped fixture is the canonical shape every consumer copies.
    proc = subprocess.run(["python3", str(VALIDATOR), str(FIXTURE_FEATURES)], capture_output=True, timeout=60)
    rec.add(
        SUITE,
        "validator accepts the shipped test fixture's features.json",
        proc.returncode == 0,
        proc.stderr.decode("utf-8", "replace")[:200],
    )


def check_schema_agreement(rec: Recorder) -> None:
    """The schema and the validator are two statements of one contract.

    A field required by one and unknown to the other is a silent disagreement:
    a document passes the gate that runs and fails the gate that does not.
    """
    schema = json.loads(SCHEMA.read_text())
    feature_def = schema["$defs"]["feature"]
    schema_required = set(feature_def.get("required") or [])
    schema_known = set((feature_def.get("properties") or {}).keys())

    source = VALIDATOR.read_text(encoding="utf-8")

    def tuple_literal(name: str) -> set:
        match = re.search(rf"^{name} = \(\n(.*?)\n\)", source, re.S | re.M)
        if not match:
            return set()
        return set(re.findall(r'"([^"]+)"', match.group(1)))

    validator_required = tuple_literal("REQUIRED_FEATURE_FIELDS")
    validator_optional = tuple_literal("OPTIONAL_FEATURE_FIELDS")
    validator_known = validator_required | validator_optional

    rec.add(SUITE, "the validator's required-field list was extracted", bool(validator_required))
    rec.add(SUITE, "the validator's optional-field list was extracted", bool(validator_optional))
    rec.add(
        SUITE,
        "schema and validator agree on the required feature fields",
        schema_required == validator_required,
        f"schema-only={sorted(schema_required - validator_required)} "
        f"validator-only={sorted(validator_required - schema_required)}",
    )
    rec.add(
        SUITE,
        "schema and validator agree on the known feature fields",
        schema_known == validator_known,
        f"schema-only={sorted(schema_known - validator_known)} "
        f"validator-only={sorted(validator_known - schema_known)}",
    )


ANSWERS = "project_name=Eval Project\nstack=python\nmode=new\n"


def _stamp(answers: Path, target: Path, timeout=120):
    proc = subprocess.run(
        ["bash", str(STAMP), str(answers), str(target)],
        capture_output=True,
        cwd=str(REPO_ROOT),
        timeout=timeout,
    )
    return proc.returncode, proc.stdout.decode("utf-8", "replace"), proc.stderr.decode("utf-8", "replace")


def _files(root: Path) -> dict:
    out = {}
    for dirpath, _dirs, names in os.walk(root):
        for name in names:
            full = Path(dirpath) / name
            out[os.path.relpath(full, root)] = full.read_bytes()
    return out


def run_stamp(rec: Recorder, root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)
    answers = root / "answers.txt"
    answers.write_text(ANSWERS, encoding="utf-8")

    fresh = root / "fresh"
    fresh.mkdir(parents=True, exist_ok=True)
    rc, out, err = _stamp(answers, fresh)
    rec.add(SUITE, "stamp[new] exits 0 on an empty target", rc == 0, f"rc={rc} {err[-200:]}")
    rec.add(SUITE, "stamp[new] raises no traceback", TRACEBACK not in err, err[-200:])
    produced = _files(fresh)
    for expected in (".harness/harness.json", ".harness/features.json", ".claude/settings.json"):
        rec.add(SUITE, f"stamp[new] writes {expected}", expected in produced, str(sorted(produced)[:8]))
    for name, blob in produced.items():
        if name.endswith(".json"):
            try:
                json.loads(blob.decode("utf-8"))
                ok, detail = True, ""
            except Exception as exc:
                ok, detail = False, str(exc)[:120]
            rec.add(SUITE, f"stamp[new] writes valid JSON at {name}", ok, detail)

    # What it writes must satisfy the contract the validator enforces.
    features = fresh / ".harness" / "features.json"
    if features.is_file():
        proc = subprocess.run(["python3", str(VALIDATOR), str(features)], capture_output=True, timeout=60)
        rec.add(
            SUITE,
            "stamp[new] writes a features.json its own validator accepts",
            proc.returncode == 0,
            proc.stderr.decode("utf-8", "replace")[:200],
        )

    # new mode's promise: refuse a target that already has one of its files,
    # and write nothing at all.
    collided = root / "collided"
    (collided / ".harness").mkdir(parents=True, exist_ok=True)
    (collided / ".harness" / "harness.json").write_text('{"mine": true}', encoding="utf-8")
    before = _files(collided)
    rc, out, err = _stamp(answers, collided)
    after = _files(collided)
    rec.add(SUITE, "stamp[new/collision] exits non-zero", rc != 0, f"rc={rc}")
    rec.add(SUITE, "stamp[new/collision] writes nothing", before == after, str(sorted(set(after) - set(before))[:6]))
    rec.add(
        SUITE,
        "stamp[new/collision] leaves the existing file untouched",
        (collided / ".harness" / "harness.json").read_text() == '{"mine": true}',
    )

    # upgrade mode's promise: a no-op refresh succeeds and changes nothing.
    upgrade_answers = root / "answers-upgrade.txt"
    upgrade_answers.write_text("project_name=Eval Project\nstack=python\nmode=upgrade\n", encoding="utf-8")
    snapshot = _files(fresh)
    rc, out, err = _stamp(upgrade_answers, fresh)
    rec.add(SUITE, "stamp[upgrade] exits 0 on an already-stamped project", rc == 0, f"rc={rc} {err[-200:]}")
    rec.add(SUITE, "stamp[upgrade] is idempotent", _files(fresh) == snapshot,
            str(sorted(k for k in _files(fresh) if _files(fresh).get(k) != snapshot.get(k))[:6]))

    # upgrade must not silently overwrite a customized file.
    customized = fresh / ".claude" / "settings.json"
    if customized.is_file():
        original = json.loads(customized.read_text())
        original["_customization"] = "mine"
        customized.write_text(json.dumps(original, indent=2), encoding="utf-8")
        marker = customized.read_bytes()
        rc, out, err = _stamp(upgrade_answers, fresh)
        rec.add(SUITE, "stamp[upgrade/customized] still exits 0", rc == 0, f"rc={rc}")
        rec.add(
            SUITE,
            "stamp[upgrade/customized] does not overwrite a customized file",
            customized.read_bytes() == marker,
        )

    # Hostile answers are data, never code, and never a way out of the target.
    hostile = root / "answers-hostile.txt"
    hostile.write_text(
        'project_name=$(touch /tmp/vv-eval-pwned) `id` "quoted" \\ backslash\n'
        "stack=python\nmode=new\n",
        encoding="utf-8",
    )
    hostile_target = root / "hostile"
    hostile_target.mkdir(parents=True, exist_ok=True)
    sentinel = Path("/tmp/vv-eval-pwned")
    if sentinel.exists():
        sentinel.unlink()
    rc, out, err = _stamp(hostile, hostile_target)
    rec.add(SUITE, "stamp[hostile-answers] exits 0 or 1", rc in (0, 1), f"rc={rc}")
    rec.add(SUITE, "stamp[hostile-answers] raises no traceback", TRACEBACK not in err, err[-200:])
    rec.add(SUITE, "stamp[hostile-answers] executes nothing from the answers file", not sentinel.exists())
    for name, blob in _files(hostile_target).items():
        if name.endswith(".json"):
            try:
                json.loads(blob.decode("utf-8"))
                ok, detail = True, ""
            except Exception as exc:
                ok, detail = False, str(exc)[:120]
            rec.add(SUITE, f"stamp[hostile-answers] writes valid JSON at {name}", ok, detail)

    # A missing answers file must fail loudly and write nothing.
    empty_target = root / "no-answers"
    empty_target.mkdir(parents=True, exist_ok=True)
    rc, out, err = _stamp(root / "does-not-exist.txt", empty_target)
    rec.add(SUITE, "stamp[missing-answers] exits non-zero", rc != 0, f"rc={rc}")
    rec.add(SUITE, "stamp[missing-answers] writes nothing", not _files(empty_target), str(sorted(_files(empty_target))[:6]))


def run(rec: Recorder, root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)
    run_validator(rec, root / "validator")
    check_schema_agreement(rec)
    run_stamp(rec, root / "stamp")
