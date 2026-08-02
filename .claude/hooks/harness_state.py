#!/usr/bin/env python3
import fcntl
import json
import os
import sys
import time

CLAIMABLE_STATUSES = ("pending", "failed")
LOCK_TIMEOUT_SECONDS = 5
LOCK_POLL_SECONDS = 0.05


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


def _with_file_lock(path, fn):
    """Acquire an exclusive, cross-process lock on path + '.lock' (bounded wait up
    to LOCK_TIMEOUT_SECONDS), then call fn() while holding it. Returns fn()'s
    return value, or None if the lock could not be acquired -- callers must
    treat None as "fn did not run", never as a successful no-op.

    The lock file is never unlinked: unlinking a lockfile after release is a
    known race (a waiter can hold a live fd's lock on an inode that a
    concurrent process has already unlinked and replaced at the same path, so
    two processes end up believing they each hold the lock). The same lock
    file persists for the project's lifetime instead -- harmless, and
    gitignored the same way SESSION_INCOMPLETE is."""
    lock_path = path + ".lock"
    try:
        lock_fh = open(lock_path, "a+")
    except OSError as exc:
        print(f"harness_state: could not open lock file {lock_path}: {exc}", file=sys.stderr)
        return None
    deadline = time.time() + LOCK_TIMEOUT_SECONDS
    acquired = False
    try:
        while True:
            try:
                fcntl.flock(lock_fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
                acquired = True
                break
            except OSError:
                if time.time() >= deadline:
                    break
                time.sleep(LOCK_POLL_SECONDS)
        if not acquired:
            print(f"harness_state: timed out waiting for lock on {lock_path}", file=sys.stderr)
            return None
        return fn()
    finally:
        if acquired:
            fcntl.flock(lock_fh, fcntl.LOCK_UN)
        lock_fh.close()


def _write_atomic(path, data):
    """Write data to path via a uniquely-named tmp file (PID-suffixed, so two
    concurrent writers can never collide on or delete each other's in-flight
    file) and an atomic os.replace. Caller must hold the file lock -- this
    function only makes the WRITE atomic, not the read-modify-write around
    it."""
    tmp_path = f"{path}.{os.getpid()}.tmp"
    try:
        with open(tmp_path, "w") as fh:
            json.dump(data, fh, indent=2)
            fh.write("\n")
        os.replace(tmp_path, path)
    except OSError as exc:
        print(f"harness_state: could not write {path}: {exc}", file=sys.stderr)
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
    def do_increment():
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
        return 0 if _write_atomic(path, data) else 1

    # The read, the mutation, and the write all happen inside do_increment,
    # which only runs while the lock is held -- this is what makes the whole
    # read-modify-write a single critical section instead of a read outside
    # the lock followed by a write inside it.
    result = _with_file_lock(path, do_increment)
    return 1 if result is None else result


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
