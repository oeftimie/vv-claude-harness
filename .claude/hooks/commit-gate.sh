#!/bin/bash
# VV Claude Code Harness - PreToolUse commit-content gate
# Runs before Bash tool calls; no-ops unless the command tokenizes to a
# segment starting with "git" whose subcommand is "commit" (see
# segment_subcommand below). Three earlier revisions used progressively wider
# regexes for this decision (bash substring match -> \bgit\s+commit\b ->
# \bgit\b.*\bcommit\b -> \bgit\b[^|;&]*(?:^|\s)commit(?:\s|$)), each fixing
# one adversarial-review finding while introducing another (a filename or
# branch name containing "commit"/"add" as a substring; a newline inside the
# command letting an unrelated later line match; a separator with no
# surrounding whitespace bypassing the boundary check entirely). Real
# tokenization replaces all four of those regexes: it compares whole tokens,
# so a substring occurrence inside a longer word is never a match, and
# segmenting on the control operators command_segments recognizes (see its
# own comment) up front means a token from one logical command can't pair
# with a token from another -- for those operators specifically. This is
# still pattern-based tokenization, not a real shell parser: an operator
# command_segments doesn't split on, or a leading token segment_subcommand
# doesn't know to skip, can still glue two logical commands into one
# unrecognized segment (see Residual holes below for the ones found so far).
# Adapted from Setlist's commit-gate.sh (Alex Ciortan, CC BY 4.0).
#
# Checks (each names a closed finding class in its denial):
#   0. compound-stage-and-commit -- denies a command that stages AND commits in one
#      step (`git add|stage ... && git commit`, or
#      `git commit -a`/`-i`/`--all`/`--include`, including combined short-flag
#      clusters like `-am`). A pre-commit hook can only scan an index that already
#      holds the content; newly staged content in the SAME command is invisible to
#      Check 1's scan. Quoted spans (single, double, ANSI-C $'...') are masked (not
#      deleted -- see mask_quotes) when finding segment boundaries, so a commit
#      message like `git commit -m "run git add later"` does not false-trip on the
#      words "git"/"add" inside it, while the real tokens of a quoted invocation
#      like `git "commit" -m x` still tokenize correctly (F025).
#   1. secret-assignment / url-credential -- scans staged additions
#      (`git diff --cached -U0`, `+` lines) for key/secret/password/token
#      assignments >= 16 chars (keyword may appear as part of a larger identifier,
#      e.g. AWS_SECRET_ACCESS_KEY or a quoted JSON key, not just a bare word --
#      this trades some false positives for fewer false negatives, acceptable
#      since the pattern set is the project's own tuning surface) and
#      URL-embedded credentials (any scheme, not just http/https). Any staged
#      path whose basename matches `*.env.example` is exempt. Denial names the
#      finding class, file, and line number -- NEVER the matched value or line
#      content, to avoid writing a candidate secret into the transcript or hook
#      logs. Pattern set is tuned by editing this copied-then-project-owned file
#      directly; no separate runtime override mechanism exists. The pattern is
#      still worst-case polynomial in a single line's length on adversarially
#      repeated keyword-shaped text with no valid terminator (removing its
#      leading wildcard prefix cut the constant factor by roughly two orders of
#      magnitude but did not change its complexity class) -- SECRET_SCAN_MAX_LEN
#      bounds any one line's scan time regardless, and SCAN_TIME_BUDGET_SECONDS
#      bounds the total across every line, so neither the pattern's exact
#      complexity nor the number of staged lines can make this hook hang.
#   2. style-violation -- opt-in via harness.json's `style_gate` key (shape
#      `{"enabled": false}`; absent, false, or any non-object value means off).
#      Example shipped: an em-dash ban, built from an escape sequence so this
#      file never contains the character.
#
# Fail-open for: parse errors, not a git repo, `git diff --cached` exiting non-zero
# or timing out (COMMIT_GATE_DIFF_TIMEOUT env var, default 5 seconds -- overridable
# only for testing; production installs should not set it), the scan-time budget
# being exceeded, python3 unavailable, or any unexpected scanning exception
# (logged to stderr as the exception TYPE NAME only, never its message/args,
# since exception text can itself carry matched line content).
#
# Residual holes: `git commit <pathspec>` commits the working tree without
# staging, which this hook cannot distinguish from a normal commit of
# already-staged content. A single staged line longer than SECRET_SCAN_MAX_LEN
# is only scanned up to that length -- a secret past that point on the same
# line is silently missed (accepted: scanning overlapping windows to close
# this adds real complexity for a line length no ordinary commit approaches).
# No automated latency test exists for any hook in this repo; design target
# (undocumented elsewhere) is under 1 second for a typical commit's staged diff,
# since this hook blocks an interactive PreToolUse Bash call synchronously.
# Check 0's quote handling (mask_quotes/unquote_token) covers single/double/
# ANSI-C quoting only; recursive or nested quoting is out of scope, consistent
# with this repo's existing pattern-based-and-evadable-by-construction posture
# for Bash-command hooks. A quoted span containing a heredoc body is not
# masked correctly (the quote-matching regex doesn't cross heredoc syntax) --
# if the heredoc body's literal text happens to read like a staging command,
# this can produce a false denial (fail-closed, over-blocking); accepted,
# same evadable-by-construction posture.
# parse_command joins backslash-newline shell continuations (outside quotes)
# into a single space before segmenting, so `git \` + newline + `commit -m x`
# is recognized as one git-commit invocation rather than being split into two
# segments that neither alone tokenize as one -- an earlier version of this
# hook didn't join continuations, which no-op'ed the entire gate for a
# continued command (fail-open bypass, not merely a missed check: the secret
# scan itself was skipped). join_continuations runs on the whole raw command
# regardless of quote boundaries (it has no quote awareness of its own), so a
# continuation that happens to fall inside a quoted commit message is joined
# to a space there too -- a minor content change inside the message text, not
# a detection gap, since quoted content is preserved (not erased) through
# segmentation either way (see mask_quotes). Not attempted:
# joining a continuation that falls inside a heredoc body (see above) --
# that would require tracking heredoc state across the whole command, not a
# one-line fix like the unquoted case was.
# segment_subcommand recognizes "git" invoked directly, via a path
# (/usr/bin/git, ./git), backslash-prefixed (\git, the standard alias-bypass
# idiom), or paren-wrapped ("(git ..."); it also skips a closed set of shell
# reserved words that can lead a simple command inside a control structure
# (SHELL_LEADING_KEYWORDS: "then", "do", "else", "elif" -- e.g. "if true;
# then git commit -m x; fi"). A brace-grouped invocation ("{ git commit -m
# x; }") is not recognized, and neither is an invocation wrapped in another
# command (`sudo git commit`, `env FOO=1 git commit`) -- accepted rather
# than maintaining an open-ended wrapper/grouping-command allowlist (sudo,
# doas, env, nice, timeout, brace groups, ...) in a way the closed
# keyword/flag classification isn't. A `case ... in PATTERN) git commit
# ...` segment is also not recognized: the token immediately before "git"
# is an arbitrary case pattern, not a fixed word to skip, so closing this
# would need real shell parsing rather than one more set entry -- accepted,
# same class as the wrapper-command gap. GIT_FLAGS_WITH_VALUE enumerates
# the global flags that consume a following space-separated argument,
# probed mechanically against git 2.52 (see its own comment above); it is
# not a full git CLI parser and does not claim to track every future git
# release -- for example, `--super-prefix` consumed an argument through at
# least git 2.38 but is absent from handle_options() by 2.43 (removed
# somewhere in that range; not pinned closer), so it was dropped from the
# set per the 2.52 probe; this is a narrow regression on git older than
# roughly 2.42, not a general bypass on any currently supported git.
# GIT_COMMIT_LONG_OPTIONS/VALUE_TAKING_LONG_FLAGS (F032) is a second
# git-version-pinned table with the identical drift exposure: last
# verified against git 2.52.0, mechanically re-derived from git's own
# option-parsing errors (not assembled from memory). If a future git
# version adds, removes, or renames a `git commit` long option -- changing
# which prefixes are ambiguous with which -- this table needs
# re-verification against that version; a stale table's failure mode is a
# missed abbreviation (an over-cautious deny of a real command, never a
# bypass, since _resolve_long_flag() only ever narrows what it recognizes,
# it does not invent new matches).

INPUT=$(cat)

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$PROJECT_ROOT" 2>/dev/null || exit 0

COMMAND=$(echo "$INPUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('tool_input', {}).get('command', ''))
" 2>/dev/null)

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

DENY_REASON=$(python3 - "$COMMAND" "$PROJECT_ROOT" <<'PYEOF'
import fnmatch
import json
import os
import re
import subprocess
import sys
import time

DENY_COMPOUND = (
    "compound-stage-and-commit: this command stages and commits in one step, but "
    "a pre-commit hook can only scan an index that already holds the content -- "
    "newly staged content in the same command is invisible to the secret scan. "
    "Repair: split into a separate 'git add <files>' followed by 'git commit' "
    "with no staging flags (avoid -a/-i/--all/--include)."
)
REPAIR_STAGED = (
    "remove or redact the flagged value from the staged diff, or move it to an "
    "untracked file (e.g. .env, already gitignored)"
)
REPAIR_STYLE = "replace the em dash with a comma, period, or parentheses"

STAGING_FLAGS = {"-a", "-i", "--all", "--include"}

# The set of long options `git commit` recognizes, used as the
# disambiguation universe for _resolve_long_flag(): real git accepts any
# UNAMBIGUOUS prefix of a long option (`git commit --mess ...` resolves to
# `--message`), so a fixed VALUE_TAKING_LONG_FLAGS exact-string set alone,
# however complete, is still bypassable via abbreviation (confirmed
# against real git 2.52.0: `--mess`, `--messa`, `--trail` etc. all resolve
# and genuinely stage a dirty file via a trailing `-- -a`, found by
# adversarial review of PR #56, round 1). Built from TWO sources, not
# memory or `-h` output alone: `git commit --git-completion-helper` (the
# baseline), THEN a systematic probe of every 2- and 3-letter `--xx`/`--xyz`
# prefix against real git, collecting every option name mentioned in the
# resulting "ambiguous option: ... (could be A or B)" error messages --
# this second pass is what surfaced --allow-empty/--allow-empty-message
# and their --no- forms, which --git-completion-helper's own suggestion
# list omits entirely (confirmed: `git commit --al` genuinely errors
# "ambiguous option: al (could be --allow-empty or --allow-empty-message)"
# in real git, a 3-way ambiguity with --all that neither source alone
# would have revealed). NOT included: git's further "--no-no-X" double-
# negation forms (e.g. --no-no-verify, git's auto-negation of its own
# --no-verify) -- confirmed real but not resolved by this function, an
# accepted, narrow residual (this deep a double-negation abbreviation is
# not a realistic attack shape). The `--no-`-prefixed entries are real,
# independently abbreviation-eligible strings in git's own resolver even
# though none of them are in VALUE_TAKING_LONG_FLAGS below.
GIT_COMMIT_LONG_OPTIONS = (
    "--quiet", "--verbose", "--file", "--author", "--date", "--message",
    "--reedit-message", "--reuse-message", "--fixup", "--squash",
    "--reset-author", "--trailer", "--signoff", "--template", "--edit",
    "--cleanup", "--status", "--gpg-sign", "--all", "--include",
    "--interactive", "--patch", "--unified", "--inter-hunk-context",
    "--only", "--no-verify", "--dry-run", "--short", "--branch",
    "--ahead-behind", "--porcelain", "--long", "--null", "--amend",
    "--no-post-rewrite", "--untracked-files", "--pathspec-from-file",
    "--pathspec-file-nul", "--verify", "--post-rewrite",
    "--allow-empty", "--allow-empty-message",
    "--no-allow-empty", "--no-allow-empty-message",
)

# Long `git commit` flags that take a bare (space-separated) value, e.g.
# `git commit --message foo`. Unlike VALUE_TAKING_SHORT_FLAGS/
# REQUIRED_VALUE_SHORT_FLAGS (F027), no split into an "attached-only" vs
# "required" subset is needed here: verified against `git commit -h` that
# all 14 are genuinely required-value (shown as `<value>`, never the
# bracketed `[=<mode>]` optarg syntax `-u[<mode>]`/`-S[<keyid>]` use), so
# every bare occurrence unconditionally consumes the next token as its
# value. The attached "--message=foo" form is a single token that never
# equals any string in this set, so it's never mistaken for the bare form
# and needs no special handling. Before this, has_staging_flag() only
# recognized this space-separated-value pattern for SHORT flags (F027),
# then only 8 of these 14 long flags (round 1 of F032, missing --trailer,
# --reedit-message, --cleanup, --unified, --inter-hunk-context, and
# --pathspec-from-file -- found by the same PR #56 round-1 review that
# caught the abbreviation gap).
VALUE_TAKING_LONG_FLAGS = {
    "--message", "--file", "--author", "--date", "--template",
    "--fixup", "--squash", "--reuse-message", "--trailer",
    "--reedit-message", "--cleanup", "--unified", "--inter-hunk-context",
    "--pathspec-from-file",
}


def _resolve_long_flag(view):
    # Real git accepts any prefix of a long option that uniquely identifies
    # it among ALL options the subcommand recognizes -- not just among the
    # value-taking ones -- so resolution must check against the FULL
    # GIT_COMMIT_LONG_OPTIONS universe, not just VALUE_TAKING_LONG_FLAGS,
    # to correctly mirror real git's own ambiguity rule. Returns the
    # resolved full flag name, or None if `view` doesn't uniquely resolve
    # (no match, or an ambiguous prefix of 2+ options) -- in the ambiguous
    # case, real git itself errors out and nothing runs, so treating it as
    # "not a recognized flag" here is always safe, never a bypass.
    if view in GIT_COMMIT_LONG_OPTIONS:
        return view
    matches = [o for o in GIT_COMMIT_LONG_OPTIONS if o.startswith(view)]
    return matches[0] if len(matches) == 1 else None

# Global git flags that consume a following argument in their space-separated
# form (the "=value" form, e.g. --git-dir=.git, is already handled -- it's a
# single token with no following argument to skip). This set was probed
# mechanically against git 2.52, not assembled from memory: every long-option-
# shaped string in the git binary was tried as `git <flag> ARG1VAL ZZBOGUS`
# and classified by whether git reports ZZBOGUS (consumes an arg) or the flag
# itself (doesn't); all 52 single-letter short flags were swept the same way.
# An earlier version had only -C/-c, then a second pass added --git-dir/
# --work-tree/--namespace/--exec-path/--super-prefix/--attr-source from
# memory rather than probing -- that pass both missed two real ones
# (--config-env, --shallow-file) and kept two that don't actually consume a
# following argument (--exec-path prints and exits; --super-prefix was
# removed in 2.52) -- found by adversarial review of PR #40. Any flag missing
# from this set causes the same bypass: segment_subcommand returns the flag's
# VALUE as the subcommand, no-op'ing the entire gate.
GIT_FLAGS_WITH_VALUE = {
    "-C", "-c", "--config-env", "--git-dir", "--work-tree",
    "--namespace", "--attr-source", "--shallow-file",
}

# No leading wildcard prefix before the keyword: an earlier version had
# "[A-Za-z0-9_.\-]*" before the keyword alternation, which is a second
# independent quantifier over an overlapping character class -- adversarially
# repeated keyword-shaped text with no valid 16+ char terminator forced
# polynomial-time backtracking (found by adversarial review of PR #40).
# Anchoring directly on the keyword still matches AWS_SECRET_ACCESS_KEY= and
# "api_key": (the suffix wildcard after the keyword covers those), it just no
# longer also searches for an arbitrary-length prefix before it.
SECRET_KEYWORDS = "key|secret|password|passwd|pwd|token"
SECRET_PATTERN = re.compile(
    r"(?i)(?:" + SECRET_KEYWORDS + r")[A-Za-z0-9_.\-]*['\"]?\s*[:=]\s*"
    r"['\"]?([A-Za-z0-9+/_.\-]{16,})"
)
# Bounds any single line's scan time regardless of the pattern's complexity;
# no real secret assignment is anywhere close to this long.
SECRET_SCAN_MAX_LEN = 2048
# Bounds TOTAL scan time across every staged line, since the per-line cap
# alone doesn't bound aggregate time against many adversarial lines (~1000
# adversarially-crafted 2048-char lines measured at ~18s combined even with
# the per-line cap in place).
SCAN_TIME_BUDGET_SECONDS = 2.0
URL_CREDENTIAL_PATTERN = re.compile(r"[a-zA-Z][a-zA-Z0-9+.\-]*://[^\s:/@]+:[^\s@/]+@")
EM_DASH_PATTERN = re.compile("\u2014")


QUOTE_SPAN_PATTERN = re.compile(r"\$'(?:[^'\\]|\\.)*'|'[^']*'|\"(?:[^\"\\]|\\.)*\"")


def mask_quotes(command):
    # Replaces each quoted span (single, double, ANSI-C $'...') with a same-
    # LENGTH run of NUL placeholder characters -- never a real separator or
    # token character -- so that a real control operator INSIDE a quoted
    # string (a commit message like "git add later; do it now") doesn't get
    # mistaken for a real one when command_segments() scans this masked copy
    # for split positions. Unlike deleting the quoted span (an earlier
    # version of this hook did that, via a function named strip_quotes),
    # preserving length means split positions found in the masked copy line
    # up character-for-character with the ORIGINAL command, so
    # command_segments() can slice the real, still-quoted text for each
    # segment -- deleting the span instead erased the "git"/"commit" tokens
    # themselves whenever either was quoted (`git "commit" -m x`), silently
    # disabling the entire gate including the secret scan on a real staged
    # secret. Found by adversarial review of PR #42 in a sibling hook
    # (enforce-scope.sh.template/F023, same root cause: quote-erasure
    # deleting content load-bearing for the gate's decision), then
    # independently confirmed in THIS hook and fixed as F025 (PR #44).
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
    # Ported verbatim from enforce-scope.sh.template's own decoder (F038),
    # since this hook's own unquote_token() (below) had the identical gap:
    # a $'...' wrapper was stripped with a plain regex substitution that
    # never decoded what was INSIDE it, so an escaped spelling of "git"
    # (`$'\x67it'`) reached is_git_token() undecoded and failed to match --
    # which, because is_git_token() is the ONLY thing deciding whether a
    # segment is git-shaped at all, silently disabled this hook's ENTIRE
    # analysis (both the compound-stage-and-commit check and the secret
    # scan) for that segment, not just a cosmetic miss (F051, adversarial
    # review of PR #77). See enforce-scope.sh.template's own copy of this
    # function for the full formula verification, version-split notes
    # (bash 3.2.57 vs 5.3.15's differing \c? behavior), and the surrogate/
    # multi-char-uppercase crash history (F038 rounds 1-3) -- reproduced
    # here unchanged since the decode logic itself is bash-version
    # behavior, not specific to either hook.
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
            upper = ctrlchar
        return chr(ord(upper) & 0x1F)
    if u4 is not None:
        return _unicode_escape_or_literal(u4, "u")
    if u8 is not None:
        return _unicode_escape_or_literal(u8, "U")
    return ANSI_C_SIMPLE_ESCAPES.get(other, "\\" + other)


def _unicode_escape_or_literal(hexdigits, prefix):
    # Ported alongside _decode_ansi_c_escape() (F051); see
    # enforce-scope.sh.template's own copy for the full incident this
    # closes (a lone surrogate crashing this hook's own denial-printing
    # step into a silent no-op).
    codepoint = int(hexdigits, 16)
    if 0xD800 <= codepoint <= 0xDFFF or codepoint > 0x10FFFF:
        return "\\" + prefix + hexdigits
    return chr(codepoint)


def unquote_token(token):
    # Strips quote characters from a single ALREADY-TOKENIZED word -- never
    # used to re-segment or re-tokenize, only to normalize a token (which may
    # be fully quoted, "commit"/'commit'/$'commit', or partially quoted,
    # com"mit") before comparing it to "git", a subcommand name, or a flag
    # string. Safe here specifically because split_tokens() has already
    # resolved token boundaries using mask_quotes(); this function never
    # looks at whitespace or separators (F025, PR #44).
    #
    # A $'...' span's inner text is now decoded per bash's ANSI-C quoting
    # grammar in this SAME substitution, and a bare backslash outside
    # quotes is now stripped too (both ported from enforce-scope.sh.
    # template's own unquote_token(), F033/F038 and F031 respectively) --
    # this function previously only stripped the $'...' WRAPPER without
    # decoding what was inside it, and never touched an interior backslash
    # at all, so `g\it`/`\g\i\t`/`$'\x67it'` all reached is_git_token()
    # still spelling something other than the bare string "git", silently
    # disabling this hook's entire analysis for that segment (F051, found
    # by adversarial review of PR #77). Confirmed live before this fix:
    # `g\it commit -a -m "test"` and `$'\x67it' commit -a -m "test"` both
    # silently ALLOWed a real compound-stage-and-commit violation, and
    # with a real secret staged, `g\it commit -m "add config"` silently
    # ALLOWed it through where the bare `git commit -m "add config"`
    # correctly denied secret-assignment.
    token = re.sub(
        r"\$'((?:[^'\\]|\\.)*)'",
        lambda m: ANSI_C_ESCAPE_PATTERN.sub(_decode_ansi_c_escape, m.group(1)),
        token,
    )
    token = token.replace("'", "").replace('"', "")
    return re.sub(r"\\(.)", r"\1", token)


def _flag_view(tok):
    # A SEPARATE view from unquote_token(), used ONLY for decisions that
    # STOP the flag scan or SKIP a token as an opaque value (the "--"
    # pathspec-separator check, and every "this flag takes a bare value,
    # skip the next token" decision) -- never for the flag-string MATCH
    # itself, where over-recognizing due to unquote_token()'s own blanket
    # backslash-strip is safe-directional (a false DENY, never a false
    # ALLOW). Unlike unquote_token(), this does NOT strip a bare backslash
    # outside quotes: real bash treats a backslash INSIDE single or double
    # quotes as a literal character, not an escape, but unquote_token()'s
    # final backslash-strip line (ported from enforce-scope.sh's own
    # accepted residual there, F031/F051) is quote-context-BLIND -- it
    # strips a backslash the same way whether it came from inside a quote
    # (where it should stay literal) or from an entirely unquoted token
    # (where real bash DOES strip it). That residual is genuinely harmless
    # in enforce-scope.sh (it only ever changes a PATH VALUE compared
    # against a scope prefix), but dangerous here: `git commit -m x '\--'
    # -i tracked.txt` passes git the LITERAL 3-character pathspec "\--"
    # (single quotes preserve everything, confirmed against real git:
    # errors "pathspec '\--' did not match" unless a file literally named
    # "--" happens to exist and be tracked, in which case the command
    # genuinely stages AND commits tracked.txt via -i in one step) -- NOT
    # the 2-character string "--", so it must not be treated as the real
    # pathspec separator. unquote_token()'s own blanket backslash-strip
    # reduced it to plain "--" anyway, which the (pre-this-fix) separator
    # check then wrongly treated as ending the flag scan before it ever
    # reached the real -i -- a genuine fail-open this PR's own escape-
    # decoding fix introduced as a side effect (F051 round 2, adversarial
    # review of PR #79). has_staging_flag()'s long-flag/short-flag-cluster
    # bare-value skips use this view for the same reason (see
    # _consumes_next_token()). segment_subcommand()'s own GIT_FLAGS_WITH_VALUE
    # 2-token skip and generic "-"-prefix 1-token skip were NOT converted:
    # they only ever run on tokens BEFORE the subcommand, and confirmed
    # against real git, any token whose raw form has this same
    # backslash-preserved-by-quotes shape (`git '\-C' commit ...`, `git
    # '\--' commit ...`) makes real git reject the whole invocation
    # ("'\-C' is not a git command") before anything is staged or committed
    # -- unlike the post-subcommand case above, where git tolerates the
    # divergent token as an ordinary pathspec and keeps parsing later
    # flags. Not independently reachable, so left on the raw token.
    # Not stripping the backslash here means a rare unquoted-and-escaped
    # separator (`\--`, no quotes at all -- where real bash DOES strip the
    # backslash, giving a genuine "--") is no longer recognized as one
    # either, over-denying instead of under-denying: an accepted,
    # documented trade in the safe direction, not a new bypass (confirmed:
    # such a token doesn't even start with "-" once viewed this way, so it
    # falls through as an ordinary non-flag token, extending the scan
    # rather than truncating it).
    tok = re.sub(
        r"\$'((?:[^'\\]|\\.)*)'",
        lambda m: ANSI_C_ESCAPE_PATTERN.sub(_decode_ansi_c_escape, m.group(1)),
        tok,
    )
    return tok.replace("'", "").replace('"', "")


def split_tokens(segment):
    # Splits a command segment into whitespace-delimited tokens, but whitespace
    # INSIDE a quoted span is not a token boundary (exactly like the shell):
    # \S+ runs are found in a quote-MASKED copy (so masked-out quoted
    # whitespace can't match \S, keeping a quoted multi-word string as one
    # run) but sliced from the ORIGINAL segment, mirroring command_segments()'s
    # own mask-then-slice discipline one level deeper. A naive segment.split()
    # instead treated whitespace inside a quoted commit message as real token
    # boundaries, shattering it into pseudo-tokens that has_staging_flag then
    # misread: a quoted "--" anywhere in the message (`git commit -m "see --"
    # -a`) could shadow a REAL staging flag later in the segment (fail-open:
    # the "--" pseudo-token was misread as the pathspec separator, and the
    # scan stopped before reaching the real -a), and flag-shaped words inside
    # a quoted message ("fix: handle -a and -i staging flags") could trigger a
    # false compound-stage-and-commit denial on a clean repo. This was masked
    # by accident under the OLD strip_quotes()-based design (which deleted the
    # message text these pseudo-tokens came from) and only became visible once
    # F025 started preserving quoted content -- found by adversarial review of
    # PR #44.
    masked = mask_quotes(segment)
    return [segment[m.start():m.end()] for m in re.finditer(r"\S+", masked)]


def command_segments(command):
    # Splits on shell control operators, including a literal newline -- a
    # multi-line command (a heredoc'd commit message, or two commands
    # separated by a newline rather than ;/&&) must not let a "git" token on
    # one line pair with an unrelated token on another line. "&" (background
    # execution, and the leading half of "|&") is itself a control operator
    # exactly like ";" -- an earlier version omitted it, so everything before
    # an "&" stayed glued to everything after it and only the first
    # segment's subcommand was ever seen (found by adversarial review of PR
    # #40, round 6). "&&" is listed as its own alternative before the
    # single-character class, so it is still consumed whole and never
    # mistaken for two lone "&" separators. Split positions are found in a
    # quote-MASKED copy (see mask_quotes) but sliced from the ORIGINAL
    # command text, so a segment's real "git"/"commit" tokens survive intact
    # for tokenization even when quoted (see mask_quotes for why deleting
    # them instead was a critical bug, F025). A "&" is NOT a segment
    # separator when it immediately follows a ">": real bash lexes ">&" as
    # one fd-duplication operator (`2>&1`, `>&2`), not a redirect
    # immediately followed by a background/AND "&" -- splitting there was a
    # REAL GATE BYPASS, not just a usability false-positive (unlike the
    # identical bug in the sibling hook enforce-scope.sh.template, F030):
    # `git commit 2>&1 -am "x"` split into segments ['git commit 2>',
    # '1 -am "x"'], so has_staging_flag() never saw the real -am flag in
    # the second segment (its first token is "1", not "git"/"commit", so
    # segment_subcommand() never even recognized it as a git-commit
    # segment) -- confirmed against real bash that this genuinely stages
    # and commits in one step (found by adversarial review of PR #53,
    # F030, filed as F034). The mirror shape needs the SAME treatment: a
    # "&" is ALSO not a separator when immediately FOLLOWED by a ">" --
    # `&>`/`&>>` is bash's combined stdout+stderr redirect, one operator,
    # not background-"&" followed by a redirect. An initial version of
    # this fix only guarded the "&" PRECEDED by ">" (matching enforce-
    # scope.sh's own needs, where this shape is harmless -- that hook
    # extracts write targets independently of segment/command-recognition
    # boundaries, so a `&>`-caused split still leaves the redirect target
    # itself checkable in the fragment it lands in). Here it is NOT
    # harmless: `git commit &> out.log -a -m "bypass"` split into
    # segments ['git commit', '> out.log -a -m "bypass"'], putting the
    # real staging flags in a segment whose first token is ">", not
    # "git"/"commit" -- segment_subcommand() never recognized it, so
    # has_staging_flag() never ran, an identical bypass to the `2>&1`
    # case this feature was filed to close (found by adversarial review
    # of PR #58, F034). `&&` is unaffected (consumed whole by its own
    # earlier alternative); real background "&" (not adjacent to any ">"
    # on either side) still splits.
    masked = mask_quotes(command)
    segments = []
    start = 0
    for m in re.finditer(r"\|\||&&|[|;\n]|(?<!>)&(?!>)", masked):
        segments.append(command[start:m.start()])
        start = m.end()
    segments.append(command[start:])
    return [s.strip() for s in segments if s.strip()]


def is_git_token(tok):
    # Matches "git" invoked via a path (/usr/bin/git, ./git), wrapped in a
    # subshell paren ("(git add ..."), or backslash-prefixed ("\git ...", the
    # standard idiom for bypassing a shell alias named git, not adversarial
    # evasion) -- not just the bare literal "git". Found by adversarial
    # review of PR #40 (bare-literal matching let /usr/bin/git and (git ...
    # no-op the gate entirely); \git found in round 5 of the same review.
    return os.path.basename(tok.lstrip("(\\")) == "git"


SHELL_LEADING_KEYWORDS = {"then", "do", "else", "elif"}


def segment_subcommand(tokens):
    # Returns (subcommand_token, index_in_tokens) for a "git <subcommand> ..."
    # segment, e.g. ("commit", 3) for ["git", "-C", ".", "commit", "-m", "x"].
    # Skips "VAR=value" env-assignment prefixes, the closed set of shell
    # reserved words that can lead a simple command inside a control
    # structure (SHELL_LEADING_KEYWORDS -- "if true; then git commit -m x; fi"
    # splits into a segment starting "then git commit ...", and without this
    # skip "then" is mistaken for the whole segment being non-git-shaped;
    # found by adversarial review of PR #40, round 6), and git global flags --
    # both the ones that take no argument and the ones that do (see
    # GIT_FLAGS_WITH_VALUE). Returns (None, None) if this segment isn't a
    # real "git <subcommand>" invocation at all. A "case ... in PATTERN)"
    # segment is NOT handled here: unlike the four reserved words above, the
    # token immediately before the command is an arbitrary case pattern, not
    # a fixed word to skip -- accepted as a residual hole (see header).
    i = 0
    while i < len(tokens) and (
        re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tokens[i])
        or tokens[i] in SHELL_LEADING_KEYWORDS
    ):
        i += 1
    if i >= len(tokens) or not is_git_token(tokens[i]):
        return None, None
    i += 1
    while i < len(tokens):
        tok = tokens[i]
        if tok in GIT_FLAGS_WITH_VALUE:
            i += 2
            continue
        if tok.startswith("-"):
            i += 1
            continue
        return tok, i
    return None, None


def join_continuations(command):
    # Joins a backslash-newline shell continuation to a space, but only when
    # the backslash immediately before the newline is itself unescaped: an
    # ODD run of backslashes right before a newline means the last one
    # escapes the newline (a real continuation); an EVEN run (including
    # zero) means the newline is a real command separator and the
    # backslashes are literal characters, which must be left alone. The
    # first version of this fix used a blanket command.replace("\\n", " ")
    # with no parity check, which wrongly joined "echo a\\\\" + newline +
    # "git commit" (an ESCAPED backslash followed by a genuine separator
    # newline) into one segment, hiding the second command from the gate
    # entirely -- found by adversarial review of PR #40, round 6.
    def repl(m):
        backslashes = m.group(1)
        if len(backslashes) % 2 == 1:
            return backslashes[:-1] + " "
        return backslashes + "\n"

    return re.sub(r"(\\*)\n", repl, command)


def parse_command(command):
    # Segments the raw command once, then finds each segment's git subcommand
    # (if any) -- a single source of truth shared by the no-op decision and
    # the compound-stage-and-commit check below. Backslash-newline
    # continuations are joined to a space before anything else, so a
    # continued command isn't split into fragments that individually fail to
    # tokenize as git-shaped (see header). Tokens are split from the still-
    # quoted segment text with split_tokens() (quote-aware, so whitespace
    # inside a quoted string isn't a token boundary) and THEN unquoted one at
    # a time -- never the other way around -- so a quoted token like "commit"
    # or com"mit" is still recognized as the word "commit" once tokenized,
    # instead of being erased before tokenization ever saw it (F025).
    joined = join_continuations(command)
    parsed = []
    for seg in command_segments(joined):
        raw_tokens = split_tokens(seg)
        tokens = [unquote_token(t) for t in raw_tokens]
        # views[i] is _flag_view(raw_tokens[i]) -- computed from the RAW,
        # still-quoted token, never from tokens[i] (which has ALREADY had
        # its quotes AND backslashes stripped by this point, so calling
        # _flag_view() on tokens[i] instead of raw_tokens[i] would be a
        # no-op: the very distinction it exists to preserve is already
        # gone). has_staging_flag() uses this parallel list -- not tokens
        # -- for its one dangerous "does this consume the next token"
        # decision (F051 round 2, adversarial review of PR #79).
        views = [_flag_view(t) for t in raw_tokens]
        sc, idx = segment_subcommand(tokens)
        parsed.append((tokens, sc, idx, views))
    return parsed


# Short flags that take an attached value in a cluster like "-mfix" or
# "-Fdraft.txt" -- once one of these appears, the rest of that cluster is its
# value, not further flag letters. Without this, "-mfix" was denied for
# containing the letter "i", and "-- -a.txt" (a pathspec after "--", not a
# flag at all) was denied too (found by adversarial review of PR #40).
VALUE_TAKING_SHORT_FLAGS = set("mFtSCcu")

# Subset of VALUE_TAKING_SHORT_FLAGS whose BARE form (last char of a cluster,
# nothing attached) also consumes the NEXT token as its value. -S/-u are
# real git optargs (PARSE_OPT_OPTARG): bare "-S"/"-u" use a built-in default
# and do NOT take the next token -- `git commit -u -a -m x` and `git commit
# -S -a -m x` both genuinely stage and commit in real git (confirmed against
# git 2.52.0: bare -S/-u behave exactly like no-value flags such as -n/-s).
# Treating all seven letters as bare-value-taking (an earlier version of this
# fix did) made a bare/clustered "-u"/"-S" swallow the token after it as if
# it were a value, hiding a REAL trailing staging flag beyond it -- a gate
# bypass `main` never had (found by adversarial review of PR #49, round 2).
# -S/-u still belong in VALUE_TAKING_SHORT_FLAGS above: their ATTACHED form
# (`-uall`, `-Skeyid`) is a real value and must not be misread as more flag
# letters (confirmed: `-ua` -> "Invalid untracked files mode 'a'", so "a" is
# -u's value, not the staging flag; `-Sa` -> "a" is the keyid, nothing
# staged) -- only the BARE/next-token form was wrong.
REQUIRED_VALUE_SHORT_FLAGS = set("mFtCc")


# Returns (is_staging_flag, took_bare_value) for a single "-xyz"-shaped
# cluster token: is_staging_flag is True if -a/-i appears anywhere in the
# cluster; took_bare_value is True only if a REQUIRED-value short flag
# (REQUIRED_VALUE_SHORT_FLAGS, not merely VALUE_TAKING_SHORT_FLAGS) is the
# LAST character in the cluster (so its value is the NEXT token, not part of
# this one) -- e.g. "-m" or "-sm", but not "-mfix" or "-ma" (same reasoning
# as "-mfix": "m" isn't the LAST char in the cluster, so everything after it
# -- "fix", or "a" -- is its attached value, not a further flag letter; real
# git confirms "-ma" reads as message "a" with nothing staged, so that "a"
# is never a staging flag here), or "-S"/"-u" bare (optarg, no next-token
# value at all). A first pass checked only `len(tok) == 2` (bare
# "-m" alone), missing every multi-letter cluster ending on a value-taking
# flag like "-sm" or "-nm" -- found by adversarial review of PR #49 (F027),
# confirmed against real git: `git commit -sm -- -a` both signs off AND
# stages via a real trailing -a that the narrower check never reached. The
# position-aware fix for THAT gap then wrongly applied to -S/-u too, see
# REQUIRED_VALUE_SHORT_FLAGS's own comment above.
def _scan_short_flag_cluster(tok):
    body = tok[1:]
    for idx, c in enumerate(body):
        if c in ("a", "i"):
            return True, False
        if c in VALUE_TAKING_SHORT_FLAGS:
            return False, c in REQUIRED_VALUE_SHORT_FLAGS and idx == len(body) - 1
    return False, False


def _consumes_next_token(view):
    # True if VIEW (always _flag_view()'s output, never the raw/fully-
    # unquoted token) represents a flag that consumes the NEXT token as an
    # opaque, bare value -- either a long flag (exact or an unambiguous
    # abbreviation) resolving to VALUE_TAKING_LONG_FLAGS, or a short-flag
    # cluster ending in a required-value flag. Isolated into its own
    # function so has_staging_flag() can call it with EXACTLY the
    # conservative view, never the fully backslash-stripped token, for
    # this one specific decision (F051 round 2; see _flag_view()'s own
    # comment for why this decision specifically is the dangerous
    # direction and the flag-MATCH checks elsewhere in this file are not).
    if view.startswith("--") and len(view) > 2 and "=" not in view:
        return _resolve_long_flag(view) in VALUE_TAKING_LONG_FLAGS
    if view.startswith("-") and not view.startswith("--") and len(view) > 1:
        _, took_bare_value = _scan_short_flag_cluster(view)
        return took_bare_value
    return False


def has_staging_flag(tokens, views):
    i = 0
    n = len(tokens)
    while i < n:
        tok = tokens[i]
        view = views[i]
        if view == "--":
            break  # everything after this is a pathspec, never a flag
        if tok in STAGING_FLAGS:
            return True
        if tok.startswith("--") and len(tok) > 2 and "=" not in tok:
            # Resolves an EXACT long flag too (in which case this is just a
            # slower path to the same answer the old exact-match check
            # gave), but also a real, unambiguous ABBREVIATION of one --
            # `git commit --mess -- -a` staging+committing in real git,
            # exactly like the fully-spelled form, is why this branch
            # exists at all (found by adversarial review of PR #56). Same
            # abbreviation resolution also catches a real staging flag
            # abbreviated (`--inc` -> --include), a related gap the fixed
            # exact-match STAGING_FLAGS check above never covered either.
            # This match is against the fully-unquoted `tok`, not `view`,
            # deliberately: over-recognizing an abbreviation due to
            # unquote_token()'s own blanket backslash-strip only makes
            # this branch DENY more eagerly, never less -- safe-
            # directional, unlike the "consumes next token" decision below
            # (see _consumes_next_token()'s own comment).
            resolved = _resolve_long_flag(tok)
            if resolved in STAGING_FLAGS:
                return True
        elif tok.startswith("-") and not tok.startswith("--") and len(tok) > 1:
            is_staging, _ = _scan_short_flag_cluster(tok)
            if is_staging:
                return True
        # A bare value-taking flag (e.g. "-m", or a cluster ending on one
        # like "-sm", or an abbreviated long flag like "--mess") takes its
        # value from the NEXT token, whatever that token's own content
        # looks like -- it is opaque data, never itself a flag or the "--"
        # pathspec separator (F027). This decision is made against `view`
        # exclusively, never `tok`: wrongly believing a token consumes the
        # next one, when real bash/git would not (e.g. a single-quoted
        # literal pathspec that unquote_token()'s own backslash-strip
        # happens to reduce to a real flag's spelling), skips past
        # whatever REAL flag follows it -- the fail-open F051 round 2
        # exists to close.
        if _consumes_next_token(view):
            i += 1
        i += 1
    return False


def check_compound_stage_and_commit(parsed):
    subcommands = [sc for _, sc, _, _ in parsed]
    has_stage = any(sc in ("add", "stage") for sc in subcommands)
    commit_present = any(sc == "commit" for sc in subcommands)
    if has_stage and commit_present:
        return DENY_COMPOUND
    for tokens, sc, idx, views in parsed:
        if sc == "commit" and has_staging_flag(tokens[idx + 1:], views[idx + 1:]):
            return DENY_COMPOUND
    return None


def staged_diff(project_root):
    timeout = float(os.environ.get("COMMIT_GATE_DIFF_TIMEOUT", "5"))
    result = subprocess.run(
        ["git", "diff", "--cached", "-U0"],
        cwd=project_root,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if result.returncode != 0:
        return None
    return result.stdout


def added_lines(diff_text):
    # -U0 means every hunk carries only '+'/'-' lines, no unchanged context
    # lines, so the running counter is never thrown off by context. `in_hunk`
    # distinguishes a REAL "+++ " diff header (only ever seen before a file's
    # first "@@" hunk marker) from STAGED CONTENT that happens to read like one
    # (e.g. a line from a staged .patch/.diff file) -- treating the latter as a
    # header would both misattribute file/line in a denial message (leaking
    # staged content into it) and, if the fake path matched *.env.example,
    # forge the exemption and skip scanning the rest of the diff. git
    # terminates a "+++"/"---" header with a trailing tab when the path
    # contains a space; strip it.
    current_file = None
    current_line = None
    in_hunk = False
    for line in diff_text.splitlines():
        if line.startswith("diff --git "):
            current_file, current_line, in_hunk = None, None, False
            continue
        if not in_hunk and line.startswith("+++ "):
            path = line[4:].split("\t", 1)[0]
            current_file = path[2:] if path.startswith("b/") else path
            continue
        if line.startswith("@@"):
            in_hunk = True
            m = re.search(r"\+(\d+)", line)
            current_line = int(m.group(1)) if m else None
            continue
        if in_hunk and line.startswith("+") and current_file and current_line:
            yield current_file, current_line, line[1:]
            current_line += 1


def is_exempt(path):
    return fnmatch.fnmatch(path.rsplit("/", 1)[-1], "*.env.example")


def find_secret(lines, deadline):
    for path, lineno, content in lines:
        if time.monotonic() > deadline:
            return None
        if is_exempt(path):
            continue
        scanned = content[:SECRET_SCAN_MAX_LEN]
        if SECRET_PATTERN.search(scanned):
            return (
                f"secret-assignment: a staged addition at {path}:{lineno} looks "
                f"like a secret value (key/token/password assignment, length >= "
                f"16). Repair: {REPAIR_STAGED}."
            )
        if URL_CREDENTIAL_PATTERN.search(scanned):
            return (
                f"url-credential: a staged addition at {path}:{lineno} contains a "
                f"URL with embedded credentials. Repair: {REPAIR_STAGED}."
            )
    return None


def find_style_violation(lines, deadline):
    for path, lineno, content in lines:
        if time.monotonic() > deadline:
            return None
        if EM_DASH_PATTERN.search(content):
            return (
                f"style-violation: a staged addition at {path}:{lineno} violates "
                f"house style (em dash). Repair: {REPAIR_STYLE}."
            )
    return None


def style_gate_enabled(project_root):
    path = os.path.join(project_root, ".harness", "harness.json")
    try:
        with open(path) as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return False
    style_gate = data.get("style_gate")
    if not isinstance(style_gate, dict):
        return False
    return bool(style_gate.get("enabled", False))


def main():
    command = sys.argv[1]
    project_root = sys.argv[2]

    parsed = parse_command(command)
    if not any(sc == "commit" for _, sc, _, _ in parsed):
        return

    reason = check_compound_stage_and_commit(parsed)
    if reason:
        print(reason)
        return

    try:
        diff_text = staged_diff(project_root)
        if diff_text is None:
            return
        lines = list(added_lines(diff_text))
        deadline = time.monotonic() + SCAN_TIME_BUDGET_SECONDS
        reason = find_secret(lines, deadline)
        if reason:
            print(reason)
            return
        if style_gate_enabled(project_root):
            reason = find_style_violation(lines, deadline)
            if reason:
                print(reason)
    except subprocess.TimeoutExpired:
        return
    except Exception as exc:
        print(type(exc).__name__, file=sys.stderr)


main()
PYEOF
)

if [ -n "$DENY_REASON" ]; then
    deny_json "$DENY_REASON"
fi

exit 0
