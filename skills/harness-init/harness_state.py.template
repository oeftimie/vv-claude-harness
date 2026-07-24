#!/usr/bin/env python3
import json
import os
import sys

CLAIMABLE_STATUSES = ("pending", "failed")


def load_valid_features(path):
    try:
        with open(path) as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        print(f"harness_state: cannot parse {path}: {exc}", file=sys.stderr)
        return []
    features = data.get("features", []) if isinstance(data, dict) else []
    valid = []
    for entry in features:
        try:
            entry.get("status")
        except AttributeError:
            print(f"harness_state: skipping malformed feature entry: {entry!r}", file=sys.stderr)
            continue
        valid.append(entry)
    return valid


def compute_claimable(valid):
    passing_ids = {f.get("id") for f in valid if f.get("status") == "passing"}
    claimable = []
    for f in valid:
        try:
            deps_ok = all(dep in passing_ids for dep in f.get("depends_on") or [])
        except TypeError as exc:
            print(
                f"harness_state: skipping malformed feature entry {f.get('id')!r}: {exc}",
                file=sys.stderr,
            )
            continue
        if f.get("status") in CLAIMABLE_STATUSES and deps_ok:
            claimable.append(f)
    return claimable


def write_atomic_tmp(path, data):
    tmp_path = path + ".tmp"
    try:
        os.remove(tmp_path)
    except OSError:
        pass
    try:
        with open(tmp_path, "w") as fh:
            json.dump(data, fh, indent=2)
            fh.write("\n")
    except OSError as exc:
        print(f"harness_state: could not write {tmp_path}: {exc}", file=sys.stderr)
        try:
            os.remove(tmp_path)
        except OSError:
            pass
        return False
    return True


def cmd_load(path):
    print(json.dumps(load_valid_features(path)))
    return 0


def cmd_next_claimable(path):
    claimable = compute_claimable(load_valid_features(path))
    if not claimable:
        print("no claimable feature")
        return 0
    claimable.sort(key=lambda f: f.get("priority", 999))
    print(json.dumps({"count": len(claimable), "next": claimable[0]}))
    return 0


def cmd_counts(path):
    valid = load_valid_features(path)
    passing = sum(1 for f in valid if f.get("status") == "passing")
    in_progress = [f.get("id") for f in valid if f.get("status") == "in-progress"]
    print(json.dumps({"passing": passing, "total": len(valid), "in_progress": in_progress}))
    return 0


def cmd_increment_correction_cycles(path, feature_id):
    try:
        with open(path) as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        print(f"harness_state: cannot parse {path}: {exc}", file=sys.stderr)
        return 1
    features = data.get("features", []) if isinstance(data, dict) else []
    match = next(
        (f for f in features if isinstance(f, dict) and f.get("id") == feature_id), None
    )
    if match is None:
        print(f"harness_state: no feature with id {feature_id!r}", file=sys.stderr)
        return 3
    if match.get("status") != "in-progress":
        return 0
    current = match.get("correction_cycles")
    match["correction_cycles"] = (current if current is not None else 0) + 1
    return 0 if write_atomic_tmp(path, data) else 1


USAGE = (
    "usage: harness_state.py <load|next-claimable|counts|increment-correction-cycles> "
    "<features.json> [feature_id]"
)


def main(argv):
    if len(argv) < 3:
        print(USAGE, file=sys.stderr)
        return 2
    verb, path = argv[1], argv[2]
    if verb == "load":
        return cmd_load(path)
    if verb == "next-claimable":
        return cmd_next_claimable(path)
    if verb == "counts":
        return cmd_counts(path)
    if verb == "increment-correction-cycles":
        if len(argv) < 4:
            print(USAGE, file=sys.stderr)
            return 2
        return cmd_increment_correction_cycles(path, argv[3])
    print(f"harness_state: unknown verb {verb!r}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
