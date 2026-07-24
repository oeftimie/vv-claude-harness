#!/usr/bin/env python3
import json
import re
import sys
from datetime import datetime

FEATURE_ID_RE = re.compile(r"^F[0-9]{3}$")
STATUS_VALUES = {"pending", "in-progress", "blocked", "passing", "failed"}
SPEC_VERDICTS = (None, "PASS", "ASK", "BLOCK")
EVIDENCE_TYPES = ("unit", "integration", "journey", "manual", "corpus", "conformance")
PROOF_SUBFIELDS = ("claim", "artifact", "not_established")

REQUIRED_FEATURE_FIELDS = (
    "id", "description", "priority", "status", "scope",
    "depends_on", "assigned_to", "test_file", "coverage", "notes",
)
OPTIONAL_FEATURE_FIELDS = (
    "correction_cycles", "scope_expansions", "approaches_tried",
    "failure_reason", "discovered_via", "spec",
    "qa_binding", "proof", "coverage_target", "delivered", "design_contract",
)
KNOWN_FEATURE_FIELDS = set(REQUIRED_FEATURE_FIELDS) | set(OPTIONAL_FEATURE_FIELDS)


def is_plain_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def is_string_array(value):
    return isinstance(value, list) and all(isinstance(v, str) for v in value)


def check_id(feature, index, errors):
    value = feature.get("id")
    if not isinstance(value, str) or not FEATURE_ID_RE.match(value):
        errors.append(f"features[{index}].id: invalid value {value!r}, expected pattern F###")


def check_description(feature, index, errors):
    value = feature.get("description")
    if not isinstance(value, str) or not value:
        errors.append(f"features[{index}].description: must be a non-empty string")


def check_priority(feature, index, errors):
    value = feature.get("priority")
    if not is_plain_int(value) or value < 1:
        errors.append(f"features[{index}].priority: must be an integer >= 1, got {value!r}")


def check_status(feature, index, errors):
    value = feature.get("status")
    if value not in STATUS_VALUES:
        errors.append(f"features[{index}].status: invalid value {value!r}")


def check_scope(feature, index, errors):
    if not is_string_array(feature.get("scope")):
        errors.append(f"features[{index}].scope: must be an array of strings")


def check_depends_on(feature, index, errors):
    if not is_string_array(feature.get("depends_on")):
        errors.append(f"features[{index}].depends_on: must be an array of strings")


def make_nullable_string_check(field):
    def check(feature, index, errors):
        value = feature.get(field)
        if value is not None and not isinstance(value, str):
            errors.append(f"features[{index}].{field}: must be a string or null")
    return check


def check_coverage(feature, index, errors):
    value = feature.get("coverage")
    if value is None or isinstance(value, str):
        return
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        errors.append(f"features[{index}].coverage: must be a number, string, or null")


def make_optional_int_check(field):
    def check(feature, index, errors):
        if field not in feature:
            return
        value = feature[field]
        if not is_plain_int(value) or value < 0:
            errors.append(f"features[{index}].{field}: must be an integer >= 0, got {value!r}")
    return check


def make_optional_array_check(field):
    def check(feature, index, errors):
        if field in feature and not is_string_array(feature[field]):
            errors.append(f"features[{index}].{field}: must be an array of strings")
    return check


def make_optional_nullable_string_check(field):
    inner = make_nullable_string_check(field)

    def check(feature, index, errors):
        if field in feature:
            inner(feature, index, errors)
    return check


def check_spec(feature, index, errors):
    if "spec" not in feature or feature["spec"] is None:
        return
    value = feature["spec"]
    if not isinstance(value, dict):
        errors.append(f"features[{index}].spec: must be an object or null")
        return
    if value.get("verdict") not in SPEC_VERDICTS:
        errors.append(f"features[{index}].spec.verdict: invalid value {value.get('verdict')!r}")


def check_qa_binding(feature, index, errors):
    if "qa_binding" not in feature or feature["qa_binding"] is None:
        return
    value = feature["qa_binding"]
    if value not in EVIDENCE_TYPES:
        errors.append(f"features[{index}].qa_binding: invalid value {value!r}")


def check_proof(feature, index, errors):
    if "proof" not in feature or feature["proof"] is None:
        return
    value = feature["proof"]
    if not isinstance(value, dict):
        errors.append(f"features[{index}].proof: must be an object or null")
        return
    for key in PROOF_SUBFIELDS:
        sub = value.get(key)
        if not isinstance(sub, str) or not sub:
            errors.append(f"features[{index}].proof.{key}: must be a non-empty string")
    evidence_type = value.get("evidence_type")
    if evidence_type not in EVIDENCE_TYPES:
        errors.append(f"features[{index}].proof.evidence_type: invalid value {evidence_type!r}")


def check_coverage_target(feature, index, errors):
    if "coverage_target" not in feature or feature["coverage_target"] is None:
        return
    value = feature["coverage_target"]
    if not is_plain_int(value) or value < 1 or value > 100:
        errors.append(f"features[{index}].coverage_target: must be an integer 1-100, got {value!r}")


def is_iso8601(value):
    if not isinstance(value, str):
        return False
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return False
    return True


def check_delivered(feature, index, errors):
    if "delivered" not in feature or feature["delivered"] is None:
        return
    value = feature["delivered"]
    if not isinstance(value, dict):
        errors.append(f"features[{index}].delivered: must be an object or null")
        return
    if "merged_at" in value and not is_iso8601(value["merged_at"]):
        errors.append(
            f"features[{index}].delivered.merged_at: invalid ISO8601 value "
            f"{value.get('merged_at')!r}"
        )


def check_design_contract(feature, index, errors):
    if "design_contract" not in feature or feature["design_contract"] is None:
        return
    if not isinstance(feature["design_contract"], str):
        errors.append(f"features[{index}].design_contract: must be a string or null")


REQUIRED_CHECKS = {
    "id": check_id,
    "description": check_description,
    "priority": check_priority,
    "status": check_status,
    "scope": check_scope,
    "depends_on": check_depends_on,
    "assigned_to": make_nullable_string_check("assigned_to"),
    "test_file": make_nullable_string_check("test_file"),
    "notes": make_nullable_string_check("notes"),
    "coverage": check_coverage,
}

OPTIONAL_CHECKS = {
    "correction_cycles": make_optional_int_check("correction_cycles"),
    "scope_expansions": make_optional_array_check("scope_expansions"),
    "approaches_tried": make_optional_array_check("approaches_tried"),
    "failure_reason": make_optional_nullable_string_check("failure_reason"),
    "discovered_via": make_optional_nullable_string_check("discovered_via"),
    "spec": check_spec,
    "qa_binding": check_qa_binding,
    "proof": check_proof,
    "coverage_target": check_coverage_target,
    "delivered": check_delivered,
    "design_contract": check_design_contract,
}


def check_required_fields(feature, index, errors):
    for field in REQUIRED_FEATURE_FIELDS:
        if field not in feature:
            errors.append(f"features[{index}]: missing required field '{field}'")


def check_unknown_fields(feature, index, warnings):
    for field in feature:
        if field not in KNOWN_FEATURE_FIELDS:
            warnings.append(f"features[{index}]: unknown field '{field}' (warning, ignored)")


def validate_feature(feature, index, errors, warnings):
    if not isinstance(feature, dict):
        errors.append(f"features[{index}]: must be an object")
        return
    check_required_fields(feature, index, errors)
    for field, check in REQUIRED_CHECKS.items():
        if field in feature:
            check(feature, index, errors)
    for check in OPTIONAL_CHECKS.values():
        check(feature, index, errors)
    check_unknown_fields(feature, index, warnings)


def check_duplicate_ids(features, errors):
    seen = {}
    for index, feature in enumerate(features):
        fid = feature.get("id") if isinstance(feature, dict) else None
        if not isinstance(fid, str):
            continue
        if fid in seen:
            errors.append(
                f"features[{index}].id: duplicate id '{fid}' "
                f"(first seen at features[{seen[fid]}])"
            )
        else:
            seen[fid] = index
    return set(seen)


def check_dangling_depends_on(features, known_ids, errors):
    for index, feature in enumerate(features):
        if not isinstance(feature, dict):
            continue
        for dep_index, dep in enumerate(feature.get("depends_on") or []):
            if isinstance(dep, str) and dep not in known_ids:
                errors.append(
                    f"features[{index}].depends_on[{dep_index}]: unknown feature id '{dep}'"
                )


def check_envelope(data, errors):
    if not isinstance(data, dict):
        errors.append("<root>: must be a JSON object")
        return False
    if not isinstance(data.get("features"), list):
        errors.append("features: must be an array")
        return False
    for field in ("project", "created"):
        if field in data and not isinstance(data[field], str):
            errors.append(f"{field}: must be a string")
    for field in ("total_features", "passing"):
        if field in data and (not is_plain_int(data[field]) or data[field] < 0):
            errors.append(f"{field}: must be an integer >= 0")
    return True


def validate(data):
    errors = []
    warnings = []
    if not check_envelope(data, errors):
        return errors, warnings
    features = data["features"]
    for index, feature in enumerate(features):
        validate_feature(feature, index, errors, warnings)
    known_ids = check_duplicate_ids(features, errors)
    check_dangling_depends_on(features, known_ids, errors)
    return errors, warnings


def main(argv):
    path = argv[1] if len(argv) > 1 else ".harness/features.json"
    try:
        with open(path) as fh:
            data = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"{path}: {exc}", file=sys.stderr)
        return 1
    errors, warnings = validate(data)
    for warning in warnings:
        print(f"WARNING: {warning}", file=sys.stderr)
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
