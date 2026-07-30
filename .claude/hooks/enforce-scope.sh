#!/bin/bash
# VV Claude Code Harness - PreToolUse scope enforcement hook
# Runs before Edit/Write/MultiEdit tool calls (scope enforcement) and before Bash tool
# calls (best-effort write-boundary coverage) when a teammate scope file exists.
# The pre-existing out-of-scope Edit/Write check below is a legacy path: it blocks by
# exiting 2, unchanged since before state ownership + Bash coverage were added. The two
# denial paths added for that feature -- lead-owned state files, and Bash write
# commands -- use the hookSpecificOutput.permissionDecision:"deny" JSON form (exit 0)
# instead, per cross-harness reconciliation (OVI-51).
# Failure posture: fail-open for ENVIRONMENT failures, fail-closed for per-segment
# ANALYSIS failures (F042). If PROJECT_ROOT can't be resolved, the scope file is
# unreadable, or the tool-input JSON can't be parsed, the action is ALLOWED, not
# blocked. Residual: a broken environment silently disables enforcement rather than
# blocking everything. Bash coverage is pattern-based and evadable by construction
# (compound commands, command substitution/subshells, and a write hidden inside a
# heredoc body fed to a nested interpreter are known false-negative surfaces) --
# the goal is stopping accidental drift, not defeating an adversarial teammate.
# Once a segment's own analysis begins, though, an exception anywhere in it (a
# decoder crash, or anything else _check_segment() can't handle) denies that
# segment unconditionally instead -- see main()'s own comment for why. The same
# split applies one layer up, at the FILE_PATH/COMMAND extraction near the top of
# this file (F043): the JSON itself failing to parse stays fail-open, but anything
# that goes wrong AFTER a successful parse (a raw surrogate crashing the final
# print(), or any other unexpected shape) fails closed instead.
# Straightforward single/double/ANSI-C quoting of a separator or a write target is
# handled (see mask_quotes()/unquote_token()); nested or otherwise unusual quoting
# is not attempted. Known false-positive residual: redirect-target extraction
# matches every >/>> on the line, so a bare comparison like [[ "$v" > "1.0" ]]
# (no real redirect) can still be mistaken for one even with quotes correctly
# preserved and stripped from the captured group -- the regex has no way to tell
# a real redirect from a test-bracket comparison operator; distinguishing them
# would need real shell parsing, judged disproportionate for this hook. Since
# write_targets() now checks every target it finds (F024) and denies on the
# FIRST out-of-scope one, a bogus match like this can deny a command before a
# real, later, genuinely in-scope redirect is ever reached -- broader than
# when only the last match was checked, but still the same underlying
# trade-off, not a new one.
# write_targets()/redirect_targets() return EVERY write target in a segment,
# not just one: a command with multiple real write targets (`rm a b`, `tee`
# or `sed -i` given two files, multiple redirects like `> f1 2> f2`, or a
# real write command followed by an unrelated trailing redirect like
# `tee f1 > f2`) is checked against ALL of them, not just whichever one an
# earlier version happened to find first -- an out-of-scope target elsewhere
# in the segment went uncaught otherwise (found by adversarial review of PR
# #42/F023 and PR #46, reported as F024). `cp -t DIR`/`-tDIR`/`mv -t DIR` and
# `--target-directory=DIR` (GNU-only; not present on BSD/macOS cp) put the
# real destination in a flag argument instead of the last positional one;
# cp_mv_targets() recognizes all three forms, treating every other flagless
# argument as a source (read, not written) once any is present -- clustered
# short flags (`-rt DIR`, combining -r and -t) are not recognized, a
# documented residual. `--` as a pathspec separator (e.g. `rm -- -a.txt`,
# where -a.txt is a real filename, not a flag) is recognized by
# all_flagless_tokens()/last_flagless_token() the same way commit-gate.sh
# .template's has_staging_flag() handles the same shape (F029): the first
# "--" ends flag parsing, so every later token is kept as a real pathspec
# even if it starts with "-". cp_mv_targets()'s own -t/--target-directory=
# scan and sed_inplace_targets()'s flag-detection (including its two
# any()-based guards, not just its token-walking loop) are "--"-aware the
# same way (F029 rounds 2-3).
# normalize()/FILE_PATH resolve "."/".." path traversal (F026). A backslash-
# escaped traversal segment (`\..`) is also resolved (F031): unquote_token()
# strips shell backslash-escapes, not just quote characters, before
# normalize() ever sees the token. One related gap remains, documented in
# full where the code lives (normalize()'s own comment): the resolution is
# purely lexical, so a symlink inside a scope directory can make the real
# write land somewhere normpath can't see.
# verified live 2026-07-24 on Claude Code 2.1.218

# Read hook input from stdin
INPUT=$(cat)

# Anchor to the project root so the hook works from any working directory
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$PROJECT_ROOT" 2>/dev/null || exit 0

# Only enforce if a scope file exists. In practice this is teammates only (the
# lead's own session has no scope file of its own to spawn WITH) -- but this
# check has no actual session-awareness: it's a single shared file's existence,
# checked identically regardless of who is asking. While ANY teammate's scope
# file exists, the LEAD's own actions are gated by it too (confirmed live
# during F060's review: the lead's own reassignment-rewrite and teardown-delete
# of this very file are denied while a team is active) -- see F061.
SCOPE_FILE=".claude/teammate-scope.txt"
if [ ! -f "$SCOPE_FILE" ]; then
    exit 0
fi

ANNOTATION="(verified live 2026-07-24 on Claude Code 2.1.218)"

deny_json() {
    python3 - "$1" <<'PYEOF'
import json
import sys

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": sys.argv[1],
    }
}))
PYEOF
    exit 0
}

# Extract file path (Edit/Write/MultiEdit) and command (Bash) from tool input.
# FILE_PATH is normalized here (project-root prefix stripped, then "."/".."
# segments resolved) rather than with plain bash substring stripping, so a
# traversal that escapes scope (`src/parser/../other/y.py`) or reaches a
# lead-owned file (`src/parser/../../.harness/features.json`) can't survive
# as a string that merely STARTS WITH the allowed prefix or fails the
# lead-owned exact-match -- this is the SAME bug normalize() (used by the
# Bash-command path below) had, in the MORE authoritative gate (Edit/Write/
# MultiEdit tool calls are blocked outright; Bash coverage is only best-
# effort). Unlike normalize(), no trailing-"/" restore is needed here: an
# Edit/Write/MultiEdit file_path is always a file, never a directory, so
# there's no directory-style scope-pattern case to preserve -- confirmed
# dead code by mutation-testing (removing it changed zero assertions),
# consistent with this project's "no error handling for impossible states"
# standard (found by adversarial review of PR #48, F026 round 2). Literal
# `path.startswith(...)` (not a bash glob pattern) also means a project
# root containing shell metacharacters (e.g. "root[1]") can't break this
# the way the OLD bash-side `${FILE_PATH#$PROJECT_ROOT/}` could (unquoted
# $PROJECT_ROOT in pattern position; a documented, unadvertised side
# benefit found in the same round).
FILE_PATH=$(echo "$INPUT" | python3 -c "
import json, os, sys
# The JSON parse itself is in its OWN try/except, exiting 2 on failure:
# a genuinely unparseable tool-input document is this file's own
# documented fail-open contract (see the header), and rc 2 tells the
# caller to leave that behavior alone. Everything AFTER a successful
# parse -- extracting the field, normalizing it, and printing it -- is a
# SEPARATE try/except that exits 1 instead (F043): a raw lone UTF-16
# surrogate (0xD800-0xDFFF) arriving directly in the input JSON (e.g.
# {\"tool_input\":{\"file_path\":\"src/other/\ud800pwned.txt\"}}) is
# perfectly valid JSON -- json.load() decodes its \uD800 escape into a
# real Python str containing a lone surrogate with no error at all -- but
# crashes the FINAL print(path) with UnicodeEncodeError once stdout isn't
# a tty (confirmed live: identical code succeeds interactively, raises
# under \$(...) capture). The 2>/dev/null on this whole command
# substitution swallowed that traceback, FILE_PATH came back empty, and
# the caller's own \"if [ -n \\\"\$FILE_PATH\\\" ]\" then skipped the
# ENTIRE Edit/Write scope check -- silently allowing what should have
# gone through this file's own AUTHORITATIVE gate (Edit/Write/MultiEdit
# calls are blocked outright, not best-effort like the Bash coverage path
# F038 already patches for its own \$'...' decoder). Two distinct exit
# codes (not 'any nonzero') are required here: an uncaught exception's
# default exit code is 1 regardless of which try/except raised it, so a
# single except-and-exit(1) around BOTH stages would make a genuinely
# unparseable document fail closed too, silently reversing this file's
# own documented environment-failure contract -- rc 2 vs rc 1 is what
# lets the caller (below) tell 'can't parse at all, stay fail-open' apart
# from 'parsed fine, but unsafe to process further, fail closed'.
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(2)
try:
    path = data.get('tool_input', {}).get('file_path', '')
    project_root = sys.argv[1]
    if path:
        if path.startswith(project_root + '/'):
            path = path[len(project_root) + 1:]
        path = os.path.normpath(path)
    print(path)
except Exception:
    sys.exit(1)
" "$PROJECT_ROOT" 2>/dev/null)
FILE_PATH_RC=$?
if [ "$FILE_PATH_RC" -eq 1 ]; then
    # Claude Code discards a hook's stdout entirely on exit 2 and feeds only
    # stderr back to the blocked agent as its error message
    # (code.claude.com/docs/en/hooks) -- this legacy exit-2 site (unlike
    # deny_json()'s own JSON-on-stdout-at-exit-0 path used elsewhere in this
    # file) still wrote its message to stdout, silently discarding it on
    # every real PreToolUse block (F053, the identical defect F046 fixed in
    # check-remaining-tasks.sh.template).
    echo "Edit blocked: file_path could not be safely extracted from tool input (treating as outside your assigned scope). $ANNOTATION" >&2
    exit 2
fi

COMMAND=$(echo "$INPUT" | python3 -c "
import json, sys
# Same two-stage split as FILE_PATH above, and for the same reason: a
# crash AFTER a successful JSON parse -- the identical raw-surrogate
# print() crash, reachable here via tool_input.command instead of
# file_path -- fails closed (rc 1), while a genuinely unparseable
# document stays fail-open (rc 2) (F043).
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(2)
try:
    print(data.get('tool_input', {}).get('command', ''))
except Exception:
    sys.exit(1)
" 2>/dev/null)
COMMAND_RC=$?
if [ "$COMMAND_RC" -eq 1 ]; then
    deny_json "command could not be safely extracted from tool input (best-effort, pattern-based check; treating as outside your assigned scope). $ANNOTATION"
fi

if [ -n "$FILE_PATH" ]; then
    case "$FILE_PATH" in
        # .harness/harness.json added by F058: it was NOT lead-owned before this --
        # only protected by the ordinary scope check below, so a teammate scoped to
        # .harness/ (or to harness.json specifically) could edit it directly like any
        # other assigned file (confirmed live before this fix: both a Write and a Bash
        # redirect to it returned ALLOW under a .harness/ scope, unlike features.json's
        # genuine denial). harness.json holds git identity config, prep/stamp config,
        # and (as of F054) commit-gate.sh's secret-scan exemption list -- security-
        # relevant configuration a scoped teammate shouldn't be able to edit
        # unilaterally the way it edits its own assigned source files (F058).
        .harness/features.json|.harness/context_summary.md|.harness/claude-progress.txt|.harness/harness.json)
            deny_json "state file is lead-owned; report via SendMessage instead. $ANNOTATION"
            ;;
        # .claude/teammate-scope.txt added by F060: confirmed live (review-pr91-f058)
        # that a teammate scoped to .claude/ could edit its OWN scope definition
        # directly -- a strictly larger hole than F058's harness.json gap, since the
        # edit takes effect on the teammate's very next tool call in the same
        # session. Deliberately NOT extended to .claude/hooks/*.sh (the enforcement
        # hooks themselves): per rules/agent-teams-protocol.md, this file is
        # created/rewritten by the LEAD per spawn/reassignment, so a teammate never
        # legitimately needs to touch it regardless of what it's assigned -- unlike
        # the hooks, which a teammate explicitly scoped to .claude/hooks/ can be
        # legitimately assigned to modify (this repo's own sweep does exactly that
        # routinely). Protecting only the scope-definition file, not the whole
        # .claude/ directory or the hooks, closes the MOST DIRECT self-widening
        # route without blocking real hook-development work -- two others remain
        # deliberately open: a teammate scoped to .claude/ can still rewrite
        # .claude/hooks/enforce-scope.sh itself, or edit .claude/settings.json to
        # remove the hook wiring outright, disarming enforcement entirely. Both
        # residuals are accepted for the same reason (a teammate can be
        # legitimately assigned that scope), not fixed here (F060).
        .claude/teammate-scope.txt)
            deny_json "teammate-scope.txt is lead-owned; report via SendMessage instead. $ANNOTATION"
            ;;
    esac

    # Legacy path (unchanged): check if file path matches any scope pattern
    while IFS= read -r pattern || [ -n "$pattern" ]; do
        # Skip empty lines and comments
        [[ -z "$pattern" || "$pattern" =~ ^# ]] && continue
        # Use bash pattern matching
        if [[ "$FILE_PATH" == $pattern* ]]; then
            exit 0
        fi
    done < "$SCOPE_FILE"

    # F053: same stdout-discard-on-exit-2 defect as above -- every line of
    # this denial (including the scope-file dump) must reach stderr, or a
    # scoped teammate blocked from an out-of-scope edit sees nothing at all.
    echo "Edit blocked: $FILE_PATH is outside your assigned scope." >&2
    echo "Your scope (from $SCOPE_FILE):" >&2
    cat "$SCOPE_FILE" | grep -v '^#' | grep -v '^$' >&2
    echo "" >&2
    echo "Repair: request a scope expansion from the lead: SendMessage({ type: \"message\", recipient: \"team-lead\", content: \"Requesting scope expansion to $FILE_PATH because [reason].\" })" >&2
    exit 2
fi

if [ -n "$COMMAND" ]; then
    SCOPE_PATTERNS=()
    while IFS= read -r pattern || [ -n "$pattern" ]; do
        [[ -z "$pattern" || "$pattern" =~ ^# ]] && continue
        SCOPE_PATTERNS+=("$pattern")
    done < "$SCOPE_FILE"

    DENY_REASON=$(python3 - "$COMMAND" "$PROJECT_ROOT" "${SCOPE_PATTERNS[@]}" <<'PYEOF'
import os
import re
import sys

LEAD_OWNED = {
    ".harness/features.json",
    ".harness/context_summary.md",
    ".harness/claude-progress.txt",
    # Added by F058 -- see the mirrored Edit/Write case statement above for the
    # full rationale (git identity, prep/stamp config, and the F054 secret-scan
    # exemption list are all security-relevant configuration this file holds).
    ".harness/harness.json",
    # Added by F060 -- see the mirrored Edit/Write case statement above for the
    # full rationale (a teammate's own scope definition; the lead is its only
    # legitimate writer, deliberately narrower than protecting .claude/hooks/*.sh
    # too, which a teammate can be legitimately assigned to work on).
    ".claude/teammate-scope.txt",
}
ANNOTATION = "(verified live 2026-07-24 on Claude Code 2.1.218)"

# A narrow, enumerated allowlist of ordinary character-device sinks (never
# part of the project tree, so a write to one of these is never a real scope
# violation) -- deliberately NOT the whole /dev/* namespace. An earlier
# version of this exemption matched any path starting with "/dev/", which
# also silently allowed /dev/shm/* (a real writable tmpfs on Linux, where
# this template runs in CI) and bash's /dev/tcp/HOST/PORT network-redirect
# extension (confirmed live: bash attempts a real TCP connect for this path,
# not a "no such file" error -- a live egress channel, not a device node) --
# found by adversarial review of PR #53, round 1. /dev/fd/N (bash's
# process-substitution/fd-as-path idiom) is matched by pattern, not the
# fixed set, since N is unbounded.
DEV_EXEMPT_EXACT = {"/dev/null", "/dev/zero", "/dev/stdout", "/dev/stderr", "/dev/tty"}
DEV_FD_PATTERN = re.compile(r"^/dev/fd/\d+$")


def is_dev_exempt(norm):
    return norm in DEV_EXEMPT_EXACT or DEV_FD_PATTERN.match(norm) is not None


def strip_heredoc_bodies(command):
    # Heredoc bodies are excluded from matching entirely (not split, not scanned)
    # so payload text can never trigger a false denial.
    lines = command.split("\n")
    kept = []
    in_heredoc = False
    strip_tabs = False
    marker = None
    for line in lines:
        if in_heredoc:
            check = line.lstrip("\t") if strip_tabs else line
            if check == marker:
                in_heredoc = False
            continue
        kept.append(line)
        m = re.search(r"<<(-?)\s*(['\"]?)(\w+)\2", line)
        if m:
            strip_tabs = bool(m.group(1))
            marker = m.group(3)
            in_heredoc = True
    return "\n".join(kept)


def join_continuations(command):
    # Joins a backslash-newline shell continuation to a space, but only when
    # the backslash immediately before the newline is itself unescaped: an
    # ODD run of backslashes right before a newline means the last one
    # escapes the newline (a real continuation); an EVEN run (including
    # zero) means the newline is a real command separator and the
    # backslashes are literal characters, which must be left alone. Ported
    # from commit-gate.sh.template (F011/OVI-64, round 6), which needed this
    # as soon as it started splitting on a literal newline -- without it, a
    # continued command like `sed \` + newline + `-i 's/a/b/' file` splits
    # into two fragments, neither of which alone carries the `-i` flag next
    # to `sed`, so sed_inplace_targets() never recognizes it (found by
    # adversarial review of PR #42, F023 round 1).
    def repl(m):
        backslashes = m.group(1)
        if len(backslashes) % 2 == 1:
            return backslashes[:-1] + " "
        return backslashes + "\n"

    return re.sub(r"(\\*)\n", repl, command)


QUOTE_SPAN_PATTERN = re.compile(r"\$'(?:[^'\\]|\\.)*'|'[^']*'|\"(?:[^\"\\]|\\.)*\"")


def mask_quotes(command):
    # Replaces each quoted span (single, double, ANSI-C $'...') with a same-
    # LENGTH run of NUL placeholder characters -- never a real separator or
    # target character -- so that a real "&"/"|"/";" INSIDE a quoted string
    # (sed's 's/foo/[&]/' whole-match idiom, a filename like "a & b.txt")
    # doesn't get mistaken for a shell control operator when segments_of()
    # below scans this masked copy for split positions. Unlike deleting the
    # quoted span (an earlier version of this fix did that, via a function
    # named strip_quotes, ported from commit-gate.sh.template verbatim),
    # preserving length means split positions found in the masked copy line
    # up character-for-character with the ORIGINAL command, so segments_of()
    # can slice the real, still-quoted text for each segment -- the quoted
    # write target itself must survive segmentation intact, unlike in
    # commit-gate.sh where quotes only ever wrap non-target text (a commit
    # message) and erasing them is harmless. Deleting the span instead of
    # masking it erased the write target whenever it was quoted at all
    # (`echo x > "src/forbidden/a.txt"`, `rm "src/forbidden/a.txt"`, and the
    # lead-owned-state-file guard the same way) -- a much bigger bypass than
    # the one this hook exists to close, since quoting a path is the
    # ordinary way to write one, not an adversarial evasion (found by
    # adversarial review of PR #42, F023 round 2).
    def repl(m):
        return "\0" * len(m.group(0))

    return QUOTE_SPAN_PATTERN.sub(repl, command)


ANSI_C_SIMPLE_ESCAPES = {
    "\\": "\\", "'": "'", '"': '"',
    "a": "\a", "b": "\b", "e": "\x1b", "f": "\f",
    "n": "\n", "r": "\r", "t": "\t", "v": "\v",
}
ANSI_C_ESCAPE_PATTERN = re.compile(
    r"\\(?:x([0-9A-Fa-f]{1,2})|([0-7]{1,3})|c(.)"
    r"|u([0-9A-Fa-f]{1,4})|U([0-9A-Fa-f]{1,8})|(.))"
)


def _decode_ansi_c_escape(m):
    # One match alternative fires per call, per ANSI_C_ESCAPE_PATTERN's own
    # six groups (hex, octal, control-char, 4-hex Unicode, 8-hex Unicode,
    # single-char) -- verified against real bash 3.2.57 (`printf '%s'
    # $'a\x2eb'`, `$'a\056b'`, `$'a\eb'`, `$'a\qb'`, `$'a\8b'`, `$'a\xzb'`):
    # \xHH (1-2 hex digits, case-insensitive) and \nnn (1-3 octal digits)
    # decode to that byte; \\, \', \", \a, \b, \e, \f, \n, \r, \t, \v
    # decode to their usual meaning; any OTHER backslash escape (including
    # \8/\9, not valid octal, and \x with no hex digit following) is left
    # as a literal backslash followed by that character, UNCHANGED -- bash
    # does not drop the backslash for an escape it doesn't recognize
    # inside $'...'. \cX/\uHHHH/\UHHHHHHHH (F038) were a documented,
    # unverified-in-this-environment residual until now: this repo's bash
    # 3.2.57 does not decode \u/\U at all (confirmed: `$'a.b'` prints
    # literally, backslash intact), so the traversal risk was inert on
    # THIS machine specifically -- but installing bash 5.3.15 via Homebrew
    # to check directly (rather than leaving it "believed added around
    # bash 4.2, unverified") confirmed ./\U0000002e both genuinely
    # decode to "." on any bash new enough, a live, not merely theoretical,
    # bypass class identical to F033's own. \cX decodes on BOTH bash
    # versions already (found by adversarial review of PR #57), using
    # `ord(X.upper()) & 0x1F` -- verified against 10+ characters spanning
    # letters, digits, and punctuation on BOTH bash versions (bash's real
    # formula masks to the low 5 bits; a naive "XOR 0x40" convention some
    # documentation implies gives the WRONG byte for digits/`~`/`{`/`|`/
    # space on either version). "?" (0x3F) is a genuine, disclosed
    # version split, not a single fixed answer: bash 3.2.57 decodes \c? to
    # 0x1F (matching the general formula), but bash 5.3.15 special-cases
    # it to 0x7F (DEL) -- confirmed on both directly (found by adversarial
    # review of PR #66, round 1, which caught an earlier version of this
    # comment wrongly claiming a single universal 0x1F answer verified
    # against 5.3.15, when 5.3.15 itself gives 0x7F). Matching modern
    # bash's special case here, since a newer bash is what most
    # environments actually run. \cX can only ever produce a non-printable
    # control byte (0x00-0x1F) or DEL (0x7F), never "." (0x2e) or "/"
    # (0x2f), so it is not independently traversal-exploitable the way
    # \u/\U are -- implemented anyway for completeness now that the
    # pattern is being extended regardless, and its exact value IS
    # observable through this hook's own ALLOW/DENY interface despite
    # looking like it shouldn't be: the byte survives into the resolved
    # path and the JSON-encoded denial message renders it as a distinct,
    # inspectable escape sequence (found by the same review round, which
    # used exactly this to prove the wrong formula was uncaught by any
    # test). \u/\U are both GREEDY up to their digit cap (4 for \u, 8 for
    # \U), matching \x's own greedy 1-2 digit behavior -- confirmed
    # empirically (`\u2b` consumes BOTH hex-looking characters as one
    # 2-digit codepoint 0x2B ('+'), not \u2 followed by literal "b"), and
    # the resulting codepoint is encoded the same way Python's own str
    # type stores it (chr()), which downstream scope-pattern string
    # comparisons consume directly with no further byte-level re-encoding
    # needed. Both \u and \U reject two ranges into the literal-text
    # fallback rather than calling chr() unconditionally: a codepoint
    # outside Unicode's own valid range (above 0x10FFFF -- real bash uses
    # an extended, pre-RFC-3629 UTF-8 byte encoding for these that
    # Python's chr() cannot represent) and, CRITICALLY, the UTF-16
    # surrogate range 0xD800-0xDFFF. An earlier version of this fix only
    # guarded the out-of-range case (a try/except around chr() catching
    # ValueError) and let a lone surrogate through unchecked, since
    # Python's chr() happily constructs a string containing one WITHOUT
    # raising -- this was a genuine, newly-introduced fail-open, not a
    # residual: this hook's own later json.dumps()/print() of the denial
    # message DOES raise (UnicodeEncodeError: surrogates not allowed) once
    # a resolved path contains one, and because this hook's whole design
    # is fail-OPEN on any exception (DENY_REASON coming back empty means
    # deny_json() is never called), a plain out-of-scope write with NO
    # traversal at all -- just a lone \ud800 anywhere in the target --
    # silently bypassed detection entirely, and composed with the EXISTING
    # F031/F033 defenses too (a real `..` PLUS a trailing \ud800 also
    # crashed past the point where the real target had already been
    # correctly resolved) (found by adversarial review of PR #66, round 1;
    # confirmed by direct execution: the write genuinely lands, rc 0, no
    # deny fields, traceback on stderr only). Neither a surrogate nor an
    # out-of-range codepoint can ever spell "." or "/" regardless of exact
    # byte representation, so rejecting both into the literal fallback
    # costs nothing security-wise while removing the crash-to-silent-
    # ALLOW lever entirely.
    hexdigits, octdigits, ctrlchar, u4, u8, other = (
        m.group(1), m.group(2), m.group(3), m.group(4), m.group(5), m.group(6)
    )
    if hexdigits is not None:
        return chr(int(hexdigits, 16))
    if octdigits is not None:
        return chr(int(octdigits, 8) & 0xFF)
    if ctrlchar is not None:
        upper = ctrlchar.upper()
        if upper == "?":
            return "\x7f"
        if len(upper) != 1:
            # ANSI_C_ESCAPE_PATTERN's c(.) captures ANY single character, and
            # for 102 distinct Unicode characters str.upper() returns TWO
            # characters (e.g. U+00DF, the German sharp s, uppercases to the
            # two-character string "SS"), which
            # made ord() raise TypeError -- crashing this hook's Python
            # subprocess, which this hook's own fail-open design (see header)
            # then turns into a SILENT ALLOW for the entire command, not just
            # a missed decode: `$'src/parser/\c<that char>q.txt'` anywhere in
            # a compound command let an UNRELATED, plain-ASCII, ordinarily-
            # denied out-of-scope write elsewhere in the SAME command through
            # too, confirmed live on main (found by adversarial review of PR
            # #67, the exact same fail-open class the surrogate fix above
            # closes, recurring one branch over with a different exception
            # type no source-range guard on \u/\U could ever have caught).
            # Falling back to the ORIGINAL (non-uppercased) character instead
            # of crashing diverges from real bash's own byte-wise result for
            # these characters, but \cX can never spell "." or "/" on either
            # reading, so only not-crashing matters here.
            upper = ctrlchar
        return chr(ord(upper) & 0x1F)
    if u4 is not None:
        return _unicode_escape_or_literal(u4, "u")
    if u8 is not None:
        return _unicode_escape_or_literal(u8, "U")
    return ANSI_C_SIMPLE_ESCAPES.get(other, "\\" + other)


def _unicode_escape_or_literal(hexdigits, prefix):
    # Shared by \uHHHH and \UHHHHHHHH: rejects a codepoint that Python's
    # chr() would accept but this hook's own later JSON encoding cannot --
    # see _decode_ansi_c_escape()'s own comment for the full incident this
    # closes (a lone surrogate crashed the hook into a silent ALLOW).
    codepoint = int(hexdigits, 16)
    if 0xD800 <= codepoint <= 0xDFFF or codepoint > 0x10FFFF:
        return "\\" + prefix + hexdigits
    return chr(codepoint)


def unquote_token(token):
    # Strips quote characters from a single ALREADY-EXTRACTED target token --
    # never used to re-segment or re-tokenize, only to normalize a target
    # string (which may be fully quoted, "foo"/'foo'/$'foo', or partially
    # quoted, foo/"bar".txt) before comparing it against scope patterns. Safe
    # here specifically because segments_of() has already correctly resolved
    # segment boundaries using mask_quotes(); this function never looks at
    # separators. A $'...' span's inner text is decoded per bash's ANSI-C
    # quoting grammar (F033) in this SAME substitution -- not left for the
    # generic backslash-unescape pass below to mangle, and not merely
    # stripped of its wrapper unresolved: before this, `$'src/parser/
    # \x2e\x2e/other/x.txt'` genuinely resolves to src/other/x.txt in real
    # bash (\x2e decodes to "."), but the hook never decoded the escape, so
    # normalize() never saw a real ".." to resolve and the traversal was
    # wrongly ALLOWED (found by adversarial review of PR #50, F031, filed
    # separately as F033: a different mechanism from F031 -- escape
    # DECODING inside an already-recognized $'...' span, not escape
    # REMOVAL outside quotes). \cX (control-char), \uHHHH, and \UHHHHHHHH
    # escapes are ALSO decoded (F038) -- see _decode_ansi_c_escape()'s own
    # comment for the exact formulas, verification, and the one disclosed
    # residual (a \U codepoint outside Unicode's valid range, or landing
    # in the surrogate range, is left undecoded rather than crashing).
    token = re.sub(
        r"\$'((?:[^'\\]|\\.)*)'",
        lambda m: ANSI_C_ESCAPE_PATTERN.sub(_decode_ansi_c_escape, m.group(1)),
        token,
    )
    token = token.replace("'", "").replace('"', "")
    # Outside quotes, real bash strips a backslash and makes the next
    # character literal -- e.g. "\.." really means "..", letting a traversal
    # segment hide from normalize()'s os.path.normpath() resolution, which
    # only recognizes the exact string ".." (F031). Applied uniformly after
    # quote-stripping since this function no longer tracks which spans were
    # originally quoted (where bash treats a backslash as ordinary,
    # non-special text, true of both single- and double-quoted spans) --
    # an accepted, documented residual, same as the rest of this
    # pattern-based, evadable-by-construction hook: a real literal
    # backslash in a quoted filename is normalized away too.
    return re.sub(r"\\(.)", r"\1", token)


def segments_of(command):
    # Splits on shell control operators. An earlier version omitted a literal
    # newline and "&" (background execution, and the leading half of "|&"):
    # without them, two separately-written commands glue into one segment.
    # At the time this was fixed, write_target()/redirect_target() (singular)
    # only ever checked the LAST target found across the whole (possibly
    # merged) segment, so an in-scope write later in the command masked an
    # out-of-scope write earlier in it. write_targets()/redirect_targets()
    # (plural, F024) now check every target in a segment, which independently
    # bounds that specific consequence, but correct segmentation still
    # matters for its own sake (a target belongs to a specific logical
    # command, not an accidental merge of two). The identical missing-
    # newline bug was found and fixed in commit-gate.sh.template (F011/
    # OVI-64, round 3); this hook never got the same fix (found by
    # adversarial review of PR #40, reported as F023). Adding the newline
    # split required join_continuations() as a prerequisite, exactly as it
    # did in commit-gate.sh (found by adversarial review of PR #42, F023
    # round 1). Split positions are found in a quote-MASKED copy (see
    # mask_quotes) but sliced from the ORIGINAL, still-quoted text, so a
    # segment's real write target survives intact for
    # write_targets()/redirect_targets() to extract -- deleting quotes
    # outright (as round 1's first attempt did) erased the target whenever
    # it was quoted, a much bigger bypass than the one being fixed (found by
    # adversarial review of PR #42, F023 round 2). A "&" is NOT a segment
    # separator when it immediately follows a ">": real bash lexes ">&" as
    # one fd-duplication operator (`2>&1`, `>&2`), not a redirect
    # immediately followed by a background/AND "&" -- splitting there
    # fragmented the redirect, leaving a dangling ">" with no target after
    # it for strip_redirects()/redirect_targets() to recognize, so it
    # survived into rm/tee's own target extraction as a bogus write target
    # (F030). A bare "&" anywhere else (background, "&&", or the leading
    # half of `&> file`) is unaffected and still splits as before.
    sanitized = strip_heredoc_bodies(command)
    joined = join_continuations(sanitized)
    masked = mask_quotes(joined)
    segments = []
    start = 0
    for m in re.finditer(r"[|;\n]|(?<!>)&", masked):
        segments.append(joined[start:m.start()])
        start = m.end()
    segments.append(joined[start:])
    return [s.strip() for s in segments if s.strip()]


def all_flagless_tokens(tokens):
    # A literal "--" ends flag parsing for the rest of THIS token list, same
    # as commit-gate.sh.template's has_staging_flag(): every token after it
    # is a real pathspec, never a flag, even if it starts with "-" (e.g. the
    # real filename in `rm -- -a.txt`). Before this, a token starting with
    # "-" was excluded unconditionally, so "--" and "-a.txt" were BOTH
    # dropped and no target was found at all -- an out-of-scope -a.txt was
    # then silently ALLOWED, not merely misnamed (F029). Only the FIRST
    # "--" is a separator; any later one is already past it, so it's just
    # ordinary token text, kept like any other post-separator token. The
    # separator check and the "starts with -" flag check both run against
    # _flag_view(tok), not the raw token -- a quoted "--" (e.g. `cp "--"
    # "-t" src/parser/d/ src/other/x`) is just as real a separator to the
    # RECEIVING command as an unquoted one, since the shell strips quotes
    # before the program ever sees its argv. Comparing only the flag
    # checks against the view while leaving THIS "--" check on the raw
    # token (an earlier version of the F035 fix did exactly that) created a
    # NEW asymmetry: quoted flags were recognized but a quoted "--" was
    # not, so `past_separator` never became True for it, silently
    # swallowing the real (possibly out-of-scope) destination that follows
    # -- found by adversarial review of PR #59, F035, the same
    # guard-vs-check asymmetry class F029 round 3 already fixed once for a
    # different trigger (a value-consumed "--" there; a quoted "--" here).
    result = []
    past_separator = False
    for tok in tokens:
        if not tok:
            continue
        view = _flag_view(tok)
        if view == "--" and not past_separator:
            past_separator = True
            continue
        if past_separator or not view.startswith("-"):
            result.append(tok)
    return result


def last_flagless_token(tokens):
    flagless = all_flagless_tokens(tokens)
    return flagless[-1] if flagless else None


def redirect_targets(segment):
    # Finds the token after EVERY REAL >/>> on the line, regardless of other
    # operators (e.g. <<EOF) on the same line, so a heredoc-into-redirect
    # line is still caught. An earlier version returned only the LAST match,
    # so `echo x > out-of-scope 2> in-scope` in one segment checked only the
    # in-scope target and masked the out-of-scope one -- found by
    # adversarial review of PR #42/F023, reported as F024. Matching runs
    # against a quote-MASKED copy (so a ">" INSIDE a quoted string, e.g.
    # echo "a => b" > file, is masked to a NUL run and can't match) but each
    # match's target text is sliced from the ORIGINAL segment at the same
    # position, so a legitimately quoted target still returns its real
    # (still-quoted) text for write_targets()/unquote_token() to normalize --
    # matching directly against the unmasked segment, as an earlier version
    # of the F024 fix did, treated every quoted ">" as a real redirect too.
    masked = mask_quotes(segment)
    targets = [
        segment[m.start(1):m.end(1)]
        for m in re.finditer(r">>?\s*([^\s<>|&;]+)", masked)
    ]
    # `>&word` with word NOT purely digits/"-" is `&>word`, an ordinary FILE
    # redirect (bash: `echo x >&outfile.txt` genuinely creates outfile.txt),
    # not fd-duplication -- this was a real fail-open, confirmed identical on
    # main and after F030's own fix: the pattern above can never match it
    # (the char class it captures into explicitly excludes "&", so a target
    # class starting right at "&" fails to match at all). Whitespace or
    # quoting between `>&` and the word doesn't change bash's behavior (`>&
    # outfile.txt`, `>&'outfile.txt'` both still create the file, confirmed
    # against real bash) -- found by adversarial review of PR #53, round 3.
    # Whether a given word counts as "purely digits/-" has to be decided on
    # its UNQUOTED value, not the raw/masked text: `>&'1'` is STILL
    # fd-duplication in real bash (quoting doesn't change the classification,
    # confirmed empirically), so checking the masked capture (a NUL run for
    # a quoted span) would wrongly treat it as a real target. This pattern
    # deliberately matches `>&word` with ANY preceding fd digit (or none) --
    # an earlier version of this fix claimed EVERY fd-prefixed word form
    # (`2>&outfile.txt`) is a hard "ambiguous redirect" syntax error, so no
    # fd-prefix handling was needed; that claim is true for fd 0, 2, and
    # 3+, but FALSE for fd 1 specifically: `1>&outfile.txt` is a real,
    # long-standing bash extension (confirmed against real bash and bash's
    # own redir.c: a dedicated `redirector == 1` branch converts it to the
    # same r_err_and_out redirect as `&>`) that genuinely writes the file,
    # capturing both stdout and stderr -- found by adversarial review of PR
    # #63, round 1. This function's own pattern was never anchored to "no
    # fd prefix" in the first place (it just looks for `>&` anywhere in the
    # segment), so `1>&outfile.txt` was already correctly caught here even
    # under the old, wrong justification; strip_redirects() below is the
    # function that actually needed the fix once this was understood.
    # Digit-or-dash classification also has a known, narrow, non-regression
    # residual: it decides on unquote_token()'s output, which strips
    # backslashes as well as quotes, but real bash classifies fd-dup-vs-file
    # on the word BEFORE backslash/quote removal -- `>&'\1'` genuinely
    # creates a file named "1" in real bash (confirmed), which this check
    # wrongly treats as fd-duplication and allows. Reachable target is only
    # ever a bare digit-named file or "-" in the cwd (never a real path,
    # since "/" can't satisfy .isdigit()), and main allowed every `>&word`
    # unconditionally, so this is not a regression -- found by the same
    # review round, not fixed here.
    for m in re.finditer(r">&\s*([^\s<>|&;]+)", masked):
        raw_word = segment[m.start(1):m.end(1)]
        view_word = unquote_token(raw_word)
        if view_word == "-" or view_word.isdigit():
            continue
        targets.append(raw_word)
    return targets


TARGET_DIRECTORY_FLAGS = ("-t", "--target-directory")

# The only other cp/mv options (beyond -t/--target-directory, handled separately
# since they name the destination rather than merely consuming a value) that take
# a MANDATORY value as a SEPARATE token when not attached via "=" -- confirmed
# against real GNU cp/mv 9.11: `cp --suffix .bak a b`, `cp -S .bak a b`, `cp
# --no-preserve mode a b`, and `cp --sparse always a b` all genuinely consume the
# following token as the flag's own value (the command succeeds using only the
# TWO remaining flagless arguments as source/dest); `cp --update all a b`, `cp
# --context x a b`, `cp --preserve mode a b`, `cp --backup numbered a b`, and `cp
# --reflink auto a b` do NOT (each errors "cannot stat" on the following token,
# proving it was left as an ordinary flagless argument, never consumed) -- the
# distinguishing factor is GNU getopt_long's own optional-vs-mandatory-argument
# rule: every one of the non-consuming flags takes its value ONLY via an
# attached "=value" ("[=X]" in --help), and GNU getopt_long can never treat a
# separate following token as an optional argument's value (it would be
# ambiguous with the next real operand), while these three take a value that is
# genuinely mandatory ("=X" with no brackets in --help), so a bare separate
# token is unambiguously theirs. -S is --suffix's short form; --no-preserve and
# --sparse have no short form.
CP_MV_VALUE_ONLY_LONG = ("--suffix", "--no-preserve", "--sparse")


def _flag_view(tok):
    # Unquoted view of a token for FLAG RECOGNITION only (cp_mv_targets()/
    # sed_inplace_targets()' own comparisons against known flag strings) --
    # never returned or stored as a target/token itself. A raw, still-
    # quoted token is always what gets returned to write_targets(), which
    # applies its OWN single unquote_token() pass over the final target
    # list -- calling unquote_token() a SECOND time on an already-unquoted
    # string would silently undo F031's backslash-escape traversal defense
    # (unquote_token() is not idempotent: e.g. "a\\\\b.txt" unquoted once is
    # "a\\b.txt", unquoted TWICE becomes "ab.txt"). Before this, cp_mv_targets()
    # and sed_inplace_targets() compared flag tokens RAW, so quoting a flag
    # evaded recognition entirely: `cp "-t" "src/other/d/" src/parser/a`
    # was wrongly ALLOWED (real bash writes to src/other/d/ via -t, but the
    # quoted "-t" token never matched TARGET_DIRECTORY_FLAGS, so
    # cp_mv_targets() fell through to last_flagless_token() and picked the
    # wrong argument) -- found by adversarial review of PR #51, F028,
    # filed as F035.
    return unquote_token(tok)


def _attached_value_raw(tok, prefix_len):
    # Returns the RAW (not-yet-unquoted) suffix of `tok` starting right after
    # its recognized `prefix_len`-character flag prefix (e.g. 2 for "-t", or
    # len("--target-directory=")), for write_targets()'s single later
    # unquote_token() pass to resolve -- mirroring how the bare "-t DIR"/
    # "--target-directory DIR" forms already return tokens[i+1] untouched.
    # An earlier version sliced the VIEW instead (view.split("=", 1)[1] /
    # view[2:]), handing write_targets() an ALREADY-unquoted-and-unescaped
    # string that its own unquote_token() pass then processed a SECOND time.
    # unquote_token() is not idempotent (F031's backslash-unescape isn't),
    # so this silently mis-resolved any backslash in the destination:
    # confirmed both directions by sweeping 3,645 backslash-bearing -t
    # destinations against real GNU cp -- 70 unquoted cases regressed
    # DENY->ALLOW (a fail-open: `cp -ts\\rc/parser/x a.txt` really targets
    # the literal directory `s\rc/parser/x`, confirmed via `gcp` execution,
    # but double-unquoting silently stripped the surviving backslash and
    # made it look like the in-scope "src/parser/x") and 1,376 regressed
    # ALLOW->DENY (found by adversarial review of PR #59, round 2).
    # Since unquote_token() strips quote characters from ANYWHERE in a
    # token (not just matched pairs at the edges) and unescapes backslashes
    # globally, the fix below walks the RAW token counting non-quote
    # characters until `prefix_len` of them are consumed, skipping over
    # (but preserving in the returned suffix) any quote characters seen
    # along the way. This correctly locates the raw split point whether the
    # flag prefix is bare, only the value is quoted, or the WHOLE token
    # (prefix included) is quoted -- in every case the returned suffix still
    # carries any quote/backslash characters untouched, for write_targets()
    # to resolve in exactly one pass, the same as the bare-form path.
    # Documented residual (found by adversarial review of PR #59, round 3):
    # a backslash-escaped character INSIDE the flag prefix itself (as opposed
    # to inside the value) throws off the count by one per escape, since this
    # walk counts a quote character as free but a backslash as a real,
    # counted character -- `cp -\tsrc/parser/x a.txt`, `cp $'-t'src/parser/x
    # a.txt`, and `cp --target-\directory=src/parser/x a.txt` are all
    # genuinely in scope but wrongly DENIED (18 false positives found across
    # 112 brute-forced prefix/destination spellings, zero fail-opens --
    # strictly over-denial, not a bypass, and a new-vs-main regression only
    # in this narrow, adversarial-quoting shape). Not fixed: nobody escapes
    # characters inside a bare flag name in practice, and closing this
    # would require tracking escape state through the prefix walk itself,
    # not just counting past it.
    seen = 0
    for idx, ch in enumerate(tok):
        if ch in ("'", '"'):
            continue
        seen += 1
        if seen == prefix_len:
            return tok[idx + 1 :]
    return ""


# The union of every long option GNU cp and GNU mv each recognize, used as
# the disambiguation universe for _resolve_cp_mv_long_flag() (F048) --
# mirroring enforce-scope.sh's own SED_LONG_OPTIONS/_resolve_sed_long_flag()
# (F041) and commit-gate.sh's GIT_COMMIT_LONG_OPTIONS/_resolve_long_flag()
# (F032). Mechanically extracted from `gcp --help`/`gmv --help` (GNU
# coreutils 9.11), not assembled from memory. cp_mv_targets() is shared by
# both commands and doesn't know which one triggered it, so the UNION is
# the correct universe: --target-directory is the only long option in
# either command's own set starting with "--t" (confirmed: no ambiguity at
# any prefix length from "--t" up, in cp's set, mv's set, or the union),
# so using the broader union here is never less safe than a per-command
# set would be for this specific flag.
CP_MV_LONG_OPTIONS = (
    "--archive", "--attributes-only", "--backup", "--context",
    "--copy-contents", "--debug", "--dereference", "--exchange", "--force",
    "--help", "--interactive", "--keep-directory-symlink", "--link",
    "--no-clobber", "--no-copy", "--no-dereference", "--no-preserve",
    "--no-target-directory", "--one-file-system", "--parents", "--preserve",
    "--recursive", "--reflink", "--remove-destination", "--sparse",
    "--strip-trailing-slashes", "--suffix", "--symbolic-link",
    "--target-directory", "--update", "--verbose", "--version",
)


def _resolve_cp_mv_long_flag(view):
    # Resolves a "--xxx" token (flag-name part only, caller splits off any
    # attached "=value" first) to its full long-option name if it's an
    # exact match or an UNAMBIGUOUS prefix of exactly one entry in
    # CP_MV_LONG_OPTIONS (the UNION of cp's and mv's real option sets, so a
    # prefix ambiguous only against the other command's options, e.g. "--p"
    # against mv's real set, returns None here too -- strictly more
    # conservative than the single command actually being run, never less).
    # Returns None on no match or an ambiguous prefix -- for the ONE flag
    # this function cares about, --target-directory, that never matters:
    # it's the only long option in either command's set (or their union)
    # starting with "--t", so nothing here can ever misresolve a real
    # ambiguous-in-cp/mv prefix INTO --target-directory. Treating an
    # unresolved prefix as "not a recognized flag" is always safe either
    # way, never a bypass.
    if view in CP_MV_LONG_OPTIONS:
        return view
    matches = [o for o in CP_MV_LONG_OPTIONS if o.startswith(view)]
    return matches[0] if len(matches) == 1 else None


def cp_mv_targets(tokens):
    # cp/mv normally write to only the LAST flagless argument (the
    # destination); every earlier flagless argument is a SOURCE, read not
    # written. `-t DIR`/`-tDIR`/`--target-directory=DIR` name the destination
    # explicitly instead, in which case EVERY flagless argument is a source
    # and DIR is the sole write target -- an earlier version didn't look for
    # any of these forms at all, so an out-of-scope -t destination was never
    # checked (found by adversarial review of PR #42/F023, reported as
    # F024). Clustered short flags (`-rt DIR`, -r and -t combined; likewise
    # `-rS VALUE`, -r and -S combined, since F056 gave -S the same
    # value-consuming recognition as -t) are not recognized, a documented
    # residual (see header) -- confirmed against real GNU cp that `cp
    # src/parser/a.txt src/other/d -rS src/parser/x` still writes to
    # src/other/d (the real destination) while this function, both before
    # and after F056, returns the wrong token (src/parser/x) since neither
    # -t nor -S is recognized once clustered with another short flag. F056
    # narrows this residual's reach (bare -S is now handled) without closing
    # it for the clustered form, identically to the pre-existing -rt gap.
    # The scan stops at a literal "--" (end of flag parsing): without this, a
    # real filename that happens to start with "-t" after "--" (e.g. `mv --
    # -t.txt dest.txt`)
    # was misread as the -t flag itself, string-sliced into a bogus target
    # ".txt", and the REAL destination (dest.txt, via the last_flagless_token
    # fallback, never reached because this loop already returned) went
    # unchecked -- the exact failure mode F029 exists to close, just in this
    # sibling function instead of all_flagless_tokens() (found by
    # adversarial review of PR #52, F029). The "--" check and every FLAG
    # comparison below run against _flag_view(tok), not the raw token, so a
    # quoted flag OR a quoted "--" can't evade recognition (F035): a quoted
    # "--" (e.g. `cp "--" "-t" src/parser/d/ src/other/x`) is just as real a
    # separator to the receiving command as an unquoted one, since the
    # shell strips quotes before the program's argv is built. An earlier
    # version of this fix left the "--" check on the raw token, reasoning
    # it matched all_flagless_tokens()'s own then-current convention and
    # was out of F035's reported shape -- that was wrong on both counts: it
    # created a NEW asymmetry (flags view-aware, "--" not) that let a
    # quoted "--" swallow the real destination that follows, and
    # all_flagless_tokens() itself needed the identical correction for the
    # identical reason (found by adversarial review of PR #59, F035). The
    # bare `-t DIR`/`--target-directory DIR` forms return the RAW next
    # token (tokens[i+1], untouched, unquoted exactly once later by
    # write_targets()); the attached `--target-directory=DIR`/`-tDIR` forms
    # go through _attached_value_raw() for the identical reason (see its
    # own docstring) -- an earlier version extracted their value from the
    # VIEW instead, framed as "a documented, narrower residual"; a reviewer
    # proved that framing wrong (it flips scope decisions in BOTH
    # directions vs. main, a regression, not a residual) and this replaces
    # it (F035 round 2, PR #59 round-2 review). Both the exact "--target-
    # directory" spelling AND any unambiguous GNU-getopt_long abbreviation
    # of it (bare "--targ", attached "--targ=DIR") are recognized via
    # _resolve_cp_mv_long_flag() -- confirmed against real GNU cp/mv 9.11
    # that `cp --targ=out src.txt`/`cp --t out src.txt`/`mv --targ=out
    # src.txt` all genuinely redirect via -t's own mechanism, and every one
    # of them was wrongly ALLOWED before this (F048, discovered alongside
    # F041's identical gap in sed_inplace_targets(), filed separately since
    # it's a different function with its own flag set and call sites).
    #
    # Real GNU cp/mv PERMUTE argv: a value-consuming option is free to appear
    # AFTER both operands, and it still consumes the token immediately
    # following it as ITS OWN value, never as a new flagless operand -- this
    # function used to walk tokens with a plain enumerate() and no notion of
    # "this flag consumes the next token", so `cp src other-real-dest --suffix
    # not-the-dest` fell through to last_flagless_token() on the UNFILTERED
    # token list, which returned "not-the-dest" (--suffix's own value, an
    # ordinary-looking path) as the destination while the REAL destination
    # (other-real-dest) was never checked at all (confirmed against real GNU
    # cp 9.11; identically reachable via -S, --no-preserve, and --sparse,
    # CP_MV_VALUE_ONLY_LONG above) (F056, discovered by review-pr82-f048 while
    # verifying F048 didn't introduce or worsen it -- confirmed present
    # identically on main). Fixed by switching to an explicit index-managed
    # while loop (mirroring sed_inplace_targets()'s own token-walking style)
    # that skips BOTH the flag token and its consumed value when building the
    # token list handed to last_flagless_token(), so a value that merely looks
    # like a flagless path is never treated as one -- consuming the value via
    # an index skip, not a filter pass afterward, also matters for a value
    # that itself looks like a FLAG (e.g. `cp --suffix -t src dest`, where
    # "-t" is the literal suffix, not a target-directory flag): confirmed
    # against real GNU cp that the token immediately after a value-consuming
    # flag is unconditionally that flag's value, never re-parsed as a new
    # flag, matching how a manual index skip (i += 2, never re-visiting the
    # skipped index) behaves, unlike a filter-after-the-fact approach would if
    # it left the main scanning loop free to re-inspect that same token.
    remaining = []
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        view = _flag_view(tok)
        if view == "--":
            remaining.extend(tokens[i:])
            break
        if view in TARGET_DIRECTORY_FLAGS and i + 1 < len(tokens):
            return [tokens[i + 1]]
        if view.startswith("--"):
            flag_name = view.split("=", 1)[0]
            resolved = _resolve_cp_mv_long_flag(flag_name)
            if resolved == "--target-directory":
                if "=" in view:
                    return [_attached_value_raw(tok, len(flag_name) + 1)]
                if i + 1 < len(tokens):
                    return [tokens[i + 1]]
            elif resolved in CP_MV_VALUE_ONLY_LONG and "=" not in view and i + 1 < len(tokens):
                remaining.append(tok)
                i += 2
                continue
        elif view == "-S" and i + 1 < len(tokens):
            remaining.append(tok)
            i += 2
            continue
        elif view.startswith("-t") and len(view) > 2:
            return [_attached_value_raw(tok, 2)]
        remaining.append(tok)
        i += 1
    last = last_flagless_token(remaining)
    return [last] if last else []


SED_SCRIPT_VALUE_FLAGS = ("-e", "-f", "--expression", "--file")

# The full set of long options GNU sed recognizes, used as the
# disambiguation universe for _resolve_sed_long_flag() (F041) -- mirroring
# commit-gate.sh's GIT_COMMIT_LONG_OPTIONS/_resolve_long_flag() (F032).
# Mechanically extracted from `gsed --help` (GNU sed 4.10, installed via
# `brew install gnu-sed` specifically to ground-truth this), not assembled
# from memory: --quiet/--silent are both listed as -n's long form; the
# rest are one option each. GNU sed accepts any prefix of a long option
# that uniquely identifies it among this FULL set (confirmed: `gsed --xyz`
# errors "unrecognized option"; `gsed --f=x` errors "option '--f=x' is
# ambiguous; possibilities: '--file' '--follow-symlinks'"), the same
# unambiguous-prefix rule real git uses. Before this, sed_inplace_targets()'s in-place-
# presence guard recognized only the exact string "--in-place" or the
# attached "--in-place=" prefix -- confirmed against real gsed that
# --i, --in, --in-p, --in-pla, --in-plac (bare) and --i=.bak, --in-p=.bak
# (attached, abbreviated) all genuinely perform a real in-place edit,
# since --in-place is the only long option starting with "--i" (no
# ambiguity to resolve), and every one of these was wrongly ALLOWED
# (F041). The identical abbreviation gap also affects has_explicit_script's
# own --expression=/--file= recognition, AND the main token-walking loop's
# 2-token skip for -e/-f/--expression/--file, AND _separator_index()'s own
# copy of that same skip -- all four sites now recognize a bare OR
# attached abbreviated form via _sed_consumes_next_as_script() below, not
# just an exact SED_SCRIPT_VALUE_FLAGS string.
#
# An earlier version of this fix recognized the bare abbreviated form ONLY
# in the in-place guard, leaving the other three sites (has_explicit_script,
# the walking loop, _separator_index()) matching the exact-string
# SED_SCRIPT_VALUE_FLAGS set only, on the theory that a single bare
# abbreviated script flag's "wrong by one token" error in the (unfixed)
# walking loop exactly cancels has_explicit_script's own "wrong by one
# token" error, landing on the same real target either way. That theory is
# FALSE whenever the flag's value is not itself a flagless token -- i.e.
# starts with "-" (a script/script-file argument that happens to look like
# a flag, e.g. a file named "-x.sed") or is exactly "--". In that case the
# walking loop's `view.startswith("-"): i += 1` branch swallows the VALUE
# as if it were an unrelated flag instead of leaving it for the
# (unfixed) 2-token skip to consume, so the cancellation breaks down and
# the REAL target is what gets swallowed as the implicit script instead --
# a genuine fail-open, not a cosmetic mis-naming. Confirmed against real
# gsed 4.10 (adversarial review of PR #71): `sed -i --fi -x.sed
# out-of-scope-file` and `sed -i --fi -- out-of-scope-file` (with a file
# literally named "--" containing a script) both genuinely in-place edit
# the real file, and the hook (with only the in-place guard fixed)
# silently ALLOWed both -- reachable even against this fix's OWN newly
# recognized --in-place, since `sed --in-place --fi -x.sed file` hits the
# identical gap one flag later. This fix closes it at all four sites with
# one shared predicate, confirmed by mutation testing that: (a) all four
# shapes above now DENY and name the real file, (b) the previously
# mis-named 2-flag case (`sed -i --exp 's/a/b/' --exp 's/c/d/'
# out-of-scope-file`) now correctly names the real file instead of the
# second script fragment, and (c) a genuine pre-existing FALSE POSITIVE is
# also fixed as a side effect: `sed --fi -i.bak file1 file2` was wrongly
# DENIED (the unrecognized `--fi` left "-i.bak" looking like a flag
# position, which IN_PLACE_CLUSTER_PATTERN then mismatched as enabling
# in-place mode) even though real gsed treats "-i.bak" as --file's own
# script-file value and performs no in-place edit at all -- the same
# "value that looks like a flag" bug class PR #52 round 4 already fixed
# for the exact-spelling form, reintroduced here via abbreviation.
SED_LONG_OPTIONS = (
    "--quiet", "--silent", "--debug", "--expression", "--file",
    "--follow-symlinks", "--in-place", "--line-length", "--posix",
    "--regexp-extended", "--separate", "--sandbox", "--unbuffered",
    "--null-data", "--help", "--version",
)


def _resolve_sed_long_flag(view):
    # Resolves a "--xxx" token to its full long-option name if it's an
    # exact match or an UNAMBIGUOUS prefix of exactly one entry in
    # SED_LONG_OPTIONS, mirroring commit-gate.sh's _resolve_long_flag()
    # (F032). Returns None on no match or an ambiguous prefix -- in the
    # ambiguous case, real GNU sed itself errors out and nothing runs, so
    # treating it as "not a recognized flag" here is always safe, never a
    # bypass. Operates on the flag-name part only: callers split off any
    # attached "=value" suffix before calling this, since GNU's own
    # abbreviation resolution happens on the option name, not the value
    # (confirmed: `gsed --i=.bak` and `gsed --in-place=.bak` resolve
    # identically).
    if view in SED_LONG_OPTIONS:
        return view
    matches = [o for o in SED_LONG_OPTIONS if o.startswith(view)]
    return matches[0] if len(matches) == 1 else None


def _sed_long_flag_name(tok):
    # Splits a (possibly _flag_view-unquoted) token into its flag-name part
    # -- everything before the first "=" -- and resolves THAT against
    # SED_LONG_OPTIONS, so both the bare form ("--in-place") and the
    # attached form ("--in-place=.bak", or an abbreviation of either) are
    # recognized identically (F041). Returns None for a non-"--" token
    # without ever calling _resolve_sed_long_flag on it, since a short
    # flag or a plain filename could otherwise coincidentally prefix-match
    # (e.g. an empty string is a prefix of everything).
    if not tok.startswith("--"):
        return None
    return _resolve_sed_long_flag(tok.split("=", 1)[0])


def _sed_consumes_next_as_script(view):
    # True if `view` is a BARE (not self-contained) script-value flag that
    # consumes the NEXT token as its value -- either an exact
    # SED_SCRIPT_VALUE_FLAGS entry, or an unambiguous abbreviation of
    # --expression/--file with no attached "=value" (F041). An attached
    # form ("--exp=script") is a single self-contained token that must NOT
    # be counted here (no extra token to skip) -- distinguished by the
    # absence of "=" in `view`, since _sed_long_flag_name() resolves the
    # name portion the same way for both attached and bare forms and can't
    # itself tell them apart. This is the ONE predicate all four places in
    # this function that need to agree on "does this flag position consume
    # 2 tokens or 1" must share -- _separator_index(), the flag_positions
    # walk, has_explicit_script, and the main token-walking loop -- so an
    # abbreviated flag can never be recognized at one site and missed at
    # another (the same guard-vs-loop disagreement risk F029/F052
    # established for this file, now extended to abbreviation as well as
    # quoting).
    if view in SED_SCRIPT_VALUE_FLAGS:
        return True
    return "=" not in view and _sed_long_flag_name(view) in ("--expression", "--file")


# Matches a short-flag cluster ending in "i" (F037): both GNU's and BSD/
# macOS's own argument-less short flags may precede "i" in the same token
# (`-ri`, `-ni`, `-Ei`, `-nsi`, ... on GNU; `-ai.bak`, `-Hi.bak`, `-ali.bak`
# on BSD/macOS's own /usr/bin/sed, confirmed against it directly -- this
# repo's own stated platform, and this same function already accommodates
# a BSD idiom elsewhere, the `-i ''` empty-suffix skip below). "e"/"f" are
# excluded on both flavors since they take their OWN argument and consume
# the REST of the token once encountered, so "-fi" is -f's value "i" (a
# file literally named "i"), never -f combined with -i (confirmed against
# real GNU sed: `sed -fi file` prints to stdout, unmodified). "l" is a
# genuine, irreconcilable conflict between the two flavors and included
# here as a deliberate choice, not an oversight: BSD's `-l` takes no
# argument (line-buffered output; confirmed via `sed -li.bak ...`
# genuinely in-place edits), but GNU's `-l N` takes a MANDATORY numeric
# one (confirmed via `gsed -li file`: prints to stdout, unmodified -- "i"
# is consumed as -l's line-length value, not a flag). Including "l"
# closes the real BSD fail-open at the cost of over-denying an unusual
# GNU combination (`sed -li... ` intending -l's own value, not -i) --
# accepted, same class as this hook's other documented safe-direction
# residuals, since a fail-open is worse than an over-caution and BSD/macOS
# is the platform this repo itself runs on. "a"/"H" (BSD-only, confirmed
# via `sed -ai.bak`/`sed -Hi.bak`) cost nothing on GNU either way: real
# GNU sed rejects them outright as invalid options, so a command using
# them can never reach GNU's own in-place logic regardless of what this
# hook decides (found by adversarial review of PR #65, round 1).
IN_PLACE_CLUSTER_PATTERN = re.compile(r"^-[nrEsuzalH]*i")


def _is_inplace_flag(view):
    # True if VIEW enables in-place editing at all (clustered short form or
    # --in-place, bare or abbreviated) -- the ONE predicate every check in
    # this function that needs to agree on "is this the in-place flag" must
    # share, mirroring _sed_consumes_next_as_script()'s own role for the
    # "does this flag consume the next token" decision. Used by both the
    # presence-check any() below and _sed_inplace_suffix_raw()'s caller, so
    # they can never disagree about which flag positions are in-place flags
    # (the same guard-vs-loop disagreement risk F029/F052/F041 already
    # established for this file).
    return bool(IN_PLACE_CLUSTER_PATTERN.match(view)) or _sed_long_flag_name(view) == "--in-place"


def _sed_inplace_suffix_raw(tok):
    # Returns the RAW (not-yet-unquoted) backup-suffix text attached to TOK
    # -- an in-place flag already confirmed via _is_inplace_flag() -- or ""
    # if TOK carries no attached suffix at all (a bare "-i"/"--in-place",
    # which GNU sed itself treats as "no backup made", the same as an
    # explicit empty suffix). Mirrors _attached_value_raw()'s own technique
    # (walk the RAW token counting non-quote characters past the matched
    # flag-prefix length) so the returned suffix still carries any quote/
    # backslash characters untouched, for combining with a RAW file token
    # and unquoting exactly once later (F049) -- extracting from the VIEW
    # instead would double-unquote once combined and unquoted again,
    # reintroducing the exact bug class F035 round 2/3 fixed for cp_mv_targets().
    view = _flag_view(tok)
    match = IN_PLACE_CLUSTER_PATTERN.match(view)
    if match:
        return _attached_value_raw(tok, match.end())
    if _sed_long_flag_name(view) == "--in-place" and "=" in view:
        flag_name = view.split("=", 1)[0]
        return _attached_value_raw(tok, len(flag_name) + 1)
    return ""


def _separator_index(args):
    # Returns the index of the first literal "--" that acts as a REAL
    # separator, skipping any "--" consumed as an -e/-f/--expression/--file
    # VALUE (e.g. `sed -f -- 's/a/b/'`, where "--" is a script file's own
    # name, not the pathspec separator). Mirrors sed_inplace_targets()'s own
    # token-walking loop for separator-finding purposes, so callers that
    # need to know "where does flag parsing end" (the two any() guards)
    # agree with the loop that actually walks past that point -- a naive
    # `args.index("--")` could disagree and truncate one token too early
    # (found by adversarial review of PR #52, round 3). Does not replicate
    # the loop's `-i ''` two-token skip: that skip is gated on the NEXT
    # token's unquoted view being empty, which can never equal "--" (a
    # real "--" always has a non-empty view), so it cannot change where
    # the real separator is and is safely omitted
    # here (verified by adversarial review of PR #52, round 4: brute-forced
    # every arg sequence up to length 4 over this function's own alphabet,
    # zero disagreements with the full loop). Compares _flag_view(args[i]),
    # not the raw token, against SED_SCRIPT_VALUE_FLAGS -- so a quoted
    # "-e"/"-f" is recognized as consuming the next token too, keeping this
    # in agreement with sed_inplace_targets()'s own now-view-aware checks
    # (F035); using the raw token here instead would silently reintroduce
    # the exact guard-vs-loop disagreement bug class F029 round 3 fixed,
    # just triggered by quoting instead of a value-consumed "--".
    i = 0
    while i < len(args):
        if _flag_view(args[i]) == "--":
            return i
        i += 2 if _sed_consumes_next_as_script(_flag_view(args[i])) else 1
    return len(args)


def sed_inplace_targets(args):
    # Walks sed's own arguments token by token (mirroring commit-gate.sh's
    # segment_subcommand flag-walking loop) instead of assuming a fixed
    # position is "the script": -e/-f/--expression/--file each consume
    # their OWN following value as a script fragment, not a file (closing a
    # false denial the first version had for `sed -i -e '...' -e '...'
    # file`, since each -e's value is itself a flagless token); a bare "-i"
    # immediately followed by an empty-quote token ("''"/'""') is the
    # mandatory-backup-suffix BSD/macOS idiom (`sed -i '' 's/a/b/' file`) --
    # that empty-suffix token is consumed too, never mistaken for the script
    # or a file (the first version denied this ordinary, in-scope command on
    # this repo's own platform). GNU's `--expression=value`/`--file=value`
    # attached forms need no special skip logic: the value is part of the
    # same token as the flag, so it's never a flagless token in the first
    # place, but a script provided this way means there is no POSITIONAL
    # script argument to skip either -- has_explicit_script tracks that so
    # the first real file isn't mistaken for an implicit script and dropped
    # (found by adversarial review of PR #46). Documented residual: a bare
    # "-i" followed by a NON-empty separate backup-suffix token (`sed -i
    # '.bak' 's/a/b/' file`, as opposed to the far more common attached
    # form `-i.bak` or the empty-suffix form `-i ''`) is not recognized --
    # that token is misread as the implicit script, denying an in-scope
    # command. Not fixed: the check only matches a token whose unquoted
    # view IS empty, and widening it to "any token after a bare -i"
    # would reintroduce the exact ambiguity this function exists to resolve
    # (GNU's bare "-i" never takes a following value at all) (found by
    # adversarial review of PR #46, round 2). Same "--" gap as
    # cp_mv_targets()/all_flagless_tokens() (F029): before this, EVERY token
    # starting with "-" was skipped as a flag unconditionally, including a
    # literal "--" itself and a real filename after it (e.g. `sed -i -- -a
    # .txt`), so a real out-of-scope file target following "--" was never
    # recognized and went unchecked (found by adversarial review of PR #52,
    # F029). Once "--" is seen, EVERY flag-detection scan in this function --
    # the `-i`/`--in-place` presence check and the has_explicit_script check
    # immediately below, not just the token-walking loop further down --
    # stops looking at flags for the rest of the arguments; every later
    # token falls through to the same implicit-script-then-target logic as
    # an ordinary flagless token. Missing this for the two `any()` checks
    # (round 1 of PR #52 only fixed the loop) both under- and over-denies: a
    # real out-of-scope FILE target that happens to start with "-i" (e.g.
    # `sed 's/a/b/' -- -input.txt`, no actual -i flag at all) would wrongly
    # trigger the in-place guard, and a real target literally named "-e" or
    # "-f" after "--" would wrongly trigger has_explicit_script -- both
    # found by adversarial review of PR #52, round 2). Round 2's fix used a
    # NAIVE first-literal-"--" index for the two any() guards, but the
    # token-walking loop below uses a FLAG-AWARE walk that skips a "--"
    # consumed as an -e/-f/--expression/--file VALUE (e.g. `sed -f -- ...`,
    # a script FILE literally named "--"). When a "--" is consumed as a
    # value, the naive index and the flag-aware walk disagree about where
    # the real separator is, so the guards could truncate one token too
    # early and miss a genuine -i flag positioned after the value-consumed
    # "--" (found by adversarial review of PR #52, round 3). _separator_index()
    # duplicates the loop's own flag-aware walk (not the loop itself, to
    # keep it a plain boundary lookup with no target-collection side
    # effects) so the guards and the loop always agree on where flag
    # parsing actually ends.
    # Every FLAG comparison in this function (the two any() guards above and
    # the loop below), AND the "--" check itself, run against _flag_view(tok),
    # not the raw token, so a quoted flag OR a quoted "--" can't evade
    # recognition -- e.g. `sed "-i" "" -e "s/a/b/" src/other/f.txt` was
    # wrongly ALLOWED before this, since a quoted "-i" never matched the
    # bare-"-i" guard (found by adversarial review of PR #51, F028, filed
    # as F035). An earlier version of this fix left the "--" check raw,
    # reasoning it matched all_flagless_tokens()'s then-current convention
    # -- that reasoning, and the convention itself, were both wrong: a
    # quoted "--" (e.g. `sed -i "--" -i src/other/f.txt`, where the real
    # script becomes the literal text "-i" and the real target is
    # src/other/f.txt) is just as real a separator to the receiving sed as
    # an unquoted one, and leaving it raw while flags were view-aware
    # silently swallowed the real destination that follows (found by
    # adversarial review of PR #59, F035).
    # In-place presence used to recognize only a BARE "-i", an attached
    # short-flag suffix ("-i" as a literal prefix, e.g. "-i.bak"), or an
    # EXACT "--in-place" -- missing two real, ordinary invocation shapes
    # (F037): CLUSTERED short flags where -i is not first in the token
    # (`sed -ri 's/a/b/' file`, `sed -ni 's/a/b/p' file`), and the attached
    # long-form suffix `--in-place=.bak`. Both are more reachable in
    # ordinary usage than anything F029 fixed (no unusual quoting or "--"
    # needed, just an everyday flag-combining habit). See
    # IN_PLACE_CLUSTER_PATTERN's own comment above for exactly which short
    # flags may precede "i" in a cluster and why (a GNU/BSD flavor
    # difference this repo's own platform makes relevant, not an
    # arbitrary choice).
    # Takes ARGS (the tokens AFTER the command name), not the full token
    # list including the command name itself -- the caller (write_targets())
    # is the single place responsible for deciding this segment really
    # invokes sed, via _resolve_command_tokens() (F044), which recognizes
    # quoted/escaped spellings (F040), path-form indirection (/bin/sed,
    # ./sed), env-assignment prefixes (FOO=1 sed), and wrapper commands
    # (sudo/env/command/xargs sed). An earlier version of this function
    # duplicated a NARROWER piece of that same resolution internally
    # (`_flag_view(tokens[0]) != "sed"`, recognizing only quoting/escaping,
    # not indirection) -- once write_targets() gained the fuller resolver
    # for its own cp/mv/tee/rm dispatch, keeping a second, weaker copy of
    # the same decision here would have silently reintroduced the exact
    # indirection bypass F044 fixes, just for sed specifically instead of
    # cp/mv/tee/rm.
    pre_separator_args = args[: _separator_index(args)]
    # The two presence-checking any() guards below only scan FLAG
    # positions, not positions consumed as a preceding -e/-f/--expression/
    # --file's own VALUE -- mirrors the main token-walking loop's own skip
    # logic further down, so a value that merely LOOKS like a flag can't
    # be misread as one. Without this, `sed -f -i.bak file` (a real file
    # named "-i.bak" used as -f's own script-file argument, confirmed
    # against real gsed: prints to stdout, unmodified, no in-place edit
    # happens at all) was wrongly treated as specifying -i, over-denying
    # an ordinary read command that writes nothing (found by adversarial
    # review of PR #52, round 4; folded into this fix per that review's
    # own note).
    flag_positions = []
    fi = 0
    while fi < len(pre_separator_args):
        flag_positions.append(fi)
        if _sed_consumes_next_as_script(_flag_view(pre_separator_args[fi])):
            fi += 2
        else:
            fi += 1
    if not any(
        _is_inplace_flag(_flag_view(pre_separator_args[idx])) for idx in flag_positions
    ):
        return []
    has_explicit_script = any(
        _flag_view(pre_separator_args[idx]) in SED_SCRIPT_VALUE_FLAGS
        or _sed_long_flag_name(_flag_view(pre_separator_args[idx]))
        in ("--expression", "--file")
        for idx in flag_positions
    )
    # The backup-suffix VALUE itself is a second, independent write target
    # whenever it contains "*": GNU sed replaces every "*" in the suffix
    # with the file argument exactly as given on the command line (not just
    # its basename) and resolves the result relative to the CURRENT
    # directory, not relative to the file's own directory -- so a suffix
    # like "../other/*" can genuinely write the backup somewhere completely
    # different from the file being edited (confirmed against real GNU sed
    # 4.10: `sed -i'../other/*' 's/a/b/' p.txt`, run from an in-scope cwd,
    # creates a real file at `../other/p.txt`). sed_inplace_targets() used
    # to only ever check the file argument itself, never this second target
    # hiding inside the suffix's own value (F049, found by adversarial
    # review of PR #71 while differentially fuzzing this function's
    # abbreviation handling for a different bug class entirely). Only the
    # LAST in-place-enabling flag position's suffix matters: confirmed
    # against real GNU sed that a later "-i"/"--in-place" (with or without
    # its own suffix) entirely overrides an earlier one's suffix, not just
    # its presence -- `sed -i.first -i'../third/*' ...` uses ONLY
    # `../third/*`, and `sed -i'../third/*' -i ...` (bare, no suffix) makes
    # NO backup at all, the earlier suffix discarded along with it. A
    # suffix with NO "*" is always either empty (no backup at all) or a
    # plain literal string GNU sed APPENDS directly to the file argument
    # (`file.txt` + `.bak` = `file.txt.bak`, always alongside the original
    # file, never a new scope decision) -- confirmed this is true even when
    # that literal suffix itself contains "/", since without "*" there is
    # no path-joining semantics at all, just string concatenation, which in
    # practice produces a malformed path GNU sed's own rename immediately
    # rejects (documented residual, not fixed: vanishingly narrow, and
    # accepted rather than modeling GNU's own rename-failure behavior here).
    inplace_suffix_raw = ""
    for idx in flag_positions:
        view = _flag_view(pre_separator_args[idx])
        if _is_inplace_flag(view):
            inplace_suffix_raw = _sed_inplace_suffix_raw(pre_separator_args[idx])
    inplace_suffix_view = unquote_token(inplace_suffix_raw)
    targets = []
    consumed_implicit_script = has_explicit_script
    past_separator = False
    i = 0
    while i < len(args):
        tok = args[i]
        view = _flag_view(tok)
        if view == "--" and not past_separator:
            past_separator = True
            i += 1
            continue
        if not past_separator:
            if _sed_consumes_next_as_script(view):
                i += 2
                continue
            if view == "-i" and i + 1 < len(args) and _flag_view(args[i + 1]) == "":
                i += 2
                continue
            if view.startswith("-"):
                i += 1
                continue
        if not consumed_implicit_script:
            consumed_implicit_script = True
            i += 1
            continue
        targets.append(tok)
        # Documented residual (found by adversarial review of PR #83): the
        # "*" PRESENCE check reads the DECODED view (inplace_suffix_view),
        # but the substitution below replaces "*" in the RAW string --
        # correct for an ordinary literal "*", but when the "*" only exists
        # after ANSI-C decoding (e.g. a suffix given as $'\x2a'), the RAW
        # string has no literal "*" character for .replace() to find, so
        # the substitution silently no-ops and the RAW suffix (still
        # containing the undecoded escape) is returned as-is -- once
        # write_targets() unquotes it later, the resulting "target" is just
        # a bare "*" rather than the true suffix-with-file-substituted
        # path, which can wrongly DENY an otherwise in-scope command (the
        # bare "*" never matches a real scope prefix). Confirmed this can
        # only ever OVER-deny, never bypass: the derived string here and
        # the true (fully-substituted) string always share the same prefix
        # up to the first "*", and scope matching is a plain prefix check
        # with no globbing, so wrongly denying is the only possible
        # direction of error. Not fixed: doing so would require detecting
        # AND substituting against the same (decoded) representation while
        # still returning a RAW value for write_targets()'s single later
        # unquote pass -- a real restructure for an edge case that needs an
        # ANSI-C-escaped asterisk specifically inside a sed backup suffix.
        if "*" in inplace_suffix_view:
            targets.append(inplace_suffix_raw.replace("*", tok))
        i += 1
    return targets


def strip_redirects(segment):
    # Removes every real (mask-aware) >/>> operator, its OPTIONAL leading
    # file-descriptor digits, and its target from the segment, leaving only
    # the command and its own arguments -- so cp/mv/tee/rm/sed-i target
    # extraction below doesn't misread a trailing redirect's operator or
    # target as one of the COMMAND's OWN arguments (found by adversarial
    # review of PR #46, round 1). The fd digits (`2>`, `1>`) are matched
    # ONLY when they form a complete token of their own (whitespace or
    # start-of-segment immediately before them) -- a real bash fd prefix is
    # a word consisting ENTIRELY of digits, so a real argument that merely
    # ENDS in a digit right before an unprefixed redirect (`file2> out`,
    # where "file2" is one whole word) must not have that trailing digit
    # mistaken for an fd number and stripped off with it: `echo abc2> out`
    # writes "abc2" in real bash, not "abc" (found by adversarial review of
    # PR #46, round 2 -- an earlier version's `>>?\s*[^\s<>|&;]+` pattern
    # left a bare digit token behind whenever the redirect had an explicit
    # fd prefix, which the command extractors then misread as a real write
    # target). ONLY the optional digit run is anchored to a token boundary
    # (as its own capture-free group), not the whole match -- an earlier
    # version of this fix anchored the ENTIRE match, which made a BARE ">"
    # (no fd prefix at all) fail to match unless it was ALSO preceded by
    # whitespace, so a real redirect glued directly onto the end of a
    # command argument with no separating space (`cp a b> log`, real bash:
    # this writes to "log" and reads/copies from "a"/"b") was never stripped
    # at all -- cp/mv's own destination detection then fell through to the
    # UNSTRIPPED trailing text and picked the redirect's own in-scope target
    # instead of the real, possibly out-of-scope destination, reintroducing
    # the exact masking bug F024 exists to close (found by adversarial
    # review of PR #46, round 3). A leading alternative strips the
    # fd-duplication form `[n]>&<digits-or-dash>` (`2>&1`, `>&2`, `2>&-`)
    # too: real bash never writes to a file for THIS specific, digit-or-
    # dash-only form (it duplicates one fd onto another, or closes one), so
    # it can never be a real write target, but left unstripped it survived
    # into command_tokens as a bogus flagless "target" once segments_of()
    # stopped fragmenting it (F030) -- its own `[^\s<>|&;]+` target-char
    # class already excludes "&", so this form never matched the plain-
    # redirect alternative either. Deliberately narrower than `>&word` for
    # any word: bash's `>&word` with a NON-numeric, non-"-" word (e.g.
    # `>&outfile.txt`) is `&>word`, an ordinary FILE redirect, not fd
    # duplication -- confirmed against real bash (`echo HELLO >&outfile.txt`
    # creates outfile.txt) -- so widening this alternative's `(?:\d+|-)` to
    # match any word would silently create a NEW unstripped-redirect gap,
    # the opposite of this fix's purpose (found by adversarial review of
    # PR #53, round 1). A THIRD alternative below closes that gap properly
    # (F036): `>&word` is matched and removed like any other real redirect,
    # regardless of whether `word` turns out to be digits/"-"
    # (redirect_targets() is what decides whether a given occurrence is a
    # real target worth denying; this function's only job is removing
    # redirect text so the command's OWN arguments parse cleanly, so the
    # two functions can disagree about "is this fd-dup or a file" without a
    # bug -- stripping a genuine `>&1` here too is harmless, since the
    # plain fd-dup alternative already strips it first at the same
    # position). This alternative DOES take the same optional FD_PREFIX as
    # the plain-redirect alternative -- an earlier version of this fix
    # omitted it, on the reasoning that an fd-prefixed word form
    # (`2>&outfile.txt`) is always a hard bash syntax error with nothing to
    # strip. That reasoning is right for fd 0, 2, and 3+, but wrong for fd
    # 1: `1>&outfile.txt` is a genuine, long-standing bash extension that
    # writes the file (confirmed against real bash and bash's own
    # `redir.c`, which special-cases `redirector == 1`) -- without
    # FD_PREFIX here, the leading "1" survived unstripped as a bogus
    # flagless argument, which could shadow the real target in a
    # last-flagless-token context (cp/mv) or just report the wrong target
    # in a denial (found by adversarial review of PR #63, round 1). The
    # fd-dup alternative's own `(?:\d+|-)` is anchored with a trailing
    # negative lookahead ensuring it only matches a COMPLETE digit/dash
    # word, not a prefix of a longer one -- without it, `>&12abc` (a real
    # file redirect to "12abc", confirmed against real bash) let the greedy
    # `\d+` consume just "12", stripping only `>&12` and leaving "abc" as a
    # phantom trailing argument; the fallback `>&word` alternative below now
    # correctly claims the whole match once the fd-dup alternative can't
    # (found by the same review round).
    masked = mask_quotes(segment)
    kept = []
    last = 0
    FD_PREFIX = r"(?:(?:^|(?<=\s))\d+)?"
    pattern = (
        FD_PREFIX + r">&(?:\d+|-)(?![^\s<>|&;])|"
        + FD_PREFIX + r">&\s*[^\s<>|&;]+|"
        + FD_PREFIX + r">>?\s*[^\s<>|&;]+"
    )
    for m in re.finditer(pattern, masked):
        kept.append(segment[last:m.start()])
        last = m.end()
    kept.append(segment[last:])
    return "".join(kept)


def split_tokens(segment):
    # Splits a command segment into whitespace-delimited tokens, but
    # whitespace INSIDE a quoted span is not a token boundary (exactly like
    # the shell): \S+ runs are found in a quote-MASKED copy (so masked-out
    # quoted whitespace can't match \S, keeping a quoted multi-word string
    # as one run) but sliced from the ORIGINAL segment -- the same
    # mask-then-slice discipline segments_of()/redirect_targets() already
    # use one level up, ported from commit-gate.sh.template's split_tokens()
    # (F011/OVI-64). Before this, write_targets() fed command_tokens a plain
    # `.split()`, which shattered a quoted target containing a space into
    # TWO pseudo-tokens: `rm "my file.txt"` was wrongly DENIED naming just
    # "file.txt" (the quotes stripped from each half independently, no
    # single real path ever reconstructed), and worse, `cp a "out-of-scope
    # in-scope-looking-tail"` was wrongly ALLOWED, since cp/mv's own
    # last-flagless-token destination logic picked the tail fragment -- a
    # reachable fail-open, not just a cosmetic misnaming (found by
    # adversarial review of PR #51, F028; F028 was originally filed
    # against a DIFFERENT function, redirect_target()'s own regex, which
    # F024 closed as a side effect before this feature was picked up --
    # this second, still-open root cause is the one F028's own "Likely fix"
    # note already named).
    masked = mask_quotes(segment)
    return [segment[m.start():m.end()] for m in re.finditer(r"\S+", masked)]


# Wrapper commands that immediately exec the NEXT real command name given to
# them, rather than being the write-relevant command themselves (F044).
# xargs is included even though its full semantics (building an argv from
# stdin, possibly with an unrelated leading command) are more elaborate than
# the other three -- confirmed against real bash that `xargs rm` (piped a
# filename on stdin) genuinely runs rm, and treating "xargs CMD ..." as "this
# segment can end up running CMD ..." is the same order of approximation
# this hook already makes elsewhere (best-effort, not a full shell parser).
# Other real exec-wrappers (nohup, exec, nice, time, setsid, stdbuf, timeout,
# busybox, doas) are NOT included -- a documented, deliberate residual (not
# an oversight): the feature this set closes named exactly these four,
# extending it further is a scope decision for a future feature, not silently
# assumed complete here (found by adversarial review of PR #76).
COMMAND_WRAPPERS = ("sudo", "env", "command", "xargs")

# Each wrapper's own flags (short AND long form) that take a value as a
# SEPARATE argument token (as opposed to attached, e.g. "-uroot"/"-n1"/
# "--user=root", which the walk below already handles correctly without
# this set, since an attached value is part of the SAME token and never
# needs an extra one consumed). Without this, `sudo -u root rm file`,
# `xargs -n 1 rm file`, and `env -u FOO rm file` were all wrongly treated
# as invoking the FLAG'S OWN VALUE ("root"/"1"/"FOO") as the command name,
# silently allowing the real rm -- confirmed against real bash that
# `env -u FOO rm`/`echo f | xargs -n 1 rm` both genuinely delete the
# target file (found by adversarial review of PR #76 round 2, which noted
# the round-1 comment's claim that wrapper flags are "fully skipped" was
# true only for the attached form). Round 2 of that same review confirmed
# TWO further live gaps a short-flag-only set missed: a CLUSTERED short
# flag ending in a value-taking one (`env -iu FOO rm`, `xargs -0n 1 rm`
# -- handled by _is_wrapper_value_flag()'s own cluster check below, not by
# widening this set) and a LONG option given its value as a separate
# argument (`xargs --max-args 1 rm`, `env --unset FOO rm` -- handled by
# including the long form directly in this set, same as the short one).
# Sourced from this platform's own `sudo`/`env`/`xargs` --help output
# (BSD/macOS, this repo's stated platform) plus the reviewer's own
# cross-checked GNU-coreutils list; not independently verified against
# every GNU/Linux coreutils version or every possible long-option spelling
# -- a disclosed, not silent, residual for any flag this set is missing.
WRAPPER_VALUE_FLAGS = {
    "sudo": (
        "-u", "--user", "-g", "--group", "-h", "--host", "-p", "--prompt",
        "-r", "-t", "-U", "-C", "--close-from", "-D", "--chdir",
        "-R", "--chroot", "-T",
    ),
    "env": ("-u", "--unset", "-C", "--chdir", "-S", "--split-string", "-P"),
    "xargs": (
        "-E", "--eof", "-I", "--replace", "-J", "-L", "--max-lines",
        "-n", "--max-args", "-P", "--max-procs", "-s", "--max-chars",
        "-a", "--arg-file", "-d", "--delimiter",
    ),
    "command": (),
}

VAR_ASSIGNMENT_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def _is_wrapper_value_flag(view, value_flags):
    # True if `view` is a flag position that consumes the NEXT token as a
    # separate-argument value: either an exact match against `value_flags`
    # (covers both a bare short flag like "-u" and any long option
    # registered there like "--user"), or a CLUSTERED short-flag token
    # (e.g. "-iu") whose LAST character is itself one of the short flags
    # in `value_flags` -- confirmed against real bash that `env -iu FOO`
    # and `xargs -0n 1` both genuinely consume the following token as the
    # clustered flag's value, the same way a bare "-u"/"-n" would (F044
    # round 3, adversarial review of PR #76 round 2).
    if view in value_flags:
        return True
    if view.startswith("--") or not view.startswith("-") or len(view) <= 2:
        return False
    last_flag = "-" + view[-1]
    return last_flag in value_flags


def _resolve_command_tokens(tokens):
    # Returns (command_name, args) -- the REAL write-relevant command name
    # this segment ultimately invokes, and every token after it -- resolving
    # three kinds of indirection real bash honors but the bare
    # `command_tokens[0] in (...)` comparison this replaced did not (F044):
    # a path-form command name (`/bin/rm`, `./rm`; resolved via
    # os.path.basename(), the same mechanism commit-gate.sh's is_git_token()
    # already uses for git, extended here to cp/mv/tee/rm/sed), one or more
    # leading `VAR=value` environment-assignment prefixes (`FOO=1 rm file`,
    # a real bash feature for setting a variable for one command, not
    # adversarial), and the wrapper commands in COMMAND_WRAPPERS (each of
    # which is followed by its OWN leading flags, also skipped, before the
    # real command name). Confirmed live against real bash that every one of
    # these forms genuinely runs the wrapped/indirected command: `/bin/rm`,
    # `FOO=1 rm`, `command rm`, `env rm`, and `xargs rm` (piped a filename)
    # all deleted the target file; `sudo rm` is the same mechanism as
    # `command`/`env` (immediate exec of the given argv) and not separately
    # re-verified here since this repo's own sandbox has no sudo access.
    # Bounded by len(tokens) (not an unconditional while True) so a
    # pathological all-wrapper token list (e.g. "env env env env") can never
    # loop indefinitely -- it simply resolves to (None, []) once every token
    # is consumed without finding a real command name, the same "not a
    # recognized write command" outcome as any other unrecognized name.
    i = 0
    n = len(tokens)
    while i < n:
        view = _flag_view(tokens[i])
        if VAR_ASSIGNMENT_PATTERN.match(view):
            i += 1
            continue
        name = os.path.basename(view.lstrip("(\\"))
        if name in COMMAND_WRAPPERS:
            value_flags = WRAPPER_VALUE_FLAGS.get(name, ())
            i += 1
            while i < n and _flag_view(tokens[i]).startswith("-"):
                if _is_wrapper_value_flag(_flag_view(tokens[i]), value_flags) and i + 1 < n:
                    i += 2
                else:
                    i += 1
            continue
        return name, tokens[i + 1:]
    return None, []


def write_targets(segment):
    # Returns EVERY real write target in a segment, not just one -- a command
    # can write to multiple targets at once (`rm a b`, `tee f1 f2`, `sed -i`
    # given multiple files, or multiple redirects on one line), and checking
    # only one (an earlier version checked only the last) let an out-of-scope
    # target earlier in the segment go unchecked (F024). Redirect targets and
    # command-type targets (cp/mv/tee/rm/sed -i) are BOTH collected, not
    # treated as alternatives -- an earlier version only checked command-type
    # targets when the segment had NO redirect at all, so a real write
    # command followed by an unrelated trailing redirect (`tee out-of-scope >
    # in-scope-log`) only ever had the redirect's target checked, masking the
    # command's own real target (found by adversarial review of PR #46).
    targets = redirect_targets(segment)
    command_tokens = split_tokens(strip_redirects(segment))
    if command_tokens:
        # _resolve_command_tokens() (F044) handles BOTH the quoting/escaping
        # indirection F040 fixed (a backslash-escaped or quoted command name
        # like `\rm src/other/f.txt`, `"rm" src/other/f.txt` -- ordinary
        # everyday shell, not adversarial, since real bash runs it as plain
        # rm regardless) AND path-form/wrapper-command/env-assignment
        # indirection (`/bin/rm`, `sudo rm`, `FOO=1 rm`, ... -- see its own
        # comment). This is a command-NAME recognition check, not a target-
        # VALUE extraction, so there is no double-unquote risk: the command
        # name itself is never returned as a target.
        command_name, args = _resolve_command_tokens(command_tokens)
        if command_name in ("cp", "mv"):
            targets = targets + cp_mv_targets(args)
        elif command_name in ("tee", "rm"):
            targets = targets + all_flagless_tokens(args)
        elif command_name == "sed":
            targets = targets + sed_inplace_targets(args)
    # Truncate at the first embedded NUL, matching real bash: a NUL byte
    # inside a word (e.g. from a $'...' escape like \x00/\000/\c@/\U00000000)
    # can never survive into a real argv element, since argv strings are
    # NUL-terminated C strings -- real bash silently truncates the WORD
    # there when building the target filename. Confirmed against real bash:
    # `echo x > $'src/other/bad.txt\x00/../../parser/ok.txt'` genuinely
    # creates "src/other/bad.txt" (truncated at the NUL, out of scope), but
    # this hook previously processed the WHOLE string including everything
    # after the NUL, resolving the "../.." past it and landing on the
    # in-scope-looking "src/parser/ok.txt" -- wrongly ALLOWED (F039,
    # confirmed pre-existing on main before F033 too, not a regression;
    # F033 just made it more directly reachable once \x00 genuinely decodes
    # to a real NUL byte instead of staying inert 4-character text).
    # Applied HERE, after unquote_token()'s own decoding is complete and
    # before normalize()/the scope-prefix comparison ever see the target,
    # so it covers every decode route (F031's backslash-unescape, F033's
    # \x/\nnn, F038's \c/\u/\U) that could produce an embedded NUL, not
    # just one specific escape spelling.
    #
    # A decoder exception here is NOT caught locally (F042): main()'s own
    # per-segment try/except is the single place that decides what happens
    # on ANY analysis failure, covering this call and everything else that
    # processes this segment's targets -- see main()'s own comment for why
    # an EARLIER version of this fix tried a per-target raw-text fallback
    # here instead, and why that was a real bypass, not a residual.
    return [unquote_token(t).split("\0", 1)[0] for t in targets]


def normalize(path, project_root):
    # Strips the project-root prefix, then resolves "."/".." segments so a
    # write target that escapes an allowed directory via traversal
    # (`src/allowed/../forbidden/x.txt`, which real bash resolves to
    # src/forbidden/x.txt) no longer merely STARTS WITH the allowed prefix
    # string -- an earlier version returned the path unresolved, so the
    # scope-prefix check (a bare .startswith()) and the lead-owned exact-
    # match check (both read this same return value) were both fooled by
    # traversal. A path that resolves to something outside the project
    # entirely (more ".." than real leading segments, e.g. "../../etc/x")
    # is left with a leading ".." by os.path.normpath, which correctly
    # never matches any scope pattern (found by adversarial review of PR
    # #42/F023, reported as F026). os.path.normpath also strips a trailing
    # "/", which this hook's directory-style scope patterns (and a `cp -t
    # DIR/` destination) rely on for prefix matching -- restored if the
    # pre-normalize path had one, so a destination that IS a scope
    # directory (e.g. "src/parser/") still compares equal to the pattern
    # itself, not just its own strict subdirectories. os.path.normpath is
    # purely lexical (string manipulation only, no filesystem access) --
    # if a scope directory contains a symlink, a target that traverses
    # THROUGH it (e.g. "src/allowed/link/../escape.txt" where "link" points
    # outside "src/allowed/") resolves lexically to "src/allowed/escape.txt"
    # (in scope) while the real write, after the kernel follows the
    # symlink, lands somewhere else entirely. Accepted: this hook has no
    # filesystem access either (it only ever sees the command string), so
    # resolving symlinks would need to run in a live checkout and still
    # couldn't know what the symlink pointed to WHEN the write actually
    # happens; not a regression versus the pre-F026 behavior, which had no
    # traversal resolution at all (found by adversarial review of PR #48,
    # round 1).
    if path.startswith(project_root + "/"):
        path = path[len(project_root) + 1:]
    resolved = os.path.normpath(path)
    if path.endswith("/") and not resolved.endswith("/"):
        resolved += "/"
    return resolved


def main():
    command = sys.argv[1]
    project_root = sys.argv[2]
    patterns = sys.argv[3:]
    for segment in segments_of(command):
        try:
            if _check_segment(segment, project_root, patterns):
                return
        except Exception:
            # ANY exception anywhere while analyzing this segment -- a
            # decoder crash inside write_targets() (still none currently
            # known; F038 rounds 2-3 closed the only two ever found, this
            # is defense-in-depth against the next one), or anywhere else
            # in normalize()/is_dev_exempt()/the scope-comparison below --
            # means denying UNCONDITIONALLY, never comparing any
            # attacker-controlled fallback text against scope (F042).
            #
            # An earlier version of this fix instead fell back to treating
            # raw, undecoded text (either one target's raw token, or the
            # whole raw segment) as if it were a real path to compare
            # against scope patterns, reasoning that a still-escaped
            # string "essentially never" matches a real scope-directory
            # prefix. That reasoning was FALSE: the attacker chooses the
            # raw text, and can trivially place an in-scope-looking prefix
            # (e.g. "src/parser/") immediately before the crash-triggering
            # escape, making the exact SAME construction this fix's own
            # tests used to prove "processing continues past the crash"
            # into a genuine bypass instead -- confirmed live (adversarial
            # review of PR #73): `src/parser/$'\Qx' > src/other/evil.txt`
            # silently ALLOWed the real out-of-scope redirect, because the
            # raw segment fallback text happened to start with "src/parser/".
            # Comparing ANY fallback text against scope patterns is
            # unsound in general, since the fallback text is exactly the
            # part of the input that couldn't be safely analyzed -- there
            # is no text to fall back to that isn't also attacker-
            # controlled. Denying unconditionally removes that lever
            # entirely: a segment (or anything in it) that can't be
            # analyzed is always treated as a violation, full stop, same
            # as this hook already refuses to run rather than guess when
            # PROJECT_ROOT/the scope file/the tool-input JSON can't be
            # resolved (see this file's own header). This also closes a
            # SEPARATE gap the per-target/per-segment split had: the
            # final `print(f"Bash write to '{norm}' is outside...")` call
            # below crashes with UnicodeEncodeError if `norm` ever
            # contains a raw lone surrogate (the actual F038 round 2
            # incident -- a surrogate reaching PRINT, not a ValueError
            # from chr() itself, which F038's own fix already prevents by
            # returning literal escape text instead of a real surrogate
            # character) -- that print() call sits INSIDE this same
            # try/except now, not in a separate uncovered path.
            #
            # A one-line stderr note is added here (F042 round 2): before
            # this fix, ANY decoder crash left a visible Python traceback
            # on stderr; the earlier per-target/per-segment fallback made
            # that failure completely silent, removing the only signal
            # that anything went wrong (found by adversarial review of PR
            # #73). stderr is never captured into DENY_REASON, so this
            # costs nothing operationally.
            print(f"enforce-scope: segment analysis failed, denying: {segment!r}", file=sys.stderr)
            print(
                f"Bash write target in {segment!r} could not be safely analyzed "
                f"(best-effort, pattern-based check; treating as outside your "
                f"assigned scope). {ANNOTATION}"
            )
            return


def _check_segment(segment, project_root, patterns):
    # Returns True once a real scope decision has been printed for this
    # segment (main() must stop entirely at that point, not keep scanning
    # later segments) -- False means this segment raised no violation, so
    # main()'s own loop should move on to the next one.
    for target in write_targets(segment):
        norm = normalize(target, project_root)
        # normalize() runs before this check so equivalent spellings of
        # an exempt path (`/dev//null`, `/dev/./null`)
        # are recognized as the same exact string is_dev_exempt() checks
        # against -- NOT to prevent traversal from laundering a real
        # out-of-scope path INTO looking exempt: is_dev_exempt() is
        # exact-set/pattern membership, not a prefix match, so
        # `/dev/../etc/passwd` (which resolves to `/etc/passwd`) was
        # never going to match regardless of ordering -- confirmed by
        # mutation-testing this ordering claim itself (moving the check
        # before normalize() changed zero assertions). An earlier
        # version of this comment claimed the ordering was load-bearing
        # against traversal laundering; that was true of round 1's
        # broad `startswith("/dev/")` prefix check, but became false
        # once this round narrowed the check to exact membership --
        # found by adversarial review of PR #53, round 2. Ordering WOULD
        # become load-bearing again if DEV_EXEMPT_EXACT/DEV_FD_PATTERN
        # were ever widened back to a prefix-style match.
        if is_dev_exempt(norm):
            continue
        if norm in LEAD_OWNED:
            print(f"state file is lead-owned; report via SendMessage instead. {ANNOTATION}")
            return True
        if not any(norm.startswith(p) for p in patterns):
            print(
                f"Bash write to '{norm}' is outside your assigned scope "
                f"(best-effort, pattern-based check; see .claude/teammate-scope.txt). "
                f"{ANNOTATION}"
            )
            return True
    return False


main()
PYEOF
)

    if [ -n "$DENY_REASON" ]; then
        deny_json "$DENY_REASON"
    fi
fi

exit 0
